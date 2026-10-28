-- Hoàn tác 20261028130000_dien_ma_san_pham_chua_co.sql
-- Trả mã SP của dòng kế hoạch và quota FY26 về bản chụp. 60 dòng "Chưa có" đã gộp vào
-- dòng cùng khoá có mã (log quota_chuan_hoa_log buoc 'gop_dong_trung' ngày 28/10) không
-- tự tách lại; SL của chúng nằm trong dòng giữ.

BEGIN;

SET CONSTRAINTS shared.uq_sale_target_khoa DEFERRED;

UPDATE shared.sale_target s SET ma_san_pham = b.ma_san_pham, updated_at = now()
FROM backup.bak_20261028_ma_chua_co b
WHERE b.id = s.id AND s.ma_san_pham IS DISTINCT FROM b.ma_san_pham;

SET CONSTRAINTS shared.uq_sale_target_khoa IMMEDIATE;

UPDATE shared.quota_thau q SET ma_san_pham = b.ma_san_pham
FROM backup.bak_20261028_ma_chua_co_quota b
WHERE b.id = q.id AND q.ma_san_pham IS DISTINCT FROM b.ma_san_pham;

COMMIT;
