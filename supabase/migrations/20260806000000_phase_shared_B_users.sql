-- ════════════════════════════════════════════════════════════════════════
-- PHASE SHARED — BƯỚC B: public.users → shared.users (bước cuối).
--
-- Sau bước này: public không còn bảng app nào, chỉ còn RPC/function.
--
-- Đụng cả 3 app (login đọc users). shared ĐÃ được expose từ Bước A → KHÔNG cần
-- thêm expose. Chỉ chạy SQL này rồi redeploy 3 app.
--
-- An toàn (căn cứ introspection):
--   • CHỈ move public.users — TUYỆT ĐỐI KHÔNG đụng auth.users (bảng của Supabase Auth).
--   • 3 FK từ app_kpi (evaluations, kpi_profiles×2) trỏ users theo OID → tự đi theo,
--     KHÔNG cần DDL trong app_kpi.
--   • View app_kpi.kpi_users đọc users theo OID → vẫn chạy, không cần sửa.
--   • KHÔNG có RPC nào đọc users trong thân → không sửa hàm.
--   • Grant + RLS + trigger đi theo bảng. shared đã có USAGE + default privileges.
--
-- Áp dụng: dán vào SQL Editor → Run. Rồi redeploy:
--   order  : push master (deploy-edge → order-api + order-login)
--   sale   : supabase functions deploy sale_target-login --no-verify-jwt --project-ref nrfxymnfmjhbsgpipvkb
--   kpi    : supabase functions deploy login            --no-verify-jwt --project-ref nrfxymnfmjhbsgpipvkb
-- ════════════════════════════════════════════════════════════════════════

begin;

do $$
begin
  if exists (select 1 from pg_class c join pg_namespace n on n.oid=c.relnamespace
             where n.nspname='public' and c.relname='users' and c.relkind='r') then
    execute 'alter table public.users set schema shared';
    raise notice 'moved public.users -> shared.users';
  else
    raise notice 'public.users không tồn tại (đã move rồi?) — bỏ qua';
  end if;
end $$;

commit;

-- ─── KIỂM TRA ─────────────────────────────────────────────────────────────
-- (a) users đã sang shared, auth.users KHÔNG đụng:
--   select n.nspname, c.relname from pg_class c join pg_namespace n on n.oid=c.relnamespace
--   where c.relname='users' order by 1;   -- kỳ vọng: auth.users + shared.users
-- (b) FK app_kpi vẫn trỏ đúng (giờ là shared.users):
--   select conname, pg_get_constraintdef(oid) from pg_constraint
--   where conname like 'kpi_profiles%fkey' or conname like 'evaluations%fkey';
-- (c) view kpi_users còn đọc được:
--   select count(*) from app_kpi.kpi_users;
