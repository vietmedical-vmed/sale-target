-- Chụp (chốt) kế hoạch update hằng tháng để so sánh giữa các kỳ.
--
-- Mỗi kỳ (YYYY-MM) giữ một bản sao các dòng shared.sale_target của năm tài chính
-- đang chạy, kèm DThu KH update tính đúng như app lúc chụp:
--   tháng < tháng hiện tại, hoặc = tháng hiện tại mà đã có thực hiện -> DThu thực hiện;
--   còn lại -> (SL update, nếu trống thì SL đầu năm) × đơn giá.
-- "Tháng hiện tại" lấy từ shared.app_config.current_month tại lúc chụp.
--
-- Tự động: pg_cron chạy 23:59 giờ VN mỗi ngày; từ ngày hạn chót (app_config.deadline_day,
-- mặc định 5, không quá ngày cuối tháng) trở đi, nếu kỳ của tháng đó chưa có bản chụp
-- thì chụp. Admin có thể chụp tay (ghi đè) hoặc xoá bản chụp qua app.

BEGIN;

CREATE TABLE IF NOT EXISTS shared.ke_hoach_chot_ky (
  ky              text PRIMARY KEY CHECK (ky ~ '^\d{4}-(0[1-9]|1[0-2])$'),
  nam_tai_chinh   text NOT NULL,
  thang_hien_tai  text,
  chot_luc        timestamptz NOT NULL DEFAULT now(),
  nguon           text NOT NULL CHECK (nguon IN ('tu_dong', 'thu_cong')),
  nguoi           text,
  so_dong         integer NOT NULL DEFAULT 0,
  tong_dt_kh_update numeric NOT NULL DEFAULT 0
);

CREATE TABLE IF NOT EXISTS shared.ke_hoach_chot (
  ky                  text   NOT NULL REFERENCES shared.ke_hoach_chot_ky (ky) ON DELETE CASCADE,
  sale_target_id      bigint NOT NULL,
  nam_tai_chinh       text,
  thang_ke_hoach      text,
  bu                  text,
  mien                text,
  ps                  text,
  ma_khach_hang       text,
  khach_hang          text,
  nhom_san_pham       text,
  bo_vat_tu           text,
  san_pham            text,
  ma_san_pham         text,
  don_gia             numeric,
  ngoai_ke_hoach      boolean,
  sl_ke_hoach_dau_nam numeric,
  sl_ke_hoach_update  numeric,
  sl_thuc_hien        numeric,
  doanh_thu_thuc_hien numeric,
  dt_kh_update        numeric NOT NULL DEFAULT 0,
  PRIMARY KEY (ky, sale_target_id)
);

ALTER TABLE shared.ke_hoach_chot_ky ENABLE ROW LEVEL SECURITY;
ALTER TABLE shared.ke_hoach_chot    ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON shared.ke_hoach_chot_ky, shared.ke_hoach_chot FROM PUBLIC, anon, authenticated;
GRANT SELECT, INSERT, UPDATE, DELETE ON shared.ke_hoach_chot_ky, shared.ke_hoach_chot TO service_role;

-- Năm tài chính chứa tháng 'YYYY-MM' (FY26 = 2026-04 .. 2027-03).
CREATE OR REPLACE FUNCTION shared.nam_tai_chinh_cua_thang(p_thang text)
RETURNS text
LANGUAGE sql
IMMUTABLE
SET search_path = ''
AS $$
  SELECT 'FY' || lpad((((left(p_thang, 4)::int
           - CASE WHEN substr(p_thang, 6, 2)::int < 4 THEN 1 ELSE 0 END) % 100))::text, 2, '0');
$$;

-- Chụp kế hoạch update của năm tài chính đang chạy vào kỳ p_ky.
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

-- Cron gọi mỗi ngày 23:59 giờ VN; chỉ chụp khi đã tới hạn chót và kỳ chưa có bản chụp.
CREATE OR REPLACE FUNCTION public.chot_ke_hoach_tu_dong()
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_now  timestamp := now() AT TIME ZONE 'Asia/Ho_Chi_Minh';
  v_ky   text := to_char(v_now, 'YYYY-MM');
  v_han  integer;
  v_cuoi integer := extract(day FROM (date_trunc('month', v_now) + interval '1 month - 1 day'))::int;
BEGIN
  SELECT CASE WHEN (value #>> '{}') ~ '^\d+$' THEN (value #>> '{}')::int END
    INTO v_han FROM shared.app_config WHERE key = 'deadline_day';
  v_han := least(greatest(coalesce(v_han, 5), 1), v_cuoi);

  IF extract(day FROM v_now)::int < v_han THEN
    RETURN NULL;
  END IF;
  IF EXISTS (SELECT 1 FROM shared.ke_hoach_chot_ky WHERE ky = v_ky) THEN
    RETURN NULL;
  END IF;
  RETURN public.chot_ke_hoach(v_ky, 'tu_dong', 'cron', false);
END;
$$;

-- So sánh DThu KH update giữa kỳ p_a và kỳ p_b (p_b NULL = dữ liệu hiện tại, tính theo
-- tháng hiện tại đang cấu hình). Chi tiết đến PS × khách hàng × nhóm sản phẩm × tháng
-- (bỏ qua SP/giá/mã: đổi tên SP, đổi giá trong cùng nhóm vẫn khớp). Trả mảng gọn để
-- edge function không dính giới hạn 1.000 dòng của PostgREST:
--   [fy, thang, bu, mien, ps, ma_kh, ten_kh, nhom, dt_a, dt_b]
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
    SELECT nam_tai_chinh, thang_ke_hoach, ps, ma_khach_hang, nhom_san_pham,
           max(bu) AS bu, max(mien) AS mien, max(khach_hang) AS khach_hang,
           round(coalesce(sum(dt) FILTER (WHERE ben = 'a'), 0)) AS dt_a,
           round(coalesce(sum(dt) FILTER (WHERE ben = 'b'), 0)) AS dt_b
    FROM hop
    GROUP BY nam_tai_chinh, thang_ke_hoach, ps, ma_khach_hang, nhom_san_pham
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

REVOKE ALL ON FUNCTION shared.nam_tai_chinh_cua_thang(text)               FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.chot_ke_hoach(text, text, text, boolean)    FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.chot_ke_hoach_tu_dong()                     FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.so_sanh_chot_ke_hoach(text, text)           FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION shared.nam_tai_chinh_cua_thang(text)            TO service_role;
GRANT EXECUTE ON FUNCTION public.chot_ke_hoach(text, text, text, boolean) TO service_role;
GRANT EXECUTE ON FUNCTION public.chot_ke_hoach_tu_dong()                  TO service_role;
GRANT EXECUTE ON FUNCTION public.so_sanh_chot_ke_hoach(text, text)        TO service_role;

-- 16:59 UTC = 23:59 giờ VN.
SELECT cron.schedule('chot-ke-hoach-thang', '59 16 * * *', 'select public.chot_ke_hoach_tu_dong()');

COMMIT;
