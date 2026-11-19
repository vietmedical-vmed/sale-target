-- Tab "Kiểm tra thông tin thầu" (admin + manager): 3 bước kiểm soát
--   1 'dot' — đợt thầu chính / bổ sung thiếu tháng thầu hoặc hiệu lực
--   2 'am'  — sản phẩm trên Chi tiết kế hoạch có quota khả dụng âm
--   3 'hd'  — đối chiếu quota ↔ hợp đồng (khoá KH × SP chưa khớp)
--
-- 1. app_sale.kiem_tra_thau_xu_ly: trạng thái xử lý từng việc (đang xử lý / bỏ qua có lý do /
--    xong). Không có dòng = chưa xử lý. Danh sách việc do app tính (bước 1, 2 dùng đúng logic
--    lưới trong lib/quota.js); app tự chuyển 'xong' khi việc không còn trong danh sách.
-- 2. app_sale.kiem_tra_thau_snapshot: số việc + giá trị mỗi bước theo ngày × BU. App ghi đè bản
--    của ngày hiện tại mỗi lần admin / manager mở tab; thẻ bước so với bản gần nhất trước đó.
--    Không chụp bằng cron: bước 2 cần đúng logic lưới (JS), viết lại bằng SQL dễ lệch số.
-- 3. RPC đọc (trả 1 json để khỏi giới hạn số dòng của PostgREST):
--    app_sale.kiem_tra_doi_chieu_hop_dong()   — gọn cột của shared.doi_chieu_quota_hop_dong()
--    app_sale.goi_y_dot_tu_hop_dong()          — tháng thầu / hiệu lực gợi ý cho đợt thiếu, theo HĐ
--    app_sale.hop_dong_theo_san_pham(items)    — SL HĐ (1.4 còn lại, trong năm) cho SP quota âm
--    app_sale.chi_tiet_khoa_hop_dong(kh, khoa) — dòng quota, dòng HĐ, liên kết của 1 khoá
-- 4. RPC ghi (admin): app_sale.gan_tay_quota_hop_dong / bo_gan_tay_quota_hop_dong /
--    them_alias_khoa_sp.
-- 5. Cron 'kiem-tra-thau-don-xong': xoá việc 'xong' quá 60 ngày.
-- Mọi đối tượng REVOKE anon / authenticated, chỉ service_role (edge sale_target-api).
-- Rollback: supabase/rollbacks/20261119100000_kiem_tra_thong_tin_thau_ROLLBACK.sql

begin;

create table if not exists app_sale.kiem_tra_thau_xu_ly (
  buoc text not null check (buoc in ('dot', 'am', 'hd')),
  khoa text not null,
  bu text not null default '',
  trang_thai text not null check (trang_thai in ('dang_xu_ly', 'bo_qua', 'xong')),
  nguoi_phu_trach text,
  ghi_chu text,
  mo_ta text,
  cap_nhat_boi text,
  cap_nhat_luc timestamptz not null default now(),
  xong_luc timestamptz,
  primary key (buoc, khoa),
  constraint kiem_tra_thau_bo_qua_can_ly_do
    check (trang_thai <> 'bo_qua' or nullif(btrim(ghi_chu), '') is not null)
);
create index if not exists ix_kiem_tra_thau_xu_ly_xong
  on app_sale.kiem_tra_thau_xu_ly (xong_luc) where trang_thai = 'xong';
alter table app_sale.kiem_tra_thau_xu_ly enable row level security;
comment on table app_sale.kiem_tra_thau_xu_ly is
  'Trạng thái xử lý việc ở tab Kiểm tra thông tin thầu. khoa = khoá việc do app tạo (bước dot: fy|ps|kh|nhóm|loại|đợt; am: fy|ps|kh|nhóm|bvt|sp|giá; hd: cửa sổ|kh|khoá SP). mo_ta: nhãn đọc được để hiện việc đã xong.';

create table if not exists app_sale.kiem_tra_thau_snapshot (
  ngay date not null,
  bu text not null default '',
  buoc text not null check (buoc in ('dot', 'am', 'hd')),
  so_viec integer not null,
  gia_tri numeric not null default 0,
  chi_tiet jsonb,
  cap_nhat_boi text,
  cap_nhat_luc timestamptz not null default now(),
  primary key (ngay, bu, buoc)
);
alter table app_sale.kiem_tra_thau_snapshot enable row level security;
comment on table app_sale.kiem_tra_thau_snapshot is
  'Số việc + giá trị mỗi bước tab Kiểm tra thông tin thầu theo ngày (giờ VN) × BU ('''' = tất cả). App ghi đè bản trong ngày.';

-- ---------- đọc: đối chiếu quota ↔ HĐ (gọn cột) ----------
create or replace function app_sale.kiem_tra_doi_chieu_hop_dong()
returns json
language sql
stable
set search_path = shared, app_sale, pg_temp
set statement_timeout = '60s'
as $$
  select coalesce(json_agg(json_build_object(
    'kh', d.ma_khach_hang, 'tenKh', d.khach_hang, 'bu', d.bu, 'mien', d.mien,
    'nhom', d.nhom_san_pham, 'khoa', d.khoa_sp, 'tenSp', d.ten_sp,
    'maSp', d.ma_san_pham_quota, 'bungBo', d.bung_bo,
    'psQ', d.ps_quota, 'psH', d.ps_hop_dong,
    'q14', d.sl_quota_1_4, 'qChinh', d.sl_quota_chinh_on, 'qBs', d.sl_quota_bs_on,
    'qUp', d.sl_quota_up,
    'tQ14', d.tien_quota_1_4, 'tQOn', d.tien_quota_on, 'tQUp', d.tien_quota_up,
    'hTruoc', d.sl_hd_truoc_fy, 'h14', d.sl_hd_con_lai_dau_fy, 'hFy', d.sl_hd_trong_fy,
    'tHTruoc', d.tien_hd_truoc_fy, 'tHFy', d.tien_hd_trong_fy,
    'giaQ', d.gia_quota, 'giaH', d.gia_hd,
    'soHdTruoc', d.so_hd_truoc_fy, 'soHdFy', d.so_hd_trong_fy, 'ngayKy', d.ngay_ky_gan_nhat,
    'kq14', d.kq_quota_1_4, 'kqFy', d.kq_trong_fy, 'canhBao', d.canh_bao
  )), '[]'::json)
  from shared.doi_chieu_quota_hop_dong() d;
$$;

-- ---------- đọc: gợi ý tháng thầu / hiệu lực cho đợt thiếu, theo HĐ ----------
-- Với mỗi đợt chính / bổ sung thiếu tháng hoặc hiệu lực: lấy các khoá SP của quota trong đợt,
-- tìm HĐ cùng KH có dòng cùng khoá; chọn HĐ phủ nhiều khoá nhất, hoà thì ký gần nhất.
-- Tháng gợi ý = tháng ký; hiệu lực = số tháng từ tháng ký tới tháng hết hạn HĐ (1..120).
create or replace function app_sale.goi_y_dot_tu_hop_dong(p_nam text default 'FY26')
returns json
language sql
stable
set search_path = shared, app_sale, pg_temp
set statement_timeout = '60s'
as $$
with thieu as (
  select d.nam_tai_chinh, d.ps, d.ma_khach_hang, d.nhom_san_pham, d.loai, d.dot
  from shared.dot_thau d
  where d.nam_tai_chinh = p_nam
    and d.trang_thai = 'chinh_thuc'
    and d.loai in ('chinh', 'bo_sung')
    and (coalesce(d.thang_thau, '') !~ '^\d{4}-\d{2}$'
         or d.thoi_gian is null or d.thoi_gian <> trunc(d.thoi_gian)
         or d.thoi_gian not between 1 and 120)
),
qk as (
  select distinct t.ps, t.ma_khach_hang, t.nhom_san_pham, t.loai, t.dot, q.khoa_sp
  from thieu t
  join app_sale.quota_theo_khoa(p_nam) q
    on q.ps = t.ps and q.ma_khach_hang = t.ma_khach_hang
   and q.nhom_san_pham = t.nhom_san_pham and q.loai = t.loai and q.dot = t.dot
),
so_khoa as (
  select ps, ma_khach_hang, nhom_san_pham, loai, dot, count(*) as n
  from qk group by 1, 2, 3, 4, 5
),
hd as (
  select qk.ps, qk.ma_khach_hang, qk.nhom_san_pham, qk.loai, qk.dot,
    h.so_hd, min(h.ngay_ky) as ngay_ky, max(h.thoi_han) as thoi_han,
    count(distinct qk.khoa_sp) as n_khop
  from qk
  join app_sale.v_hop_dong_dong h on h.ma_kh = qk.ma_khach_hang and h.khoa_sp = qk.khoa_sp
  where h.ngay_ky is not null
  group by 1, 2, 3, 4, 5, 6
),
chon as (
  select distinct on (ps, ma_khach_hang, nhom_san_pham, loai, dot) *
  from hd
  order by ps, ma_khach_hang, nhom_san_pham, loai, dot, n_khop desc, ngay_ky desc, so_hd
)
select coalesce(json_agg(json_build_object(
  'fy', p_nam, 'ps', c.ps, 'custId', c.ma_khach_hang, 'grp', c.nhom_san_pham,
  'loai', c.loai, 'dot', c.dot,
  'thang', to_char(c.ngay_ky, 'YYYY-MM'),
  'hieuLuc', case when c.thoi_han > c.ngay_ky then
    least(120, greatest(1,
      (extract(year from c.thoi_han) * 12 + extract(month from c.thoi_han))
      - (extract(year from c.ngay_ky) * 12 + extract(month from c.ngay_ky))))::int end,
  'soHd', c.so_hd, 'ngayKy', c.ngay_ky, 'thoiHan', c.thoi_han,
  'khop', c.n_khop, 'tong', s.n
)), '[]'::json)
from chon c
join so_khoa s using (ps, ma_khach_hang, nhom_san_pham, loai, dot);
$$;

-- ---------- đọc: SL HĐ cho sản phẩm (bước quota âm) ----------
-- p_items: [{i, kh, ps, nhom, bvt, sp}]. Mã SP lấy từ dòng kế hoạch cùng khoá; khoá SP theo
-- ghép mã đã duyệt (khoa_sp_alias) → bộ 'B:' → lẻ 'S:' như app_sale.quota_theo_khoa.
create or replace function app_sale.hop_dong_theo_san_pham(p_items jsonb)
returns json
language sql
stable
set search_path = shared, app_sale, pg_temp
set statement_timeout = '60s'
as $$
with it as (
  select (x->>'i')::int as i, btrim(x->>'kh') as kh, btrim(x->>'ps') as ps,
    btrim(x->>'nhom') as nhom, coalesce(btrim(x->>'bvt'), '') as bvt, btrim(x->>'sp') as sp
  from jsonb_array_elements(coalesce(p_items, '[]'::jsonb)) x
),
ma as (
  select it.*, m.ma_sp, m.ma_bvt
  from it
  left join lateral (
    select nullif(btrim(st.ma_san_pham), '') as ma_sp, nullif(btrim(st.ma_bo_vat_tu), '') as ma_bvt
    from shared.sale_target st
    where st.ps = it.ps and st.ma_khach_hang = it.kh and st.nhom_san_pham = it.nhom
      and coalesce(btrim(st.bo_vat_tu), '') = it.bvt and btrim(st.san_pham) = it.sp
      and coalesce(st.ngoai_ke_hoach, false) = false
    order by (st.ma_san_pham is null), st.id
    limit 1
  ) m on true
),
k as (select nut, khoa from app_sale.v_khoa_so_sanh_sp),
khoa as (
  select ma.*, coalesce(
    (select coalesce(kk.khoa, a.nut_den) from app_sale.khoa_sp_alias a
       left join k kk on kk.nut = a.nut_den
      where (a.ma_kh = ma.kh or a.ma_kh is null)
        and a.nut_tu in ('S:' || ma.ma_sp, 'B:' || ma.ma_sp)
      order by a.ma_kh nulls last limit 1),
    (select kk.khoa from k kk where kk.nut = 'B:' || ma.ma_sp),
    (select kk.khoa from k kk where kk.nut = 'S:' || ma.ma_sp),
    (select kk.khoa from k kk where kk.nut = 'B:' || ma.ma_bvt)
  ) as khoa_sp
  from ma
),
h as (
  select h.ma_kh, h.khoa_sp,
    sum(h.sl_con_lai_dau_fy) filter (where h.cua_so = 'truoc') as h14,
    sum(h.so_luong) filter (where h.cua_so = 'trong') as hfy,
    string_agg(distinct h.so_hd, ' | ') as so_hd
  from app_sale.hop_dong_theo_khoa() h
  where h.ma_kh in (select kh from it)
  group by 1, 2
)
select coalesce(json_agg(json_build_object(
  'i', khoa.i, 'maSp', coalesce(khoa.ma_sp, khoa.ma_bvt), 'khoa', khoa.khoa_sp,
  'h14', h.h14, 'hFy', h.hfy, 'soHd', h.so_hd
)), '[]'::json)
from khoa
left join h on h.ma_kh = khoa.kh and h.khoa_sp = khoa.khoa_sp;
$$;

-- ---------- đọc: chi tiết 1 khoá KH × SP ----------
create or replace function app_sale.chi_tiet_khoa_hop_dong(p_ma_kh text, p_khoa text, p_nam text default 'FY26')
returns json
language sql
stable
set search_path = shared, app_sale, pg_temp
set statement_timeout = '60s'
as $$
with q as (
  select * from app_sale.quota_theo_khoa(p_nam) q
  where q.ma_khach_hang = p_ma_kh and q.khoa_sp = p_khoa
),
h as (
  select h.*, v.ten_hang_hoa, v.don_gia, v.so_bao_gia, v.so_goi_thau
  from app_sale.hop_dong_theo_khoa() h
  left join app_sale.v_hop_dong_dong v on v.contract_item_id = h.contract_item_id
  where h.ma_kh = p_ma_kh and h.khoa_sp = p_khoa
),
l as (
  select x.* from app_sale.quota_hop_dong x
  where x.khoa_sp = p_khoa
    and (x.quota_id in (select quota_id from q) or x.contract_item_id in (select contract_item_id from h))
)
select json_build_object(
  'quota', (select coalesce(json_agg(json_build_object(
      'quotaId', q.quota_id, 'ps', q.ps, 'loai', q.loai, 'dot', q.dot, 'thang', q.thang_thau,
      'tt', q.tt, 'nhom', q.nhom_san_pham, 'sp', q.san_pham, 'maSp', q.ma_san_pham,
      'soLuong', q.so_luong, 'donGia', q.don_gia, 'sl', q.sl, 'bung', q.bung,
      'dinhMuc', q.dinh_muc, 'nKhoaBo', q.n_khoa_bo
    ) order by q.ps, q.thang_thau nulls last, q.loai, q.dot), '[]'::json) from q),
  'hopDong', (select coalesce(json_agg(json_build_object(
      'itemId', h.contract_item_id, 'maHd', h.ma_hd, 'soHd', h.so_hd, 'maChung', h.ma_chung,
      'ten', h.ten_hang_hoa, 'ps', h.ps, 'ngayKy', h.ngay_ky, 'thoiHan', h.thoi_han,
      'cuaSo', h.cua_so, 'soLuong', h.so_luong, 'conLai', h.sl_con_lai_dau_fy,
      'donGia', h.don_gia, 'thanhTien', h.thanh_tien,
      'soBaoGia', h.so_bao_gia, 'soGoiThau', h.so_goi_thau
    ) order by h.cua_so, h.ngay_ky, h.contract_item_id), '[]'::json) from h),
  'lienKet', (select coalesce(json_agg(json_build_object(
      'id', l.id, 'quotaId', l.quota_id, 'itemId', l.contract_item_id, 'maHd', l.ma_hd,
      'cuaSo', l.cua_so, 'slHd', l.sl_hd, 'slQuota', l.sl_quota, 'cachGan', l.cach_gan,
      'nguoi', l.nguoi_gan, 'luc', l.gan_luc
    ) order by l.id), '[]'::json) from l)
);
$$;

-- ---------- ghi: gắn tay 1 dòng quota ↔ 1 dòng HĐ ----------
-- sl_hd theo đơn vị dòng HĐ; sl_quota quy đổi như hàm gắn tự động (bộ bung: ÷ định mức ÷ số
-- khoá linh kiện). Liên kết tự động của 2 dòng này bị xoá ngay (lần gắn tự động sau cũng bỏ
-- qua dòng đã có liên kết tay).
create or replace function app_sale.gan_tay_quota_hop_dong(
  p_quota_id bigint, p_contract_item_id integer, p_khoa text, p_sl_hd numeric,
  p_nguoi text, p_nam text default 'FY26'
)
returns json
language plpgsql
volatile
set search_path = shared, app_sale, pg_temp
set statement_timeout = '60s'
as $$
declare
  q record;
  h record;
  v_id bigint;
begin
  if p_sl_hd is null or p_sl_hd <= 0 then
    raise exception 'sl_khong_hop_le';
  end if;
  select * into q from app_sale.quota_theo_khoa(p_nam) x
   where x.quota_id = p_quota_id and x.khoa_sp = p_khoa limit 1;
  if not found then raise exception 'khong_tim_thay_quota'; end if;
  select * into h from app_sale.v_hop_dong_dong x
   where x.contract_item_id = p_contract_item_id and x.khoa_sp = p_khoa limit 1;
  if not found then raise exception 'khong_tim_thay_dong_hd'; end if;
  if p_sl_hd > h.so_luong then raise exception 'sl_vuot_dong_hd'; end if;

  delete from app_sale.quota_hop_dong
   where cach_gan = 'tu_dong'
     and (quota_id = p_quota_id or contract_item_id = p_contract_item_id);

  insert into app_sale.quota_hop_dong
    (quota_id, contract_item_id, ma_hd, khoa_sp, cua_so, sl_hd, sl_quota, cach_gan, quy_tac, nguoi_gan)
  values (p_quota_id, p_contract_item_id, h.ma_hd, p_khoa,
    case when q.tt = 'cu' then 'quota_1_4' else 'trong_nam' end,
    p_sl_hd, p_sl_hd / q.dinh_muc / q.n_khoa_bo, 'tay', 'tay', p_nguoi)
  on conflict (quota_id, contract_item_id, khoa_sp) do update
    set sl_hd = excluded.sl_hd, sl_quota = excluded.sl_quota, cua_so = excluded.cua_so,
        cach_gan = 'tay', quy_tac = 'tay', nguoi_gan = excluded.nguoi_gan, gan_luc = now()
  returning id into v_id;
  return json_build_object('id', v_id);
end;
$$;

create or replace function app_sale.bo_gan_tay_quota_hop_dong(p_id bigint)
returns integer
language sql
volatile
set search_path = app_sale, pg_temp
as $$
  with x as (delete from app_sale.quota_hop_dong where id = p_id and cach_gan = 'tay' returning 1)
  select count(*)::int from x;
$$;

-- ---------- ghi: ghép mã quota ↔ khoá HĐ (riêng 1 KH) ----------
-- Nút phía quota chọn như quota_theo_khoa: 'B:' nếu mã là bộ trong v_khoa_so_sanh_sp, 'S:' nếu
-- là SP lẻ, còn lại 'Q:' (mã chưa có trong danh mục). Ghép lại cùng (KH, nút) thì ghi đè đích.
create or replace function app_sale.them_alias_khoa_sp(
  p_ma_kh text, p_ma_sp text[], p_khoa_den text, p_ghi_chu text, p_nguoi text
)
returns integer
language plpgsql
volatile
set search_path = shared, app_sale, pg_temp
as $$
declare
  v_ma text;
  v_nut text;
  n integer := 0;
begin
  if coalesce(btrim(p_ma_kh), '') = '' or coalesce(btrim(p_khoa_den), '') = '' then
    raise exception 'thieu_tham_so';
  end if;
  foreach v_ma in array coalesce(p_ma_sp, '{}') loop
    v_ma := btrim(v_ma);
    continue when v_ma = '';
    select case
      when exists (select 1 from app_sale.v_khoa_so_sanh_sp where nut = 'B:' || v_ma) then 'B:' || v_ma
      when exists (select 1 from app_sale.v_khoa_so_sanh_sp where nut = 'S:' || v_ma) then 'S:' || v_ma
      else 'Q:' || v_ma end into v_nut;
    continue when v_nut = p_khoa_den;
    insert into app_sale.khoa_sp_alias (ma_kh, nut_tu, nut_den, ghi_chu, nguon)
    values (btrim(p_ma_kh), v_nut, btrim(p_khoa_den), p_ghi_chu, 'app:' || coalesce(p_nguoi, ''))
    on conflict (ma_kh, nut_tu) do update
      set nut_den = excluded.nut_den, ghi_chu = excluded.ghi_chu,
          nguon = excluded.nguon, tao_luc = now();
    n := n + 1;
  end loop;
  return n;
end;
$$;

revoke all on app_sale.kiem_tra_thau_xu_ly from public, anon, authenticated;
revoke all on app_sale.kiem_tra_thau_snapshot from public, anon, authenticated;
grant select, insert, update, delete on app_sale.kiem_tra_thau_xu_ly to service_role;
grant select, insert, update, delete on app_sale.kiem_tra_thau_snapshot to service_role;

revoke all on function app_sale.kiem_tra_doi_chieu_hop_dong() from public, anon, authenticated;
revoke all on function app_sale.goi_y_dot_tu_hop_dong(text) from public, anon, authenticated;
revoke all on function app_sale.hop_dong_theo_san_pham(jsonb) from public, anon, authenticated;
revoke all on function app_sale.chi_tiet_khoa_hop_dong(text, text, text) from public, anon, authenticated;
revoke all on function app_sale.gan_tay_quota_hop_dong(bigint, integer, text, numeric, text, text) from public, anon, authenticated;
revoke all on function app_sale.bo_gan_tay_quota_hop_dong(bigint) from public, anon, authenticated;
revoke all on function app_sale.them_alias_khoa_sp(text, text[], text, text, text) from public, anon, authenticated;
grant execute on function app_sale.kiem_tra_doi_chieu_hop_dong() to service_role;
grant execute on function app_sale.goi_y_dot_tu_hop_dong(text) to service_role;
grant execute on function app_sale.hop_dong_theo_san_pham(jsonb) to service_role;
grant execute on function app_sale.chi_tiet_khoa_hop_dong(text, text, text) to service_role;
grant execute on function app_sale.gan_tay_quota_hop_dong(bigint, integer, text, numeric, text, text) to service_role;
grant execute on function app_sale.bo_gan_tay_quota_hop_dong(bigint) to service_role;
grant execute on function app_sale.them_alias_khoa_sp(text, text[], text, text, text) to service_role;

select cron.unschedule(jobid) from cron.job where jobname = 'kiem-tra-thau-don-xong';
select cron.schedule('kiem-tra-thau-don-xong', '20 19 * * *',
  $c$delete from app_sale.kiem_tra_thau_xu_ly where trang_thai = 'xong' and xong_luc < now() - interval '60 days'$c$);

commit;
