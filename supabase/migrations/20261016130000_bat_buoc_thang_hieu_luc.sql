-- Bắt buộc tháng thầu + hiệu lực thầu cho đợt thầu, và tính quota theo hiệu lực.
--
-- Hiệu lực = dot_thau.thoi_gian (số tháng, chuyển từ "Thời gian thầu chính" cũ).
-- Hết hạn = tháng thầu + hiệu lực − 1 tháng (shared.het_han_dot). Trạng thái quota:
--   Upcoming: tháng hiện tại < tháng thầu, hoặc đợt còn thiếu tháng / hiệu lực.
--   On hand : tháng thầu ≤ tháng hiện tại ≤ hết hạn. Thầu cũ luôn On hand.
--   Hết hiệu lực: tháng hiện tại > hết hạn → không tính on hand, không vào tổng.
-- Chặn nhập (user chốt 15/10):
--   * upsert_dot_thau: đợt phải có tháng thầu + hiệu lực (số tháng nguyên 1–120).
--   * upsert_quota_thau: quota > 0 chỉ vào đợt đủ tháng + hiệu lực (về 0 / xoá vẫn được).
--   * duyet_dot_thau: không duyệt đợt thiếu thông tin.
-- Chưa thêm CHECK trên dot_thau: 144 đợt cũ đang thiếu, và trigger giữ khoá (P3) còn
-- chép / chuyển các đợt đó. Thêm CHECK khi dữ liệu cũ đã điền đủ.
-- v_quota_thau_xuat: trang_thai có thêm 'Hết hiệu lực'; thêm cột hieu_luc, het_han.
-- Tổng app = các dòng không cảnh báo và trang_thai <> 'Hết hiệu lực'.

BEGIN;

CREATE OR REPLACE FUNCTION shared.het_han_dot(p_thang text, p_hieu_luc numeric)
RETURNS text LANGUAGE sql IMMUTABLE AS $$
  SELECT CASE WHEN p_thang ~ '^\d{4}-\d{2}$' AND p_hieu_luc > 0
              THEN to_char(to_date(p_thang || '-01', 'YYYY-MM-DD')
                           + make_interval(months => p_hieu_luc::int - 1), 'YYYY-MM') END;
$$;
REVOKE ALL ON FUNCTION shared.het_han_dot(text, numeric) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION shared.het_han_dot(text, numeric) TO service_role;

CREATE OR REPLACE FUNCTION public.upsert_dot_thau(p_rows jsonb, p_bu text, p_mien text, p_ps text, p_groups text[], p_actor text DEFAULT NULL::text)
 RETURNS integer
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'shared'
AS $function$
DECLARE
  r      jsonb;
  v_bu   text;
  v_mien text;
  v_fy   text;
  v_ps   text;
  v_cust text;
  v_grp  text;
  v_loai text;
  v_dot  int;
  v_thang text;
  v_tg   numeric;
  v_done int := 0;
BEGIN
  FOR r IN SELECT * FROM jsonb_array_elements(coalesce(p_rows, '[]'::jsonb))
  LOOP
    v_fy   := r->>'fy';
    v_ps   := r->>'ps';
    v_cust := coalesce(r->>'custId', '');
    v_grp  := coalesce(r->>'grp', '');
    v_loai := r->>'loai';
    v_thang := nullif(r->>'thang', '');

    IF v_loai NOT IN ('chinh', 'bo_sung') THEN
      RAISE EXCEPTION 'loai_khong_hop_le: %', v_loai USING ERRCODE = '22023';
    END IF;
    IF v_thang IS NOT NULL AND v_thang !~ '^\d{4}-\d{2}$' THEN
      RAISE EXCEPTION 'thang_sai_dinh_dang: % (cần yyyy-mm)', v_thang USING ERRCODE = '22023';
    END IF;

    SELECT s.bu, s.mien INTO v_bu, v_mien
    FROM shared.scope_nhom_sp(v_fy, v_ps, v_cust, v_grp, p_bu, p_mien, p_ps, p_groups) s;

    IF NOT FOUND THEN
      RAISE EXCEPTION 'out_of_scope: nhóm % / KH % / PS % nằm ngoài phạm vi quyền hoặc không tồn tại',
                      v_grp, v_cust, v_ps USING ERRCODE = '42501';
    END IF;

    v_dot := nullif(r->>'dot', '')::int;
    IF v_dot IS NULL THEN
      SELECT coalesce(max(d.dot), 0) + 1 INTO v_dot
      FROM   shared.dot_thau d
      WHERE  d.nam_tai_chinh = v_fy AND d.ps = v_ps
        AND  d.ma_khach_hang = v_cust AND d.nhom_san_pham = v_grp
        AND  d.loai = v_loai;
    END IF;

    -- Bắt buộc tháng thầu + hiệu lực (số tháng). Không gửi thoiGian = giữ hiệu lực đang có.
    IF r ? 'thoiGian' THEN
      v_tg := nullif(r->>'thoiGian', '')::numeric;
    ELSE
      SELECT d.thoi_gian INTO v_tg FROM shared.dot_thau d
      WHERE d.nam_tai_chinh = v_fy AND d.ps = v_ps AND d.ma_khach_hang = v_cust
        AND d.nhom_san_pham = v_grp AND d.loai = v_loai AND d.dot = v_dot;
    END IF;
    IF v_thang IS NULL THEN
      RAISE EXCEPTION 'dot_thieu_thong_tin: đợt thầu phải có tháng thầu (yyyy-mm)' USING ERRCODE = '22023';
    END IF;
    IF v_tg IS NULL OR v_tg <= 0 OR v_tg > 120 OR v_tg <> trunc(v_tg) THEN
      RAISE EXCEPTION 'dot_thieu_thong_tin: đợt thầu phải có hiệu lực (số tháng nguyên, 1–120)' USING ERRCODE = '22023';
    END IF;

    INSERT INTO shared.dot_thau
      (nam_tai_chinh, bu, mien, ps, ma_khach_hang, nhom_san_pham,
       loai, dot, thang_thau, thoi_gian, updated_by)
    VALUES
      (v_fy, v_bu, v_mien, v_ps, v_cust, v_grp,
       v_loai, v_dot, v_thang, v_tg, p_actor)
    ON CONFLICT (nam_tai_chinh, ps, ma_khach_hang, nhom_san_pham, loai, dot)
    DO UPDATE SET
      trang_thai = 'chinh_thuc',
      thang_thau = EXCLUDED.thang_thau,
      thoi_gian  = EXCLUDED.thoi_gian,
      updated_at = now(),
      updated_by = p_actor;

    v_done := v_done + 1;
  END LOOP;

  RETURN v_done;
END;
$function$;

CREATE OR REPLACE FUNCTION public.upsert_quota_thau(p_rows jsonb, p_bu text, p_mien text, p_ps text, p_groups text[], p_actor text DEFAULT NULL::text)
 RETURNS integer
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'shared'
AS $function$
DECLARE
  r       jsonb;
  v_bu    text;
  v_mien  text;
  v_fy    text;
  v_ps    text;
  v_cust  text;
  v_grp   text;
  v_mset  text;
  v_prod  text;
  v_price numeric;
  v_loai  text;
  v_dot   int;
  v_qty   numeric;
  v_done  int := 0;
  v_keys  jsonb := '[]'::jsonb;
BEGIN
  FOR r IN SELECT * FROM jsonb_array_elements(coalesce(p_rows, '[]'::jsonb))
  LOOP
    v_fy    := r->>'fy';
    v_ps    := r->>'ps';
    v_cust  := coalesce(r->>'custId', '');
    v_grp   := coalesce(r->>'grp', '');
    v_mset  := coalesce(r->>'mset', '');
    v_prod  := coalesce(r->>'prod', '');
    v_price := coalesce(nullif(r->>'price', '')::numeric, 0);
    v_loai  := r->>'loai';
    v_qty   := nullif(r->>'qty', '')::numeric;

    IF v_loai NOT IN ('cu', 'chinh', 'bo_sung') THEN
      RAISE EXCEPTION 'loai_khong_hop_le: %', v_loai USING ERRCODE = '22023';
    END IF;

    SELECT s.bu, s.mien INTO v_bu, v_mien
    FROM shared.scope_nhom_sp(v_fy, v_ps, v_cust, v_grp, p_bu, p_mien, p_ps, p_groups) s;

    IF NOT FOUND THEN
      RAISE EXCEPTION 'out_of_scope: nhóm % / KH % / PS % nằm ngoài phạm vi quyền hoặc không tồn tại',
                      v_grp, v_cust, v_ps USING ERRCODE = '42501';
    END IF;

    IF v_loai = 'cu' THEN
      v_dot := 1;
    ELSE
      v_dot := coalesce(nullif(r->>'dot', '')::int, 1);
      PERFORM 1 FROM shared.dot_thau d
       WHERE d.nam_tai_chinh = v_fy AND d.ps = v_ps
         AND d.ma_khach_hang = v_cust AND d.nhom_san_pham = v_grp
         AND d.loai = v_loai AND d.dot = v_dot;
      IF NOT FOUND THEN
        RAISE EXCEPTION 'dot_khong_ton_tai: % đợt % của nhóm % — tạo đợt trước khi nhập quota',
                        v_loai, v_dot, v_grp USING ERRCODE = '23503';
      END IF;
      -- Quota > 0 chỉ nhập được vào đợt đã có tháng thầu + hiệu lực (xoá / về 0 vẫn được).
      IF coalesce(v_qty, 0) <> 0 AND EXISTS (
           SELECT 1 FROM shared.dot_thau d
           WHERE d.nam_tai_chinh = v_fy AND d.ps = v_ps AND d.ma_khach_hang = v_cust
             AND d.nhom_san_pham = v_grp AND d.loai = v_loai AND d.dot = v_dot
             AND (d.thang_thau IS NULL OR d.thoi_gian IS NULL OR d.thoi_gian <= 0)) THEN
        RAISE EXCEPTION 'dot_thieu_thong_tin: % đợt % của nhóm % chưa có tháng thầu / hiệu lực — điền trước khi nhập quota',
                        v_loai, v_dot, v_grp USING ERRCODE = '22023';
      END IF;
    END IF;

    IF v_qty IS NULL OR v_qty = 0 THEN
      DELETE FROM shared.quota_thau q
      WHERE q.nam_tai_chinh = v_fy AND q.ps = v_ps
        AND q.ma_khach_hang = v_cust AND q.nhom_san_pham = v_grp
        AND q.bo_vat_tu = v_mset AND q.san_pham = v_prod
        AND q.don_gia = v_price AND q.loai = v_loai AND q.dot = v_dot;
    ELSE
      INSERT INTO shared.quota_thau
        (nam_tai_chinh, bu, mien, ps, ma_khach_hang, khach_hang, nhom_san_pham,
         bo_vat_tu, san_pham, don_gia, loai, dot, so_luong, updated_by)
      VALUES
        (v_fy, v_bu, v_mien, v_ps, v_cust, nullif(r->>'cust', ''), v_grp,
         v_mset, v_prod, v_price, v_loai, v_dot, v_qty, p_actor)
      ON CONFLICT (nam_tai_chinh, ps, ma_khach_hang, nhom_san_pham, bo_vat_tu,
                   san_pham, don_gia, loai, dot)
      DO UPDATE SET
        trang_thai = 'chinh_thuc',
        so_luong   = EXCLUDED.so_luong,
        khach_hang = coalesce(EXCLUDED.khach_hang, shared.quota_thau.khach_hang),
        updated_at = now(),
        updated_by = p_actor;
    END IF;

    v_keys := v_keys || jsonb_build_object(
      'fy', v_fy, 'ps', v_ps, 'cust', v_cust,
      'grp', v_grp, 'mset', v_mset, 'prod', v_prod
    );
    v_done := v_done + 1;
  END LOOP;

  RETURN v_done;
END;
$function$;

CREATE OR REPLACE FUNCTION public.duyet_dot_thau(p_ids bigint[], p_duyet boolean, p_actor text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'shared'
AS $function$
DECLARE
  v_n int := 0;
BEGIN
  IF p_duyet THEN
    IF EXISTS (SELECT 1 FROM shared.dot_thau d
               WHERE d.id = ANY(p_ids) AND d.trang_thai = 'cho_duyet'
                 AND (d.thang_thau IS NULL OR d.thoi_gian IS NULL OR d.thoi_gian <= 0)) THEN
      RAISE EXCEPTION 'dot_thieu_thong_tin: có đợt chưa có tháng thầu / hiệu lực — điền trước khi duyệt'
        USING ERRCODE = '22023';
    END IF;
    WITH doi AS (
      UPDATE shared.dot_thau d SET trang_thai = 'chinh_thuc', updated_at = now(), updated_by = p_actor
      WHERE d.id = ANY(p_ids) AND d.trang_thai = 'cho_duyet'
      RETURNING d.*)
    , log AS (
      INSERT INTO shared.quota_chuan_hoa_log (buoc, bang, ban_ghi_id, sau)
      SELECT 'duyet', 'dot_thau', id, to_jsonb(doi) FROM doi RETURNING 1)
    SELECT count(*) INTO v_n FROM doi;
  ELSE
    WITH xoa AS (
      DELETE FROM shared.dot_thau d
      WHERE d.id = ANY(p_ids) AND d.trang_thai = 'cho_duyet'
        AND NOT EXISTS (SELECT 1 FROM shared.quota_thau q
                        WHERE q.nam_tai_chinh = d.nam_tai_chinh AND q.ps = d.ps AND q.ma_khach_hang = d.ma_khach_hang
                          AND q.nhom_san_pham = d.nhom_san_pham AND q.loai = d.loai AND q.dot = d.dot)
      RETURNING d.*)
    , log AS (
      INSERT INTO shared.quota_chuan_hoa_log (buoc, bang, ban_ghi_id, truoc)
      SELECT 'loai', 'dot_thau', id, to_jsonb(xoa) FROM xoa RETURNING 1)
    SELECT count(*) INTO v_n FROM xoa;
  END IF;
  RETURN jsonb_build_object('dot', v_n);
END;
$function$;

CREATE OR REPLACE VIEW shared.v_quota_thau_xuat
WITH (security_invoker = true) AS
WITH
cur AS (
  SELECT value #>> '{}' AS thang FROM shared.app_config WHERE key = 'current_month'
),
ke_hoach AS (
  SELECT * FROM shared.sale_target
  WHERE nam_tai_chinh IS NOT NULL AND NOT coalesce(ngoai_ke_hoach, false)
),
nhom_co_dot AS (
  SELECT DISTINCT nam_tai_chinh, ps, ma_khach_hang, nhom_san_pham FROM shared.dot_thau
),
gia_co_quota AS (
  SELECT DISTINCT nam_tai_chinh, ps, ma_khach_hang, nhom_san_pham, bo_vat_tu, san_pham, don_gia
  FROM shared.quota_thau
),
-- Khoá sản phẩm × mức giá đang có trên kế hoạch. Gom DISTINCT trước rồi hash
-- join: EXISTS tương quan trên CTE quét lại cả sale_target cho từng dòng quota.
kh_gia AS (
  SELECT DISTINCT nam_tai_chinh, ps, coalesce(ma_khach_hang, '') AS ma_khach_hang,
         coalesce(nhom_san_pham, '') AS nhom_san_pham, coalesce(bo_vat_tu, '') AS bo_vat_tu,
         coalesce(san_pham, '') AS san_pham, coalesce(don_gia, 0) AS don_gia
  FROM ke_hoach
),
kh_sp AS (
  SELECT DISTINCT nam_tai_chinh, ps, ma_khach_hang, nhom_san_pham, bo_vat_tu, san_pham
  FROM kh_gia
),
-- Tập khoá theo tên chuẩn hoá / mã để phân loại quota mồ côi (hash join, không EXISTS tương quan)
kh_ten AS (
  SELECT DISTINCT nam_tai_chinh, ps, coalesce(ma_khach_hang, '') AS ma_khach_hang, shared.ten_sp_chuan(san_pham) AS ten
  FROM ke_hoach
),
kh_ma AS (
  SELECT DISTINCT nam_tai_chinh, ps, coalesce(ma_khach_hang, '') AS ma_khach_hang, shared.ma_sp_hop_le(ma_san_pham) AS ma
  FROM ke_hoach WHERE shared.ma_sp_hop_le(ma_san_pham) IS NOT NULL
),
kh_kh_ten AS (  -- theo KH, không theo PS
  SELECT DISTINCT nam_tai_chinh, coalesce(ma_khach_hang, '') AS ma_khach_hang, shared.ten_sp_chuan(san_pham) AS ten
  FROM ke_hoach
),
kh_kh_ma AS (
  SELECT DISTINCT nam_tai_chinh, coalesce(ma_khach_hang, '') AS ma_khach_hang, shared.ma_sp_hop_le(ma_san_pham) AS ma
  FROM ke_hoach WHERE shared.ma_sp_hop_le(ma_san_pham) IS NOT NULL
),
-- A. Nguồn mới
moi AS (
  SELECT q.nam_tai_chinh, q.bu, q.mien, q.ps, q.ma_khach_hang, q.khach_hang,
         q.nhom_san_pham, q.bo_vat_tu, q.san_pham, q.don_gia, q.loai, q.dot,
         d.thang_thau, q.so_luong,
         'quota_thau'::text AS nguon,
         CASE
           WHEN q.trang_thai = 'cho_duyet' THEN 'Chờ duyệt (chưa hiện trên app)'
           WHEN g.san_pham IS NOT NULL THEN NULL
           WHEN p.san_pham IS NOT NULL THEN 'Mức giá không còn trên kế hoạch'
           WHEN t.ten IS NOT NULL THEN 'Khớp tên - khác nhóm / BVT / cách viết'
           WHEN m.ma IS NOT NULL THEN 'Khác tên - khớp mã'
           WHEN kt.ten IS NOT NULL OR km.ma IS NOT NULL THEN 'SP còn ở KH nhưng PS khác'
           ELSE 'Khác tên - khác mã (SP không còn trên kế hoạch)'
         END AS canh_bao,
         d.thoi_gian AS hieu_luc
  FROM shared.quota_thau q
  LEFT JOIN shared.dot_thau d
         ON d.nam_tai_chinh = q.nam_tai_chinh AND d.ps = q.ps
        AND d.ma_khach_hang = q.ma_khach_hang AND d.nhom_san_pham = q.nhom_san_pham
        AND d.loai = q.loai AND d.dot = q.dot AND q.loai <> 'cu'
  LEFT JOIN kh_gia g
         ON g.nam_tai_chinh = q.nam_tai_chinh AND g.ps = q.ps
        AND g.ma_khach_hang = q.ma_khach_hang AND g.nhom_san_pham = q.nhom_san_pham
        AND g.bo_vat_tu = q.bo_vat_tu AND g.san_pham = q.san_pham AND g.don_gia = q.don_gia
  LEFT JOIN kh_sp p
         ON p.nam_tai_chinh = q.nam_tai_chinh AND p.ps = q.ps
        AND p.ma_khach_hang = q.ma_khach_hang AND p.nhom_san_pham = q.nhom_san_pham
        AND p.bo_vat_tu = q.bo_vat_tu AND p.san_pham = q.san_pham
  LEFT JOIN kh_ten t
         ON t.nam_tai_chinh = q.nam_tai_chinh AND t.ps = q.ps AND t.ma_khach_hang = q.ma_khach_hang
        AND t.ten = shared.ten_sp_chuan(q.san_pham)
  LEFT JOIN kh_ma m
         ON m.nam_tai_chinh = q.nam_tai_chinh AND m.ps = q.ps AND m.ma_khach_hang = q.ma_khach_hang
        AND m.ma = q.ma_san_pham
  LEFT JOIN kh_kh_ten kt
         ON kt.nam_tai_chinh = q.nam_tai_chinh AND kt.ma_khach_hang = q.ma_khach_hang
        AND kt.ten = shared.ten_sp_chuan(q.san_pham)
  LEFT JOIN kh_kh_ma km
         ON km.nam_tai_chinh = q.nam_tai_chinh AND km.ma_khach_hang = q.ma_khach_hang
        AND km.ma = q.ma_san_pham
  WHERE q.so_luong <> 0
),
-- B. Cột cũ: chỉ sản phẩm × mức giá chưa chuyển sang nguồn mới
cu_raw AS (
  SELECT s.* FROM ke_hoach s
  WHERE NOT EXISTS (SELECT 1 FROM nhom_co_dot g
                    WHERE g.nam_tai_chinh = s.nam_tai_chinh AND g.ps = s.ps
                      AND g.ma_khach_hang = coalesce(s.ma_khach_hang, '')
                      AND g.nhom_san_pham = coalesce(s.nhom_san_pham, ''))
    AND NOT EXISTS (SELECT 1 FROM gia_co_quota p
                    WHERE p.nam_tai_chinh = s.nam_tai_chinh AND p.ps = s.ps
                      AND p.ma_khach_hang = coalesce(s.ma_khach_hang, '')
                      AND p.nhom_san_pham = coalesce(s.nhom_san_pham, '')
                      AND p.bo_vat_tu = coalesce(s.bo_vat_tu, '')
                      AND p.san_pham = coalesce(s.san_pham, '')
                      AND p.don_gia = coalesce(s.don_gia, 0))
),
cu AS (
  SELECT s.nam_tai_chinh, min(s.bu) AS bu, min(s.mien) AS mien, s.ps,
         coalesce(s.ma_khach_hang, '') AS ma_khach_hang, min(s.khach_hang) AS khach_hang,
         coalesce(s.nhom_san_pham, '') AS nhom_san_pham, coalesce(s.bo_vat_tu, '') AS bo_vat_tu,
         coalesce(s.san_pham, '') AS san_pham, coalesce(s.don_gia, 0) AS don_gia,
         x.loai, NULL::int AS dot, x.thang AS thang_thau, sum(x.sl) AS so_luong,
         'sale_target (cột cũ)'::text AS nguon, NULL::text AS canh_bao, NULL::numeric AS hieu_luc
  FROM cu_raw s
  CROSS JOIN LATERAL (VALUES
    ('cu',      NULL::text,                                     coalesce(s.quota_thau_cu_con_lai, 0)),
    ('chinh',   shared.thang_thau_hop_le(s.thang_thau_chinh),   coalesce(s.quota_thau_chinh, 0)),
    ('bo_sung', shared.thang_thau_hop_le(s.thang_thau_bo_sung), coalesce(s.quota_bo_sung, 0))
  ) x(loai, thang, sl)
  WHERE x.sl <> 0
  GROUP BY s.nam_tai_chinh, s.ps, coalesce(s.ma_khach_hang, ''), coalesce(s.nhom_san_pham, ''),
           coalesce(s.bo_vat_tu, ''), coalesce(s.san_pham, ''), coalesce(s.don_gia, 0),
           x.loai, x.thang
)
SELECT
  -- stt duy nhất và ổn định để edge function phân trang theo .order('stt').
  row_number() OVER (ORDER BY u.nam_tai_chinh, u.bu, u.ps, u.ma_khach_hang, u.nhom_san_pham,
                              u.bo_vat_tu, u.san_pham, u.don_gia, u.loai, u.dot,
                              u.thang_thau, u.nguon) AS stt,
  u.nam_tai_chinh, u.bu, u.mien, u.ps, u.ma_khach_hang, u.khach_hang, u.nhom_san_pham,
  u.bo_vat_tu, u.san_pham, u.don_gia, u.loai, u.dot, u.thang_thau, u.so_luong, u.nguon,
  CASE WHEN u.bu = 'test' THEN 'Dữ liệu demo (BU test)' ELSE u.canh_bao END AS canh_bao,
  u.so_luong * u.don_gia AS thanh_tien,
  CASE WHEN u.loai = 'cu' THEN 'On hand'
       WHEN u.thang_thau IS NULL OR u.hieu_luc IS NULL OR u.hieu_luc <= 0 OR u.thang_thau > cur.thang THEN 'Upcoming'
       WHEN shared.het_han_dot(u.thang_thau, u.hieu_luc) < cur.thang THEN 'Hết hiệu lực'
       ELSE 'On hand' END AS trang_thai,
  u.hieu_luc,
  shared.het_han_dot(u.thang_thau, u.hieu_luc) AS het_han
FROM (SELECT * FROM moi UNION ALL SELECT * FROM cu) u
LEFT JOIN cur ON true;

COMMENT ON VIEW shared.v_quota_thau_xuat IS
  'Quota thầu gộp quota_thau + cột cũ sale_target, theo SP × mức giá × loại × đợt. Chỉ admin (qua edge function).';

REVOKE ALL ON shared.v_quota_thau_xuat FROM PUBLIC, anon, authenticated, service_role;
GRANT SELECT ON shared.v_quota_thau_xuat TO service_role;

REVOKE ALL ON FUNCTION public.upsert_dot_thau(jsonb, text, text, text, text[], text) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.upsert_dot_thau(jsonb, text, text, text, text[], text) TO service_role;
REVOKE ALL ON FUNCTION public.upsert_quota_thau(jsonb, text, text, text, text[], text) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.upsert_quota_thau(jsonb, text, text, text, text[], text) TO service_role;
REVOKE ALL ON FUNCTION public.duyet_dot_thau(bigint[], boolean, text) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.duyet_dot_thau(bigint[], boolean, text) TO service_role;

COMMIT;
