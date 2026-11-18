-- P2 liên kết quota ↔ hợp đồng: đối chiếu CHỈ ĐỌC (không ghi vào quota_thau / hợp đồng).
--
-- 1. shared.v_khoa_so_sanh_sp: mỗi mã (nút) → khoá so sánh chung.
--    Nút: 'S:' mã sản phẩm (dm_vat_tu.ma_san_pham), 'C:' mã chung, 'B:' mã bộ
--    (dm_bo_vat_tu.ma_bo_vat_tu), 'T:' nhóm thay thế trong bộ không có mã chung.
--    Cạnh: S–C (dm_vat_tu), B–C (dm_bo_vat_tu có mã chung), S–T (các linh kiện thay thế
--    nhau trong bộ chưa có mã chung, vd Persona MC). Khoá = nút nhỏ nhất của thành
--    phần liên thông, nên các mã wildcard cùng 1 mã chung (vd AR-1xxxC / AR-5035TC-xx)
--    và 1 mã SP ứng nhiều mã chung (AR-1588RT) gộp về 1 khoá.
-- 2. shared.v_hop_dong_dong: từng dòng hợp đồng + khoá SP (theo mã chung, dự phòng theo
--    mã NCC) + PS ngắn (dm_ps). khoa_sp NULL = chưa map được.
-- 3. shared.doi_chieu_quota_hop_dong(): theo KH × khoá SP, so quota (1.4 / chính & BS
--    on hand / upcoming) với hợp đồng (ký trước năm TC còn hạn / ký trong năm TC).
--    Bộ chưa có mã chung (Zimmer, UO.HTPD.COP1): hợp đồng ghi linh kiện, nên quota bộ
--    được bung ra linh kiện theo dm_bo_vat_tu_mapping (SL × định mức; nhóm thay thế
--    tính 1 lần; tiền quota chia theo giá thầu mới × định mức).
--    Quota 1.4 so với SL CÒN LẠI đầu năm TC của HĐ ký trước năm TC còn hạn
--    (SL HĐ − hóa đơn app_contract.hoa_don_bovattu trước đầu năm, theo số HĐ × mã chung;
--    hóa đơn chỉ có từ 04/2025). Quota chính + BS on hand so với SL HĐ ký trong năm TC
--    đến hết tháng hiện tại. On hand / upcoming theo luật đợt của app (current_month).
--
-- Bảng hợp đồng public.contract_* bật RLS không policy; view chạy quyền owner nên
-- PHẢI thu quyền anon / authenticated (xem memory drop-function-mat-quyen).

create or replace view shared.v_khoa_so_sanh_sp as
with recursive canh(a, b) as (
  select 'S:' || trim(ma_san_pham), 'C:' || trim(ma_chung)
  from shared.dm_vat_tu
  where coalesce(trim(ma_san_pham), '') not in ('', 'Chưa có')
    and coalesce(trim(ma_chung), '') not in ('', 'Chưa có')
  union
  select 'B:' || trim(ma_bo_vat_tu), 'C:' || trim(ma_chung)
  from shared.dm_bo_vat_tu
  where coalesce(trim(ma_bo_vat_tu), '') not in ('', 'Chưa có')
    and coalesce(trim(ma_chung), '') not in ('', 'Chưa có')
  union
  select 'S:' || trim(m.ma_san_pham), 'T:' || m.ma_bo_vat_tu || '|' || m.nhom_thay_the
  from shared.dm_bo_vat_tu_mapping m
  join shared.dm_bo_vat_tu b using (ma_bo_vat_tu)
  where coalesce(trim(b.ma_chung), '') in ('', 'Chưa có')
    and nullif(trim(m.nhom_thay_the), '') is not null
    and coalesce(trim(m.ma_san_pham), '') not in ('', 'Chưa có')
),
g(a, b) as (
  select a, b from canh
  union
  select b, a from canh
),
r(nut, toi) as (
  select a, a from g
  union
  select r.nut, g.b from r join g on g.a = r.toi
)
select nut, min(toi) as khoa
from r
group by nut;

create or replace view shared.v_hop_dong_dong as
with k as (select nut, khoa from shared.v_khoa_so_sanh_sp),
ncc as (
  select distinct on (trim(v.ma_ncc)) trim(v.ma_ncc) as ma_ncc, k.khoa
  from shared.dm_vat_tu v
  join k on k.nut = 'S:' || trim(v.ma_san_pham)
  where coalesce(trim(v.ma_ncc), '') not in ('', 'Chưa có')
  order by trim(v.ma_ncc), k.khoa
),
ps as (
  select distinct on (ten_ps) ten_ps, ps
  from shared.dm_ps
  order by ten_ps, (trang_thai = 'Active') desc, ps
)
select
  i.id as contract_item_id,
  c.ma_hd, c.so_hd, c.ngay_ky, c.thoi_han, c.khay, c.mien,
  c.ma_kh, c.ten_kh, c.ten_ps, ps.ps,
  c.so_bao_gia, c.so_goi_thau, c.is_ngoai_khoa,
  i.ma_chung, i.ma_ncc, i.ten_hang_hoa,
  i.so_luong, i.don_gia, i.so_luong * i.don_gia as thanh_tien,
  coalesce(kc.khoa, ncc.khoa) as khoa_sp,
  case when kc.khoa is not null then 'ma_chung'
       when ncc.khoa is not null then 'ma_ncc' end as nguon_map
from public.contract_items i
join public.contract_contracts c using (ma_hd)
left join k kc on kc.nut = 'C:' || trim(i.ma_chung)
left join ncc on kc.khoa is null and ncc.ma_ncc = trim(i.ma_ncc)
left join ps on ps.ten_ps = c.ten_ps;

create or replace function shared.doi_chieu_quota_hop_dong(
  p_nam text default 'FY26',
  p_fy_start date default date '2026-04-01',
  p_thang text default null
)
returns table (
  ma_khach_hang text, khach_hang text, mien text, bu text, nhom_san_pham text,
  khoa_sp text, ten_sp text, ma_san_pham_quota text, bung_bo text,
  ps_quota text, ps_hop_dong text,
  sl_quota_1_4 numeric, sl_quota_chinh_on numeric, sl_quota_bs_on numeric,
  sl_quota_up numeric, sl_quota_het numeric,
  tien_quota_1_4 numeric, tien_quota_on numeric, tien_quota_up numeric,
  sl_hd_truoc_fy numeric, sl_hd_con_lai_dau_fy numeric, sl_hd_trong_fy numeric,
  tien_hd_truoc_fy numeric, tien_hd_trong_fy numeric,
  gia_quota numeric, gia_hd numeric,
  so_hd_truoc_fy text, so_hd_trong_fy text, ngay_ky_gan_nhat date,
  kq_quota_1_4 text, kq_trong_fy text, canh_bao text
)
language sql
stable
set search_path = shared, public, pg_temp
as $$
with tham_so as (
  select
    coalesce(p_thang,
             (select value #>> '{}' from shared.app_config where key = 'current_month'),
             to_char(now() at time zone 'Asia/Ho_Chi_Minh', 'YYYY-MM')) as thang,
    to_char(p_fy_start, 'YYYY-MM') as fy_thang
),
k as (select nut, khoa from shared.v_khoa_so_sanh_sp),
-- quota chính thức của năm, kèm trạng thái đợt giống lib/quota.js trangThaiDot
q0 as (
  select q.*, d.thang_thau,
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
    lk.trong_so / nullif(sum(lk.trong_so) over (partition by lk.ma_bo), 0) as ty_trong
  from linh_kien_gia lk
),
qk as (
  -- sản phẩm lẻ / bộ có mã chung
  select q0.*, coalesce(kb.khoa, ks.khoa, 'Q:' || coalesce(trim(q0.ma_san_pham), q0.san_pham)) as khoa,
         q0.so_luong as sl, q0.so_luong * q0.don_gia as tien, false as bung
  from q0
  left join k kb on kb.nut = 'B:' || trim(q0.ma_san_pham)
  left join k ks on ks.nut = 'S:' || trim(q0.ma_san_pham)
  where not exists (select 1 from bo_bung bb where bb.ma_bo = trim(q0.ma_san_pham))
  union all
  -- bộ chưa có mã chung: bung ra linh kiện
  select q0.*, lk.khoa,
         q0.so_luong * lk.dinh_muc, q0.so_luong * q0.don_gia * lk.ty_trong, true
  from q0
  join linh_kien_w lk on lk.ma_bo = trim(q0.ma_san_pham)
),
qa as (
  select ma_khach_hang as ma_kh, khoa,
    string_agg(distinct mien, ', ') as mien,
    string_agg(distinct bu, ', ') as bu,
    string_agg(distinct nhom_san_pham, ', ') as nhom_san_pham,
    string_agg(distinct san_pham, ' | ') as ten_sp,
    string_agg(distinct ma_san_pham, ' | ') as ma_sp,
    string_agg(distinct case when bung then ma_san_pham end, ', ') as bung_bo,
    string_agg(distinct ps, ', ') as ps,
    sum(sl) filter (where tt = 'cu') as sl_cu,
    sum(sl) filter (where tt = 'on' and loai = 'chinh') as sl_chinh_on,
    sum(sl) filter (where tt = 'on' and loai = 'bo_sung') as sl_bs_on,
    sum(sl) filter (where tt = 'up') as sl_up,
    sum(sl) filter (where tt = 'het') as sl_het,
    sum(tien) filter (where tt = 'cu') as tien_cu,
    sum(tien) filter (where tt = 'on') as tien_on,
    sum(tien) filter (where tt = 'up') as tien_up,
    sum(so_luong * don_gia) filter (where not bung) / nullif(sum(so_luong) filter (where not bung), 0) as gia,
    bool_or(chinh_truoc_fy) as chinh_truoc_fy
  from qk
  group by 1, 2
),
hd as (
  select h.*,
    (h.ngay_ky < p_fy_start and coalesce(h.thoi_han, 'infinity'::date) >= p_fy_start) as truoc_fy,
    (h.ngay_ky >= p_fy_start
     and h.ngay_ky < (to_date(ts.thang || '-01', 'YYYY-MM-DD') + interval '1 month')) as trong_fy
  from shared.v_hop_dong_dong h
  cross join tham_so ts
  where h.khoa_sp is not null
),
-- SL đã xuất hóa đơn TRƯỚC đầu năm TC theo HĐ × mã chung (cùng nguồn với
-- public.contract_items_remaining_view). Hóa đơn chỉ có từ 04/2025.
ban_truoc as (
  select so_hd, ma_chung, sum(coalesce(so_luong, 0)) as sl
  from app_contract.hoa_don_bovattu
  where ma_chung is not null and ngay_tai_lieu < p_fy_start
  group by 1, 2
),
-- gộp mức HĐ × mã chung rồi mới trừ phần đã bán (1 mã chung có thể nhiều dòng giá)
hd_mc as (
  select hd.ma_kh, hd.khoa_sp, hd.so_hd, hd.ma_chung, hd.truoc_fy, hd.trong_fy,
    min(hd.mien) as mien, min(coalesce(hd.ps, hd.ten_ps)) as ps, min(hd.ngay_ky) as ngay_ky,
    sum(hd.so_luong) as sl, sum(hd.thanh_tien) as tien
  from hd
  where hd.truoc_fy or hd.trong_fy
  group by 1, 2, 3, 4, 5, 6
),
ha as (
  select h.ma_kh, h.khoa_sp as khoa,
    string_agg(distinct h.mien, ', ') as mien,
    string_agg(distinct h.ps, ', ') as ps,
    sum(h.sl) filter (where h.truoc_fy) as sl_truoc,
    sum(greatest(h.sl - coalesce(b.sl, 0), 0)) filter (where h.truoc_fy) as sl_con_lai_truoc,
    sum(h.sl) filter (where h.trong_fy) as sl_trong,
    sum(h.tien) filter (where h.truoc_fy) as tien_truoc,
    sum(h.tien) filter (where h.trong_fy) as tien_trong,
    sum(h.tien) / nullif(sum(h.sl), 0) as gia,
    string_agg(distinct case when h.truoc_fy then h.so_hd end, ' | ') as so_hd_truoc,
    string_agg(distinct case when h.trong_fy then h.so_hd end, ' | ') as so_hd_trong,
    max(h.ngay_ky) as ngay_ky_max,
    bool_or(h.truoc_fy and h.ngay_ky < date '2025-04-01') as hd_truoc_du_lieu_hd
  from hd_mc h
  left join ban_truoc b on b.so_hd = h.so_hd and b.ma_chung = h.ma_chung
  group by 1, 2
),
ten_khoa as (
  select k.khoa,
    min(coalesce(b.bo_vat_tu, v.san_pham)) as ten,
    min(coalesce(b.nhom_san_pham, v.nhom_san_pham)) as nhom,
    min(coalesce(b.bu_code, v.bu_code)) as bu
  from k
  left join shared.dm_vat_tu v
    on k.nut = 'S:' || trim(v.ma_san_pham)
  left join shared.dm_bo_vat_tu b
    on k.nut = 'B:' || trim(b.ma_bo_vat_tu)
  group by 1
),
gop as (
  select coalesce(qa.ma_kh, ha.ma_kh) as ma_kh, coalesce(qa.khoa, ha.khoa) as khoa, qa, ha
  from qa full join ha on ha.ma_kh = qa.ma_kh and ha.khoa = qa.khoa
),
kq as (
  select g.*,
    coalesce((g.qa).sl_cu, 0) as q14,
    coalesce((g.qa).sl_chinh_on, 0) + coalesce((g.qa).sl_bs_on, 0) as qon,
    coalesce((g.qa).sl_up, 0) as qup,
    coalesce((g.ha).sl_con_lai_truoc, 0) as h14,
    coalesce((g.ha).sl_trong, 0) as hfy
  from gop g
)
select
  kq.ma_kh,
  kh.customer_name,
  coalesce((kq.qa).mien, (kq.ha).mien),
  coalesce((kq.qa).bu, tk.bu),
  coalesce((kq.qa).nhom_san_pham, tk.nhom),
  kq.khoa,
  coalesce((kq.qa).ten_sp, tk.ten),
  (kq.qa).ma_sp,
  (kq.qa).bung_bo,
  (kq.qa).ps,
  (kq.ha).ps,
  (kq.qa).sl_cu, (kq.qa).sl_chinh_on, (kq.qa).sl_bs_on, (kq.qa).sl_up, (kq.qa).sl_het,
  round((kq.qa).tien_cu), round((kq.qa).tien_on), round((kq.qa).tien_up),
  (kq.ha).sl_truoc, (kq.ha).sl_con_lai_truoc, (kq.ha).sl_trong,
  round((kq.ha).tien_truoc), round((kq.ha).tien_trong),
  round((kq.qa).gia), round((kq.ha).gia),
  (kq.ha).so_hd_truoc, (kq.ha).so_hd_trong, (kq.ha).ngay_ky_max,
  case when kq.q14 = 0 and kq.h14 = 0 then null
       when kq.h14 = 0 and coalesce((kq.ha).sl_truoc, 0) > 0 then 'HĐ đã bán hết trước 1/4'
       when kq.h14 = 0 then 'Chỉ có quota'
       when kq.q14 = 0 then 'Chỉ có HĐ'
       when kq.q14 = kq.h14 then 'Khớp'
       when kq.q14 > kq.h14 then 'Quota > HĐ'
       else 'HĐ > quota' end,
  case when kq.qon = 0 and kq.hfy = 0 then null
       when kq.hfy = 0 then 'Chỉ có quota'
       when kq.qon = 0 then 'Chỉ có HĐ'
       when kq.qon = kq.hfy then 'Khớp'
       when kq.qon > kq.hfy then 'Quota > HĐ'
       else 'HĐ > quota' end,
  nullif(concat_ws('; ',
    case when kq.qup > 0 and kq.hfy > kq.qon then 'Upcoming nhưng đã có HĐ trong năm' end,
    case when (kq.qa).chinh_truoc_fy then 'Quota chính có tháng thầu trước năm TC' end,
    case when (kq.qa).gia > 0 and (kq.ha).gia > 0
          and abs((kq.ha).gia / (kq.qa).gia - 1) > 0.01
          and abs((kq.ha).gia / (kq.qa).gia - 1.05) > 0.01 then 'Lệch giá' end,
    case when kq.khoa like 'Q:%' then 'Mã SP quota chưa có trong danh mục' end,
    case when (kq.ha).hd_truoc_du_lieu_hd then 'Có HĐ ký trước 04/2025: thiếu hóa đơn cũ, SL còn lại có thể cao hơn thực tế' end
  ), '')
from kq
left join ten_khoa tk on tk.khoa = kq.khoa
left join shared.dm_khach_hang kh on kh.customer_id = kq.ma_kh
order by kq.ma_kh, kq.khoa;
$$;

revoke all on shared.v_khoa_so_sanh_sp from public, anon, authenticated;
revoke all on shared.v_hop_dong_dong from public, anon, authenticated;
revoke all on function shared.doi_chieu_quota_hop_dong(text, date, text) from public, anon, authenticated;

comment on view shared.v_khoa_so_sanh_sp is
  'Khoá so sánh SP: nút S:/C:/B:/T: → khoá thành phần liên thông (dm_vat_tu, dm_bo_vat_tu, nhóm thay thế). P2 liên kết quota ↔ hợp đồng.';
comment on view shared.v_hop_dong_dong is
  'Dòng hợp đồng (public.contract_*) + khoá SP + PS ngắn. khoa_sp NULL = chưa map mã. Không mở cho anon/authenticated.';
comment on function shared.doi_chieu_quota_hop_dong(text, date, text) is
  'Đối chiếu quota_thau với hợp đồng theo KH × khoá SP (chỉ đọc). p_thang mặc định app_config.current_month.';
