-- Hoàn tác 20261016150000: trả đơn giá CTTM FY26 và quota_thau về như trước khi ánh xạ.
-- Trả don_gia trên sale_target sẽ làm trigger giữ khoá chuyển quota ngược lại; sau đó
-- dựng lại quota_thau từ bản chụp (kể cả các quota mồ côi đã xoá) cho đúng từng dòng.

BEGIN;

UPDATE shared.sale_target s
SET don_gia = b.don_gia
FROM shared.bak_20261016_cttm_don_gia b
WHERE s.id = b.id AND s.don_gia IS DISTINCT FROM b.don_gia;

DELETE FROM shared.quota_thau q
WHERE NOT EXISTS (SELECT 1 FROM shared.bak_20261016_cttm_quota_thau b WHERE b.id = q.id);

UPDATE shared.quota_thau q
SET nam_tai_chinh = b.nam_tai_chinh, ps = b.ps, ma_khach_hang = b.ma_khach_hang,
    nhom_san_pham = b.nhom_san_pham, bo_vat_tu = b.bo_vat_tu, san_pham = b.san_pham,
    don_gia = b.don_gia, so_luong = b.so_luong, khach_hang = b.khach_hang
FROM shared.bak_20261016_cttm_quota_thau b
WHERE b.id = q.id;

INSERT INTO shared.quota_thau OVERRIDING SYSTEM VALUE
SELECT b.* FROM shared.bak_20261016_cttm_quota_thau b
WHERE NOT EXISTS (SELECT 1 FROM shared.quota_thau q WHERE q.id = b.id);

COMMIT;
