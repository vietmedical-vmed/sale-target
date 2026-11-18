-- Rollback 20261118110000_cron_gan_quota_hop_dong: gỡ cron + hàm bọc (liên kết đã gắn giữ nguyên).
select cron.unschedule(jobid) from cron.job where jobname = 'gan-quota-hop-dong';
drop function if exists app_sale.chay_gan_quota_hop_dong(text);
delete from shared.app_config where key = 'gan_quota_hop_dong_lan_cuoi';
