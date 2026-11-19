-- Rollback 20261119100000_kiem_tra_thong_tin_thau.sql
-- Xoá bảng trạng thái xử lý + ảnh chụp số liệu của tab Kiểm tra thông tin thầu và các RPC mới.
-- KHÔNG hoàn tác dữ liệu đã ghi qua app vào bảng dùng chung:
--   - liên kết tay ở app_sale.quota_hop_dong (cach_gan = 'tay', quy_tac = 'tay'),
--   - ghép mã ở app_sale.khoa_sp_alias (nguon like 'app:%').
-- Muốn gỡ cả hai thì chạy thêm 2 câu delete ở cuối (đang để comment), rồi chạy lại
-- select app_sale.chay_gan_quota_hop_dong('rollback');
begin;

select cron.unschedule(jobid) from cron.job where jobname = 'kiem-tra-thau-don-xong';

drop function if exists app_sale.kiem_tra_doi_chieu_hop_dong();
drop function if exists app_sale.goi_y_dot_tu_hop_dong(text);
drop function if exists app_sale.hop_dong_theo_san_pham(jsonb);
drop function if exists app_sale.chi_tiet_khoa_hop_dong(text, text, text);
drop function if exists app_sale.gan_tay_quota_hop_dong(bigint, integer, text, numeric, text, text);
drop function if exists app_sale.bo_gan_tay_quota_hop_dong(bigint);
drop function if exists app_sale.them_alias_khoa_sp(text, text[], text, text, text);

drop table if exists app_sale.kiem_tra_thau_snapshot;
drop table if exists app_sale.kiem_tra_thau_xu_ly;

-- delete from app_sale.quota_hop_dong where cach_gan = 'tay' and quy_tac = 'tay';
-- delete from app_sale.khoa_sp_alias where nguon like 'app:%';

commit;
