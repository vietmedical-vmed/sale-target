-- ════════════════════════════════════════════════════════════════════════
-- Sửa PS trong hoá đơn theo PS địa bàn (dùng cho ly_do = 'sai_ps')
--
-- BỐI CẢNH
-- Khi cấu hình địa bàn là chân lý (thống nhất mức 1: cảnh báo + cho phép sửa),
-- dòng OOP có ly_do='sai_ps' nghĩa là: ps trong hoá đơn (đã dịch qua dm_ps từ
-- ten_ps) khác ps đang khai báo địa bàn cho (KH × ngành hàng × tháng). Người
-- dùng thấy 87 dòng như thế (2026-08-07), muốn nút "sửa theo địa bàn" ngay
-- trong modal.
--
-- CÁCH SỬA
-- app_sale.hoa_don_bovattu mang cột ten_ps (tên đầy đủ). Sửa ten_ps sang tên
-- đầy đủ của PS đích, rồi map + refresh để sale_target.sl_thuc_hien chuyển
-- theo. Không đụng cột ps trong sale_target — nó vẫn giữ theo địa bàn.
--
-- Phạm vi khoá 4 trường: (thang, ma_kh, bo_vat_tu, san_pham). Thêm điều kiện
-- ten_ps hiện đang dịch về ps CŨ để không đè lên dòng vốn đã đúng (một tổ hợp
-- 4 khoá có thể có nhiều dòng hoá đơn cùng, nhưng bản dịch ps thường thống
-- nhất). Nếu p_ps_cu để null thì đè bất kể — dùng khi biết chắc.
-- ════════════════════════════════════════════════════════════════════════

CREATE OR REPLACE FUNCTION public.sua_ps_hoa_don(
  p_thang      text,
  p_ma_kh      text,
  p_bo_vat_tu  text,
  p_san_pham   text,
  p_ps_cu      text,        -- ps rút gọn của hoá đơn hiện tại (để không đè nhầm)
  p_ps_moi     text         -- ps rút gọn theo địa bàn
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, shared, app_sale
AS $$
DECLARE
  v_ten_moi text;
  v_ten_cu  text[];
  v_updated int;
  v_map     jsonb;
BEGIN
  IF coalesce(btrim(p_ps_moi), '') = '' THEN
    RAISE EXCEPTION 'thieu_du_lieu: chưa có ps mới' USING ERRCODE = '22023';
  END IF;

  -- ten_ps đầy đủ cho ps mới (ưu tiên Active để tránh gán dòng vào PS đã nghỉ).
  SELECT ten_ps INTO v_ten_moi
    FROM shared.dm_ps
   WHERE ps = p_ps_moi
   ORDER BY (trang_thai = 'Active') DESC, ten_ps
   LIMIT 1;
  IF v_ten_moi IS NULL THEN
    RAISE EXCEPTION 'ps_khong_ton_tai: PS "%" không có trong dm_ps', p_ps_moi
      USING ERRCODE = '02000';
  END IF;

  -- Tập ten_ps đầy đủ ứng với ps rút gọn CŨ (một ps rút gọn có thể trùng ở nhiều
  -- ten_ps do dữ liệu cũ, tuy hiếm). Không truyền p_ps_cu → mảng NULL → bỏ ràng buộc.
  IF coalesce(btrim(p_ps_cu), '') <> '' THEN
    SELECT array_agg(ten_ps) INTO v_ten_cu
      FROM shared.dm_ps
     WHERE ps = p_ps_cu;
  END IF;

  UPDATE app_sale.hoa_don_bovattu h
     SET ten_ps = v_ten_moi
   WHERE h.thang                                    =     p_thang
     AND lower(btrim(coalesce(h.ma_kh, '')))        = lower(btrim(coalesce(p_ma_kh, '')))
     AND lower(btrim(coalesce(h.bo_vat_tu, '')))    = lower(btrim(coalesce(p_bo_vat_tu, '')))
     AND lower(btrim(coalesce(h.san_pham, '')))     = lower(btrim(coalesce(p_san_pham, '')))
     AND (v_ten_cu IS NULL
          OR lower(btrim(coalesce(h.ten_ps, ''))) = ANY (
             SELECT lower(btrim(coalesce(u, ''))) FROM unnest(v_ten_cu) AS u))
     AND coalesce(h.ten_ps, '') <> v_ten_moi;       -- bỏ dòng vốn đã đúng
  GET DIAGNOSTICS v_updated = ROW_COUNT;

  -- Map lại actual + refresh matview báo cáo — 1 lệnh (đã có sẵn).
  v_map := public.cap_nhat_thuc_hien();

  RETURN jsonb_build_object(
    'updated_hoa_don', v_updated,
    'ten_ps_moi',      v_ten_moi,
    'map',             v_map
  );
END;
$$;

REVOKE ALL ON FUNCTION public.sua_ps_hoa_don(text, text, text, text, text, text) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.sua_ps_hoa_don(text, text, text, text, text, text) TO service_role;

COMMENT ON FUNCTION public.sua_ps_hoa_don(text, text, text, text, text, text) IS
  'Sửa PS trong hoa_don_bovattu (theo tổ hợp thang+ma_kh+bo_vat_tu+san_pham) sang PS đích, sau đó map_hoadon_to_sale_target + refresh báo cáo. Dùng cho action "Sửa PS hoá đơn" ở modal Đối chiếu ngoài kế hoạch (ly_do=sai_ps).';
