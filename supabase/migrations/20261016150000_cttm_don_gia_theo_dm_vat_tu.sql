-- Đơn giá kế hoạch BU CTTM & CTUT (FY26) lấy theo danh mục vật tư:
-- sale_target.don_gia := dm_vat_tu.don_gia_thau_moi (giữ nguyên, không trừ VAT).
-- User chốt 15/10: ghi đè MỌI dòng kế hoạch, kể cả SP đang có giá riêng theo bệnh viện.
--
-- Khớp SP với danh mục (chỉ dm_vat_tu.bu_code = 'cttm', don_gia_thau_moi > 0):
--   1. theo tên SP (mỗi tên CTTM chỉ có 1 giá thầu mới);
--   2. không có tên → theo mã SP (bỏ 'Chưa có'), chỉ khi mã ra đúng 1 giá;
--   3. vẫn không có → tên so không phân biệt hoa thường.
-- Không đổi: dòng ngoài kế hoạch (OOP, giá theo hoá đơn), SP không có trong danh mục.
--
-- Quota thầu đi theo khoá mới nhờ trg_sale_target_giu_khoa_quota (20261015150000).
-- Khoá giá mới có sẵn quota mồ côi (không còn dòng sale_target nào, app không hiện)
-- cùng loại/đợt → xoá bản mồ côi trước để quota ĐANG HIỆN được chuyển sang
-- (nguyên tắc "giữ số đang hiện"). Bản xoá ghi ở quota_chuan_hoa_log
-- (buoc 'cttm_don_gia_xoa_mo_coi') và còn trong bak_20261016_cttm_quota_thau.
-- Dry-run 15/10: 11 bản mồ côi bị xoá (BV0074 khác số, user chốt giữ bản đang hiện);
-- 6 quota import KHKD_280926 đang ẩn vì lệch giá sẽ tự hiện (user đồng ý).
-- Hoàn tác: supabase/rollbacks/20261016150000_cttm_don_gia_theo_dm_vat_tu_ROLLBACK.sql

BEGIN;

CREATE TABLE shared.bak_20261016_cttm_don_gia AS
SELECT id, nam_tai_chinh, bu, ps, ma_khach_hang, nhom_san_pham, bo_vat_tu, san_pham, ma_san_pham,
       thang_ke_hoach, don_gia
FROM shared.sale_target
WHERE nam_tai_chinh = 'FY26' AND bu = 'cttm';
ALTER TABLE shared.bak_20261016_cttm_don_gia ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON shared.bak_20261016_cttm_don_gia FROM PUBLIC, anon, authenticated;

CREATE TABLE shared.bak_20261016_cttm_quota_thau AS
SELECT * FROM shared.quota_thau;
ALTER TABLE shared.bak_20261016_cttm_quota_thau ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON shared.bak_20261016_cttm_quota_thau FROM PUBLIC, anon, authenticated;

CREATE TEMP TABLE _cttm_gia ON COMMIT DROP AS
WITH v AS (
  SELECT san_pham, nullif(nullif(trim(ma_san_pham), ''), 'Chưa có') AS ma, don_gia_thau_moi AS g
  FROM shared.dm_vat_tu
  WHERE bu_code = 'cttm' AND don_gia_thau_moi > 0
), theo_ten AS (
  SELECT san_pham, min(g) g FROM v GROUP BY 1 HAVING count(DISTINCT g) = 1
), theo_ma AS (
  SELECT ma, min(g) g FROM v WHERE ma IS NOT NULL GROUP BY 1 HAVING count(DISTINCT g) = 1
), theo_ten_thuong AS (
  SELECT lower(trim(san_pham)) ten, min(g) g FROM v GROUP BY 1 HAVING count(DISTINCT g) = 1
)
SELECT s.id, s.nam_tai_chinh, s.ps, s.ma_khach_hang, s.nhom_san_pham, s.bo_vat_tu, s.san_pham,
       coalesce(s.don_gia, 0) AS gia_cu,
       coalesce(t.g, m.g, tt.g) AS gia_moi
FROM shared.sale_target s
LEFT JOIN theo_ten t ON t.san_pham = s.san_pham
LEFT JOIN theo_ma m ON m.ma = nullif(nullif(trim(s.ma_san_pham), ''), 'Chưa có')
LEFT JOIN theo_ten_thuong tt ON tt.ten = lower(trim(s.san_pham))
WHERE s.nam_tai_chinh = 'FY26' AND s.bu = 'cttm'
  AND NOT coalesce(s.ngoai_ke_hoach, false);

DELETE FROM _cttm_gia WHERE gia_moi IS NULL OR gia_moi = gia_cu;

-- Quota mồ côi đang nằm sẵn ở khoá giá mới, trùng loại/đợt với quota sẽ chuyển tới.
CREATE TEMP TABLE _cttm_mo_coi ON COMMIT DROP AS
SELECT DISTINCT d.id
FROM (SELECT DISTINCT nam_tai_chinh, ps, ma_khach_hang, nhom_san_pham, bo_vat_tu, san_pham, gia_cu, gia_moi
      FROM _cttm_gia) k
JOIN shared.quota_thau q
  ON q.nam_tai_chinh = k.nam_tai_chinh AND q.ps = k.ps AND q.ma_khach_hang = k.ma_khach_hang
 AND q.nhom_san_pham = k.nhom_san_pham AND q.bo_vat_tu = k.bo_vat_tu AND q.san_pham = k.san_pham
 AND q.don_gia = k.gia_cu
JOIN shared.quota_thau d
  ON d.nam_tai_chinh = k.nam_tai_chinh AND d.ps = k.ps AND d.ma_khach_hang = k.ma_khach_hang
 AND d.nhom_san_pham = k.nhom_san_pham AND d.bo_vat_tu = k.bo_vat_tu AND d.san_pham = k.san_pham
 AND d.don_gia = k.gia_moi AND d.loai = q.loai AND d.dot = q.dot
WHERE NOT EXISTS (
  SELECT 1 FROM shared.sale_target s
  WHERE s.nam_tai_chinh = d.nam_tai_chinh AND s.ps = d.ps AND s.ma_khach_hang = d.ma_khach_hang
    AND s.nhom_san_pham = d.nhom_san_pham AND s.bo_vat_tu = d.bo_vat_tu AND s.san_pham = d.san_pham
    AND coalesce(s.don_gia, 0) = d.don_gia);

INSERT INTO shared.quota_chuan_hoa_log (buoc, bang, ban_ghi_id, truoc, sau)
SELECT 'cttm_don_gia_xoa_mo_coi', 'quota_thau', q.id, to_jsonb(q), NULL
FROM shared.quota_thau q WHERE q.id IN (SELECT id FROM _cttm_mo_coi);

DELETE FROM shared.quota_thau WHERE id IN (SELECT id FROM _cttm_mo_coi);

UPDATE shared.sale_target s
SET don_gia = g.gia_moi
FROM _cttm_gia g
WHERE s.id = g.id;

COMMIT;
