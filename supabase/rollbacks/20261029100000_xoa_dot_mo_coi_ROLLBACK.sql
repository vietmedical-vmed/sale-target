-- Hoàn tác 20261029100000_xoa_dot_mo_coi: dựng lại đợt từ quota_chuan_hoa_log.

BEGIN;

INSERT INTO shared.dot_thau
SELECT (jsonb_populate_record(NULL::shared.dot_thau, l.truoc)).*
FROM shared.quota_chuan_hoa_log l
WHERE l.buoc = 'xoa_dot_mo_coi' AND l.bang = 'dot_thau'
ON CONFLICT DO NOTHING;

DELETE FROM shared.quota_chuan_hoa_log WHERE buoc = 'xoa_dot_mo_coi';

COMMIT;
