-- P3 liên kết quota ↔ hợp đồng (tiếp P2 20261112100000, schema sau 20261112200000).
--
-- 1. Tách 2 hàm dùng chung (đối chiếu + gắn liên kết đọc CÙNG logic, không lệch nhau):
--    app_sale.quota_theo_khoa()    — từng dòng quota_thau × khoá SP (bộ chưa có mã chung
--                                    bung ra linh kiện), kèm trạng thái đợt cu/on/up/het.
--    app_sale.hop_dong_theo_khoa() — từng dòng HĐ có khoá SP, cửa sổ 'truoc' (ký trước
--                                    năm TC, còn hạn) / 'trong' (ký trong năm TC tới hết
--                                    tháng hiện tại), SL còn lại đầu năm chia FIFO theo dòng.
-- 2. shared.doi_chieu_quota_hop_dong() viết lại trên 2 hàm trên; cột ra giữ nguyên.
-- 3. app_sale.quota_hop_dong: bảng liên kết dòng quota ↔ dòng HĐ (n–n).
--    contract_item_id KHÔNG đặt FK: app hợp đồng có thể nạp lại bảng (TRUNCATE sẽ lỗi);
--    dòng mồ côi xem ở app_sale.v_quota_hop_dong_mo_coi. quota_id FK ON DELETE CASCADE
--    (trigger gộp dòng trùng / chuyển khoá xoá dòng quota → chạy lại hàm gắn).
-- 4. app_sale.gan_quota_hop_dong_tu_dong(): xoá liên kết 'tu_dong' của năm rồi gắn lại cho
--    các khoá KH × SP có kết quả 'Khớp' (Quota 1.4 ↔ SL HĐ còn lại đầu năm; chính + BS on
--    hand ↔ HĐ ký trong năm). Trong 1 khoá: xếp 2 phía theo PS rồi thời gian (quota: tháng
--    thầu, loại, đợt; HĐ: ngày ký) và cắt khoảng SL luỹ kế — PS khớp nhau thì gắn đúng PS.
--    Dòng quota / dòng HĐ đã có liên kết 'tay' được bỏ qua.
-- 5. app_sale.v_quota_lien_ket_hop_dong: mức độ đã liên kết của từng dòng quota.
-- Mọi đối tượng mới REVOKE anon / authenticated (xem memory drop-function-mat-quyen).

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

create or replace function app_sale.hop_dong_theo_khoa(
  p_fy_start date default date '2026-04-01',
  p_thang text default null
)
returns table (
  contract_item_id integer, ma_hd text, so_hd text, ma_chung text,
  ma_kh text, khoa_sp text, ps text, mien text,
  ngay_ky date, thoi_han date, cua_so text,
  so_luong numeric, thanh_tien numeric, sl_ban_truoc numeric, sl_con_lai_dau_fy numeric
)
language sql
stable
set search_path = shared, app_sale, app_contract, pg_temp
as $$
with tham_so as (
  select coalesce(p_thang,
           (select value #>> '{}' from shared.app_config where key = 'current_month'),
           to_char(now() at time zone 'Asia/Ho_Chi_Minh', 'YYYY-MM')) as thang
),
h as (
  select hd.contract_item_id, hd.ma_hd, hd.so_hd, hd.ma_chung, hd.ma_kh, hd.khoa_sp,
    coalesce(hd.ps, hd.ten_ps) as ps, hd.mien, hd.ngay_ky, hd.thoi_han,
    case
      when hd.ngay_ky < p_fy_start and coalesce(hd.thoi_han, 'infinity'::date) >= p_fy_start then 'truoc'
      when hd.ngay_ky >= p_fy_start
       and hd.ngay_ky < (to_date(ts.thang || '-01', 'YYYY-MM-DD') + interval '1 month') then 'trong'
    end as cua_so,
    hd.so_luong, hd.thanh_tien
  from app_sale.v_hop_dong_dong hd
  cross join tham_so ts
  where hd.khoa_sp is not null
),
-- SL đã xuất hóa đơn TRƯỚC đầu năm TC theo số HĐ × mã chung (cùng nguồn với
-- app_contract.contract_items_remaining_view). Hóa đơn chỉ có từ 04/2025.
ban_truoc as (
  select hb.so_hd, hb.ma_chung, sum(coalesce(hb.so_luong, 0)) as sl
  from app_contract.hoa_don_bovattu hb
  where hb.ma_chung is not null and hb.ngay_tai_lieu < p_fy_start
  group by 1, 2
),
luy_ke as (
  select h.*, coalesce(b.sl, 0) as ban,
    sum(h.so_luong) over (partition by h.so_hd, h.ma_chung order by h.contract_item_id) as cum_end
  from h
  left join ban_truoc b on b.so_hd = h.so_hd and b.ma_chung = h.ma_chung
  where h.cua_so is not null
)
-- phần đã bán trừ dần theo thứ tự dòng (FIFO) trong cùng số HĐ × mã chung
select l.contract_item_id, l.ma_hd, l.so_hd, l.ma_chung, l.ma_kh, l.khoa_sp, l.ps, l.mien,
  l.ngay_ky, l.thoi_han, l.cua_so, l.so_luong, l.thanh_tien,
  l.ban,
  case when l.cua_so = 'truoc'
       then l.cum_end - greatest(l.cum_end - l.so_luong, least(l.cum_end, l.ban)) end
from luy_ke l;
$$;

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
with k as (select nut, khoa from app_sale.v_khoa_so_sanh_sp),
qk as (select * from app_sale.quota_theo_khoa(p_nam, p_fy_start, p_thang)),
qa as (
  select qk.ma_khach_hang as ma_kh, qk.khoa_sp as khoa,
    string_agg(distinct qk.mien, ', ') as mien,
    string_agg(distinct qk.bu, ', ') as bu,
    string_agg(distinct qk.nhom_san_pham, ', ') as nhom_san_pham,
    string_agg(distinct qk.san_pham, ' | ') as ten_sp,
    string_agg(distinct qk.ma_san_pham, ' | ') as ma_sp,
    string_agg(distinct case when qk.bung then qk.ma_san_pham end, ', ') as bung_bo,
    string_agg(distinct qk.ps, ', ') as ps,
    sum(qk.sl) filter (where qk.tt = 'cu') as sl_cu,
    sum(qk.sl) filter (where qk.tt = 'on' and qk.loai = 'chinh') as sl_chinh_on,
    sum(qk.sl) filter (where qk.tt = 'on' and qk.loai = 'bo_sung') as sl_bs_on,
    sum(qk.sl) filter (where qk.tt = 'up') as sl_up,
    sum(qk.sl) filter (where qk.tt = 'het') as sl_het,
    sum(qk.tien) filter (where qk.tt = 'cu') as tien_cu,
    sum(qk.tien) filter (where qk.tt = 'on') as tien_on,
    sum(qk.tien) filter (where qk.tt = 'up') as tien_up,
    sum(qk.so_luong * qk.don_gia) filter (where not qk.bung)
      / nullif(sum(qk.so_luong) filter (where not qk.bung), 0) as gia,
    bool_or(qk.chinh_truoc_fy) as chinh_truoc_fy
  from qk
  group by 1, 2
),
hd as (select * from app_sale.hop_dong_theo_khoa(p_fy_start, p_thang)),
ha as (
  select h.ma_kh, h.khoa_sp as khoa,
    string_agg(distinct h.mien, ', ') as mien,
    string_agg(distinct h.ps, ', ') as ps,
    sum(h.so_luong) filter (where h.cua_so = 'truoc') as sl_truoc,
    sum(h.sl_con_lai_dau_fy) filter (where h.cua_so = 'truoc') as sl_con_lai_truoc,
    sum(h.so_luong) filter (where h.cua_so = 'trong') as sl_trong,
    sum(h.thanh_tien) filter (where h.cua_so = 'truoc') as tien_truoc,
    sum(h.thanh_tien) filter (where h.cua_so = 'trong') as tien_trong,
    sum(h.thanh_tien) / nullif(sum(h.so_luong), 0) as gia,
    string_agg(distinct case when h.cua_so = 'truoc' then h.so_hd end, ' | ') as so_hd_truoc,
    string_agg(distinct case when h.cua_so = 'trong' then h.so_hd end, ' | ') as so_hd_trong,
    max(h.ngay_ky) as ngay_ky_max,
    bool_or(h.cua_so = 'truoc' and h.ngay_ky < date '2025-04-01') as hd_truoc_du_lieu_hd
  from hd h
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

create table if not exists app_sale.quota_hop_dong (
  id bigint generated always as identity primary key,
  quota_id bigint not null references shared.quota_thau(id) on delete cascade,
  contract_item_id integer not null,
  ma_hd text not null,
  khoa_sp text not null,
  cua_so text not null check (cua_so in ('quota_1_4', 'trong_nam')),
  sl_hd numeric not null check (sl_hd > 0),
  sl_quota numeric not null check (sl_quota > 0),
  cach_gan text not null default 'tu_dong' check (cach_gan in ('tu_dong', 'tay')),
  quy_tac text,
  nguoi_gan text,
  gan_luc timestamptz not null default now(),
  unique (quota_id, contract_item_id, khoa_sp)
);
create index if not exists ix_quota_hop_dong_item on app_sale.quota_hop_dong (contract_item_id);
alter table app_sale.quota_hop_dong enable row level security;

comment on table app_sale.quota_hop_dong is
  'Liên kết dòng quota_thau ↔ dòng hợp đồng (app_contract.contract_items). sl_hd: đơn vị dòng HĐ; sl_quota: quy về đơn vị quota (bộ bung linh kiện: ÷ định mức ÷ số khoá linh kiện của bộ). cach_gan tu_dong do app_sale.gan_quota_hop_dong_tu_dong() tạo lại mỗi lần chạy; tay thì giữ.';

create or replace function app_sale.gan_quota_hop_dong_tu_dong(
  p_nam text default 'FY26',
  p_fy_start date default date '2026-04-01',
  p_thang text default null
)
returns json
language plpgsql
volatile
set search_path = shared, app_sale, pg_temp
as $$
declare
  v_xoa int;
  v_them int;
  v_kq json;
begin
  delete from app_sale.quota_hop_dong l
  using shared.quota_thau q
  where q.id = l.quota_id and q.nam_tai_chinh = p_nam and l.cach_gan = 'tu_dong';
  get diagnostics v_xoa = row_count;

  with khop as (
    select d.ma_khach_hang, d.khoa_sp, 'quota_1_4'::text as cua_so
    from shared.doi_chieu_quota_hop_dong(p_nam, p_fy_start, p_thang) d
    where d.kq_quota_1_4 = 'Khớp'
    union all
    select d.ma_khach_hang, d.khoa_sp, 'trong_nam'
    from shared.doi_chieu_quota_hop_dong(p_nam, p_fy_start, p_thang) d
    where d.kq_trong_fy = 'Khớp'
  ),
  tay_q as (select distinct quota_id from app_sale.quota_hop_dong where cach_gan = 'tay'),
  tay_h as (select distinct contract_item_id from app_sale.quota_hop_dong where cach_gan = 'tay'),
  qs as (
    select q.quota_id, q.ma_khach_hang, q.khoa_sp, kh.cua_so, q.sl, q.dinh_muc, q.n_khoa_bo,
      sum(q.sl) over w as e
    from app_sale.quota_theo_khoa(p_nam, p_fy_start, p_thang) q
    join khop kh on kh.ma_khach_hang = q.ma_khach_hang and kh.khoa_sp = q.khoa_sp
     and kh.cua_so = case when q.tt = 'cu' then 'quota_1_4' when q.tt = 'on' then 'trong_nam' end
    where q.quota_id not in (select quota_id from tay_q)
      and q.sl > 0
    window w as (partition by q.ma_khach_hang, q.khoa_sp, kh.cua_so
                 order by q.ps nulls last, q.thang_thau nulls last, q.loai, q.dot, q.quota_id
                 rows unbounded preceding)
  ),
  hs as (
    select h.contract_item_id, h.ma_hd, h.ma_kh, h.khoa_sp, kh.cua_so,
      case when kh.cua_so = 'quota_1_4' then h.sl_con_lai_dau_fy else h.so_luong end as sl,
      sum(case when kh.cua_so = 'quota_1_4' then h.sl_con_lai_dau_fy else h.so_luong end) over w as e
    from app_sale.hop_dong_theo_khoa(p_fy_start, p_thang) h
    join khop kh on kh.ma_khach_hang = h.ma_kh and kh.khoa_sp = h.khoa_sp
     and kh.cua_so = case h.cua_so when 'truoc' then 'quota_1_4' when 'trong' then 'trong_nam' end
    where h.contract_item_id not in (select contract_item_id from tay_h)
      and case when kh.cua_so = 'quota_1_4' then h.sl_con_lai_dau_fy else h.so_luong end > 0
    window w as (partition by h.ma_kh, h.khoa_sp, kh.cua_so
                 order by h.ps nulls last, h.ngay_ky, h.ma_hd, h.contract_item_id
                 rows unbounded preceding)
  ),
  cat as (
    select qs.quota_id, hs.contract_item_id, hs.ma_hd, qs.khoa_sp, qs.cua_so,
      least(qs.e, hs.e) - greatest(qs.e - qs.sl, hs.e - hs.sl) as sl_hd,
      qs.dinh_muc, qs.n_khoa_bo
    from qs
    join hs on hs.ma_kh = qs.ma_khach_hang and hs.khoa_sp = qs.khoa_sp and hs.cua_so = qs.cua_so
     and hs.e - hs.sl < qs.e and qs.e - qs.sl < hs.e
  )
  insert into app_sale.quota_hop_dong
    (quota_id, contract_item_id, ma_hd, khoa_sp, cua_so, sl_hd, sl_quota, cach_gan, quy_tac, nguoi_gan)
  select quota_id, contract_item_id, ma_hd, khoa_sp, cua_so, sl_hd,
    sl_hd / dinh_muc / n_khoa_bo, 'tu_dong', 'khop_sl_' || cua_so, 'gan_quota_hop_dong_tu_dong'
  from cat
  where sl_hd > 0;
  get diagnostics v_them = row_count;

  select json_build_object(
    'xoa_tu_dong', v_xoa,
    'them', v_them,
    'so_dong_quota_co_lien_ket', (select count(distinct l.quota_id) from app_sale.quota_hop_dong l
                                  join shared.quota_thau q on q.id = l.quota_id where q.nam_tai_chinh = p_nam),
    'so_dong_hd_co_lien_ket', (select count(distinct l.contract_item_id) from app_sale.quota_hop_dong l
                               join shared.quota_thau q on q.id = l.quota_id where q.nam_tai_chinh = p_nam)
  ) into v_kq;
  return v_kq;
end;
$$;

-- Mức độ liên kết của từng dòng quota (đơn vị quota). ty_le = 1 là đã có đủ HĐ.
create or replace view app_sale.v_quota_lien_ket_hop_dong as
select q.id as quota_id, q.nam_tai_chinh, q.bu, q.mien, q.ps, q.ma_khach_hang, q.nhom_san_pham,
  q.san_pham, q.ma_san_pham, q.don_gia, q.loai, q.dot, q.so_luong,
  coalesce(l.sl_quota, 0) as sl_da_lien_ket,
  round(coalesce(l.sl_quota, 0) / nullif(q.so_luong, 0), 4) as ty_le,
  l.so_hd, l.ma_hd, l.cach_gan
from shared.quota_thau q
left join (
  select x.quota_id, sum(x.sl_quota) as sl_quota,
    string_agg(distinct c.so_hd, ' | ') as so_hd,
    string_agg(distinct x.ma_hd, ' | ') as ma_hd,
    string_agg(distinct x.cach_gan, ', ') as cach_gan
  from app_sale.quota_hop_dong x
  left join app_contract.contract_contracts c on c.ma_hd = x.ma_hd
  group by x.quota_id
) l on l.quota_id = q.id
where q.trang_thai = 'chinh_thuc' and q.bu is distinct from 'test';

-- Liên kết trỏ tới dòng HĐ không còn (app hợp đồng nạp lại / xoá dòng).
create or replace view app_sale.v_quota_hop_dong_mo_coi as
select l.*
from app_sale.quota_hop_dong l
where not exists (select 1 from app_contract.contract_items i where i.id = l.contract_item_id);

revoke all on function app_sale.quota_theo_khoa(text, date, text) from public, anon, authenticated;
revoke all on function app_sale.hop_dong_theo_khoa(date, text) from public, anon, authenticated;
revoke all on function shared.doi_chieu_quota_hop_dong(text, date, text) from public, anon, authenticated;
revoke all on function app_sale.gan_quota_hop_dong_tu_dong(text, date, text) from public, anon, authenticated;
revoke all on app_sale.quota_hop_dong from public, anon, authenticated;
revoke all on app_sale.v_quota_lien_ket_hop_dong from public, anon, authenticated;
revoke all on app_sale.v_quota_hop_dong_mo_coi from public, anon, authenticated;
