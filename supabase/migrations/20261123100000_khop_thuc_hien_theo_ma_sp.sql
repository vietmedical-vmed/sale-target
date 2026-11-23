-- Đồng bộ thực hiện khớp theo MÃ SP khi một tên SP có nhiều dòng kế hoạch khác mã.
--
-- Ca gốc 23/11: BV0336 "Hút áp lực âm" (Mai Trịnh) có 3 dòng kế hoạch mỗi tháng
-- (66801274 bình chứa dịch, 66800794 / 66800795 băng bọt). Hoá đơn bán 4 mã, nhưng
-- map_hoadon_to_sale_target chỉ khớp theo tháng | PS | KH | bộ VT | tên SP rồi lấy dòng id nhỏ nhất,
-- nên toàn bộ thực hiện dồn vào dòng 66801274, hai dòng còn lại luôn 0.
-- FY26 có 480 khoá tháng bị như vậy.
--
-- Thay đổi:
-- 1. View mới app_sale.hoa_don_actual_theo_ma: như hoa_don_actual nhưng tách thêm theo mã SP
--    (ma_vat_tu trên hoá đơn → shared.dm_vat_tu.ma_bravo → ma_san_pham; dòng bộ không có mã vật tư
--    thì mã = null).
-- 2. hoa_don_actual đọc lại từ view mới (cùng cột, cùng số liệu theo khoá).
-- 3. map_hoadon_to_sale_target:
--    - khớp dòng kế hoạch cùng khoá + cùng mã SP trước;
--    - mã không có dòng riêng thì vào dòng cùng khoá có đơn giá gần đơn giá bình quân hoá đơn nhất,
--      hoà thì id nhỏ nhất; mã null (dòng bộ) giữ cách cũ: dòng id nhỏ nhất;
--    - một dòng kế hoạch nhận nhiều mã thì cộng dồn;
--    - dòng OOP vẫn một dòng mỗi khoá như cũ; mã SP lấy mã có SL lớn nhất trên hoá đơn
--      (trước đây tra dm_vat_tu theo tên, limit 1 không thứ tự → có thể ra mã không bán).
--    - đọc hoá đơn một lần vào bảng tạm thay vì 3 lần qua view.
-- Tổng SL / doanh thu thực hiện theo tháng không đổi, chỉ chia lại giữa các dòng cùng khoá.
-- Sau migration chạy "Cập nhật thực hiện" (cap_nhat_thuc_hien).
-- Hoàn tác: supabase/rollbacks/20261123100000_khop_thuc_hien_theo_ma_sp_ROLLBACK.sql

CREATE OR REPLACE VIEW app_sale.hoa_don_actual_theo_ma AS
WITH ps_map AS (
  SELECT DISTINCT ON (lower(btrim(dm_ps.ten_ps)))
         lower(btrim(dm_ps.ten_ps)) AS k,
         dm_ps.ps,
         dm_ps.area,
         dm_ps.bu
    FROM shared.dm_ps
   ORDER BY lower(btrim(dm_ps.ten_ps)), (dm_ps.trang_thai = 'Active'::text) DESC
), vt_map AS (
  SELECT DISTINCT ON (v.ma_bravo) v.ma_bravo, v.ma_san_pham
    FROM shared.dm_vat_tu v
   WHERE v.ma_bravo IS NOT NULL
     AND NULLIF(btrim(v.ma_san_pham), '') IS NOT NULL
   ORDER BY v.ma_bravo, v.id
), base AS (
  SELECT h.thang AS thang_ke_hoach,
         COALESCE(d.ps, h.ten_ps) AS ps,
         h.ma_kh AS ma_khach_hang,
         h.bo_vat_tu,
         h.san_pham,
         vt.ma_san_pham,
         h.so_luong,
         h.tong_gia_ban,
         d.area AS mien,
         COALESCE(d.bu, NULLIF(btrim(h.bu), ''::text)) AS bu,
         h.nhom_san_pham,
         h.ten_kh AS khach_hang
    FROM app_sale.hoa_don_bovattu_chia h
    LEFT JOIN ps_map d ON d.k = lower(btrim(h.ten_ps))
    LEFT JOIN vt_map vt ON vt.ma_bravo = h.ma_vat_tu
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
       ma_san_pham,
       sum(so_luong) AS sl_thuc_hien,
       sum(tong_gia_ban) / NULLIF(sum(so_luong), 0::numeric) AS don_gia,
       sum(tong_gia_ban) AS doanh_thu_thuc_hien
  FROM base
 GROUP BY thang_ke_hoach, ps, ma_khach_hang, bo_vat_tu, san_pham, ma_san_pham;

REVOKE ALL ON app_sale.hoa_don_actual_theo_ma FROM public, anon, authenticated;
GRANT SELECT ON app_sale.hoa_don_actual_theo_ma TO service_role;

CREATE OR REPLACE VIEW app_sale.hoa_don_actual AS
SELECT thang_ke_hoach,
       max(mien) AS mien,
       ps,
       ma_khach_hang,
       max(khach_hang) AS khach_hang,
       max(bu) AS bu,
       max(nhom_san_pham) AS nhom_san_pham,
       bo_vat_tu,
       san_pham,
       sum(sl_thuc_hien) AS sl_thuc_hien,
       sum(doanh_thu_thuc_hien) / NULLIF(sum(sl_thuc_hien), 0::numeric) AS don_gia,
       sum(doanh_thu_thuc_hien) AS doanh_thu_thuc_hien
  FROM app_sale.hoa_don_actual_theo_ma
 GROUP BY thang_ke_hoach, ps, ma_khach_hang, bo_vat_tu, san_pham;

REVOKE ALL ON app_sale.hoa_don_actual FROM public, anon, authenticated;
GRANT SELECT ON app_sale.hoa_don_actual TO service_role;

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
  v_theo_ma   int := 0;
  v_deleted   int := 0;
  v_inserted  int := 0;
begin
  -- Hoá đơn sau chia PS, tách theo mã SP; đọc view một lần.
  create temp table _hd on commit drop as
  select h.*,
         regexp_replace(lower(btrim(h.ps)), '\s+', ' ', 'g')            as ps_n,
         regexp_replace(lower(btrim(h.ma_khach_hang)), '\s+', ' ', 'g') as kh_n,
         regexp_replace(lower(btrim(h.bo_vat_tu)), '\s+', ' ', 'g')     as bo_n,
         regexp_replace(lower(btrim(h.san_pham)), '\s+', ' ', 'g')      as sp_n,
         nullif(lower(btrim(h.ma_san_pham)), '')                        as ma_n
    from hoa_don_actual_theo_ma h;

  select array_agg(distinct thang_ke_hoach) into v_months from _hd;
  if v_months is null then
    return jsonb_build_object('months', 0, 'zeroed', 0, 'set_rows', 0,
                              'matched_keys', 0, 'total_keys', 0, 'unmatched_keys', 0,
                              'matched_by_code', 0, 'oop_deleted', 0, 'oop_inserted', 0);
  end if;

  update sale_target
     set sl_thuc_hien = 0, doanh_thu_thuc_hien = 0, updated_at = now()
   where thang_ke_hoach = any(v_months)
     and coalesce(ngoai_ke_hoach, false) = false
     and (sl_thuc_hien is distinct from 0
          or doanh_thu_thuc_hien is distinct from 0);
  get diagnostics v_zeroed = row_count;

  -- Mỗi (khoá, mã) tìm 1 dòng kế hoạch: cùng mã trước, không có thì dòng giá gần nhất.
  create temp table _agg on commit drop as
  with a as (
    select thang_ke_hoach, ps_n, kh_n, bo_n, sp_n, ma_n,
           sum(sl_thuc_hien)        as sl,
           sum(doanh_thu_thuc_hien) as dt,
           -- Mã null (dòng bộ, không có mã vật tư): không so giá, giữ cách cũ là dòng id nhỏ nhất.
           case when ma_n is not null
                then sum(doanh_thu_thuc_hien) / nullif(sum(sl_thuc_hien), 0) end as gia_hd
      from _hd
     group by 1, 2, 3, 4, 5, 6
  )
  select a.*, coalesce(t_ma.id, t_gia.id) as target_id, (t_ma.id is not null) as theo_ma
    from a
    left join lateral (
      select s.id from sale_target s
       where a.ma_n is not null
         and s.thang_ke_hoach                = a.thang_ke_hoach
         and coalesce(s.ngoai_ke_hoach, false) = false
         and regexp_replace(lower(btrim(s.ps)), '\s+', ' ', 'g')            = a.ps_n
         and regexp_replace(lower(btrim(s.ma_khach_hang)), '\s+', ' ', 'g') = a.kh_n
         and regexp_replace(lower(btrim(s.bo_vat_tu)), '\s+', ' ', 'g')     = a.bo_n
         and regexp_replace(lower(btrim(s.san_pham)), '\s+', ' ', 'g')      = a.sp_n
         and lower(btrim(s.ma_san_pham)) = a.ma_n
       order by s.id
       limit 1
    ) t_ma on true
    left join lateral (
      select s.id from sale_target s
       where t_ma.id is null
         and s.thang_ke_hoach                = a.thang_ke_hoach
         and coalesce(s.ngoai_ke_hoach, false) = false
         and regexp_replace(lower(btrim(s.ps)), '\s+', ' ', 'g')            = a.ps_n
         and regexp_replace(lower(btrim(s.ma_khach_hang)), '\s+', ' ', 'g') = a.kh_n
         and regexp_replace(lower(btrim(s.bo_vat_tu)), '\s+', ' ', 'g')     = a.bo_n
         and regexp_replace(lower(btrim(s.san_pham)), '\s+', ' ', 'g')      = a.sp_n
       order by abs(s.don_gia - a.gia_hd) nulls last, s.id
       limit 1
    ) t_gia on true;

  update sale_target s
     set sl_thuc_hien = x.sl,
         doanh_thu_thuc_hien = x.dt,
         updated_at = now()
    from (select target_id, sum(sl) as sl, sum(dt) as dt
            from _agg
           where target_id is not null
           group by target_id) x
   where x.target_id = s.id;
  get diagnostics v_set = row_count;

  delete from sale_target
   where thang_ke_hoach = any(v_months)
     and ngoai_ke_hoach = true;
  get diagnostics v_deleted = row_count;

  -- OOP: khoá không có dòng kế hoạch nào, một dòng mỗi khoá như cũ.
  with agg_oop as (
    select distinct a.thang_ke_hoach, a.ps_n, a.kh_n, a.bo_n, a.sp_n
      from _agg a
     where a.target_id is null
  ),
  ha as (
    select thang_ke_hoach, ps, ma_khach_hang, bo_vat_tu, san_pham,
           max(ps_n) as ps_n, max(kh_n) as kh_n, max(bo_n) as bo_n, max(sp_n) as sp_n,
           max(mien)          as mien,
           max(khach_hang)    as khach_hang,
           max(bu)            as bu,
           max(nhom_san_pham) as nhom_san_pham,
           sum(sl_thuc_hien)  as sl,
           sum(doanh_thu_thuc_hien) as dt,
           sum(doanh_thu_thuc_hien)::numeric / nullif(sum(sl_thuc_hien),0)::numeric as don_gia
      from _hd
     group by 1,2,3,4,5
  ),
  ma_chinh as (
    select distinct on (thang_ke_hoach, ps, ma_khach_hang, bo_vat_tu, san_pham)
           thang_ke_hoach, ps, ma_khach_hang, bo_vat_tu, san_pham, ma_san_pham
      from _hd
     where ma_n is not null
     order by thang_ke_hoach, ps, ma_khach_hang, bo_vat_tu, san_pham,
              sl_thuc_hien desc nulls last, ma_san_pham
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
         coalesce(mc.ma_san_pham, dvt.ma_san_pham, dbvt_sp.ma_bo_vat_tu) as ma_san_pham,
         ha.sl, ha.dt, ha.don_gia, true, now()
    from ha
    join agg_oop o
      on o.thang_ke_hoach = ha.thang_ke_hoach
     and o.ps_n = ha.ps_n
     and o.kh_n = ha.kh_n
     and o.bo_n = ha.bo_n
     and o.sp_n = ha.sp_n
    left join ma_chinh mc
      on mc.thang_ke_hoach = ha.thang_ke_hoach
     and mc.ps = ha.ps
     and mc.ma_khach_hang = ha.ma_khach_hang
     and mc.bo_vat_tu is not distinct from ha.bo_vat_tu
     and mc.san_pham is not distinct from ha.san_pham
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
       order by ma_san_pham
       limit 1
    ) dvt on true
    left join lateral (
      select ma_bo_vat_tu from shared.dm_bo_vat_tu
       where lower(btrim(bo_vat_tu)) = lower(btrim(ha.san_pham))
       limit 1
    ) dbvt_sp on true;
  get diagnostics v_inserted = row_count;

  select count(*), count(*) filter (where target_id is not null), count(*) filter (where theo_ma)
    into v_total, v_matched, v_theo_ma
    from _agg;

  return jsonb_build_object(
    'months',          array_length(v_months, 1),
    'zeroed',          v_zeroed,
    'set_rows',        v_set,
    'matched_keys',    v_matched,
    'total_keys',      v_total,
    'unmatched_keys',  v_total - v_matched,
    'matched_by_code', v_theo_ma,
    'oop_deleted',     v_deleted,
    'oop_inserted',    v_inserted
  );
end;
$function$;
