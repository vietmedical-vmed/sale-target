-- HOÀN TÁC 20261107160000_rls_internal_config_sync_job.sql.
-- Chạy tay qua SQL Editor; KHÔNG để file này trong supabase/migrations/.

ALTER TABLE shared._internal_config DISABLE ROW LEVEL SECURITY;
ALTER TABLE shared.sync_job DISABLE ROW LEVEL SECURITY;
