-- Contract links for one product group (FY × PS × customer × group), shown in the
-- Quota thầu popup (chip per quota line) and in the round bar (DotThauPanel).
-- One row per link in app_sale.quota_hop_dong. Scope params are the same as
-- public.get_quota_thau, so a user only sees links for quota they can already see.
-- Rollback: drop function public.get_quota_hop_dong_nhom(text, text, text, text, text, text, text, text[]);

create or replace function public.get_quota_hop_dong_nhom(
  p_fy text, p_ps_nhom text, p_cust text, p_grp text,
  p_bu text, p_mien text, p_ps text, p_groups text[]
)
returns table(
  quota_id bigint, mset text, prod text, price numeric, loai text, dot integer, quota_qty numeric,
  ma_hd text, so_hd text, ngay_ky date, thoi_han date,
  item_id integer, ma_chung text, ten_hang_hoa text, gia_hd numeric,
  sl_hd numeric, sl_quota numeric, sl_hd_dong numeric, sl_da_ban numeric,
  cua_so text, cach_gan text, nguoi_gan text, gan_luc timestamptz
)
language sql
stable security definer
set search_path to ''
as $function$
  with q as (
    select q.id, q.bo_vat_tu, q.san_pham, q.don_gia, q.loai, q.dot, q.so_luong
    from shared.quota_thau q
    where q.nam_tai_chinh = p_fy
      and q.ps = p_ps_nhom
      and coalesce(q.ma_khach_hang, '') = coalesce(p_cust, '')
      and coalesce(q.nhom_san_pham, '') = coalesce(p_grp, '')
      and q.trang_thai = 'chinh_thuc'
      and (p_bu is null or q.bu = p_bu)
      and shared.mien_in(q.mien, p_mien)
      and (p_ps is null or q.ps = p_ps)
      and (p_groups is null or q.nhom_san_pham = any(p_groups))
      and (p_bu is not null or q.bu is null or q.bu <> 'test')
  ), lk as (
    -- The contract app can reload contract_items with new ids (no FK, see
    -- v_quota_hop_dong_mo_coi). When the linked id is gone, fall back to the line
    -- with the same contract + common code taken from khoa_sp 'C:<ma_chung>'.
    select q.*, x.ma_hd, x.contract_item_id, x.sl_hd, x.sl_quota, x.cua_so, x.cach_gan,
           x.nguoi_gan, x.gan_luc, c.so_hd, c.ngay_ky, c.thoi_han,
           coalesce(i.ma_chung, i2.ma_chung) as ma_chung,
           coalesce(i.ten_hang_hoa, i2.ten_hang_hoa) as ten_hang_hoa,
           coalesce(i.don_gia, i2.don_gia) as gia_hd
    from q
    join app_sale.quota_hop_dong x on x.quota_id = q.id
    left join app_contract.contract_contracts c on c.ma_hd = x.ma_hd
    left join app_contract.contract_items i on i.id = x.contract_item_id
    left join lateral (
      select i2.ma_chung, i2.ten_hang_hoa, i2.don_gia
      from app_contract.contract_items i2
      where i.id is null and x.khoa_sp like 'C:%'
        and i2.ma_hd = x.ma_hd and i2.ma_chung = substr(x.khoa_sp, 3)
      order by i2.id
      limit 1
    ) i2 on true
  ), dong as (
    -- Contract quantity of the line, summed like contract_items_remaining_view.
    select i.ma_hd, i.ma_chung, sum(i.so_luong) as sl
    from app_contract.contract_items i
    where (i.ma_hd, i.ma_chung) in (select distinct lk.ma_hd, lk.ma_chung from lk)
    group by 1, 2
  ), ban as (
    select h.so_hd, h.ma_chung, sum(coalesce(h.so_luong, 0)) as sl
    from app_contract.hoa_don_bovattu h
    where (h.so_hd, h.ma_chung) in (select distinct lk.so_hd, lk.ma_chung from lk)
    group by 1, 2
  )
  select lk.id, lk.bo_vat_tu, lk.san_pham, lk.don_gia, lk.loai, lk.dot, lk.so_luong,
         lk.ma_hd, lk.so_hd, lk.ngay_ky, lk.thoi_han,
         lk.contract_item_id, lk.ma_chung, lk.ten_hang_hoa, lk.gia_hd,
         lk.sl_hd, lk.sl_quota, d.sl, coalesce(b.sl, 0),
         lk.cua_so, lk.cach_gan, lk.nguoi_gan, lk.gan_luc
  from lk
  left join dong d on d.ma_hd = lk.ma_hd and d.ma_chung = lk.ma_chung
  left join ban b on b.so_hd = lk.so_hd and b.ma_chung = lk.ma_chung
  order by lk.bo_vat_tu, lk.san_pham, lk.don_gia, lk.loai, lk.dot, lk.ngay_ky, lk.ma_hd, lk.ma_chung;
$function$;

revoke all on function public.get_quota_hop_dong_nhom(text, text, text, text, text, text, text, text[]) from public, anon, authenticated;
grant execute on function public.get_quota_hop_dong_nhom(text, text, text, text, text, text, text, text[]) to service_role;
