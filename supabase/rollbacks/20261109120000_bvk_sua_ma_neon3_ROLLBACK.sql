-- Rollback 20261109120000_bvk_sua_ma_neon3.sql: trả mã CS91 cho dòng "Vít cổ sau Neon3" của BV K.
BEGIN;
SET CONSTRAINTS shared.uq_sale_target_khoa DEFERRED;
UPDATE shared.sale_target s SET ma_san_pham = 'CS91', updated_at = now()
FROM shared.quota_chuan_hoa_log l
WHERE l.buoc = 'bvk_sua_ma_neon3_20261109' AND l.bang = 'sale_target' AND s.id = l.ban_ghi_id AND s.ma_san_pham = 'CS 390x';
UPDATE shared.quota_thau q SET ma_san_pham = 'CS91', updated_at = now(), updated_by = 'bvk_sua_ma_neon3_20261109_rollback'
FROM shared.quota_chuan_hoa_log l
WHERE l.buoc = 'bvk_sua_ma_neon3_20261109' AND l.bang = 'quota_thau' AND q.id = l.ban_ghi_id AND q.ma_san_pham = 'CS 390x';
SET CONSTRAINTS shared.uq_sale_target_khoa IMMEDIATE;
COMMIT;
