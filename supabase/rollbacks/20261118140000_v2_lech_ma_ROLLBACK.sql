-- Rollback 20261118140000_v2_lech_ma: trả mã/tên SP kế hoạch (quota đi theo qua trigger), gỡ bảng ghép
-- mã + trả app_sale.quota_theo_khoa về bản 20261118100000, xoá dòng danh mục đã thêm.
-- Sau đó chạy lại app_sale.chay_gan_quota_hop_dong('rollback_v2').
BEGIN;

SET CONSTRAINTS shared.uq_sale_target_khoa DEFERRED;
UPDATE shared.sale_target s
SET ma_san_pham = l.truoc->>'ma_san_pham', san_pham = l.truoc->>'san_pham', updated_at = now()
FROM app_sale.quota_chuan_hoa_log l
WHERE l.buoc = 'v2_lech_ma_20261118' AND l.bang = 'sale_target' AND l.ban_ghi_id = s.id;
SET CONSTRAINTS shared.uq_sale_target_khoa IMMEDIATE;

-- trigger giu_khoa / ma_sp_quota đã đưa quota về khoá cũ; trả nốt mã SP + dấu thời gian cũ
UPDATE shared.quota_thau q
SET ma_san_pham = l.truoc->>'ma_san_pham', updated_at = (l.truoc->>'updated_at')::timestamptz,
    updated_by = l.truoc->>'updated_by'
FROM app_sale.quota_chuan_hoa_log l
WHERE l.buoc = 'v2_lech_ma_20261118' AND l.bang = 'quota_thau' AND l.ban_ghi_id = q.id;

create or replace function app_sale.quota_theo_khoa(
  p_nam text default 'FY26',
  p_fy_start date default date '2026-04-01',
  p_thang text default null
)
returns table (
  quota_id bigint, ma_khach_hang text, khoa_sp text,
  ps text, loai text, dot integer, thang_thau text, tt text, chinh_truoc_fy boolean,
  bu text, mien text, nhom_san_pham text, san_pham text, ma_san_pham text,
  so_luong numeric, don_gia numeric,
  bung boolean, dinh_muc numeric, n_khoa_bo integer,
  sl numeric, tien numeric
)
language sql
stable
set search_path = shared, app_sale, pg_temp
as $$
with tham_so as (
  select
    coalesce(p_thang,
             (select value #>> '{}' from shared.app_config where key = 'current_month'),
             to_char(now() at time zone 'Asia/Ho_Chi_Minh', 'YYYY-MM')) as thang,
    to_char(p_fy_start, 'YYYY-MM') as fy_thang
),
k as (select nut, khoa from app_sale.v_khoa_so_sanh_sp),
-- quota chính thức của năm, kèm trạng thái đợt giống lib/quota.js trangThaiDot
q0 as (
  select q.id, q.ma_khach_hang, q.ps, q.loai, q.dot, q.bu, q.mien, q.nhom_san_pham,
    q.san_pham, q.ma_san_pham, q.so_luong, q.don_gia, d.thang_thau,
    case
      when q.loai = 'cu' then 'cu'
      when shared.het_han_dot(d.thang_thau, d.thoi_gian) is null or d.thang_thau > ts.thang then 'up'
      when shared.het_han_dot(d.thang_thau, d.thoi_gian) < ts.thang
       and shared.het_han_dot(d.thang_thau, d.thoi_gian) < ts.fy_thang then 'het'
      else 'on'
    end as tt,
    (q.loai = 'chinh' and d.thang_thau < ts.fy_thang) as chinh_truoc_fy
  from shared.quota_thau q
  cross join tham_so ts
  left join shared.dot_thau d
    on d.nam_tai_chinh = q.nam_tai_chinh and d.ps = q.ps and d.ma_khach_hang = q.ma_khach_hang
   and d.nhom_san_pham = q.nhom_san_pham and d.loai = q.loai and d.dot = q.dot
  where q.nam_tai_chinh = p_nam
    and q.trang_thai = 'chinh_thuc'
    and q.bu is distinct from 'test'
    and coalesce(q.so_luong, 0) <> 0
),
-- bộ chưa có mã chung → linh kiện (nhóm thay thế đã gộp 1 khoá trong v_khoa_so_sanh_sp)
bo_bung as (
  select trim(b.ma_bo_vat_tu) as ma_bo
  from shared.dm_bo_vat_tu b
  where coalesce(trim(b.ma_chung), '') in ('', 'Chưa có')
),
gia_sp as (
  select trim(ma_san_pham) as sp, avg(nullif(don_gia_thau_moi, 0)) as gia
  from shared.dm_vat_tu
  group by 1
),
linh_kien as (
  select trim(m.ma_bo_vat_tu) as ma_bo, k.khoa,
         max(m.so_luong_dinh_muc) as dinh_muc,
         avg(g.gia) as gia
  from shared.dm_bo_vat_tu_mapping m
  join bo_bung bb on bb.ma_bo = trim(m.ma_bo_vat_tu)
  join k on k.nut = 'S:' || trim(m.ma_san_pham)
  left join gia_sp g on g.sp = trim(m.ma_san_pham)
  group by 1, 2
),
linh_kien_gia as (
  select lk.*,
    lk.dinh_muc * coalesce(lk.gia, avg(lk.gia) over (partition by lk.ma_bo), 1) as trong_so
  from linh_kien lk
),
linh_kien_w as (
  select lk.*,
    lk.trong_so / nullif(sum(lk.trong_so) over (partition by lk.ma_bo), 0) as ty_trong,
    count(*) over (partition by lk.ma_bo)::int as n_khoa
  from linh_kien_gia lk
)
-- sản phẩm lẻ / bộ có mã chung
select q0.id, q0.ma_khach_hang,
       coalesce(kb.khoa, ks.khoa, 'Q:' || coalesce(trim(q0.ma_san_pham), q0.san_pham)),
       q0.ps, q0.loai, q0.dot, q0.thang_thau, q0.tt, q0.chinh_truoc_fy,
       q0.bu, q0.mien, q0.nhom_san_pham, q0.san_pham, q0.ma_san_pham,
       q0.so_luong, q0.don_gia,
       false, 1::numeric, 1,
       q0.so_luong, q0.so_luong * q0.don_gia
from q0
left join k kb on kb.nut = 'B:' || trim(q0.ma_san_pham)
left join k ks on ks.nut = 'S:' || trim(q0.ma_san_pham)
where not exists (select 1 from bo_bung bb where bb.ma_bo = trim(q0.ma_san_pham))
union all
-- bộ chưa có mã chung: bung ra linh kiện (SL × định mức; tiền chia theo giá × định mức)
select q0.id, q0.ma_khach_hang, lk.khoa,
       q0.ps, q0.loai, q0.dot, q0.thang_thau, q0.tt, q0.chinh_truoc_fy,
       q0.bu, q0.mien, q0.nhom_san_pham, q0.san_pham, q0.ma_san_pham,
       q0.so_luong, q0.don_gia,
       true, lk.dinh_muc, lk.n_khoa,
       q0.so_luong * lk.dinh_muc, q0.so_luong * q0.don_gia * lk.ty_trong
from q0
join linh_kien_w lk on lk.ma_bo = trim(q0.ma_san_pham);
$$;

revoke all on function app_sale.quota_theo_khoa(text, date, text) from public, anon, authenticated;
DROP TABLE IF EXISTS app_sale.khoa_sp_alias;

DELETE FROM shared.dm_vat_tu v USING app_sale.quota_chuan_hoa_log l
WHERE l.buoc = 'v2_lech_ma_20261118' AND l.bang = 'dm_vat_tu' AND l.ban_ghi_id = v.id;
DELETE FROM shared.dm_bo_vat_tu b USING app_sale.quota_chuan_hoa_log l
WHERE l.buoc = 'v2_lech_ma_20261118' AND l.bang = 'dm_bo_vat_tu' AND l.ban_ghi_id = b.id;

DELETE FROM app_sale.quota_chuan_hoa_log WHERE buoc = 'v2_lech_ma_20261118';

COMMIT;
