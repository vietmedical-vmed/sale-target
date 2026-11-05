-- Loại điều chỉnh đơn giá của admin khỏi phần chênh khi so sánh bản chụp kế hoạch.
--
-- Khi admin đổi đơn giá (ô chi tiết, tab So sánh đơn giá — đều qua updateCells), edge
-- function gọi public.ap_gia_admin_vao_ban_chup(ids): mọi bản chụp có dòng sale_target đó
-- nhận đơn giá mới; DThu KH update của các tháng chưa có thực hiện (theo tháng hiện tại lúc
-- chụp) tính lại = SL × giá mới. Chênh giữa bản chụp và kỳ sau chỉ còn phần sale đổi.
--
-- Giữ nguyên bản: don_gia_goc / dt_kh_update_goc không bao giờ bị sửa; mỗi lần áp ghi một
-- dòng vào shared.ke_hoach_chot_dieu_chinh (trước/sau, ai, lúc nào). Admin bỏ tick
-- "Loại điều chỉnh giá của admin" thì so sánh theo số gốc (p_loai_admin = false).
--
-- Khoá theo sale_target_id: updateCells không gộp dòng (uq_sale_target_khoa IMMEDIATE, trùng
-- khoá thì báo lỗi 409, không ghi), nên id dòng admin sửa giá không đổi. Tab so sánh gộp theo
-- BU × miền × PS × KH × nhóm, nên dòng bị script hàng loạt gộp/xoá sau khi chụp vẫn khớp nhóm.

BEGIN;

ALTER TABLE shared.ke_hoach_chot
  ADD COLUMN IF NOT EXISTS don_gia_goc      numeric,
  ADD COLUMN IF NOT EXISTS dt_kh_update_goc numeric;

UPDATE shared.ke_hoach_chot
   SET don_gia_goc = don_gia, dt_kh_update_goc = dt_kh_update
 WHERE dt_kh_update_goc IS NULL;

ALTER TABLE shared.ke_hoach_chot ALTER COLUMN dt_kh_update_goc SET DEFAULT 0;
ALTER TABLE shared.ke_hoach_chot ALTER COLUMN dt_kh_update_goc SET NOT NULL;

CREATE TABLE IF NOT EXISTS shared.ke_hoach_chot_dieu_chinh (
  id             bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  ky             text   NOT NULL REFERENCES shared.ke_hoach_chot_ky (ky) ON DELETE CASCADE,
  sale_target_id bigint NOT NULL,
  thang_ke_hoach text,
  gia_truoc      numeric,
  gia_sau        numeric,
  dt_truoc       numeric,
  dt_sau         numeric,
  nguoi          text,
  luc            timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS ke_hoach_chot_dieu_chinh_ky_idx
  ON shared.ke_hoach_chot_dieu_chinh (ky, sale_target_id);
-- Tra bản chụp theo id dòng kế hoạch khi admin đổi giá.
CREATE INDEX IF NOT EXISTS ke_hoach_chot_sale_target_id_idx
  ON shared.ke_hoach_chot (sale_target_id);

ALTER TABLE shared.ke_hoach_chot_dieu_chinh ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON shared.ke_hoach_chot_dieu_chinh FROM PUBLIC, anon, authenticated;
GRANT SELECT, INSERT, UPDATE, DELETE ON shared.ke_hoach_chot_dieu_chinh TO service_role;

-- Bản chụp mới: cột gốc = giá trị lúc chụp.
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
    sl_ke_hoach_dau_nam, sl_ke_hoach_update, sl_thuc_hien, doanh_thu_thuc_hien, dt_kh_update,
    don_gia_goc
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
    END,
    s.don_gia
  FROM shared.sale_target s
  WHERE s.nam_tai_chinh = v_fy;

  UPDATE shared.ke_hoach_chot SET dt_kh_update_goc = dt_kh_update WHERE ky = p_ky;

  SELECT count(*), round(coalesce(sum(dt_kh_update), 0)) INTO v_n, v_tong
  FROM shared.ke_hoach_chot WHERE ky = p_ky;

  UPDATE shared.ke_hoach_chot_ky SET so_dong = v_n, tong_dt_kh_update = v_tong WHERE ky = p_ky;

  RETURN jsonb_build_object('ky', p_ky, 'nam_tai_chinh', v_fy, 'thang_hien_tai', v_cur,
                            'so_dong', v_n, 'tong_dt_kh_update', v_tong);
END;
$$;


-- Áp đơn giá hiện tại của các dòng p_ids (admin vừa sửa) vào mọi bản chụp có dòng đó.
CREATE OR REPLACE FUNCTION public.ap_gia_admin_vao_ban_chup(p_ids bigint[], p_nguoi text DEFAULT NULL)
RETURNS integer
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_n integer;
BEGIN
  IF p_ids IS NULL OR cardinality(p_ids) = 0 THEN
    RETURN 0;
  END IF;

  WITH s AS (
    SELECT id, don_gia FROM shared.sale_target WHERE id = ANY (p_ids)
  ),
  k AS (
    SELECT c.ky, c.sale_target_id, c.thang_ke_hoach,
           c.don_gia AS gia_truoc, s.don_gia AS gia_sau, c.dt_kh_update AS dt_truoc,
           CASE
             WHEN c.thang_ke_hoach < h.thang_hien_tai
               OR (c.thang_ke_hoach = h.thang_hien_tai AND coalesce(c.sl_thuc_hien, 0) <> 0)
               THEN c.dt_kh_update
             ELSE coalesce(c.sl_ke_hoach_update, c.sl_ke_hoach_dau_nam, 0) * coalesce(s.don_gia, 0)
           END AS dt_sau
    FROM shared.ke_hoach_chot c
    JOIN shared.ke_hoach_chot_ky h ON h.ky = c.ky
    JOIN s ON s.id = c.sale_target_id
    WHERE c.don_gia IS DISTINCT FROM s.don_gia
  ),
  u AS (
    UPDATE shared.ke_hoach_chot c
       SET don_gia = k.gia_sau, dt_kh_update = k.dt_sau
      FROM k
     WHERE c.ky = k.ky AND c.sale_target_id = k.sale_target_id
    RETURNING c.ky
  )
  INSERT INTO shared.ke_hoach_chot_dieu_chinh
    (ky, sale_target_id, thang_ke_hoach, gia_truoc, gia_sau, dt_truoc, dt_sau, nguoi)
  SELECT ky, sale_target_id, thang_ke_hoach, gia_truoc, gia_sau, dt_truoc, dt_sau, p_nguoi FROM k;

  GET DIAGNOSTICS v_n = ROW_COUNT;
  RETURN v_n;
END;
$$;

-- So sánh: thêm p_loai_admin (true = số đã áp giá admin, false = số gốc lúc chụp).
DROP FUNCTION IF EXISTS public.so_sanh_chot_ke_hoach(text, text);
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


REVOKE ALL ON FUNCTION public.chot_ke_hoach(text, text, text, boolean)      FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.ap_gia_admin_vao_ban_chup(bigint[], text)     FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.so_sanh_chot_ke_hoach(text, text, boolean)    FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.chot_ke_hoach(text, text, text, boolean)   TO service_role;
GRANT EXECUTE ON FUNCTION public.ap_gia_admin_vao_ban_chup(bigint[], text)  TO service_role;
GRANT EXECUTE ON FUNCTION public.so_sanh_chot_ke_hoach(text, text, boolean) TO service_role;

COMMIT;
