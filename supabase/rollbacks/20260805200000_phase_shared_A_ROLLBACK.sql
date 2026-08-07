-- ════════════════════════════════════════════════════════════════════════
-- ROLLBACK cho 20260805200000_phase_shared_A.sql
-- Đưa mọi thứ về public + khôi phục search_path/thân RPC.
-- Chạy xong: gỡ 'shared' + 'app_sale' khỏi Exposed schemas + revert code.
-- ════════════════════════════════════════════════════════════════════════

begin;

-- 1) View app_sale → public
do $$
declare v text;
begin
  foreach v in array array['v_actual_ngoai_ke_hoach','v_actual_unmatched',
    'v_dia_ban_khoang_trong','v_th_theo_ps','v_th_theo_sp']
  loop
    if exists (select 1 from pg_class c join pg_namespace n on n.oid=c.relnamespace
               where n.nspname='app_sale' and c.relname=v and c.relkind='v') then
      execute format('alter view app_sale.%I set schema public', v);
    end if;
  end loop;
end $$;

-- 2) Bảng về public
do $$
declare r text;
begin
  foreach r in array array['sv_bovattu_actual'] loop
    if exists (select 1 from pg_class c join pg_namespace n on n.oid=c.relnamespace
               where n.nspname='app_sale' and c.relname=r and c.relkind='r') then
      execute format('alter table app_sale.%I set schema public', r);
    end if;
  end loop;
  foreach r in array array['sale_target','dm_bo_vat_tu','dm_bo_vat_tu_mapping',
    'dm_dia_ban','dm_khach_hang','dm_nhom_san_pham','dm_ps','dm_san_pham',
    'dm_san_pham_tong','dm_vat_tu']
  loop
    if exists (select 1 from pg_class c join pg_namespace n on n.oid=c.relnamespace
               where n.nspname='shared' and c.relname=r and c.relkind='r') then
      execute format('alter table shared.%I set schema public', r);
    end if;
  end loop;
end $$;

-- 3) search_path 8 RPC về 'public'
alter function public.map_actual_to_sale_target()                              set search_path = public;
alter function public.update_sale_target_cells(jsonb,text,text,text,text[])    set search_path = public;
alter function public.upsert_dm_dia_ban(jsonb,text,text,text,text[])           set search_path = public;
alter function public.dia_ban_hieu_luc(text)                                   set search_path = public;
alter function public.kiem_tra_khoang_trong(jsonb)                             set search_path = public;
alter function public.chuyen_dia_ban(bigint,text,text,text,text,text,text,text[]) set search_path = public;
alter function public.delete_dm_dia_ban(bigint[],text,text,text,text[])        set search_path = public;
alter function public.apply_dia_ban_to_plan(bigint[])                          set search_path = public;

-- 4) 2 RPC qualify về public
create or replace function public.sale_target_agg(p_mien text, p_months text[])
returns table(mien text, san_pham text, tong numeric)
language sql stable as $function$
  select case when st.mien in ('MB','Miền Bắc') then 'MB'
              when st.mien in ('MN','Miền Nam') then 'MN' end as mien,
    st.san_pham,
    sum(case when st.sl_ke_hoach_update is not null then coalesce(st.sl_ke_hoach_update,0)
             else coalesce(st.sl_ke_hoach_dau_nam,0) end) as tong
  from public.sale_target st
  where st.thang_ke_hoach = any(p_months)
    and ( (p_mien='ALL' and st.mien in ('MB','Miền Bắc','MN','Miền Nam'))
       or (p_mien='MB' and st.mien in ('MB','Miền Bắc'))
       or (p_mien='MN' and st.mien in ('MN','Miền Nam')) )
  group by 1, st.san_pham;
$function$;

create or replace function public.usage_agg(p_mien text, p_y integer, p_m integer)
returns table(mien text, item_code text, san_pham text, th numeric, th_months integer)
language sql stable as $function$
  with base as (
    select case when s.area in ('MB','Miền Bắc') then 'MB'
                when s.area in ('MN','Miền Nam') then 'MN' end as mien,
           s.item_code, (split_part(s.month,'-',1))::int as y,
           (split_part(s.month,'-',2))::int as mo, coalesce(s.quantity,0) as q
    from app_order.sv s
    where s.item_code is not null and s.month ~ '^[0-9]{4}-[0-9]{1,2}'
      and s.month >= ((p_y-1)::text || '-01')
      and ( (p_mien='ALL' and s.area in ('MB','Miền Bắc','MN','Miền Nam'))
         or (p_mien='MB' and s.area in ('MB','Miền Bắc'))
         or (p_mien='MN' and s.area in ('MN','Miền Nam')) )
  ),
  per_month as (select b.mien,b.item_code,b.y,b.mo,sum(b.q) as q from base b
                where b.mien is not null group by b.mien,b.item_code,b.y,b.mo),
  agg as (select m.mien,m.item_code,
            coalesce(sum(m.q) filter (where m.q>0 and (m.y*12+m.mo)<=(p_y*12+p_m-1)),0) as th,
            (count(*) filter (where m.q>0 and (m.y*12+m.mo)<=(p_y*12+p_m-1)))::int as th_months
          from per_month m group by m.mien,m.item_code),
  vt as (select d.ma_bravo,max(d.san_pham) as san_pham from public.dm_vat_tu d group by d.ma_bravo)
  select a.mien,a.item_code,vt.san_pham,a.th,a.th_months
  from agg a left join vt on vt.ma_bravo=a.item_code;
$function$;

commit;

-- drop schema if exists app_sale restrict;   -- chỉ khi rỗng
-- drop schema if exists shared   restrict;
