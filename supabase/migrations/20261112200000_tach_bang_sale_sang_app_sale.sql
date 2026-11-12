-- ════════════════════════════════════════════════════════════════════════
-- Tách các bảng chỉ app sale-target dùng ra khỏi schema shared, sang app_sale
-- (đợt 2 của sắp xếp schema 2026-11-12; đợt 1 dọn public → app_contract / app_portal).
--
-- Chuyển sang app_sale:
--   bảng : _internal_config, audit_log, login_attempts, giai_trinh,
--          ke_hoach_chot, ke_hoach_chot_dieu_chinh, ke_hoach_chot_ky,
--          quota_chuan_hoa_log, sync_job, sale_target_tombstone
--   view : v_quota_thau_xuat, v_khoa_so_sanh_sp, v_hop_dong_dong
-- Giữ ở shared (app khác cũng đọc): users, sale_target, dm_*, notifications,
--   dot_thau, quota_thau, app_config (app_ccdc.v_quota_kh_nhom đọc current_month).
-- app_sale chưa có object trùng tên (app_order có audit_log / login_attempts / app_config
-- riêng, khác schema).
--
-- ALTER ... SET SCHEMA giữ OID: index, RLS, grant, trigger, FK (ke_hoach_chot* →
-- ke_hoach_chot_ky), sequence và view đọc các bảng này tự đi theo. Mức quyền không đổi:
-- shared và app_sale cùng cấp USAGE cho anon / authenticated / service_role.
--
-- Hàm GIỮ NGUYÊN schema (.rpc() không đổi). Sửa:
--   * Thân hàm viết cứng shared.<bảng đã chuyển> → app_sale.<bảng> (pg_get_functiondef +
--     regexp + EXECUTE, CREATE OR REPLACE giữ OID, grant, SET):
--     public: ap_gia_admin_vao_ban_chup, audit_log_xem, audit_thay_doi, chot_ke_hoach,
--       chot_ke_hoach_tu_dong, so_sanh_chot_ke_hoach, duyet_dot_thau, duyet_quota_thau,
--       execute_sync_job, start_sync_job
--     shared: chuyen_quota_khoa, doi_chieu_quota_hop_dong, gan_quota_theo_ma_sale_target,
--       giu_khoa_quota_sale_target, gop_dong_trung_sale_target
--   * shared.sale_target_tombstone_fn dùng tên trần → thêm app_sale vào search_path.
--   * pg_cron sale-target-tombstone-cleanup → app_sale.sale_target_tombstone.
--
-- Sau khi chạy (app lỗi các tab liên quan tới khi deploy xong):
--   supabase functions deploy sale_target-api   --no-verify-jwt --project-ref nrfxymnfmjhbsgpipvkb
--   supabase functions deploy sale_target-login --no-verify-jwt --project-ref nrfxymnfmjhbsgpipvkb
-- Không chạy lúc đang đồng bộ thực hiện (execute_sync_job / cap_nhat_thuc_hien).
-- Chạy lại được: mỗi bước kiểm tra object đang ở đâu.
--
-- Migration sau này: dùng app_sale.<bảng> cho các bảng trên.
-- Hoàn tác: supabase/rollbacks/20261112200000_tach_bang_sale_sang_app_sale_ROLLBACK.sql
-- ════════════════════════════════════════════════════════════════════════

begin;

set local lock_timeout = '10s';

-- 0. Không trùng tên ở đích
do $$
declare
  v_name text;
begin
  foreach v_name in array array['_internal_config','audit_log','login_attempts','giai_trinh',
      'ke_hoach_chot','ke_hoach_chot_dieu_chinh','ke_hoach_chot_ky','quota_chuan_hoa_log',
      'sync_job','sale_target_tombstone','v_quota_thau_xuat','v_khoa_so_sanh_sp','v_hop_dong_dong'] loop
    if to_regclass('shared.' || v_name) is not null and to_regclass('app_sale.' || v_name) is not null then
      raise exception 'Cả shared.% và app_sale.% cùng tồn tại, dừng', v_name, v_name;
    end if;
  end loop;
end $$;

-- 1. Chuyển object
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
    if to_regclass('shared.' || r.name) is not null then
      execute format('alter %s shared.%I set schema app_sale', r.kind, r.name);
      raise notice 'moved shared.% -> app_sale.%', r.name, r.name;
    elsif to_regclass('app_sale.' || r.name) is not null then
      raise notice 'already in app_sale.%', r.name;
    else
      raise exception 'Không thấy % ở shared hay app_sale', r.name;
    end if;
  end loop;
end $$;

-- 2. Viết lại tên shared.<bảng đã chuyển> trong thân hàm
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
      and p.prosrc ~ '\mshared\.(_internal_config|audit_log|login_attempts|giai_trinh|ke_hoach_chot_dieu_chinh|ke_hoach_chot_ky|ke_hoach_chot|quota_chuan_hoa_log|sync_job|sale_target_tombstone|v_quota_thau_xuat|v_khoa_so_sanh_sp|v_hop_dong_dong)\M'
  loop
    v_old := pg_get_functiondef(r.oid);
    v_new := regexp_replace(v_old,
      '\mshared\.(_internal_config|audit_log|login_attempts|giai_trinh|ke_hoach_chot_dieu_chinh|ke_hoach_chot_ky|ke_hoach_chot|quota_chuan_hoa_log|sync_job|sale_target_tombstone|v_quota_thau_xuat|v_khoa_so_sanh_sp|v_hop_dong_dong)\M',
      'app_sale.\1', 'g');
    if v_new <> v_old then
      execute v_new;
      raise notice 'rewrote %', r.sig;
    end if;
  end loop;
end $$;

-- 3. Hàm trigger dùng tên trần sale_target_tombstone
alter function shared.sale_target_tombstone_fn() set search_path = shared, public, app_sale;

-- 4. pg_cron dọn tombstone
do $$
declare
  v_job bigint;
begin
  select jobid into v_job from cron.job where jobname = 'sale-target-tombstone-cleanup';
  if v_job is not null then
    perform cron.alter_job(v_job, command :=
      'delete from app_sale.sale_target_tombstone where deleted_at < now() - interval ''2 days''');
  end if;
end $$;

-- 5. Kiểm tra
do $$
declare
  v_left int;
  v_bad text;
begin
  select count(*) into v_left
  from pg_class c join pg_namespace n on n.oid = c.relnamespace
  where n.nspname = 'shared' and c.relkind in ('r','v','m','p')
    and c.relname in ('_internal_config','audit_log','login_attempts','giai_trinh','ke_hoach_chot',
      'ke_hoach_chot_dieu_chinh','ke_hoach_chot_ky','quota_chuan_hoa_log','sync_job',
      'sale_target_tombstone','v_quota_thau_xuat','v_khoa_so_sanh_sp','v_hop_dong_dong');
  if v_left > 0 then
    raise exception 'Còn % object chưa chuyển khỏi shared', v_left;
  end if;

  select string_agg(p.oid::regprocedure::text, ', ') into v_bad
  from pg_proc p join pg_namespace n on n.oid = p.pronamespace
  where n.nspname not in ('pg_catalog','information_schema','backup')
    and p.prosrc ~ '\mshared\.(_internal_config|audit_log|login_attempts|giai_trinh|ke_hoach_chot_dieu_chinh|ke_hoach_chot_ky|ke_hoach_chot|quota_chuan_hoa_log|sync_job|sale_target_tombstone|v_quota_thau_xuat|v_khoa_so_sanh_sp|v_hop_dong_dong)\M';
  if v_bad is not null then
    raise exception 'Hàm còn trỏ shared.<bảng đã chuyển>: %', v_bad;
  end if;

  if exists (select 1 from cron.job where command ~ '\mshared\.sale_target_tombstone\M') then
    raise exception 'Cron còn trỏ shared.sale_target_tombstone';
  end if;
end $$;

commit;

notify pgrst, 'reload schema';
