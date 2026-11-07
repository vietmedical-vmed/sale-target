-- ════════════════════════════════════════════════════════════════════════
-- ĐÓNG 2 CHỖ LỘ DỮ LIỆU QUA ANON KEY
--
-- Anon key nằm công khai trong bundle frontend (src/api/client.js), và PostgREST
-- mở các schema public, shared, app_sale... (pgrst.db_schemas). Audit 07/11/2026
-- tìm ra 2 đối tượng anon đọc/ghi được:
--
-- 1) app_sale.hoa_don_bovattu_chia — view chủ sở hữu postgres (không
--    security_invoker, nên bỏ qua RLS của bảng gốc), có GRANT SELECT cho anon +
--    authenticated từ các migration 20261001100000, 20261001120000,
--    20261012100000, 20261106100000. Ai có anon key cũng đọc được toàn bộ hóa
--    đơn sau chia (KH, PS, số lượng, tiền).
-- 2) shared.giai_trinh — policy giai_trinh_service FOR ALL TO PUBLIC
--    USING (true) WITH CHECK (true) cộng grant ghi cho anon: ai cũng đọc, sửa,
--    xoá được giải trình.
--
-- Ai đang dùng (pg_stat_statements + quét script nạp): chỉ service_role (edge
-- function sale_target-api, script nạp ngoài repo dùng service key) và postgres.
-- service_role có BYPASSRLS nên bỏ policy không ảnh hưởng app.
--
-- Các migration cũ đã sửa dòng GRANT bỏ anon/authenticated để nếu bị chạy lại
-- (nhiều migration áp qua Management API, chưa ghi supabase_migrations) không
-- mở lại lỗ.
-- Hoàn tác: supabase/rollbacks/20261107110000_dong_quyen_anon_hoa_don_chia_giai_trinh_ROLLBACK.sql
-- ════════════════════════════════════════════════════════════════════════

begin;

-- 1) Luồng chia hóa đơn: chỉ postgres + service_role.
--    v_chia_ps / hoa_don_actual hiện đã không mở cho anon, revoke lại cho chắc (idempotent).
revoke all on app_sale.hoa_don_bovattu_chia from public, anon, authenticated;
revoke all on app_sale.v_chia_ps            from public, anon, authenticated;
revoke all on app_sale.hoa_don_actual       from public, anon, authenticated;
grant select on app_sale.hoa_don_bovattu_chia, app_sale.v_chia_ps, app_sale.hoa_don_actual
  to service_role;

-- 2) Giải trình: bỏ policy mở cho PUBLIC; RLS vẫn bật, không policy
--    → chỉ service_role (BYPASSRLS) đọc/ghi được.
drop policy if exists giai_trinh_service on shared.giai_trinh;
alter table shared.giai_trinh enable row level security;
revoke all on shared.giai_trinh        from public, anon, authenticated;
revoke all on shared.giai_trinh_id_seq from public, anon, authenticated;
grant select, insert, update, delete on shared.giai_trinh to service_role;
grant usage, select on shared.giai_trinh_id_seq to service_role;

-- 3) Kiểm tra sau: anon/authenticated không còn quyền gì, service_role vẫn đủ.
do $$
declare
  v_bad text;
begin
  select string_agg(r || ' ' || o, ', ') into v_bad
  from unnest(array['anon', 'authenticated']) r,
       unnest(array['app_sale.hoa_don_bovattu_chia', 'app_sale.v_chia_ps',
                    'app_sale.hoa_don_actual', 'shared.giai_trinh']) o
  where has_table_privilege(r, o, 'SELECT,INSERT,UPDATE,DELETE');
  if v_bad is not null then
    raise exception 'con_quyen_anon: %', v_bad;
  end if;

  if exists (select 1 from pg_policy where polrelid = 'shared.giai_trinh'::regclass) then
    raise exception 'giai_trinh_con_policy';
  end if;

  if not has_table_privilege('service_role', 'app_sale.hoa_don_bovattu_chia', 'SELECT')
     or not has_table_privilege('service_role', 'shared.giai_trinh', 'SELECT,INSERT')
     or not has_sequence_privilege('service_role', 'shared.giai_trinh_id_seq', 'USAGE') then
    raise exception 'service_role_thieu_quyen';
  end if;
end $$;

commit;
