-- Rollback 20261119110000_chuyen_1_4_theo_hop_dong.sql: bỏ RPC.
-- Không tự hoàn tác các lần chuyển đã chạy qua app. Muốn trả lại: đọc
-- app_sale.quota_chuan_hoa_log buoc 'app_chuyen_1_4_theo_hd' theo thứ tự id giảm dần
--   - quota_thau truoc null      → xoá dòng ban_ghi_id (dòng tách mới)
--   - quota_thau sau null        → chèn lại từ truoc (dòng nguồn đã xoá)
--   - quota_thau có truoc + sau  → cập nhật lại loai, dot, so_luong theo truoc
--   - dot_thau truoc null        → xoá đợt ban_ghi_id (nếu không còn quota trong đợt)
-- rồi chạy select app_sale.chay_gan_quota_hop_dong('rollback');
begin;
drop function if exists app_sale.chuyen_quota_1_4_theo_hop_dong(bigint, integer, text, numeric, text, integer, text, numeric, text);
commit;
