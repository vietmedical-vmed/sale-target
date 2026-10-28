-- Hoàn tác 20261028120000_gop_gia_lech_1d.sql
-- Trả các dòng kế hoạch / quota của 5 SP về bản chụp trước khi gộp giá.

BEGIN;

DELETE FROM shared.sale_target s
USING backup.gop_gia_lech_1d_20261028 m
WHERE m.nam_tai_chinh = s.nam_tai_chinh AND m.nhom_san_pham = s.nhom_san_pham
  AND m.san_pham = s.san_pham AND s.don_gia IN (m.gia_cu, m.gia_moi)
  AND NOT coalesce(s.ngoai_ke_hoach, false);
INSERT INTO shared.sale_target SELECT * FROM backup.bak_20261028_gop_gia_sale_target;

DELETE FROM shared.quota_thau q
USING backup.gop_gia_lech_1d_20261028 m
WHERE m.nam_tai_chinh = q.nam_tai_chinh AND m.nhom_san_pham = q.nhom_san_pham
  AND m.san_pham = q.san_pham AND q.don_gia IN (m.gia_cu, m.gia_moi);
INSERT INTO shared.quota_thau SELECT * FROM backup.bak_20261028_gop_gia_quota_thau;

COMMIT;
