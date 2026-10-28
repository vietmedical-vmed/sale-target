-- Điền mã SP cho dòng kế hoạch FY26 đang "Chưa có", theo danh mục sau khi chuẩn tên / giá.
--
-- 28/10: 8.277 dòng kế hoạch thiếu mã (THNK 100% vì danh mục mới, CH&CS, CTTM) dù danh
-- mục đã có mã. Mỗi (KH, nhóm, SP, đơn giá) chọn 1 mã:
--   1. 'ten'   SP (tên chuẩn hoá, cùng nhóm) chỉ có 1 mã hợp lệ trong dm_vat_tu.
--   2. 'gia'   nhiều mã, đúng 1 mã có vật tư khớp đơn giá (±2đ, thầu mới / thầu cũ,
--              có hoặc không chia 1.05).
--   3. 'bo'    SP không có trong dm_vat_tu mà là bộ gộp → dm_bo_vat_tu.ma_bo_vat_tu (1 mã).
--   4. nhiều mã cùng giá (hoặc không mã nào khớp giá) → mã KH đó mua nhiều nhất theo
--      hoá đơn ('hd_kh'), KH chưa mua → mã xuất hoá đơn nhiều nhất của SP ('hd_tong')
--      (user chốt 28/10). Không có hoá đơn → để "Chưa có".
-- Hoá đơn → mã qua hoa_don_bovattu.ma_vat_tu = dm_vat_tu.ma_bravo, đếm theo SL.
-- SP mà danh mục cũng chưa có mã (vd Bipolar dài - UOC, Rotaglide) để nguyên.
-- Mã quota_thau cùng khoá đổi theo nhờ trg_sale_target_ma_sp_quota.
-- Bảng chọn mã lưu ở backup.dien_ma_sp_20261028.
-- Hoàn tác: supabase/rollbacks/20261028130000_dien_ma_san_pham_chua_co_ROLLBACK.sql

BEGIN;

CREATE TABLE backup.bak_20261028_ma_chua_co AS
SELECT id, ma_san_pham, ma_khach_hang, nhom_san_pham, san_pham, don_gia
FROM shared.sale_target
WHERE nam_tai_chinh = 'FY26' AND NOT coalesce(ngoai_ke_hoach, false)
  AND shared.ma_sp_hop_le(ma_san_pham) IS NULL;
ALTER TABLE backup.bak_20261028_ma_chua_co ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON backup.bak_20261028_ma_chua_co FROM PUBLIC, anon, authenticated;

CREATE TABLE backup.bak_20261028_ma_chua_co_quota AS
SELECT id, ma_san_pham FROM shared.quota_thau WHERE nam_tai_chinh = 'FY26';
ALTER TABLE backup.bak_20261028_ma_chua_co_quota ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON backup.bak_20261028_ma_chua_co_quota FROM PUBLIC, anon, authenticated;

CREATE TABLE backup.dien_ma_sp_20261028 AS
WITH p AS (
  SELECT DISTINCT ma_khach_hang AS kh, nhom_san_pham AS nhom, san_pham AS sp, coalesce(don_gia, 0) AS g
  FROM shared.sale_target
  WHERE nam_tai_chinh = 'FY26' AND NOT coalesce(ngoai_ke_hoach, false)
    AND shared.ma_sp_hop_le(ma_san_pham) IS NULL),
sp AS (SELECT DISTINCT nhom, sp, g FROM p),
v AS (
  SELECT nhom_san_pham AS nhom, shared.ten_sp_chuan(san_pham) AS ten, ma_bravo,
         shared.ma_sp_hop_le(ma_san_pham) AS ma, don_gia_thau_moi, don_gia_thau_cu
  FROM shared.dm_vat_tu
  WHERE shared.ma_sp_hop_le(ma_san_pham) IS NOT NULL),
c AS (
  SELECT sp.*,
    (SELECT array_agg(DISTINCT v.ma) FROM v
      WHERE v.nhom = sp.nhom AND v.ten = shared.ten_sp_chuan(sp.sp)) AS ma_ten,
    (SELECT array_agg(DISTINCT v.ma) FROM v
      WHERE v.nhom = sp.nhom AND v.ten = shared.ten_sp_chuan(sp.sp)
        AND EXISTS (SELECT 1 FROM unnest(ARRAY[v.don_gia_thau_moi, v.don_gia_thau_cu,
                                               round(v.don_gia_thau_moi / 1.05),
                                               round(v.don_gia_thau_cu / 1.05)]) x
                    WHERE abs(x - sp.g) <= 2)) AS ma_gia,
    (SELECT CASE WHEN count(DISTINCT b.ma_bo_vat_tu) = 1 THEN min(b.ma_bo_vat_tu) END
       FROM shared.dm_bo_vat_tu b
      WHERE b.nhom_san_pham = sp.nhom AND shared.ten_sp_chuan(b.bo_vat_tu) = shared.ten_sp_chuan(sp.sp)
        AND nullif(btrim(b.ma_bo_vat_tu), '') IS NOT NULL) AS ma_bo
  FROM sp),
hd AS (
  SELECT h.ma_kh AS kh, v.nhom, v.ten, v.ma, sum(h.so_luong) AS sl
  FROM app_sale.hoa_don_bovattu h JOIN v ON v.ma_bravo = h.ma_vat_tu
  GROUP BY 1, 2, 3, 4),
k AS (
  SELECT p.kh, c.*,
    CASE WHEN cardinality(c.ma_gia) >= 1 THEN c.ma_gia ELSE c.ma_ten END AS pool
  FROM p JOIN c ON c.nhom = p.nhom AND c.sp = p.sp AND c.g = p.g)
SELECT kh AS ma_khach_hang, nhom AS nhom_san_pham, sp AS san_pham, g AS don_gia,
  coalesce(
    CASE WHEN cardinality(ma_ten) = 1 THEN ma_ten[1] END,
    CASE WHEN cardinality(ma_gia) = 1 THEN ma_gia[1] END,
    CASE WHEN ma_ten IS NULL THEN ma_bo END,
    (SELECT hd.ma FROM hd WHERE hd.kh = k.kh AND hd.nhom = k.nhom AND hd.ten = shared.ten_sp_chuan(k.sp)
        AND hd.ma = ANY(k.pool) AND hd.sl > 0 ORDER BY hd.sl DESC, hd.ma LIMIT 1),
    (SELECT hd.ma FROM hd WHERE hd.nhom = k.nhom AND hd.ten = shared.ten_sp_chuan(k.sp)
        AND hd.ma = ANY(k.pool) GROUP BY hd.ma HAVING sum(hd.sl) > 0
      ORDER BY sum(hd.sl) DESC, hd.ma LIMIT 1)) AS ma_moi,
  CASE WHEN cardinality(ma_ten) = 1 THEN 'ten'
       WHEN cardinality(ma_gia) = 1 THEN 'gia'
       WHEN ma_ten IS NULL AND ma_bo IS NOT NULL THEN 'bo'
       WHEN EXISTS (SELECT 1 FROM hd WHERE hd.kh = k.kh AND hd.nhom = k.nhom AND hd.ten = shared.ten_sp_chuan(k.sp)
                      AND hd.ma = ANY(k.pool) AND hd.sl > 0) THEN 'hd_kh'
       WHEN cardinality(pool) >= 1 THEN 'hd_tong'
       ELSE 'khong_co' END AS cach,
  ma_ten AS ung_vien
FROM k;
ALTER TABLE backup.dien_ma_sp_20261028 ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON backup.dien_ma_sp_20261028 FROM PUBLIC, anon, authenticated;

SET CONSTRAINTS shared.uq_sale_target_khoa DEFERRED;

CREATE TEMP TABLE _dien_ma ON COMMIT DROP AS
WITH u AS (
  UPDATE shared.sale_target s SET ma_san_pham = m.ma_moi, updated_at = now()
  FROM backup.dien_ma_sp_20261028 m
  WHERE s.nam_tai_chinh = 'FY26' AND NOT coalesce(s.ngoai_ke_hoach, false)
    AND shared.ma_sp_hop_le(s.ma_san_pham) IS NULL
    AND m.ma_khach_hang = s.ma_khach_hang AND m.nhom_san_pham = s.nhom_san_pham
    AND m.san_pham = s.san_pham AND m.don_gia = coalesce(s.don_gia, 0)
    AND m.ma_moi IS NOT NULL
  RETURNING s.id
)
SELECT id FROM u;

SELECT shared.gop_dong_trung_sale_target((SELECT array_agg(id) FROM _dien_ma));

SET CONSTRAINTS shared.uq_sale_target_khoa IMMEDIATE;

COMMIT;
