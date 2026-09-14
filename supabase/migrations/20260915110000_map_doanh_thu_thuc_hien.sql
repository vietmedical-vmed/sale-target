-- ════════════════════════════════════════════════════════════════════════
-- UI đọc sale_target.doanh_thu_thuc_hien (mapping COL.dtAct trong edge fn),
-- nhưng map_hoadon_to_sale_target() CHỈ ghi sl_thuc_hien → doanh thu TH cũ
-- kẹt giá trị stale (vd PS Dung Trần 2026-09 UI 1.0 tỷ, hoá đơn 4.8 tỷ).
--
-- Fix: aggregate doanh thu = sum(sl_thuc_hien * don_gia) từ hoa_don_actual
-- (view chỉ expose sl_thuc_hien + don_gia, KHÔNG có cột doanh_thu_thuc_hien;
-- don_gia đã là bình quân theo doanh thu theo migration 20260807150000)
-- rồi ghi vào sale_target.doanh_thu_thuc_hien cùng lượt zero+set.
-- ════════════════════════════════════════════════════════════════════════

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
           sum(sl_thuc_hien)                             as sl,
           sum(sl_thuc_hien * coalesce(don_gia, 0))      as dt
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
