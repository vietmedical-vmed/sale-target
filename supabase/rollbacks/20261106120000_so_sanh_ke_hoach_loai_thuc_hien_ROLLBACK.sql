-- Hoàn tác 20261106120000_so_sanh_ke_hoach_loai_thuc_hien.sql: trả hàm so sánh về bản
-- 3 tham số (20261106110000), tính chênh cả ở tháng đã có thực hiện.

BEGIN;

DROP FUNCTION IF EXISTS public.so_sanh_chot_ke_hoach(text, text, boolean, boolean);

CREATE FUNCTION public.so_sanh_chot_ke_hoach(p_a text, p_b text DEFAULT NULL, p_loai_admin boolean DEFAULT true)
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
           nhom_san_pham, CASE WHEN p_loai_admin THEN dt_kh_update ELSE dt_kh_update_goc END AS dt
    FROM shared.ke_hoach_chot WHERE ky = p_a
    UNION ALL
    SELECT 'b', nam_tai_chinh, thang_ke_hoach, bu, mien, ps, ma_khach_hang, khach_hang,
           nhom_san_pham, CASE WHEN p_loai_admin THEN dt_kh_update ELSE dt_kh_update_goc END
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


REVOKE ALL ON FUNCTION public.so_sanh_chot_ke_hoach(text, text, boolean) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.so_sanh_chot_ke_hoach(text, text, boolean) TO service_role;

COMMIT;
