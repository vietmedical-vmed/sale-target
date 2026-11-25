-- Rollback 20261109210000: trả SL 80 cho quota 7180 (chỉ khi vẫn đang 40).
BEGIN;
UPDATE shared.quota_thau SET so_luong = 80, updated_at = now(), updated_by = 'sua_cong_trung_tightrope_20261109_rollback'
WHERE id = 7180 AND so_luong = 40;
COMMIT;
