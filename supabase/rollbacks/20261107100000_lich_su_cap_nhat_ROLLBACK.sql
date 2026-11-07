-- Rollback 20261107100000_lich_su_cap_nhat.sql
-- Frontend / edge function bản mới gọi các hàm này: rollback DB thì phải deploy lại bản cũ.
DROP FUNCTION IF EXISTS public.audit_deadline(text, int, text);
DROP FUNCTION IF EXISTS public.audit_lich_su_dong(bigint[]);
DROP FUNCTION IF EXISTS public.audit_nhom(timestamptz, timestamptz, text, text[], text, text, int, int);
DROP FUNCTION IF EXISTS public.audit_thay_doi(bigint[], bigint[]);
DROP INDEX IF EXISTS shared.idx_audit_log_action_created;
