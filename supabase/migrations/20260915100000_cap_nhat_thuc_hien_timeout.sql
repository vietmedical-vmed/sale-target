-- ════════════════════════════════════════════════════════════════════════
-- Bấm "Đồng bộ thực hiện" báo: canceling statement due to statement timeout.
-- Nguyên nhân: cap_nhat_thuc_hien() gọi map_hoadon_to_sale_target() +
-- refresh 2 matview (v_th_theo_ps, v_th_theo_sp). Khi dữ liệu lớn, tổng
-- thời gian vượt statement_timeout mặc định của role gọi qua PostgREST.
--
-- Sửa: cắm SET statement_timeout='5min' cho 3 function chạy nặng. Chỉ áp
-- dụng trong scope function (per-function GUC), KHÔNG đổi cấu hình role.
-- Thân function giữ nguyên logic bản 20260807190000 + 20260806100000.
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

  update sale_target set sl_thuc_hien = 0, updated_at = now()
   where thang_ke_hoach = any(v_months)
     and sl_thuc_hien is distinct from 0;
  get diagnostics v_zeroed = row_count;

  create temp table _agg on commit drop as
  with a as (
    select thang_ke_hoach,
           lower(btrim(ps))            as ps_n,
           lower(btrim(ma_khach_hang)) as kh_n,
           lower(btrim(bo_vat_tu))     as bo_n,
           lower(btrim(san_pham))      as sp_n,
           sum(sl_thuc_hien)           as sl
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
     set sl_thuc_hien = a.sl, updated_at = now()
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


create or replace function public.refresh_bao_cao_sale()
returns void
language plpgsql
security definer
set search_path = public, shared, app_sale
set statement_timeout to '5min'
as $$
begin
  refresh materialized view app_sale.v_th_theo_ps;
  refresh materialized view app_sale.v_th_theo_sp;
end;
$$;
grant execute on function public.refresh_bao_cao_sale() to service_role;


create or replace function public.cap_nhat_thuc_hien()
returns jsonb
language plpgsql
security definer
set search_path to 'public', 'shared', 'app_sale'
set statement_timeout to '5min'
as $function$
declare
  v_map    jsonb;
  v_thang  text[];
begin
  v_map := public.map_hoadon_to_sale_target();
  perform public.refresh_bao_cao_sale();

  select array_agg(distinct thang_ke_hoach order by thang_ke_hoach)
    into v_thang from hoa_don_actual;

  return v_map
       || jsonb_build_object('refreshed_bao_cao', true,
                             'thang_trong_hoa_don', to_jsonb(coalesce(v_thang, '{}'::text[])));
end;
$function$;

revoke all on function public.cap_nhat_thuc_hien() from public, anon, authenticated;
grant execute on function public.cap_nhat_thuc_hien() to service_role;
