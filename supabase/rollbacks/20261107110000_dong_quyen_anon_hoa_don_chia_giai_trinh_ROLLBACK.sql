-- HOÀN TÁC 20261107110000_dong_quyen_anon_hoa_don_chia_giai_trinh.sql
--
-- CẢNH BÁO: chạy file này MỞ LẠI lỗ lộ dữ liệu — anon key công khai trong
-- frontend sẽ đọc được toàn bộ hóa đơn sau chia và đọc/sửa/xoá được giải trình.
-- Chỉ chạy nếu có hệ thống đang dùng anon key gãy sau migration, và chỉ tạm thời
-- trong lúc chuyển hệ thống đó sang service key.
-- Chạy tay qua SQL Editor; KHÔNG để file này trong supabase/migrations/.

begin;

grant select on app_sale.hoa_don_bovattu_chia to anon, authenticated;

grant select, insert, update, delete on shared.giai_trinh to anon, authenticated;
grant usage, select on shared.giai_trinh_id_seq to anon, authenticated;
create policy giai_trinh_service on shared.giai_trinh
  for all using (true) with check (true);

commit;
