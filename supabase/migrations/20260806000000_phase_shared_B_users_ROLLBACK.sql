-- ════════════════════════════════════════════════════════════════════════
-- ROLLBACK cho 20260806000000_phase_shared_B_users.sql
-- Đưa users về public. Chạy xong: revert code 3 app + redeploy.
-- (shared vẫn giữ nguyên cho sale_target/dm_* của Bước A — không đụng.)
-- ════════════════════════════════════════════════════════════════════════

begin;

do $$
begin
  if exists (select 1 from pg_class c join pg_namespace n on n.oid=c.relnamespace
             where n.nspname='shared' and c.relname='users' and c.relkind='r') then
    execute 'alter table shared.users set schema public';
    raise notice 'moved shared.users -> public.users';
  end if;
end $$;

commit;
