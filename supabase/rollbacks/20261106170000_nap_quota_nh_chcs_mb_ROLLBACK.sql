-- Rollback 20261106170000_nap_quota_nh_chcs_mb.sql: xoá quota đã nạp từ file ngành hàng CH&CS Miền Bắc (06/11/2026).
-- Chỉ xoá dòng còn nguon = 'nh_mb_20261106'. Dòng đã bị trigger chuyển khoá vẫn giữ nguon nên cũng bị xoá.
BEGIN;
WITH del AS (
  DELETE FROM shared.quota_thau WHERE nguon = 'nh_mb_20261106' RETURNING *
)
INSERT INTO shared.quota_chuan_hoa_log (buoc, bang, ban_ghi_id, truoc, sau)
SELECT 'nap_nh_mb_20261106_rollback', 'quota_thau', d.id, to_jsonb(d), NULL FROM del d;
COMMIT;
