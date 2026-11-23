-- Hoàn tác 20261123100000: hoa_don_actual đọc thẳng hoa_don_bovattu_chia như cũ,
-- map_hoadon_to_sale_target khớp theo tên SP (dòng id nhỏ nhất), xoá view hoa_don_actual_theo_ma.
-- Chạy lại "Cập nhật thực hiện" sau khi hoàn tác.

BEGIN;

CREATE OR REPLACE VIEW app_sale.hoa_don_actual AS
 WITH ps_map AS (
         SELECT DISTINCT ON ((lower(btrim(dm_ps.ten_ps)))) lower(btrim(dm_ps.ten_ps)) AS k,
            dm_ps.ps,
            dm_ps.area,
            dm_ps.bu
           FROM shared.dm_ps
          ORDER BY (lower(btrim(dm_ps.ten_ps))), (dm_ps.trang_thai = 'Active'::text) DESC
        ), base AS (
         SELECT h.thang AS thang_ke_hoach,
            COALESCE(d.ps, h.ten_ps) AS ps,
            h.ma_kh AS ma_khach_hang,
            h.bo_vat_tu,
            h.san_pham,
            h.so_luong,
            h.tong_gia_ban,
            d.area AS mien,
            COALESCE(d.bu, NULLIF(btrim(h.bu), ''::text)) AS bu,
            h.nhom_san_pham,
            h.ten_kh AS khach_hang
           FROM app_sale.hoa_don_bovattu_chia h
             LEFT JOIN ps_map d ON d.k = lower(btrim(h.ten_ps))
        )
 SELECT thang_ke_hoach,
    max(mien) AS mien,
    ps,
    ma_khach_hang,
    max(khach_hang) AS khach_hang,
    max(bu) AS bu,
    max(nhom_san_pham) AS nhom_san_pham,
    bo_vat_tu,
    san_pham,
    sum(so_luong) AS sl_thuc_hien,
    sum(tong_gia_ban) / NULLIF(sum(so_luong), 0::numeric) AS don_gia,
    sum(tong_gia_ban) AS doanh_thu_thuc_hien
   FROM base
  GROUP BY thang_ke_hoach, ps, ma_khach_hang, bo_vat_tu, san_pham;

REVOKE ALL ON app_sale.hoa_don_actual FROM public, anon, authenticated;
GRANT SELECT ON app_sale.hoa_don_actual TO service_role;

DROP VIEW IF EXISTS app_sale.hoa_don_actual_theo_ma;

CREATE OR REPLACE FUNCTION public.map_hoadon_to_sale_target()
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'shared', 'app_sale'
 SET statement_timeout TO '5min'
AS $function$
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
           regexp_replace(lower(btrim(ps)), '\s+', ' ', 'g')            as ps_n,
           regexp_replace(lower(btrim(ma_khach_hang)), '\s+', ' ', 'g') as kh_n,
           regexp_replace(lower(btrim(bo_vat_tu)), '\s+', ' ', 'g')     as bo_n,
           regexp_replace(lower(btrim(san_pham)), '\s+', ' ', 'g')      as sp_n,
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
         and regexp_replace(lower(btrim(s.ps)), '\s+', ' ', 'g')            = a.ps_n
         and regexp_replace(lower(btrim(s.ma_khach_hang)), '\s+', ' ', 'g') = a.kh_n
         and regexp_replace(lower(btrim(s.bo_vat_tu)), '\s+', ' ', 'g')     = a.bo_n
         and regexp_replace(lower(btrim(s.san_pham)), '\s+', ' ', 'g')      = a.sp_n
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
         dbvt.ma_bo_vat_tu,
         coalesce(dvt.ma_san_pham, dbvt_sp.ma_bo_vat_tu) as ma_san_pham,
         ha.sl, ha.dt, ha.don_gia, true, now()
    from ha
    join agg_oop o
      on o.thang_ke_hoach = ha.thang_ke_hoach
     and o.ps_n = regexp_replace(lower(btrim(ha.ps)), '\s+', ' ', 'g')
     and o.kh_n = regexp_replace(lower(btrim(ha.ma_khach_hang)), '\s+', ' ', 'g')
     and o.bo_n = regexp_replace(lower(btrim(ha.bo_vat_tu)), '\s+', ' ', 'g')
     and o.sp_n = regexp_replace(lower(btrim(ha.san_pham)), '\s+', ' ', 'g')
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
    ) dvt on true
    left join lateral (
      select ma_bo_vat_tu from shared.dm_bo_vat_tu
       where lower(btrim(bo_vat_tu)) = lower(btrim(ha.san_pham))
       limit 1
    ) dbvt_sp on true;
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

COMMIT;
