-- ════════════════════════════════════════════════════════════════════════
-- Hoàn tác 20261112200000_tach_bang_sale_sang_app_sale.sql
-- Đưa object về shared, khôi phục thân hàm, search_path và lệnh cron.
-- Sau đó deploy lại sale_target-api / sale_target-login bản trước (git revert commit code).
-- ════════════════════════════════════════════════════════════════════════

begin;

set local lock_timeout = '10s';

do $$
declare
  r record;
begin
  for r in
    select * from (values
      ('_internal_config','table'),
      ('audit_log','table'),
      ('login_attempts','table'),
      ('giai_trinh','table'),
      ('ke_hoach_chot_ky','table'),
      ('ke_hoach_chot','table'),
      ('ke_hoach_chot_dieu_chinh','table'),
      ('quota_chuan_hoa_log','table'),
      ('sync_job','table'),
      ('sale_target_tombstone','table'),
      ('v_quota_thau_xuat','view'),
      ('v_khoa_so_sanh_sp','view'),
      ('v_hop_dong_dong','view')
    ) v(name, kind)
  loop
    if to_regclass('app_sale.' || r.name) is not null then
      if to_regclass('shared.' || r.name) is not null then
        raise exception 'Cả app_sale.% và shared.% cùng tồn tại, dừng', r.name, r.name;
      end if;
      execute format('alter %s app_sale.%I set schema shared', r.kind, r.name);
      raise notice 'moved app_sale.% -> shared.%', r.name, r.name;
    end if;
  end loop;
end $$;

do $$
declare
  r record;
  v_old text;
  v_new text;
begin
  for r in
    select p.oid, p.oid::regprocedure as sig
    from pg_proc p
    join pg_namespace n on n.oid = p.pronamespace
    where n.nspname in ('public','shared')
      and p.prokind = 'f'
      and p.prosrc ~ '\mapp_sale\.(_internal_config|audit_log|login_attempts|giai_trinh|ke_hoach_chot_dieu_chinh|ke_hoach_chot_ky|ke_hoach_chot|quota_chuan_hoa_log|sync_job|sale_target_tombstone|v_quota_thau_xuat|v_khoa_so_sanh_sp|v_hop_dong_dong)\M'
  loop
    v_old := pg_get_functiondef(r.oid);
    v_new := regexp_replace(v_old,
      '\mapp_sale\.(_internal_config|audit_log|login_attempts|giai_trinh|ke_hoach_chot_dieu_chinh|ke_hoach_chot_ky|ke_hoach_chot|quota_chuan_hoa_log|sync_job|sale_target_tombstone|v_quota_thau_xuat|v_khoa_so_sanh_sp|v_hop_dong_dong)\M',
      'shared.\1', 'g');
    if v_new <> v_old then
      execute v_new;
      raise notice 'restored %', r.sig;
    end if;
  end loop;
end $$;

alter function shared.sale_target_tombstone_fn() set search_path = shared, public;

do $$
declare
  v_job bigint;
begin
  select jobid into v_job from cron.job where jobname = 'sale-target-tombstone-cleanup';
  if v_job is not null then
    perform cron.alter_job(v_job, command :=
      'delete from shared.sale_target_tombstone where deleted_at < now() - interval ''2 days''');
  end if;
end $$;

commit;

notify pgrst, 'reload schema';
