-- ════════════════════════════════════════════════════════════════════════
-- Dọn tổ hợp KH×ngành hàng có nhiều PS chồng lấn — theo bản đang hiệu lực
--
-- BỐI CẢNH
-- Sau khi chuyển sang "apply cả năm" (2026-08-07), các tổ hợp có nhiều PS
-- active bị apply skip (so_ps > 1). Data hiện có 36 tổ hợp như vậy, chủ yếu
-- do dữ liệu cũ có versioning theo tháng chồng lấn nhau khi bỏ giới hạn.
--
-- Với p_thang cho trước (mặc định app truyền CURRENT_MONTH), phân loại:
--   - "resolved": tổ hợp có DUY NHẤT 1 PS đang hiệu lực tại tháng đó
--        → giữ mọi bản của PS đó, XOÁ tất cả bản của PS khác. Sau đó apply
--          bản còn lại xuống kế hoạch (nhờ apply_dia_ban_to_plan bỏ điều kiện
--          tháng, dòng plan cả năm sẽ đổi sang PS này).
--   - "ambiguous": tổ hợp vẫn có ≥2 PS hiệu lực tại tháng đó, hoặc 0 PS
--          (mọi bản chỉ hiệu lực ở tháng khác) → không tự dọn, trả về danh
--          sách để UI hiển thị cho user tự xử.
--
-- Không đụng dm_dia_ban ngoài tổ hợp chồng lấn; không đụng dòng plan trực
-- tiếp (apply mới ghi).
-- ════════════════════════════════════════════════════════════════════════

CREATE OR REPLACE FUNCTION public.dep_dia_ban_chong_lan(p_thang text)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_deleted   int := 0;
  v_resolved  int := 0;
  v_amb_list  jsonb := '[]'::jsonb;
  v_apply     jsonb;
  v_keep_ids  bigint[];
BEGIN
  IF p_thang IS NULL OR p_thang !~ '^[0-9]{4}-[0-9]{2}$' THEN
    RAISE EXCEPTION 'thang_khong_hop_le: tháng phải dạng YYYY-MM' USING ERRCODE = '22023';
  END IF;

  -- Mọi tổ hợp có >1 PS trong dm_dia_ban, kèm số PS đang hiệu lực tại p_thang.
  -- eff_ps chỉ có giá trị khi n_eff_ps = 1 (dùng MIN/MAX trên cùng tập ps hiệu lực).
  CREATE TEMP TABLE _tup ON COMMIT DROP AS
  WITH agg AS (
    SELECT bu, cust_key, nhom_san_pham,
           count(DISTINCT ps) AS n_ps,
           count(DISTINCT CASE WHEN active
                                 AND tu_thang <= p_thang
                                 AND (den_thang IS NULL OR den_thang >= p_thang)
                               THEN ps END) AS n_eff_ps,
           min(CASE WHEN active
                      AND tu_thang <= p_thang
                      AND (den_thang IS NULL OR den_thang >= p_thang)
                    THEN ps END) AS eff_ps,
           max(khach_hang) AS khach_hang
      FROM dm_dia_ban
     GROUP BY bu, cust_key, nhom_san_pham
    HAVING count(DISTINCT ps) > 1
  )
  SELECT * FROM agg;

  -- Liệt kê tổ hợp không dọn được (≠ 1 PS hiệu lực tại tháng đó).
  SELECT coalesce(jsonb_agg(jsonb_build_object(
    'bu',             bu,
    'cust_key',       cust_key,
    'khach_hang',     khach_hang,
    'nhom_san_pham',  nhom_san_pham,
    'n_ps',           n_ps,
    'n_eff_ps',       n_eff_ps
  )), '[]'::jsonb) INTO v_amb_list
    FROM _tup WHERE n_eff_ps <> 1;

  -- Auto-dọn: với tổ hợp có 1 PS hiệu lực → xoá mọi bản khác PS.
  WITH del AS (
    DELETE FROM dm_dia_ban d
    USING _tup t
    WHERE t.n_eff_ps = 1
      AND d.bu             = t.bu
      AND d.cust_key       = t.cust_key
      AND d.nhom_san_pham  = t.nhom_san_pham
      AND d.ps            <> t.eff_ps
    RETURNING d.id
  )
  SELECT count(*) INTO v_deleted FROM del;

  SELECT count(*) INTO v_resolved FROM _tup WHERE n_eff_ps = 1;

  -- Sau xoá, tổ hợp chỉ còn 1 PS → apply xuống kế hoạch cho các bản còn lại.
  SELECT array_agg(d.id) INTO v_keep_ids
    FROM dm_dia_ban d
    JOIN _tup t ON t.n_eff_ps = 1
               AND t.bu             = d.bu
               AND t.cust_key       = d.cust_key
               AND t.nhom_san_pham  = d.nhom_san_pham;

  IF v_keep_ids IS NOT NULL AND array_length(v_keep_ids, 1) > 0 THEN
    v_apply := public.apply_dia_ban_to_plan(v_keep_ids);
  END IF;

  RETURN jsonb_build_object(
    'resolved',  v_resolved,
    'deleted',   v_deleted,
    'ambiguous', v_amb_list,
    'apply',     v_apply
  );
END;
$$;

REVOKE ALL ON FUNCTION public.dep_dia_ban_chong_lan(text) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.dep_dia_ban_chong_lan(text) TO service_role;

COMMENT ON FUNCTION public.dep_dia_ban_chong_lan(text) IS
  'Với mỗi (bu, cust_key, nhom_san_pham) có >1 PS trong dm_dia_ban: nếu tại p_thang chỉ 1 PS đang hiệu lực → giữ PS đó, xoá các bản khác, apply xuống kế hoạch. Ambiguous trả về danh sách để UI hiển thị.';
