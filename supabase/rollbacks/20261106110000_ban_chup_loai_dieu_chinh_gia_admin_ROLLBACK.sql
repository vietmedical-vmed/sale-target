-- Hoàn tác 20261106110000_ban_chup_loai_dieu_chinh_gia_admin.sql
-- Trả bản chụp về số gốc lúc chụp (bỏ mọi điều chỉnh giá admin), xoá log điều chỉnh, hàm áp
-- giá, tham số p_loai_admin; khôi phục chot_ke_hoach và so_sanh_chot_ke_hoach bản trước.

BEGIN;

UPDATE shared.ke_hoach_chot
   SET don_gia = don_gia_goc, dt_kh_update = dt_kh_update_goc
 WHERE dt_kh_update IS DISTINCT FROM dt_kh_update_goc OR don_gia IS DISTINCT FROM don_gia_goc;

DROP FUNCTION IF EXISTS public.ap_gia_admin_vao_ban_chup(bigint[], text);
DROP FUNCTION IF EXISTS public.so_sanh_chot_ke_hoach(text, text, boolean);
DROP TABLE IF EXISTS shared.ke_hoach_chot_dieu_chinh;
DROP INDEX IF EXISTS shared.ke_hoach_chot_sale_target_id_idx;

CREATE OR REPLACE FUNCTION public.chot_ke_hoach(
  p_ky     text,
  p_nguon  text DEFAULT 'thu_cong',
  p_nguoi  text DEFAULT NULL,
  p_ghi_de boolean DEFAULT false
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_cur  text;
  v_fy   text;
  v_n    integer;
  v_tong numeric;
BEGIN
  IF p_ky IS NULL OR p_ky !~ '^\d{4}-(0[1-9]|1[0-2])$' THEN
    RAISE EXCEPTION 'chot_ky_sai: kỳ phải dạng YYYY-MM';
  END IF;

  PERFORM pg_advisory_xact_lock(hashtext('chot_ke_hoach'));

  SELECT value #>> '{}' INTO v_cur FROM shared.app_config WHERE key = 'current_month';
  IF v_cur IS NULL OR v_cur !~ '^\d{4}-\d{2}$' THEN
    RAISE EXCEPTION 'chot_thieu_thang: chưa cấu hình tháng hiện tại';
  END IF;
  v_fy := shared.nam_tai_chinh_cua_thang(v_cur);

  IF EXISTS (SELECT 1 FROM shared.ke_hoach_chot_ky WHERE ky = p_ky) THEN
    IF NOT p_ghi_de THEN
      RAISE EXCEPTION 'chot_da_co: kỳ % đã có bản chụp', p_ky;
    END IF;
    DELETE FROM shared.ke_hoach_chot_ky WHERE ky = p_ky;
  END IF;

  INSERT INTO shared.ke_hoach_chot_ky (ky, nam_tai_chinh, thang_hien_tai, nguon, nguoi)
  VALUES (p_ky, v_fy, v_cur, p_nguon, p_nguoi);

  INSERT INTO shared.ke_hoach_chot (
    ky, sale_target_id, nam_tai_chinh, thang_ke_hoach, bu, mien, ps, ma_khach_hang, khach_hang,
    nhom_san_pham, bo_vat_tu, san_pham, ma_san_pham, don_gia, ngoai_ke_hoach,
    sl_ke_hoach_dau_nam, sl_ke_hoach_update, sl_thuc_hien, doanh_thu_thuc_hien, dt_kh_update
  )
  SELECT
    p_ky, s.id, s.nam_tai_chinh, s.thang_ke_hoach, s.bu, s.mien, s.ps, s.ma_khach_hang, s.khach_hang,
    s.nhom_san_pham, s.bo_vat_tu, s.san_pham, s.ma_san_pham, s.don_gia, s.ngoai_ke_hoach,
    s.sl_ke_hoach_dau_nam, s.sl_ke_hoach_update, s.sl_thuc_hien, s.doanh_thu_thuc_hien,
    CASE
      WHEN s.thang_ke_hoach < v_cur
        OR (s.thang_ke_hoach = v_cur AND coalesce(s.sl_thuc_hien, 0) <> 0)
        THEN coalesce(s.doanh_thu_thuc_hien, 0)
      ELSE coalesce(s.sl_ke_hoach_update, s.sl_ke_hoach_dau_nam, 0) * coalesce(s.don_gia, 0)
    END
  FROM shared.sale_target s
  WHERE s.nam_tai_chinh = v_fy;

  SELECT count(*), round(coalesce(sum(dt_kh_update), 0)) INTO v_n, v_tong
  FROM shared.ke_hoach_chot WHERE ky = p_ky;

  UPDATE shared.ke_hoach_chot_ky SET so_dong = v_n, tong_dt_kh_update = v_tong WHERE ky = p_ky;

  RETURN jsonb_build_object('ky', p_ky, 'nam_tai_chinh', v_fy, 'thang_hien_tai', v_cur,
                            'so_dong', v_n, 'tong_dt_kh_update', v_tong);
END;
$$;

CREATE FUNCTION public.so_sanh_chot_ke_hoach(p_a text, p_b text DEFAULT NULL)
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


ALTER TABLE shared.ke_hoach_chot DROP COLUMN IF EXISTS don_gia_goc, DROP COLUMN IF EXISTS dt_kh_update_goc;

REVOKE ALL ON FUNCTION public.chot_ke_hoach(text, text, text, boolean)    FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.so_sanh_chot_ke_hoach(text, text)           FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.chot_ke_hoach(text, text, text, boolean) TO service_role;
GRANT EXECUTE ON FUNCTION public.so_sanh_chot_ke_hoach(text, text)        TO service_role;

COMMIT;
