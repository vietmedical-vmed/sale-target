-- ════════════════════════════════════════════════════════════════════════
-- Lấy nguyên doanh thu THỰC từ hoá đơn (sum(tong_gia_ban)) thay vì suy ra
-- từ sl × don_gia. don_gia trong hoa_don_actual = tổng tiền / tổng SL của
-- nhóm 5-key nên đúng cho nhóm đó, nhưng khi RPC gộp thêm theo khoá chuẩn
-- hoá lower(btrim(..)), don_gia bình quân KHÔNG tái tạo đúng doanh thu →
-- lệch. Đưa sum(tong_gia_ban) ra ngoài view làm cột doanh_thu_thuc_hien,
-- RPC map thẳng sang sale_target.doanh_thu_thuc_hien.
--
-- create or replace view CHỈ cho phép THÊM cột vào cuối; giữ nguyên thứ tự
-- 11 cột đang có, thêm doanh_thu_thuc_hien ở cuối (cột #12).
-- ════════════════════════════════════════════════════════════════════════

create or replace view app_sale.hoa_don_actual as
with base as (
  select h.thang                                  as thang_ke_hoach,
         coalesce(d.ps, h.ten_ps)                 as ps,
         h.ma_kh                                  as ma_khach_hang,
         h.bo_vat_tu,
         h.san_pham,
         h.so_luong,
         h.tong_gia_ban,
         d.area                                   as mien,
         coalesce(d.bu, nullif(btrim(h.bu), ''))  as bu,
         h.nhom_san_pham,
         h.ten_kh                                 as khach_hang
  from app_sale.hoa_don_bovattu h
  left join lateral (
    select ps, area, bu
    from shared.dm_ps
    where lower(btrim(ten_ps)) = lower(btrim(h.ten_ps))
    order by (trang_thai = 'Active') desc
    limit 1
  ) d on true
)
select thang_ke_hoach,
       max(mien)          as mien,
       ps,
       ma_khach_hang,
       max(khach_hang)    as khach_hang,
       max(bu)            as bu,
       max(nhom_san_pham) as nhom_san_pham,
       bo_vat_tu,
       san_pham,
       sum(so_luong)      as sl_thuc_hien,
       sum(tong_gia_ban)::numeric / nullif(sum(so_luong), 0)::numeric as don_gia,
       sum(tong_gia_ban)::numeric as doanh_thu_thuc_hien
from base
group by thang_ke_hoach, ps, ma_khach_hang, bo_vat_tu, san_pham;

grant select on app_sale.hoa_don_actual to service_role, anon, authenticated;


create or replace function public.map_hoadon_to_sale_target()
returns jsonb
language plpgsql
security definer
set search_path to 'public', 'shared', 'app_sale'
set statement_timeout to '5min'
as $function$
declare
  v_months  text[];
  v_zeroed  int := 0;
  v_set     int := 0;
  v_matched int := 0;
  v_total   int := 0;
begin
  select array_agg(distinct thang_ke_hoach) into v_months from hoa_don_actual;
  if v_months is null then
    return jsonb_build_object('months', 0, 'zeroed', 0, 'set_rows', 0,
                              'matched_keys', 0, 'total_keys', 0, 'unmatched_keys', 0);
  end if;

  update sale_target
     set sl_thuc_hien = 0, doanh_thu_thuc_hien = 0, updated_at = now()
   where thang_ke_hoach = any(v_months)
     and (sl_thuc_hien is distinct from 0
          or doanh_thu_thuc_hien is distinct from 0);
  get diagnostics v_zeroed = row_count;

  create temp table _agg on commit drop as
  with a as (
    select thang_ke_hoach,
           lower(btrim(ps))            as ps_n,
           lower(btrim(ma_khach_hang)) as kh_n,
           lower(btrim(bo_vat_tu))     as bo_n,
           lower(btrim(san_pham))      as sp_n,
           sum(sl_thuc_hien)           as sl,
           sum(doanh_thu_thuc_hien)    as dt
      from hoa_don_actual
     group by 1, 2, 3, 4, 5
  )
  select a.*, t.id as target_id
    from a
    left join lateral (
      select s.id from sale_target s
       where s.thang_ke_hoach                = a.thang_ke_hoach
         and lower(btrim(s.ps))            = a.ps_n
         and lower(btrim(s.ma_khach_hang)) = a.kh_n
         and lower(btrim(s.bo_vat_tu))     = a.bo_n
         and lower(btrim(s.san_pham))      = a.sp_n
       order by s.id
       limit 1
    ) t on true;

  update sale_target s
     set sl_thuc_hien = a.sl,
         doanh_thu_thuc_hien = a.dt,
         updated_at = now()
    from _agg a
   where a.target_id = s.id;
  get diagnostics v_set = row_count;

  select count(*), count(*) filter (where target_id is not null)
    into v_total, v_matched
    from _agg;

  return jsonb_build_object(
    'months',         array_length(v_months, 1),
    'zeroed',         v_zeroed,
    'set_rows',       v_set,
    'matched_keys',   v_matched,
    'total_keys',     v_total,
    'unmatched_keys', v_total - v_matched
  );
end;
$function$;

grant execute on function public.map_hoadon_to_sale_target() to service_role;
