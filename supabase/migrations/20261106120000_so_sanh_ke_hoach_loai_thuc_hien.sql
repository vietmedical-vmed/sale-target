-- So sánh kế hoạch update: không tính chênh ở các tháng đã có thực hiện.
--
-- Trước đây tháng đã qua (và tháng hiện tại đã có thực hiện) lấy DThu thực hiện ở mỗi bên.
-- Đồng bộ thực hiện lại (loại trừ hoá đơn, chia lại PS, hoá đơn về muộn), hoặc admin chuyển
-- tháng hiện tại, làm số đó đổi và hiện thành chênh dù sale không sửa kế hoạch.
--
-- Nay ghép 2 bên theo sale_target_id. Một dòng × tháng bị loại khỏi chênh khi:
--   - bên nào đã dùng thực hiện (tháng < tháng hiện tại của bên đó, hoặc = mà có SL thực hiện), hoặc
--   - tháng < tháng hiện tại muộn hơn của 2 bên (dòng chỉ có ở 1 bên, tháng đã thành quá khứ).
-- Dòng bị loại: cả 2 bên nhận cùng một số (bên b nếu có, không thì bên a), gộp theo khoá của
-- bên đó → chênh 0. Dòng còn lại gộp theo khoá của chính bên mình như trước (dời PS vẫn hiện).
-- p_loai_thuc_hien = false (chỉ admin) trả về cách tính thô cũ.
--   [fy, thang, bu, mien, ps, ma_kh, ten_kh, nhom, dt_a, dt_b]

BEGIN;

DROP FUNCTION IF EXISTS public.so_sanh_chot_ke_hoach(text, text, boolean);

CREATE FUNCTION public.so_sanh_chot_ke_hoach(
  p_a text,
  p_b text DEFAULT NULL,
  p_loai_admin boolean DEFAULT true,
  p_loai_thuc_hien boolean DEFAULT true
)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_fy    text;
  v_cur_a text;
  v_cur_b text;
  v_cur   text;
  v_out   jsonb;
BEGIN
  SELECT nam_tai_chinh, thang_hien_tai INTO v_fy, v_cur_a FROM shared.ke_hoach_chot_ky WHERE ky = p_a;
  IF v_fy IS NULL THEN
    RAISE EXCEPTION 'chot_khong_co: kỳ % chưa có bản chụp', p_a;
  END IF;
  SELECT value #>> '{}' INTO v_cur FROM shared.app_config WHERE key = 'current_month';
  IF p_b IS NULL THEN
    v_cur_b := v_cur;
  ELSE
    SELECT thang_hien_tai INTO v_cur_b FROM shared.ke_hoach_chot_ky WHERE ky = p_b;
    IF NOT FOUND THEN
      RAISE EXCEPTION 'chot_khong_co: kỳ % chưa có bản chụp', p_b;
    END IF;
  END IF;

  WITH a AS (
    SELECT sale_target_id AS id, nam_tai_chinh, thang_ke_hoach, bu, mien, ps, ma_khach_hang,
           khach_hang, nhom_san_pham,
           CASE WHEN p_loai_admin THEN dt_kh_update ELSE dt_kh_update_goc END AS dt,
           (thang_ke_hoach < v_cur_a
             OR (thang_ke_hoach = v_cur_a AND coalesce(sl_thuc_hien, 0) <> 0)) AS da_th
    FROM shared.ke_hoach_chot WHERE ky = p_a
  ),
  b AS (
    SELECT sale_target_id AS id, nam_tai_chinh, thang_ke_hoach, bu, mien, ps, ma_khach_hang,
           khach_hang, nhom_san_pham,
           CASE WHEN p_loai_admin THEN dt_kh_update ELSE dt_kh_update_goc END AS dt,
           (thang_ke_hoach < v_cur_b
             OR (thang_ke_hoach = v_cur_b AND coalesce(sl_thuc_hien, 0) <> 0)) AS da_th
    FROM shared.ke_hoach_chot WHERE p_b IS NOT NULL AND ky = p_b
    UNION ALL
    SELECT s.id, s.nam_tai_chinh, s.thang_ke_hoach, s.bu, s.mien, s.ps, s.ma_khach_hang,
           s.khach_hang, s.nhom_san_pham,
           CASE
             WHEN s.thang_ke_hoach < v_cur_b
               OR (s.thang_ke_hoach = v_cur_b AND coalesce(s.sl_thuc_hien, 0) <> 0)
               THEN coalesce(s.doanh_thu_thuc_hien, 0)
             ELSE coalesce(s.sl_ke_hoach_update, s.sl_ke_hoach_dau_nam, 0) * coalesce(s.don_gia, 0)
           END,
           (s.thang_ke_hoach < v_cur_b
             OR (s.thang_ke_hoach = v_cur_b AND coalesce(s.sl_thuc_hien, 0) <> 0))
    FROM shared.sale_target s
    WHERE p_b IS NULL AND s.nam_tai_chinh = v_fy
  ),
  ghep AS (
    SELECT a.id AS a_id, b.id AS b_id,
           a.nam_tai_chinh AS a_fy, a.thang_ke_hoach AS a_thang, a.bu AS a_bu, a.mien AS a_mien,
           a.ps AS a_ps, a.ma_khach_hang AS a_kh, a.khach_hang AS a_ten, a.nhom_san_pham AS a_nhom,
           a.dt AS a_dt,
           b.nam_tai_chinh AS b_fy, b.thang_ke_hoach AS b_thang, b.bu AS b_bu, b.mien AS b_mien,
           b.ps AS b_ps, b.ma_khach_hang AS b_kh, b.khach_hang AS b_ten, b.nhom_san_pham AS b_nhom,
           b.dt AS b_dt,
           p_loai_thuc_hien AND (
             coalesce(a.da_th, false) OR coalesce(b.da_th, false)
             OR coalesce(b.thang_ke_hoach, a.thang_ke_hoach) < greatest(v_cur_a, v_cur_b)
           ) AS loai
    FROM a FULL JOIN b ON b.id = a.id
  ),
  hop AS (
    -- Không loại: mỗi bên theo khoá của mình.
    SELECT 'a' AS ben, a_fy AS fy, a_thang AS thang, a_bu AS bu, a_mien AS mien, a_ps AS ps,
           a_kh AS kh, a_ten AS ten, a_nhom AS nhom, a_dt AS dt
    FROM ghep WHERE NOT loai AND a_id IS NOT NULL
    UNION ALL
    SELECT 'b', b_fy, b_thang, b_bu, b_mien, b_ps, b_kh, b_ten, b_nhom, b_dt
    FROM ghep WHERE NOT loai AND b_id IS NOT NULL
    -- Loại: 2 bên cùng số, cùng khoá (ưu tiên bên b) → chênh 0.
    UNION ALL
    SELECT x.ben, coalesce(g.b_fy, g.a_fy), coalesce(g.b_thang, g.a_thang),
           CASE WHEN g.b_id IS NOT NULL THEN g.b_bu ELSE g.a_bu END,
           CASE WHEN g.b_id IS NOT NULL THEN g.b_mien ELSE g.a_mien END,
           CASE WHEN g.b_id IS NOT NULL THEN g.b_ps ELSE g.a_ps END,
           CASE WHEN g.b_id IS NOT NULL THEN g.b_kh ELSE g.a_kh END,
           CASE WHEN g.b_id IS NOT NULL THEN g.b_ten ELSE g.a_ten END,
           CASE WHEN g.b_id IS NOT NULL THEN g.b_nhom ELSE g.a_nhom END,
           CASE WHEN g.b_id IS NOT NULL THEN g.b_dt ELSE g.a_dt END
    FROM ghep g CROSS JOIN (VALUES ('a'), ('b')) AS x (ben)
    WHERE g.loai
  ),
  g AS (
    SELECT fy, thang, bu, mien, ps, kh, nhom, max(ten) AS ten,
           round(coalesce(sum(dt) FILTER (WHERE ben = 'a'), 0)) AS dt_a,
           round(coalesce(sum(dt) FILTER (WHERE ben = 'b'), 0)) AS dt_b
    FROM hop
    GROUP BY fy, thang, bu, mien, ps, kh, nhom
  )
  SELECT coalesce(jsonb_agg(jsonb_build_array(fy, thang, bu, mien, ps, kh, ten, nhom, dt_a, dt_b)), '[]'::jsonb)
    INTO v_out
  FROM g
  WHERE dt_a <> 0 OR dt_b <> 0;

  RETURN v_out;
END;
$$;

REVOKE ALL ON FUNCTION public.so_sanh_chot_ke_hoach(text, text, boolean, boolean) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.so_sanh_chot_ke_hoach(text, text, boolean, boolean) TO service_role;

COMMIT;
