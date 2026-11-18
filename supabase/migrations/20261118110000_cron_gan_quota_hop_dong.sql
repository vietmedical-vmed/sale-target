-- Chạy gắn liên kết quota ↔ hợp đồng tự động (cron hằng đêm) và từ nút admin trên app.
--
-- app_sale.chay_gan_quota_hop_dong(p_actor): bọc app_sale.gan_quota_hop_dong_tu_dong()
--   - khoá advisory: cron và nút bấm không chạy chồng (lần sau trả {dang_chay: true});
--   - ghi kết quả lần chạy cuối vào shared.app_config key 'gan_quota_hop_dong_lan_cuoi'
--     (getData trả cả app_config về client → nút hiện thời điểm chạy cuối).
-- Cron 'gan-quota-hop-dong': 18:30 UTC = 01:30 giờ VN mỗi ngày (~5 giây/lần).

create or replace function app_sale.chay_gan_quota_hop_dong(p_actor text default 'cron')
returns json
language plpgsql
volatile
set search_path = shared, app_sale, pg_temp
as $$
declare
  v jsonb;
begin
  if not pg_try_advisory_xact_lock(hashtext('app_sale.gan_quota_hop_dong')) then
    return json_build_object('dang_chay', true);
  end if;
  v := app_sale.gan_quota_hop_dong_tu_dong()::jsonb
       || jsonb_build_object('luc', now(), 'nguoi', p_actor);
  insert into shared.app_config (key, value, updated_at)
  values ('gan_quota_hop_dong_lan_cuoi', v, now())
  on conflict (key) do update set value = excluded.value, updated_at = excluded.updated_at;
  return v::json;
end;
$$;

revoke all on function app_sale.chay_gan_quota_hop_dong(text) from public, anon, authenticated;
grant execute on function app_sale.chay_gan_quota_hop_dong(text) to service_role;

select cron.unschedule(jobid) from cron.job where jobname = 'gan-quota-hop-dong';
select cron.schedule('gan-quota-hop-dong', '30 18 * * *',
                     $c$select app_sale.chay_gan_quota_hop_dong('cron')$c$);
