-- Rollback 20261119120000_chuyen_quota_theo_hop_dong.sql: bỏ hàm chung, trả
-- app_sale.chuyen_quota_1_4_theo_hop_dong về bản 20261119110000 (chạy lại file migration đó).
-- Không tự hoàn tác các lần chuyển đã chạy qua app: đọc app_sale.quota_chuan_hoa_log buoc
-- 'app_chuyen_1_4_theo_hd' / 'app_chuyen_up_theo_hd' (cách trả lại: xem
-- 20261119110000_chuyen_1_4_theo_hop_dong_ROLLBACK.sql), rồi
-- select app_sale.chay_gan_quota_hop_dong('rollback');
-- Cần deploy lại edge bản không gọi chuyen_quota_theo_hop_dong TRƯỚC khi chạy file này.
begin;
drop function if exists app_sale.chuyen_quota_theo_hop_dong(bigint, integer, text, numeric, numeric, text, integer, text, numeric, text);
commit;
-- rồi chạy: supabase/migrations/20261119110000_chuyen_1_4_theo_hop_dong.sql
