-- ════════════════════════════════════════════════════════════════════════
-- Sync OOP + addProduct chưa set nam_tai_chinh và ma_san_pham/ma_bo_vat_tu
-- đủ:
--   - Migration 20260915140000 INSERT OOP không set nam_tai_chinh → NULL.
--   - Edge fn addProduct/addProducts không set ma_san_pham/ma_bo_vat_tu (đã
--     fix trong TS ở lần deploy này).
-- Hệ quả: cùng san_pham nhưng khi query group theo (nam_tai_chinh, ma_san_pham)
-- bị tách 2 dòng (plan FY26 + ma NULL vs OOP NULL fy + ma từ dm_vat_tu).
--
-- Sửa:
--   (A) map_hoadon_to_sale_target: set nam_tai_chinh derive từ thang_ke_hoach
--       (FY VN: T4-T3), giữ nguyên các fix trước (bu_code, ma_bo_vat_tu,
--       ma_san_pham lookup).
--   (B) Backfill sale_target một lần cho toàn bộ rows đang thiếu:
--       - nam_tai_chinh từ thang_ke_hoach.
--       - ma_san_pham từ shared.dm_vat_tu (theo san_pham, case-insensitive).
--       - ma_bo_vat_tu từ shared.dm_bo_vat_tu (theo bo_vat_tu, ci).
-- ════════════════════════════════════════════════════════════════════════

-- Helper: derive FY từ 'YYYY-MM' (T4-T3)
create or replace function public.fy_from_thang(p_thang text)
returns text language sql immutable as $$
  select case
    when p_thang !~ '^\d{4}-\d{2}$' then null
    when substring(p_thang, 6, 2)::int >= 4
      then 'FY' || substring(p_thang, 3, 2)
    else 'FY' || lpad((substring(p_thang, 3, 2)::int - 1)::text, 2, '0')
  end;
$$;
grant execute on function public.fy_from_thang(text) to service_role;


-- (A) map_hoadon_to_sale_target: INSERT OOP set nam_tai_chinh
create or replace function public.map_hoadon_to_sale_target()
returns jsonb
language plpgsql
security definer
set search_path to 'public', 'shared', 'app_sale'
set statement_timeout to '5min'
as $function$
declare
  v_months    text[];
  v_zeroed    int := 0;
  v_set       int := 0;
  v_matched   int := 0;
  v_total     int := 0;
  v_deleted   int := 0;
  v_inserted  int := 0;
begin
  select array_agg(distinct thang_ke_hoach) into v_months from hoa_don_actual;
  if v_months is null then
    return jsonb_build_object('months', 0, 'zeroed', 0, 'set_rows', 0,
                              'matched_keys', 0, 'total_keys', 0, 'unmatched_keys', 0,
                              'oop_deleted', 0, 'oop_inserted', 0);
  end if;

  update sale_target
     set sl_thuc_hien = 0, doanh_thu_thuc_hien = 0, updated_at = now()
   where thang_ke_hoach = any(v_months)
     and coalesce(ngoai_ke_hoach, false) = false
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
         and coalesce(s.ngoai_ke_hoach, false) = false
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

  delete from sale_target
   where thang_ke_hoach = any(v_months)
     and ngoai_ke_hoach = true;
  get diagnostics v_deleted = row_count;

  with agg_oop as (
    select a.thang_ke_hoach, a.ps_n, a.kh_n, a.bo_n, a.sp_n
      from _agg a
     where a.target_id is null
  ),
  ha as (
    select thang_ke_hoach, ps, ma_khach_hang, bo_vat_tu, san_pham,
           max(mien)          as mien,
           max(khach_hang)    as khach_hang,
           max(bu)            as bu,
           max(nhom_san_pham) as nhom_san_pham,
           sum(sl_thuc_hien)  as sl,
           sum(doanh_thu_thuc_hien) as dt,
           sum(doanh_thu_thuc_hien)::numeric / nullif(sum(sl_thuc_hien),0)::numeric as don_gia
      from hoa_don_actual
     group by 1,2,3,4,5
  )
  insert into sale_target
    (nam_tai_chinh,
     thang_ke_hoach, mien, ps, ma_khach_hang, khach_hang, bu, nhom_san_pham,
     bo_vat_tu, san_pham, ma_bo_vat_tu, ma_san_pham,
     sl_thuc_hien, doanh_thu_thuc_hien, don_gia,
     ngoai_ke_hoach, updated_at)
  select public.fy_from_thang(ha.thang_ke_hoach),
         ha.thang_ke_hoach, ha.mien, ha.ps, ha.ma_khach_hang, ha.khach_hang,
         coalesce(dps.bu_code, ha.bu) as bu,
         ha.nhom_san_pham, ha.bo_vat_tu, ha.san_pham,
         dbvt.ma_bo_vat_tu, dvt.ma_san_pham,
         ha.sl, ha.dt, ha.don_gia, true, now()
    from ha
    join agg_oop o
      on o.thang_ke_hoach = ha.thang_ke_hoach
     and o.ps_n = lower(btrim(ha.ps))
     and o.kh_n = lower(btrim(ha.ma_khach_hang))
     and o.bo_n = lower(btrim(ha.bo_vat_tu))
     and o.sp_n = lower(btrim(ha.san_pham))
    left join lateral (
      select bu_code from shared.dm_ps
       where lower(btrim(ps)) = lower(btrim(ha.ps))
       order by (trang_thai = 'Active') desc
       limit 1
    ) dps on true
    left join lateral (
      select ma_bo_vat_tu from shared.dm_bo_vat_tu
       where lower(btrim(bo_vat_tu)) = lower(btrim(ha.bo_vat_tu))
       limit 1
    ) dbvt on true
    left join lateral (
      select ma_san_pham from shared.dm_vat_tu
       where lower(btrim(san_pham)) = lower(btrim(ha.san_pham))
       limit 1
    ) dvt on true;
  get diagnostics v_inserted = row_count;

  select count(*), count(*) filter (where target_id is not null)
    into v_total, v_matched
    from _agg;

  return jsonb_build_object(
    'months',         array_length(v_months, 1),
    'zeroed',         v_zeroed,
    'set_rows',       v_set,
    'matched_keys',   v_matched,
    'total_keys',     v_total,
    'unmatched_keys', v_total - v_matched,
    'oop_deleted',    v_deleted,
    'oop_inserted',   v_inserted
  );
end;
$function$;

grant execute on function public.map_hoadon_to_sale_target() to service_role;


-- (B) Backfill toàn bộ sale_target
-- B1. nam_tai_chinh từ thang_ke_hoach
update shared.sale_target s
   set nam_tai_chinh = public.fy_from_thang(s.thang_ke_hoach),
       updated_at = now()
 where s.nam_tai_chinh is null
   and s.thang_ke_hoach is not null;

-- B2. ma_san_pham từ dm_vat_tu (rows đang NULL)
update shared.sale_target s
   set ma_san_pham = dvt.ma_san_pham, updated_at = now()
  from shared.dm_vat_tu dvt
 where s.ma_san_pham is null
   and dvt.ma_san_pham is not null
   and lower(btrim(dvt.san_pham)) = lower(btrim(s.san_pham));

-- B3. ma_bo_vat_tu từ dm_bo_vat_tu (rows đang NULL)
update shared.sale_target s
   set ma_bo_vat_tu = dbvt.ma_bo_vat_tu, updated_at = now()
  from shared.dm_bo_vat_tu dbvt
 where s.ma_bo_vat_tu is null
   and dbvt.ma_bo_vat_tu is not null
   and lower(btrim(dbvt.bo_vat_tu)) = lower(btrim(s.bo_vat_tu));
