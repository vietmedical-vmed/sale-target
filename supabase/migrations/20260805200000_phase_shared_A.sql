-- ════════════════════════════════════════════════════════════════════════
-- PHASE SHARED — BƯỚC A: dm_* + sale_target → shared; tách app_sale.
-- (BƯỚC B tách riêng: public.users → shared — KHÔNG nằm trong file này.)
--
-- Đụng: app order (dm_*, sale_target qua RPC) + app sale (toàn bộ). KHÔNG đụng kpi.
--
-- Căn cứ introspection live (db_introspect_shared.sql):
--   • KHÔNG có FK giữa các dm_* → gom shared an toàn.
--   • View live khác repo → RELOCATE bằng ALTER VIEW SET SCHEMA (giữ định nghĩa
--     theo OID), KHÔNG tạo lại.
--   • 8 RPC dùng tên bảng không-qualify → chỉ nới search_path (không sửa thân).
--   • 2 RPC qualify cứng (sale_target_agg, usage_agg) → CREATE OR REPLACE.
--   • Grant bảng đã đầy đủ → đi theo bảng; chỉ cần cấp USAGE schema mới.
--
-- An toàn: transaction + guard idempotent. FK/RLS/policy/trigger/sequence/grant
-- đi theo bảng qua ALTER ... SET SCHEMA (đều theo OID).
--
-- Áp dụng: dán vào SQL Editor → Run. Sau đó: expose 'shared' + 'app_sale';
--          sửa code order/sale + deploy (xem PHASE_SHARED_PLAN.md mục 4).
-- ════════════════════════════════════════════════════════════════════════

begin;

-- ─── 1) Schema + USAGE + default privileges ──────────────────────────────
create schema if not exists shared;
create schema if not exists app_sale;
grant usage on schema shared   to anon, authenticated, service_role;
grant usage on schema app_sale to anon, authenticated, service_role;
alter default privileges in schema shared
  grant select, insert, update, delete on tables to anon, authenticated, service_role;
alter default privileges in schema shared
  grant usage, select on sequences to anon, authenticated, service_role;
alter default privileges in schema app_sale
  grant select, insert, update, delete on tables to anon, authenticated, service_role;
alter default privileges in schema app_sale
  grant usage, select on sequences to anon, authenticated, service_role;

-- ─── 2) Move 10 bảng → shared (sale_target + 9 dm_*). KHÔNG có users. ─────
do $$
declare r text;
begin
  foreach r in array array[
    'sale_target',
    'dm_bo_vat_tu','dm_bo_vat_tu_mapping','dm_dia_ban','dm_khach_hang',
    'dm_nhom_san_pham','dm_ps','dm_san_pham','dm_san_pham_tong','dm_vat_tu'
  ]
  loop
    if exists (select 1 from pg_class c join pg_namespace n on n.oid=c.relnamespace
               where n.nspname='public' and c.relname=r and c.relkind='r') then
      execute format('alter table public.%I set schema shared', r);
      raise notice 'moved public.% -> shared.%', r, r;
    end if;
  end loop;
end $$;

-- ─── 3) Move bảng sale-only → app_sale ───────────────────────────────────
do $$
begin
  if exists (select 1 from pg_class c join pg_namespace n on n.oid=c.relnamespace
             where n.nspname='public' and c.relname='sv_bovattu_actual' and c.relkind='r') then
    execute 'alter table public.sv_bovattu_actual set schema app_sale';
  end if;
end $$;

-- ─── 4) Relocate 5 view → app_sale (giữ định nghĩa theo OID) ──────────────
--     Thứ tự không quan trọng (phụ thuộc theo OID). View tự trỏ đúng bảng đã
--     move (sale_target→shared, sv_bovattu_actual→app_sale, dm_dia_ban→shared).
do $$
declare v text;
begin
  foreach v in array array[
    'v_actual_ngoai_ke_hoach','v_actual_unmatched','v_dia_ban_khoang_trong',
    'v_th_theo_ps','v_th_theo_sp'
  ]
  loop
    if exists (select 1 from pg_class c join pg_namespace n on n.oid=c.relnamespace
               where n.nspname='public' and c.relname=v and c.relkind='v') then
      execute format('alter view public.%I set schema app_sale', v);
      raise notice 'moved view public.% -> app_sale.%', v, v;
    end if;
  end loop;
end $$;

-- ─── 5) 8 RPC dùng tên không-qualify: chỉ nới search_path (KHÔNG sửa thân) ─
--     Bảng đã rời public → tên không-qualify sẽ resolve tiếp sang shared/app_sale.
--     Không có tên trùng giữa các schema nên không nhập nhằng.
alter function public.map_actual_to_sale_target()                              set search_path = public, shared, app_sale;
alter function public.update_sale_target_cells(jsonb,text,text,text,text[])    set search_path = public, shared, app_sale;
alter function public.upsert_dm_dia_ban(jsonb,text,text,text,text[])           set search_path = public, shared, app_sale;
alter function public.dia_ban_hieu_luc(text)                                   set search_path = public, shared, app_sale;
alter function public.kiem_tra_khoang_trong(jsonb)                             set search_path = public, shared, app_sale;
alter function public.chuyen_dia_ban(bigint,text,text,text,text,text,text,text[]) set search_path = public, shared, app_sale;
alter function public.delete_dm_dia_ban(bigint[],text,text,text,text[])        set search_path = public, shared, app_sale;
alter function public.apply_dia_ban_to_plan(bigint[])                          set search_path = public, shared, app_sale;

-- ─── 6) 2 RPC qualify cứng: đổi đúng tham chiếu (CREATE OR REPLACE giữ OID) ─

-- 6a) sale_target_agg: public.sale_target → shared.sale_target
create or replace function public.sale_target_agg(p_mien text, p_months text[])
returns table(mien text, san_pham text, tong numeric)
language sql stable as $function$
  select
    case when st.mien in ('MB','Miền Bắc') then 'MB'
         when st.mien in ('MN','Miền Nam') then 'MN' end as mien,
    st.san_pham,
    sum(case when st.sl_ke_hoach_update is not null
             then coalesce(st.sl_ke_hoach_update, 0)
             else coalesce(st.sl_ke_hoach_dau_nam, 0) end) as tong
  from shared.sale_target st
  where st.thang_ke_hoach = any(p_months)
    and ( (p_mien = 'ALL' and st.mien in ('MB','Miền Bắc','MN','Miền Nam'))
       or (p_mien = 'MB'  and st.mien in ('MB','Miền Bắc'))
       or (p_mien = 'MN'  and st.mien in ('MN','Miền Nam')) )
  group by 1, st.san_pham;
$function$;

-- 6b) usage_agg: public.dm_vat_tu → shared.dm_vat_tu (sv vẫn ở app_order)
create or replace function public.usage_agg(p_mien text, p_y integer, p_m integer)
returns table(mien text, item_code text, san_pham text, th numeric, th_months integer)
language sql stable as $function$
  with base as (
    select
      case when s.area in ('MB','Miền Bắc') then 'MB'
           when s.area in ('MN','Miền Nam') then 'MN' end               as mien,
      s.item_code,
      (split_part(s.month, '-', 1))::int                                as y,
      (split_part(s.month, '-', 2))::int                                as mo,
      coalesce(s.quantity, 0)                                           as q
    from app_order.sv s
    where s.item_code is not null
      and s.month ~ '^[0-9]{4}-[0-9]{1,2}'
      and s.month >= ((p_y - 1)::text || '-01')
      and ( (p_mien = 'ALL' and s.area in ('MB','Miền Bắc','MN','Miền Nam'))
         or (p_mien = 'MB'  and s.area in ('MB','Miền Bắc'))
         or (p_mien = 'MN'  and s.area in ('MN','Miền Nam')) )
  ),
  per_month as (
    select b.mien, b.item_code, b.y, b.mo, sum(b.q) as q
    from base b where b.mien is not null
    group by b.mien, b.item_code, b.y, b.mo
  ),
  agg as (
    select m.mien, m.item_code,
      coalesce(sum(m.q) filter (where m.q > 0 and (m.y*12+m.mo) <= (p_y*12+p_m-1)), 0) as th,
      (count(*)     filter (where m.q > 0 and (m.y*12+m.mo) <= (p_y*12+p_m-1)))::int   as th_months
    from per_month m group by m.mien, m.item_code
  ),
  vt as (
    select d.ma_bravo, max(d.san_pham) as san_pham
    from shared.dm_vat_tu d group by d.ma_bravo
  )
  select a.mien, a.item_code, vt.san_pham, a.th, a.th_months
  from agg a left join vt on vt.ma_bravo = a.item_code;
$function$;

commit;

-- ════════════════════════════════════════════════════════════════════════
-- KIỂM TRA SAU KHI CHẠY (chạy riêng)
-- ════════════════════════════════════════════════════════════════════════
-- (a) public sạch bảng app (chỉ còn RPC), shared/app_sale có đủ:
--   select n.nspname, c.relname, c.relkind from pg_class c
--   join pg_namespace n on n.oid=c.relnamespace
--   where c.relname in ('sale_target','dm_vat_tu','dm_dia_ban','sv_bovattu_actual',
--     'v_th_theo_ps','v_actual_ngoai_ke_hoach') order by 1,2;
-- (b) RPC chạy (không lỗi relation does not exist):
--   select * from public.sale_target_agg('ALL', array[to_char(now(),'YYYY-MM')]) limit 1;
--   select * from public.dia_ban_hieu_luc(to_char(now(),'YYYY-MM')) limit 1;
--   select count(*) from app_sale.v_th_theo_ps;
-- (c) Đếm dữ liệu còn nguyên:
--   select (select count(*) from shared.sale_target) st,
--          (select count(*) from app_sale.sv_bovattu_actual) actual,
--          (select count(*) from shared.dm_vat_tu) vattu;
