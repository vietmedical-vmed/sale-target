-- Thực hiện không về dòng kế hoạch vì tên lệch giữa hoá đơn và kế hoạch.
--
-- Ca gốc 27/10: Interlock 18 @ BV0320 (Hương Đồng) T8 thiếu dòng kế hoạch tháng → thực hiện
-- thành dòng ngoài kế hoạch (OOP), màn Chi tiết kế hoạch không hiện. 3 ca thiếu tháng đã tạo
-- dòng tay (audit_log ensureMonthRow, admin_script). Quét thêm ra 2 kiểu lệch tên:
--   1. Khác số dấu cách: kế hoạch "MOP dài  (non-VE) - ZB" (2 dấu cách) vs hoá đơn 1 dấu cách;
--      danh mục "Gối thay lại  - UOC" (2 dấu cách) vs kế hoạch 1 dấu cách.
--      → map_hoadon_to_sale_target so khoá sau khi gộp khoảng trắng (khớp idx_sale_target_mapkey_ws).
--   2. Bộ VT kế hoạch dùng tên cũ không có trong dm_bo_vat_tu:
--      "Vật tư riêng lẻ - NSCT (Applied)" → "Vật tư riêng lẻ - Applied" (AP.VTRL)
--      "Vật tư riêng lẻ - NSCT Khác"      → "Vật tư riêng lẻ - CSVT"    (CSVT.VTRL)
--      Hoá đơn của đúng các SP này dùng tên danh mục. Đổi tên có thể dồn dòng về cùng khoá
--      → hoãn uq_sale_target_khoa rồi gộp bằng gop_dong_trung_sale_target.
--      Quota đi theo khoá mới nhờ trg_sale_target_giu_khoa_quota.
-- Sau migration phải chạy "Cập nhật thực hiện" (start_sync_job) để số về đúng dòng.
-- Hoàn tác: supabase/rollbacks/20261027100000_khop_thuc_hien_ten_bo_vat_tu_ROLLBACK.sql

BEGIN;

CREATE TABLE backup.bak_20261027_ten_bo_vat_tu AS
SELECT * FROM shared.sale_target
WHERE bo_vat_tu IN ('Vật tư riêng lẻ - NSCT (Applied)', 'Vật tư riêng lẻ - NSCT Khác',
                    'Vật tư riêng lẻ - Applied', 'Vật tư riêng lẻ - CSVT');
ALTER TABLE backup.bak_20261027_ten_bo_vat_tu ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON backup.bak_20261027_ten_bo_vat_tu FROM PUBLIC, anon, authenticated;

SET CONSTRAINTS shared.uq_sale_target_khoa DEFERRED;

CREATE TEMP TABLE _doi_ten ON COMMIT DROP AS
WITH u AS (
  UPDATE shared.sale_target s SET
    bo_vat_tu    = m.moi,
    ma_bo_vat_tu = m.ma,
    updated_at   = now()
  FROM (VALUES ('Vật tư riêng lẻ - NSCT (Applied)', 'Vật tư riêng lẻ - Applied', 'AP.VTRL'),
               ('Vật tư riêng lẻ - NSCT Khác',      'Vật tư riêng lẻ - CSVT',    'CSVT.VTRL')) m(cu, moi, ma)
  WHERE s.bo_vat_tu = m.cu
  RETURNING s.id
)
SELECT id FROM u;

SELECT shared.gop_dong_trung_sale_target((SELECT array_agg(id) FROM _doi_ten));

SET CONSTRAINTS shared.uq_sale_target_khoa IMMEDIATE;

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

REVOKE ALL ON FUNCTION public.map_hoadon_to_sale_target() FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.map_hoadon_to_sale_target() TO service_role;

COMMIT;
