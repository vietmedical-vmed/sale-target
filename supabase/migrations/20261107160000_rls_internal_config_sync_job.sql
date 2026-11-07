-- Bật RLS cho 2 bảng shared còn tắt: _internal_config (chứa service_role_key cho
-- start_sync_job gọi pg_net) và sync_job. Hiện anon/authenticated không có grant nên chưa
-- lộ, nhưng schema shared nằm trong pgrst.db_schemas — chỉ cần một GRANT nhầm (như từng xảy
-- ra với hoa_don_bovattu_chia) là đọc được key. RLS không policy = chặn mọi role trừ chủ bảng
-- (postgres: start_sync_job / execute_sync_job SECURITY DEFINER) và service_role (BYPASSRLS:
-- edge syncJobStatus). Không đổi hành vi app.
-- Hoàn tác: supabase/rollbacks/20261107160000_rls_internal_config_sync_job_ROLLBACK.sql

ALTER TABLE shared._internal_config ENABLE ROW LEVEL SECURITY;
ALTER TABLE shared.sync_job ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON shared._internal_config FROM public, anon, authenticated;
REVOKE ALL ON shared.sync_job FROM public, anon, authenticated;

DO $$
BEGIN
  IF NOT (SELECT relrowsecurity FROM pg_class WHERE oid = 'shared._internal_config'::regclass)
     OR NOT (SELECT relrowsecurity FROM pg_class WHERE oid = 'shared.sync_job'::regclass) THEN
    RAISE EXCEPTION 'rls_chua_bat';
  END IF;
  IF pg_get_userbyid((SELECT proowner FROM pg_proc WHERE proname = 'start_sync_job' LIMIT 1))
     <> pg_get_userbyid((SELECT relowner FROM pg_class WHERE oid = 'shared._internal_config'::regclass)) THEN
    RAISE EXCEPTION 'start_sync_job_khong_cung_chu_voi_internal_config';
  END IF;
END $$;
