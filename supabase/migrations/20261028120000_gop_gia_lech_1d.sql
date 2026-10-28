-- Gộp các mức đơn giá chỉ lệch 1–2đ của cùng một sản phẩm (FY26, dòng kế hoạch).
--
-- Sau 20261028110000 (làm tròn) vẫn còn 5 SP tách 2 mức giá nguyên lệch 1đ do chia
-- 1.1 / 1.05 ở các lần nhập khác nhau, vd "Đầu đốt RF" 7333333 / 7333334,
-- "Tay dao hàn mạch" 19090909 / 19090910.
-- User chốt 28/10: gộp về mức giá có nhiều dòng kế hoạch hơn; hoà thì giá thấp hơn.
--
-- Dòng cùng KH × tháng về cùng khoá → hoãn uq_sale_target_khoa, gộp bằng
-- gop_dong_trung_sale_target (cộng SL / DThu). Quota đi theo khoá mới nhờ
-- trg_sale_target_giu_khoa_quota; quota trigger để lại vì khoá đích đã có cùng
-- loại × đợt thì cộng vào quota đích (như 20261028100000).
-- Hoàn tác: supabase/rollbacks/20261028120000_gop_gia_lech_1d_ROLLBACK.sql

BEGIN;

CREATE TABLE backup.gop_gia_lech_1d_20261028 AS
WITH g AS (
  SELECT nam_tai_chinh, nhom_san_pham, san_pham, don_gia, count(*) AS n
  FROM shared.sale_target
  WHERE nam_tai_chinh = 'FY26' AND NOT coalesce(ngoai_ke_hoach, false)
  GROUP BY 1, 2, 3, 4)
SELECT DISTINCT ON (a.nam_tai_chinh, a.nhom_san_pham, a.san_pham, a.don_gia)
       a.nam_tai_chinh, a.nhom_san_pham, a.san_pham, a.don_gia AS gia_cu, b.don_gia AS gia_moi,
       a.n AS dong_cu, b.n AS dong_moi
FROM g a
JOIN g b ON b.nam_tai_chinh = a.nam_tai_chinh AND b.nhom_san_pham = a.nhom_san_pham
        AND b.san_pham = a.san_pham AND b.don_gia <> a.don_gia
        AND abs(b.don_gia - a.don_gia) <= 2
        AND (b.n > a.n OR (b.n = a.n AND b.don_gia < a.don_gia))
ORDER BY a.nam_tai_chinh, a.nhom_san_pham, a.san_pham, a.don_gia, b.n DESC, b.don_gia;
ALTER TABLE backup.gop_gia_lech_1d_20261028 ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON backup.gop_gia_lech_1d_20261028 FROM PUBLIC, anon, authenticated;

CREATE TABLE backup.bak_20261028_gop_gia_sale_target AS
SELECT s.* FROM shared.sale_target s
JOIN backup.gop_gia_lech_1d_20261028 m
  ON m.nam_tai_chinh = s.nam_tai_chinh AND m.nhom_san_pham = s.nhom_san_pham
 AND m.san_pham = s.san_pham AND s.don_gia IN (m.gia_cu, m.gia_moi)
WHERE NOT coalesce(s.ngoai_ke_hoach, false);
ALTER TABLE backup.bak_20261028_gop_gia_sale_target ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON backup.bak_20261028_gop_gia_sale_target FROM PUBLIC, anon, authenticated;

CREATE TABLE backup.bak_20261028_gop_gia_quota_thau AS
SELECT q.* FROM shared.quota_thau q
JOIN backup.gop_gia_lech_1d_20261028 m
  ON m.nam_tai_chinh = q.nam_tai_chinh AND m.nhom_san_pham = q.nhom_san_pham
 AND m.san_pham = q.san_pham AND q.don_gia IN (m.gia_cu, m.gia_moi);
ALTER TABLE backup.bak_20261028_gop_gia_quota_thau ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON backup.bak_20261028_gop_gia_quota_thau FROM PUBLIC, anon, authenticated;

SET CONSTRAINTS shared.uq_sale_target_khoa DEFERRED;

CREATE TEMP TABLE _doi_gia ON COMMIT DROP AS
WITH u AS (
  UPDATE shared.sale_target s SET don_gia = m.gia_moi, updated_at = now()
  FROM backup.gop_gia_lech_1d_20261028 m
  WHERE m.nam_tai_chinh = s.nam_tai_chinh AND m.nhom_san_pham = s.nhom_san_pham
    AND m.san_pham = s.san_pham AND s.don_gia = m.gia_cu
    AND NOT coalesce(s.ngoai_ke_hoach, false)
  RETURNING s.id
)
SELECT id FROM u;

SELECT shared.gop_dong_trung_sale_target((SELECT array_agg(id) FROM _doi_gia));

SET CONSTRAINTS shared.uq_sale_target_khoa IMMEDIATE;

-- Quota ở giá cũ mà khoá cũ đã hết dòng kế hoạch: cộng vào quota đích cùng loại × đợt,
-- chưa có đích thì đổi giá.
CREATE TEMP TABLE _q_con ON COMMIT DROP AS
SELECT q.id, q.so_luong, m.gia_moi
FROM shared.quota_thau q
JOIN backup.gop_gia_lech_1d_20261028 m
  ON m.nam_tai_chinh = q.nam_tai_chinh AND m.nhom_san_pham = q.nhom_san_pham
 AND m.san_pham = q.san_pham AND q.don_gia = m.gia_cu
WHERE EXISTS (SELECT 1 FROM backup.bak_20261028_gop_gia_sale_target s
              WHERE s.nam_tai_chinh = q.nam_tai_chinh AND s.ps = q.ps
                AND s.ma_khach_hang = q.ma_khach_hang AND s.nhom_san_pham = q.nhom_san_pham
                AND s.bo_vat_tu = q.bo_vat_tu AND s.san_pham = q.san_pham
                AND s.don_gia = q.don_gia)
  AND NOT EXISTS (SELECT 1 FROM shared.sale_target s
                  WHERE s.nam_tai_chinh = q.nam_tai_chinh AND s.ps = q.ps
                    AND s.ma_khach_hang = q.ma_khach_hang AND s.nhom_san_pham = q.nhom_san_pham
                    AND s.bo_vat_tu = q.bo_vat_tu AND s.san_pham = q.san_pham
                    AND s.don_gia = q.don_gia AND NOT coalesce(s.ngoai_ke_hoach, false));

CREATE TEMP TABLE _q_dich ON COMMIT DROP AS
SELECT c.id, d.id AS dich_id, c.so_luong
FROM _q_con c
JOIN shared.quota_thau q ON q.id = c.id
JOIN shared.quota_thau d
  ON d.nam_tai_chinh = q.nam_tai_chinh AND d.ps = q.ps AND d.ma_khach_hang = q.ma_khach_hang
 AND d.nhom_san_pham = q.nhom_san_pham AND d.bo_vat_tu = q.bo_vat_tu
 AND d.san_pham = q.san_pham AND d.don_gia = c.gia_moi
 AND d.loai = q.loai AND d.dot IS NOT DISTINCT FROM q.dot;

INSERT INTO shared.quota_chuan_hoa_log (buoc, bang, ban_ghi_id, truoc, sau)
SELECT 'gop_gia_lech_1d_cong_quota', 'quota_thau', q.id, to_jsonb(q), jsonb_build_object('cong_vao', g.dich_id)
FROM _q_dich g JOIN shared.quota_thau q ON q.id = g.id;

UPDATE shared.quota_thau d SET so_luong = d.so_luong + t.sl, updated_at = now()
FROM (SELECT dich_id, sum(so_luong) AS sl FROM _q_dich GROUP BY 1) t
WHERE d.id = t.dich_id;

DELETE FROM shared.quota_thau WHERE id IN (SELECT id FROM _q_dich);

INSERT INTO shared.quota_chuan_hoa_log (buoc, bang, ban_ghi_id, truoc, sau)
SELECT 'gop_gia_lech_1d_chuyen_quota', 'quota_thau', q.id, to_jsonb(q), jsonb_build_object('don_gia', c.gia_moi)
FROM _q_con c JOIN shared.quota_thau q ON q.id = c.id
WHERE c.id NOT IN (SELECT id FROM _q_dich);

UPDATE shared.quota_thau q SET don_gia = c.gia_moi, updated_at = now()
FROM _q_con c
WHERE q.id = c.id AND c.id NOT IN (SELECT id FROM _q_dich);

COMMIT;
