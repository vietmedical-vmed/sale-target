-- So sánh kế hoạch update: gộp thêm theo BU và miền (trước lấy max(bu)/max(mien) theo
-- PS × KH × nhóm, nên KH có dòng ở 2 miền/BU bị dồn về một). Tab so sánh nay đi theo cây
-- BU → Miền → PS → Khách hàng → Nhóm SP. Cùng chữ ký, CREATE OR REPLACE giữ nguyên quyền;
-- vẫn REVOKE/GRANT lại cho chắc.
--   [fy, thang, bu, mien, ps, ma_kh, ten_kh, nhom, dt_a, dt_b]

BEGIN;

CREATE OR REPLACE FUNCTION public.so_sanh_chot_ke_hoach(p_a text, p_b text DEFAULT NULL)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_fy  text;
  v_cur text;
  v_out jsonb;
BEGIN
  SELECT nam_tai_chinh INTO v_fy FROM shared.ke_hoach_chot_ky WHERE ky = p_a;
  IF v_fy IS NULL THEN
    RAISE EXCEPTION 'chot_khong_co: kỳ % chưa có bản chụp', p_a;
  END IF;
  IF p_b IS NOT NULL AND NOT EXISTS (SELECT 1 FROM shared.ke_hoach_chot_ky WHERE ky = p_b) THEN
    RAISE EXCEPTION 'chot_khong_co: kỳ % chưa có bản chụp', p_b;
  END IF;
  SELECT value #>> '{}' INTO v_cur FROM shared.app_config WHERE key = 'current_month';

  WITH hop AS (
    SELECT 'a' AS ben, nam_tai_chinh, thang_ke_hoach, bu, mien, ps, ma_khach_hang, khach_hang,
           nhom_san_pham, dt_kh_update AS dt
    FROM shared.ke_hoach_chot WHERE ky = p_a
    UNION ALL
    SELECT 'b', nam_tai_chinh, thang_ke_hoach, bu, mien, ps, ma_khach_hang, khach_hang,
           nhom_san_pham, dt_kh_update
    FROM shared.ke_hoach_chot WHERE p_b IS NOT NULL AND ky = p_b
    UNION ALL
    SELECT 'b', s.nam_tai_chinh, s.thang_ke_hoach, s.bu, s.mien, s.ps, s.ma_khach_hang, s.khach_hang,
           s.nhom_san_pham,
           CASE
             WHEN s.thang_ke_hoach < v_cur
               OR (s.thang_ke_hoach = v_cur AND coalesce(s.sl_thuc_hien, 0) <> 0)
               THEN coalesce(s.doanh_thu_thuc_hien, 0)
             ELSE coalesce(s.sl_ke_hoach_update, s.sl_ke_hoach_dau_nam, 0) * coalesce(s.don_gia, 0)
           END
    FROM shared.sale_target s
    WHERE p_b IS NULL AND s.nam_tai_chinh = v_fy
  ),
  g AS (
    SELECT nam_tai_chinh, thang_ke_hoach, bu, mien, ps, ma_khach_hang, nhom_san_pham,
           max(khach_hang) AS khach_hang,
           round(coalesce(sum(dt) FILTER (WHERE ben = 'a'), 0)) AS dt_a,
           round(coalesce(sum(dt) FILTER (WHERE ben = 'b'), 0)) AS dt_b
    FROM hop
    GROUP BY nam_tai_chinh, thang_ke_hoach, bu, mien, ps, ma_khach_hang, nhom_san_pham
  )
  SELECT coalesce(jsonb_agg(jsonb_build_array(
           nam_tai_chinh, thang_ke_hoach, bu, mien, ps, ma_khach_hang, khach_hang,
           nhom_san_pham, dt_a, dt_b)), '[]'::jsonb)
    INTO v_out
  FROM g
  WHERE dt_a <> 0 OR dt_b <> 0;

  RETURN v_out;
END;
$$;

REVOKE ALL ON FUNCTION public.so_sanh_chot_ke_hoach(text, text) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.so_sanh_chot_ke_hoach(text, text) TO service_role;

COMMIT;
