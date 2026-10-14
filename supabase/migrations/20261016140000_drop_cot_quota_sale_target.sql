-- P6 chuẩn hoá quota: bỏ hẳn 6 cột quota / tháng / thời gian thầu khỏi sale_target.
-- Quota chỉ còn ở shared.quota_thau / shared.dot_thau (dữ liệu cũ đã chuyển ở các
-- migration 202610141*/2026101512*, giá trị cột cũ lưu ở bak_20261014_sale_target_quota
-- và bak_20261015_sale_target_quota).
-- Áp SAU khi edge function đã deploy bản bỏ 6 trường khỏi FIELDS / COL (nếu không,
-- getData chọn cột không còn tồn tại → app không tải được dữ liệu).
--   * Drop trigger chặn ghi 6 cột (cột không còn thì không cần chặn).
--   * Dựng lại v_quota_thau_xuat không còn nhánh "sale_target (cột cũ)" (đã rỗng) và
--     không dùng SELECT * trên sale_target.
--   * DROP COLUMN 6 cột.

BEGIN;

DROP TRIGGER IF EXISTS trg_sale_target_chan_cot_quota ON shared.sale_target;
DROP FUNCTION IF EXISTS shared.chan_ghi_cot_quota_sale_target();

CREATE OR REPLACE VIEW shared.v_quota_thau_xuat
WITH (security_invoker = true) AS
WITH
cur AS (
  SELECT value #>> '{}' AS thang FROM shared.app_config WHERE key = 'current_month'
),
ke_hoach AS (  -- liệt kê cột: SELECT * làm view phụ thuộc mọi cột của sale_target
  SELECT nam_tai_chinh, ps, ma_khach_hang, nhom_san_pham, bo_vat_tu, san_pham, don_gia, ma_san_pham
  FROM shared.sale_target
  WHERE nam_tai_chinh IS NOT NULL AND NOT coalesce(ngoai_ke_hoach, false)
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
FROM moi u
LEFT JOIN cur ON true;

COMMENT ON VIEW shared.v_quota_thau_xuat IS
  'Quota thầu (shared.quota_thau) theo SP × mức giá × loại × đợt, kèm cảnh báo khớp kế hoạch và trạng thái hiệu lực. Chỉ admin (qua edge function).';

REVOKE ALL ON shared.v_quota_thau_xuat FROM PUBLIC, anon, authenticated, service_role;
GRANT SELECT ON shared.v_quota_thau_xuat TO service_role;

ALTER TABLE shared.sale_target
  DROP COLUMN quota_thau_cu_con_lai,
  DROP COLUMN thang_thau_chinh,
  DROP COLUMN thoi_gian_thau_chinh,
  DROP COLUMN quota_thau_chinh,
  DROP COLUMN thang_thau_bo_sung,
  DROP COLUMN quota_bo_sung;

COMMIT;
