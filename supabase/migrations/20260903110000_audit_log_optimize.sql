-- Tối ưu audit_log: composite index + auto-cleanup

-- 1. Index composite cho truy vấn gom nhóm (ngày, user, action) + filter
--    Thay thế 2 index đơn (username, bu) vì composite bao phủ luôn.
DROP INDEX IF EXISTS shared.idx_audit_log_username;
DROP INDEX IF EXISTS shared.idx_audit_log_bu;

CREATE INDEX idx_audit_log_lookup
  ON shared.audit_log (username, action, created_at DESC);

-- 2. Hàm dọn log cũ hơn N tháng (mặc định 6 tháng).
--    Gọi định kỳ bằng pg_cron hoặc edge function scheduled.
CREATE OR REPLACE FUNCTION shared.cleanup_audit_log(p_months int DEFAULT 6)
RETURNS int
LANGUAGE plpgsql SECURITY DEFINER
SET search_path = shared
AS $$
DECLARE
  deleted int;
BEGIN
  DELETE FROM shared.audit_log
  WHERE created_at < now() - (p_months || ' months')::interval;
  GET DIAGNOSTICS deleted = ROW_COUNT;
  RETURN deleted;
END;
$$;

GRANT EXECUTE ON FUNCTION shared.cleanup_audit_log TO service_role;
