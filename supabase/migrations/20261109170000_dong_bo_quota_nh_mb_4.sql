-- Đồng bộ quota thầu CH&CS Miền Bắc theo file ngành hàng bản 09/11/2026 (user chốt 09/11), buoc 'dong_bo_nh_mb_20261109d':
--   0. Sửa tháng thầu 0 đợt + chuyển 0 quota sang đợt đúng on hand/upcoming theo file.
--   1. Thêm 0 đợt thầu thiếu, tháng thầu = tháng "Ngày ký" trong file, hiệu lực = số tháng từ ngày ký
--      tới ngày hết hạn (chỉ đợt đã trúng; riêng VĐ Ulrich thêm đợt dự kiến 2027-03 theo file).
--   2. Sửa quota trên khoá kế hoạch đã có: 1 dòng đổi SL, 0 dòng xoá (SL file = 0 ở loại/đợt đó),
--      0 dòng thêm (loại/đợt file có mà HT chưa có). VĐ Ulrich giữ PS Mậu Cao; ĐHY HN gối U2 theo file.
--   3. Thêm 0 sản phẩm vào kế hoạch FY26 của PS (12 tháng, SL 0, hấp thụ dòng OOP cùng khoá như "Thêm sản phẩm"),
--      rồi nạp quota cho các sản phẩm đó.
-- File NH bỏ 4 dòng trùng BV K (dòng 52, 151, 287, 303). Log: shared.quota_chuan_hoa_log buoc 'dong_bo_nh_mb_20261109d'.
-- Rollback: supabase/rollbacks/20261109170000_dong_bo_quota_nh_mb_4_ROLLBACK.sql
BEGIN;
SET CONSTRAINTS shared.uq_sale_target_khoa DEFERRED;

CREATE TEMP TABLE _dot_moi (ps text, kh text, nhom text, loai text, dot int, thang text, hl numeric) ON COMMIT DROP;

CREATE TEMP TABLE _upd (id bigint, sl_cu numeric, sl_moi numeric) ON COMMIT DROP;
INSERT INTO _upd VALUES
  (4517, 326, 647);
CREATE TEMP TABLE _del (id bigint, sl_cu numeric) ON COMMIT DROP;

CREATE TEMP TABLE _ins (ps text, kh text, nhom text, bvt text, sp text, gia numeric, loai text, dot int, sl numeric, ma text, dong text) ON COMMIT DROP;

CREATE TEMP TABLE _sp (ps text, kh text, khach_hang text, mien text, bu text, nhom text, bvt text, sp text, ma_sp text, ma_bvt text, gia numeric) ON COMMIT DROP;


CREATE TEMP TABLE _mv (id bigint, dot_cu int, dot_moi int) ON COMMIT DROP;

CREATE TEMP TABLE _dot_sua (ps text, kh text, nhom text, loai text, dot int, thang_cu text, thang_moi text) ON COMMIT DROP;


DO $$
DECLARE v_n int;
BEGIN
  -- đợt mới chưa tồn tại
  SELECT count(*) INTO v_n FROM _dot_moi m JOIN shared.dot_thau d
    ON d.nam_tai_chinh = 'FY26' AND d.ps = m.ps AND d.ma_khach_hang = m.kh AND d.nhom_san_pham = m.nhom AND d.loai = m.loai AND d.dot = m.dot;
  IF v_n > 0 THEN RAISE EXCEPTION 'dong_bo: % đợt mới đã tồn tại', v_n; END IF;
  -- dòng sửa / xoá còn đúng SL lúc lập kế hoạch
  SELECT count(*) INTO v_n FROM _upd u LEFT JOIN shared.quota_thau q ON q.id = u.id WHERE q.id IS NULL OR q.so_luong <> u.sl_cu;
  IF v_n > 0 THEN RAISE EXCEPTION 'dong_bo: % dòng cần sửa đã đổi từ lúc lập kế hoạch', v_n; END IF;
  SELECT count(*) INTO v_n FROM _del u LEFT JOIN shared.quota_thau q ON q.id = u.id WHERE q.id IS NULL OR q.so_luong <> u.sl_cu;
  IF v_n > 0 THEN RAISE EXCEPTION 'dong_bo: % dòng cần xoá đã đổi từ lúc lập kế hoạch', v_n; END IF;
  -- sản phẩm mới chưa có trong kế hoạch (kể cả OOP cùng giá)
  SELECT count(*) INTO v_n FROM _sp p JOIN shared.sale_target s
    ON s.nam_tai_chinh = 'FY26' AND s.ps = p.ps AND s.ma_khach_hang = p.kh AND s.nhom_san_pham = p.nhom
   AND s.bo_vat_tu = p.bvt AND s.san_pham = p.sp AND s.don_gia = p.gia AND NOT coalesce(s.ngoai_ke_hoach, false);
  IF v_n > 0 THEN RAISE EXCEPTION 'dong_bo: % sản phẩm mới đã có trong kế hoạch', v_n; END IF;
END $$;

-- 0a. sửa tháng thầu đợt
DO $$
DECLARE v_n int;
BEGIN
  SELECT count(*) INTO v_n FROM _dot_sua x LEFT JOIN shared.dot_thau d
    ON d.nam_tai_chinh = 'FY26' AND d.ps = x.ps AND d.ma_khach_hang = x.kh AND d.nhom_san_pham = x.nhom AND d.loai = x.loai AND d.dot = x.dot
  WHERE d.id IS NULL OR d.thang_thau IS DISTINCT FROM x.thang_cu;
  IF v_n > 0 THEN RAISE EXCEPTION 'dong_bo: % đợt cần sửa tháng đã đổi', v_n; END IF;
  SELECT count(*) INTO v_n FROM _mv m LEFT JOIN shared.quota_thau q ON q.id = m.id WHERE q.id IS NULL OR q.dot <> m.dot_cu;
  IF v_n > 0 THEN RAISE EXCEPTION 'dong_bo: % quota cần chuyển đợt đã đổi', v_n; END IF;
END $$;
WITH o AS (SELECT d.* FROM shared.dot_thau d JOIN _dot_sua x
             ON d.nam_tai_chinh = 'FY26' AND d.ps = x.ps AND d.ma_khach_hang = x.kh AND d.nhom_san_pham = x.nhom AND d.loai = x.loai AND d.dot = x.dot),
u AS (UPDATE shared.dot_thau d SET thang_thau = x.thang_moi, updated_at = now(), updated_by = 'dong_bo_nh_mb_20261109d'
      FROM _dot_sua x WHERE d.nam_tai_chinh = 'FY26' AND d.ps = x.ps AND d.ma_khach_hang = x.kh AND d.nhom_san_pham = x.nhom
        AND d.loai = x.loai AND d.dot = x.dot RETURNING d.*)
INSERT INTO shared.quota_chuan_hoa_log (buoc, bang, ban_ghi_id, truoc, sau)
SELECT 'dong_bo_nh_mb_20261109d', 'dot_thau', u.id, to_jsonb(o), to_jsonb(u) FROM u JOIN o ON o.id = u.id;

-- 1. đợt mới
WITH n AS (
  INSERT INTO shared.dot_thau (nam_tai_chinh, bu, mien, ps, ma_khach_hang, nhom_san_pham, loai, dot, thang_thau, thoi_gian,
                               updated_by, trang_thai, nguon)
  SELECT 'FY26', 'chcs', 'Miền Bắc', m.ps, m.kh, m.nhom, m.loai, m.dot, m.thang, m.hl, 'dong_bo_nh_mb_20261109d', 'chinh_thuc', 'dong_bo_nh_mb_20261109d'
  FROM _dot_moi m RETURNING *)
INSERT INTO shared.quota_chuan_hoa_log (buoc, bang, ban_ghi_id, truoc, sau)
SELECT 'dong_bo_nh_mb_20261109d', 'dot_thau', n.id, NULL, to_jsonb(n) FROM n;

-- 2a. sửa SL
WITH o AS (SELECT q.* FROM shared.quota_thau q JOIN _upd u ON u.id = q.id),
u AS (UPDATE shared.quota_thau q SET so_luong = x.sl_moi, updated_at = now(), updated_by = 'dong_bo_nh_mb_20261109d'
      FROM _upd x WHERE q.id = x.id RETURNING q.*)
INSERT INTO shared.quota_chuan_hoa_log (buoc, bang, ban_ghi_id, truoc, sau)
SELECT 'dong_bo_nh_mb_20261109d', 'quota_thau', u.id, to_jsonb(o), to_jsonb(u) FROM u JOIN o ON o.id = u.id;

-- 2a'. chuyển quota sang đợt đúng (sau khi đã có đợt mới)
DO $$
DECLARE v_n int;
BEGIN
  SELECT count(*) INTO v_n FROM _mv m JOIN shared.quota_thau q ON q.id = m.id JOIN shared.quota_thau x
    ON x.nam_tai_chinh = q.nam_tai_chinh AND x.ps = q.ps AND x.ma_khach_hang = q.ma_khach_hang AND x.nhom_san_pham = q.nhom_san_pham
   AND x.bo_vat_tu = q.bo_vat_tu AND x.san_pham = q.san_pham AND x.don_gia = q.don_gia AND x.loai = q.loai AND x.dot = m.dot_moi;
  IF v_n > 0 THEN RAISE EXCEPTION 'dong_bo: % quota chuyển đợt bị trùng khoá', v_n; END IF;
END $$;
WITH o AS (SELECT q.* FROM shared.quota_thau q JOIN _mv m ON m.id = q.id),
u AS (UPDATE shared.quota_thau q SET dot = m.dot_moi, updated_at = now(), updated_by = 'dong_bo_nh_mb_20261109d'
      FROM _mv m WHERE q.id = m.id RETURNING q.*)
INSERT INTO shared.quota_chuan_hoa_log (buoc, bang, ban_ghi_id, truoc, sau)
SELECT 'dong_bo_nh_mb_20261109d', 'quota_thau', u.id, to_jsonb(o), to_jsonb(u) FROM u JOIN o ON o.id = u.id;

-- 2b. xoá
WITH d AS (DELETE FROM shared.quota_thau q USING _del x WHERE q.id = x.id RETURNING q.*)
INSERT INTO shared.quota_chuan_hoa_log (buoc, bang, ban_ghi_id, truoc, sau)
SELECT 'dong_bo_nh_mb_20261109d', 'quota_thau', d.id, to_jsonb(d), NULL FROM d;

-- 3a. sản phẩm mới vào kế hoạch (12 tháng)
CREATE TEMP TABLE _st_moi ON COMMIT DROP AS SELECT * FROM shared.sale_target WHERE false;
WITH n AS (
  INSERT INTO shared.sale_target (nam_tai_chinh, thang_ke_hoach, mien, ps, khach_hang, ma_khach_hang, nhom_san_pham, san_pham,
                                  bo_vat_tu, ma_san_pham, ma_bo_vat_tu, don_gia, bu, sl_ke_hoach_dau_nam, sl_thuc_hien)
  SELECT 'FY26', m.t, p.mien, p.ps, p.khach_hang, p.kh, p.nhom, p.sp, p.bvt, p.ma_sp, p.ma_bvt, p.gia, p.bu, 0, 0
  FROM _sp p CROSS JOIN (VALUES ('2026-04'), ('2026-05'), ('2026-06'), ('2026-07'), ('2026-08'), ('2026-09'), ('2026-10'), ('2026-11'), ('2026-12'), ('2027-01'), ('2027-02'), ('2027-03')) m(t)
  RETURNING *)
INSERT INTO _st_moi SELECT * FROM n;
INSERT INTO shared.quota_chuan_hoa_log (buoc, bang, ban_ghi_id, truoc, sau)
SELECT 'dong_bo_nh_mb_20261109d', 'sale_target', s.id, NULL, to_jsonb(s) FROM _st_moi s;

-- 3b. hấp thụ dòng OOP cùng tháng × PS × KH × bộ vật tư × SP (như absorbOop của "Thêm sản phẩm")
CREATE TEMP TABLE _oop ON COMMIT DROP AS
SELECT o.*, (SELECT min(s.id) FROM _st_moi s
             WHERE s.thang_ke_hoach = o.thang_ke_hoach AND lower(trim(s.ps)) = lower(trim(o.ps))
               AND lower(trim(s.ma_khach_hang)) = lower(trim(o.ma_khach_hang))
               AND lower(trim(s.bo_vat_tu)) = lower(trim(o.bo_vat_tu)) AND lower(trim(s.san_pham)) = lower(trim(o.san_pham))) AS dich
FROM shared.sale_target o
WHERE o.ngoai_ke_hoach AND o.ma_khach_hang IN (SELECT kh FROM _sp);
DELETE FROM _oop WHERE dich IS NULL;
INSERT INTO shared.quota_chuan_hoa_log (buoc, bang, ban_ghi_id, truoc, sau)
SELECT 'dong_bo_nh_mb_20261109d_oop', 'sale_target', o.id, to_jsonb(o) - 'dich', jsonb_build_object('hap_thu_vao', o.dich) FROM _oop o;
UPDATE shared.sale_target s SET sl_thuc_hien = a.sl, doanh_thu_thuc_hien = a.dt, updated_at = now()
FROM (SELECT dich, sum(coalesce(sl_thuc_hien, 0)) sl, sum(coalesce(doanh_thu_thuc_hien, 0)) dt FROM _oop GROUP BY dich) a
WHERE s.id = a.dich;
DELETE FROM shared.sale_target s USING _oop o WHERE s.id = o.id;

-- 2c + 3c. thêm quota
DO $$
DECLARE v_n int;
BEGIN
  SELECT count(*) INTO v_n FROM _ins n
  WHERE NOT EXISTS (SELECT 1 FROM shared.sale_target s
                    WHERE s.nam_tai_chinh = 'FY26' AND s.ps = n.ps AND s.ma_khach_hang = n.kh AND s.nhom_san_pham = n.nhom
                      AND s.bo_vat_tu = n.bvt AND s.san_pham = n.sp AND s.don_gia = n.gia AND NOT coalesce(s.ngoai_ke_hoach, false));
  IF v_n > 0 THEN RAISE EXCEPTION 'dong_bo: % quota thêm không có dòng kế hoạch', v_n; END IF;
  SELECT count(*) INTO v_n FROM _ins n JOIN shared.quota_thau q
    ON q.nam_tai_chinh = 'FY26' AND q.ps = n.ps AND q.ma_khach_hang = n.kh AND q.nhom_san_pham = n.nhom AND q.bo_vat_tu = n.bvt
   AND q.san_pham = n.sp AND q.don_gia = n.gia AND q.loai = n.loai AND q.dot = n.dot;
  IF v_n > 0 THEN RAISE EXCEPTION 'dong_bo: % quota thêm trùng khoá đang có', v_n; END IF;
  SELECT count(*) INTO v_n FROM _ins n
  WHERE n.loai <> 'cu' AND NOT EXISTS (SELECT 1 FROM shared.dot_thau d
    WHERE d.nam_tai_chinh = 'FY26' AND d.ps = n.ps AND d.ma_khach_hang = n.kh AND d.nhom_san_pham = n.nhom
      AND d.loai = n.loai AND d.dot = n.dot AND d.thang_thau IS NOT NULL AND d.thoi_gian > 0);
  IF v_n > 0 THEN RAISE EXCEPTION 'dong_bo: % quota thêm thiếu đợt hợp lệ', v_n; END IF;
END $$;
WITH i AS (
  INSERT INTO shared.quota_thau (nam_tai_chinh, ps, ma_khach_hang, nhom_san_pham, bo_vat_tu, san_pham, don_gia, loai, dot,
                                 so_luong, bu, mien, khach_hang, updated_by, trang_thai, nguon, ma_san_pham)
  SELECT 'FY26', n.ps, n.kh, n.nhom, n.bvt, n.sp, n.gia, n.loai, n.dot, n.sl, s.bu, s.mien, s.khach_hang,
         'dong_bo_nh_mb_20261109d', 'chinh_thuc', 'dong_bo_nh_mb_20261109d', n.ma
  FROM _ins n CROSS JOIN LATERAL (
    SELECT s.bu, s.mien, s.khach_hang FROM shared.sale_target s
    WHERE s.nam_tai_chinh = 'FY26' AND s.ps = n.ps AND s.ma_khach_hang = n.kh AND s.nhom_san_pham = n.nhom
      AND s.bo_vat_tu = n.bvt AND s.san_pham = n.sp AND s.don_gia = n.gia AND NOT coalesce(s.ngoai_ke_hoach, false)
    ORDER BY s.id LIMIT 1) s
  RETURNING *)
INSERT INTO shared.quota_chuan_hoa_log (buoc, bang, ban_ghi_id, truoc, sau)
SELECT 'dong_bo_nh_mb_20261109d', 'quota_thau', i.id, NULL, to_jsonb(i) FROM i;

SET CONSTRAINTS shared.uq_sale_target_khoa IMMEDIATE;
COMMIT;
