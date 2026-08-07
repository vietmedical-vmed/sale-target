-- ════════════════════════════════════════════════════════════════════════
-- ROLLBACK cho 20260806100000_optimize_indexes_matview.sql
-- ════════════════════════════════════════════════════════════════════════

-- PHẦN 2 ngược: bỏ matview + RPC, dựng lại 2 view thường (kèm security_invoker).
drop function if exists public.refresh_bao_cao_sale();
drop materialized view if exists app_sale.v_th_theo_ps;
drop materialized view if exists app_sale.v_th_theo_sp;

create or replace view app_sale.v_th_theo_ps as
  select s.thang_ke_hoach, s.mien, s.ps, s.ma_khach_hang, s.khach_hang,
         sum(s.sl_ke_hoach_dau_nam) as sl_ke_hoach_dau_nam,
         sum(s.sl_ke_hoach_update)  as sl_ke_hoach_update,
         sum(s.doanh_thu_kh_update) as doanh_thu_ke_hoach,
         sum(s.sl_thuc_hien)        as sl_thuc_hien,
         false as la_ngoai_ke_hoach, 0 as thu_tu
  from shared.sale_target s
  group by s.thang_ke_hoach, s.mien, s.ps, s.ma_khach_hang, s.khach_hang
  union all
  select o.thang_ke_hoach, o.mien, o.ps, null::text, 'Ngoài kế hoạch'::text,
         null::numeric, null::numeric, null::numeric,
         sum(o.sl_thuc_hien), true, 1
  from app_sale.v_actual_ngoai_ke_hoach o
  group by o.thang_ke_hoach, o.mien, o.ps;
alter view app_sale.v_th_theo_ps set (security_invoker = on);
grant select on app_sale.v_th_theo_ps to anon, authenticated, service_role;

create or replace view app_sale.v_th_theo_sp as
  select s.thang_ke_hoach, s.bu, s.nhom_san_pham, s.bo_vat_tu, s.san_pham,
         s.ma_khach_hang, s.khach_hang,
         sum(s.sl_ke_hoach_dau_nam) as sl_ke_hoach_dau_nam,
         sum(s.sl_ke_hoach_update)  as sl_ke_hoach_update,
         sum(s.doanh_thu_kh_update) as doanh_thu_ke_hoach,
         sum(s.sl_thuc_hien)        as sl_thuc_hien,
         false as la_ngoai_ke_hoach, 0 as thu_tu
  from shared.sale_target s
  group by s.thang_ke_hoach, s.bu, s.nhom_san_pham, s.bo_vat_tu, s.san_pham,
           s.ma_khach_hang, s.khach_hang
  union all
  select o.thang_ke_hoach, o.bu, o.nhom_san_pham, o.bo_vat_tu, o.san_pham,
         null::text, 'Ngoài kế hoạch'::text,
         null::numeric, null::numeric, null::numeric,
         sum(o.sl_thuc_hien), true, 1
  from app_sale.v_actual_ngoai_ke_hoach o
  group by o.thang_ke_hoach, o.bu, o.nhom_san_pham, o.bo_vat_tu, o.san_pham;
alter view app_sale.v_th_theo_sp set (security_invoker = on);
grant select on app_sale.v_th_theo_sp to anon, authenticated, service_role;

-- PHẦN 1 ngược: bỏ 2 index biểu thức.
drop index if exists shared.idx_sale_target_oopkey;
drop index if exists shared.idx_sale_target_mapkey;
