-- ROLLBACK cho 20260807110000_hoa_don_actual_flow.sql
-- Trỏ 2 view về lại sv_bovattu_actual, bỏ hàm map mới + view hoa_don_actual.
-- (KHÔNG đụng dữ liệu sale_target; nếu cần khôi phục số cũ, chạy lại
--  public.map_actual_to_sale_target() sau rollback.)

-- 1) Trỏ v_actual_ngoai_ke_hoach về sv_bovattu_actual
create or replace view app_sale.v_actual_ngoai_ke_hoach as
 with ps_ref as (
         select t.ps_n, t.ps_canon, t.bu, t.mien
           from ( select lower(btrim(s.ps)) as ps_n, s.ps as ps_canon, s.bu, s.mien,
                    row_number() over (partition by (lower(btrim(s.ps))) order by (coalesce(btrim(s.bu), ''::text) <> ''::text) desc, (coalesce(btrim(s.mien), ''::text) <> ''::text) desc, (count(*)) desc) as rn
                   from shared.sale_target s
                  where coalesce(btrim(s.ps), ''::text) <> ''::text
                  group by (lower(btrim(s.ps))), s.ps, s.bu, s.mien) t
          where t.rn = 1
        ), bu_ref as (
         select t.bu_n, t.bu_canon
           from ( select regexp_replace(lower(btrim(s.bu)), '[^a-z0-9]'::text, ''::text, 'g'::text) as bu_n, s.bu as bu_canon,
                    row_number() over (partition by (regexp_replace(lower(btrim(s.bu)), '[^a-z0-9]'::text, ''::text, 'g'::text)) order by (count(*)) desc) as rn
                   from shared.sale_target s
                  where coalesce(btrim(s.bu), ''::text) <> ''::text
                  group by (regexp_replace(lower(btrim(s.bu)), '[^a-z0-9]'::text, ''::text, 'g'::text)), s.bu) t
          where t.rn = 1
        ), sp_ref as (
         select t.sp_n, t.nhom_san_pham
           from ( select lower(btrim(s.san_pham)) as sp_n, s.nhom_san_pham,
                    row_number() over (partition by (lower(btrim(s.san_pham))) order by (count(*)) desc) as rn
                   from shared.sale_target s
                  where coalesce(btrim(s.san_pham), ''::text) <> ''::text and coalesce(btrim(s.nhom_san_pham), ''::text) <> ''::text
                  group by (lower(btrim(s.san_pham))), s.nhom_san_pham) t
          where t.rn = 1
        )
 select a.thang_ke_hoach,
    coalesce(nullif(btrim(a.mien), ''::text), p.mien) as mien,
    coalesce(p.ps_canon, a.ps) as ps,
    a.ma_khach_hang, a.khach_hang,
    coalesce(p.bu, b.bu_canon, nullif(btrim(a.bu), ''::text)) as bu,
    coalesce(g.nhom_san_pham, nullif(btrim(a.nhom_san_pham), ''::text)) as nhom_san_pham,
    a.bo_vat_tu, a.san_pham, a.sl_thuc_hien
   from app_sale.sv_bovattu_actual a
     left join ps_ref p on p.ps_n = lower(btrim(a.ps))
     left join bu_ref b on b.bu_n = regexp_replace(lower(btrim(a.bu)), '[^a-z0-9]'::text, ''::text, 'g'::text)
     left join sp_ref g on g.sp_n = lower(btrim(a.san_pham))
  where not (exists ( select 1
           from shared.sale_target s
          where s.thang_ke_hoach = a.thang_ke_hoach
            and lower(btrim(coalesce(s.ps, ''::text))) = lower(btrim(coalesce(a.ps, ''::text)))
            and lower(btrim(coalesce(s.ma_khach_hang, ''::text))) = lower(btrim(coalesce(a.ma_khach_hang, ''::text)))
            and lower(btrim(coalesce(s.bo_vat_tu, ''::text))) = lower(btrim(coalesce(a.bo_vat_tu, ''::text)))
            and lower(btrim(coalesce(s.san_pham, ''::text))) = lower(btrim(coalesce(a.san_pham, ''::text)))));
grant select on app_sale.v_actual_ngoai_ke_hoach to service_role, anon, authenticated;

-- 2) Trỏ v_actual_unmatched về sv_bovattu_actual
create or replace view app_sale.v_actual_unmatched as
 select thang_ke_hoach, mien, ps, ma_khach_hang, khach_hang, bo_vat_tu, san_pham,
    sum(sl_thuc_hien) as sl_thuc_hien
   from app_sale.sv_bovattu_actual a
  where not (exists ( select 1
           from shared.sale_target s
          where s.thang_ke_hoach = a.thang_ke_hoach
            and lower(btrim(s.ps)) = lower(btrim(a.ps))
            and lower(btrim(s.ma_khach_hang)) = lower(btrim(a.ma_khach_hang))
            and lower(btrim(s.bo_vat_tu)) = lower(btrim(a.bo_vat_tu))
            and lower(btrim(s.san_pham)) = lower(btrim(a.san_pham))))
  group by thang_ke_hoach, mien, ps, ma_khach_hang, khach_hang, bo_vat_tu, san_pham
  order by (sum(sl_thuc_hien)) desc;
grant select on app_sale.v_actual_unmatched to service_role;

-- 3) Bỏ hàm map mới + view chuẩn hoá
drop function if exists public.map_hoadon_to_sale_target();
drop view if exists app_sale.hoa_don_actual;

-- 4) Bỏ 2 index biểu thức gộp khoảng trắng
drop index if exists shared.idx_sale_target_oopkey_ws;
drop index if exists shared.idx_sale_target_mapkey_ws;
