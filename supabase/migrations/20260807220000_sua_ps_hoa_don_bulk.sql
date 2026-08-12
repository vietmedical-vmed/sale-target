-- ════════════════════════════════════════════════════════════════════════
-- Sửa PS hoá đơn hàng loạt — 1 map + 1 refresh cho cả lô
--
-- Bản single sua_ps_hoa_don gọi cap_nhat_thuc_hien() sau MỖI dòng: bấm bulk
-- 87 dòng = 87 lần map + refresh = rất chậm (mỗi lần map zero mọi tháng có
-- trong hoa_don rồi ghi lại). Bản bulk: update tất cả dòng trước, rồi map +
-- refresh MỘT LẦN ở cuối. Cùng logic cho từng dòng như bản single.
--
-- Đầu vào p_rows: [{ thang, ma_kh, bo_vat_tu, san_pham, ps_cu, ps_moi }, ...]
-- Trả về: { updated_hoa_don, ps_khong_ton_tai:[...], map:{...} }
-- ════════════════════════════════════════════════════════════════════════

CREATE OR REPLACE FUNCTION public.sua_ps_hoa_don_bulk(p_rows jsonb)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, shared, app_sale
AS $$
DECLARE
  v_tong_updated int := 0;
  v_ps_thieu     text[] := '{}';
  v_map          jsonb;
BEGIN
  IF jsonb_typeof(p_rows) <> 'array' OR jsonb_array_length(p_rows) = 0 THEN
    RAISE EXCEPTION 'thieu_du_lieu: p_rows rỗng' USING ERRCODE = '22023';
  END IF;

  -- Chuẩn hoá + tra ten_ps mới cho mỗi ps_moi (1 lượt).
  CREATE TEMP TABLE _rows ON COMMIT DROP AS
  SELECT btrim(e->>'thang')      AS thang,
         btrim(e->>'ma_kh')      AS ma_kh,
         btrim(e->>'bo_vat_tu')  AS bo_vat_tu,
         btrim(e->>'san_pham')   AS san_pham,
         btrim(e->>'ps_cu')      AS ps_cu,
         btrim(e->>'ps_moi')     AS ps_moi
  FROM   jsonb_array_elements(p_rows) AS e;

  CREATE TEMP TABLE _psmap ON COMMIT DROP AS
  WITH ps_moi_list AS (
    SELECT DISTINCT ps_moi FROM _rows WHERE ps_moi <> ''
  )
  SELECT l.ps_moi,
         (SELECT ten_ps FROM shared.dm_ps d
           WHERE d.ps = l.ps_moi
           ORDER BY (d.trang_thai = 'Active') DESC, d.ten_ps
           LIMIT 1) AS ten_ps_moi
  FROM ps_moi_list l;

  -- Ghi lại các ps_moi không tra được (trả về cho app biết ai bị bỏ qua).
  SELECT array_agg(ps_moi ORDER BY ps_moi) INTO v_ps_thieu
    FROM _psmap WHERE ten_ps_moi IS NULL;
  IF v_ps_thieu IS NULL THEN v_ps_thieu := '{}'; END IF;

  -- Cho từng dòng đủ dữ liệu: UPDATE tất cả hoa_don khớp 4 khoá + ten_ps hiện
  -- đang dịch về ps_cu (nếu có ps_cu). Điều kiện “không đè dòng vốn đúng” giữ
  -- nguyên như bản single.
  WITH loi AS (
    SELECT r.*, m.ten_ps_moi,
           (SELECT array_agg(ten_ps) FROM shared.dm_ps
             WHERE r.ps_cu <> '' AND ps = r.ps_cu) AS ten_cu_arr
    FROM _rows r
    JOIN _psmap m ON m.ps_moi = r.ps_moi
    WHERE r.thang <> '' AND r.ma_kh <> '' AND m.ten_ps_moi IS NOT NULL
  )
  UPDATE app_sale.hoa_don_bovattu h
     SET ten_ps = loi.ten_ps_moi
    FROM loi
   WHERE h.thang                                    =     loi.thang
     AND lower(btrim(coalesce(h.ma_kh, '')))        = lower(btrim(loi.ma_kh))
     AND lower(btrim(coalesce(h.bo_vat_tu, '')))    = lower(btrim(loi.bo_vat_tu))
     AND lower(btrim(coalesce(h.san_pham, '')))     = lower(btrim(loi.san_pham))
     AND (loi.ten_cu_arr IS NULL
          OR lower(btrim(coalesce(h.ten_ps, ''))) = ANY (
             SELECT lower(btrim(coalesce(u, ''))) FROM unnest(loi.ten_cu_arr) AS u))
     AND coalesce(h.ten_ps, '') <> loi.ten_ps_moi;
  GET DIAGNOSTICS v_tong_updated = ROW_COUNT;

  -- Map + refresh MỘT LẦN cho cả lô, không phải mỗi dòng một lần.
  v_map := public.cap_nhat_thuc_hien();

  RETURN jsonb_build_object(
    'updated_hoa_don',   v_tong_updated,
    'ps_khong_ton_tai',  to_jsonb(v_ps_thieu),
    'map',               v_map
  );
END;
$$;

REVOKE ALL ON FUNCTION public.sua_ps_hoa_don_bulk(jsonb) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.sua_ps_hoa_don_bulk(jsonb) TO service_role;

COMMENT ON FUNCTION public.sua_ps_hoa_don_bulk(jsonb) IS
  'Sửa PS hoá đơn hàng loạt: update tất cả tổ hợp trong p_rows, rồi cap_nhat_thuc_hien 1 lần. Dùng cho action "Sửa tất cả sai_ps" ở modal Đối chiếu.';
