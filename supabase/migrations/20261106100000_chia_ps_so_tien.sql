-- ════════════════════════════════════════════════════════════════════════
-- CHIA HÓA ĐƠN THEO SỐ TIỀN NGÀNH HÀNG CUNG CẤP
--
-- Từ T9/2026 ngành hàng không gửi phiếu SV mà gửi bảng "Doanh thu VĐ T9 + T10":
-- mỗi tháng sử dụng, mỗi số hóa đơn -> số tiền (trước VAT) của từng PS.
-- Bảng chia_ps_so_tien lưu các dòng đó (nạp bằng chia_doanh_thu_hd_pipeline.py,
-- script tra sẵn ngay_tai_lieu của hóa đơn).
--
-- Thứ tự chia trong hoa_don_bovattu_chia (theo từng tài liệu + nhóm):
--   1. phiếu SV (v_chia_ps)                                  -> chia = 'chia'
--   2. số tiền ngành hàng, chia trên PHẦN CÒN LẠI sau bước 1,
--      tỷ lệ theo tiền, áp đều cho các dòng của tài liệu    -> chia = 'so_tien'
--      (nếu số tiền khai > phần còn lại thì co lại cho vừa;
--       xem v_chia_ps_so_tien_doi_chieu)
--   3. phần vẫn còn lại: tỷ lệ tạm (nếu có)                 -> chia = 'tam'
--      hoặc giữ PS đứng tên                                  -> 'goc' / 'con_lai'
-- Tổng so_luong / tong_gia_ban theo id dòng hóa đơn giữ nguyên.
--
-- Doanh thu vẫn ghi theo THÁNG HÓA ĐƠN (thang_su_dung chỉ để đối chiếu).
-- ════════════════════════════════════════════════════════════════════════

create table if not exists app_sale.chia_ps_so_tien (
  id             bigint generated always as identity primary key,
  ma_kh          text not null,
  nhom_san_pham  text not null,
  ngay_tai_lieu  date not null,
  so_tai_lieu    text not null,
  ten_ps         text not null,
  so_tien        numeric not null check (so_tien >= 0),
  thang_su_dung  text not null,
  phan_loai      text,
  ten_file       text,
  created_at     timestamptz not null default now(),
  unique (ma_kh, nhom_san_pham, ngay_tai_lieu, so_tai_lieu, ten_ps, thang_su_dung, phan_loai)
);

comment on table app_sale.chia_ps_so_tien is
  'Số tiền (trước VAT) từng PS dùng từ 1 hóa đơn trong 1 tháng sử dụng, do ngành hàng cung cấp. ten_ps = tên đầy đủ như hoa_don_bovattu.ten_ps. Chia phần hóa đơn chưa có phiếu SV.';

create index if not exists idx_chia_ps_so_tien_doc
  on app_sale.chia_ps_so_tien (ma_kh, nhom_san_pham, so_tai_lieu, ngay_tai_lieu);

alter table app_sale.chia_ps_so_tien enable row level security;
grant select, insert, update, delete on app_sale.chia_ps_so_tien to service_role;

create or replace view app_sale.hoa_don_bovattu_chia as
with a as (
  select ma_kh, nhom_san_pham, ngay_tai_lieu, so_tai_lieu, khoa, ten_ps, sum(sl) as sl
    from app_sale.v_chia_ps
   group by 1, 2, 3, 4, 5, 6
),
k as (
  -- tổng SL hóa đơn + tổng đã chia theo phiếu, theo từng khoá có phiếu
  select h.ma_kh, h.nhom_san_pham, h.ngay_tai_lieu, h.so_tai_lieu,
         coalesce(nullif(btrim(h.ma_vat_tu), ''), h.bo_vat_tu) as khoa,
         sum(h.so_luong) as q,
         max(t.tot) as tot
    from app_sale.hoa_don_bovattu_hieu_luc h
    join (select ma_kh, nhom_san_pham, ngay_tai_lieu, so_tai_lieu, khoa, sum(sl) as tot
            from a group by 1, 2, 3, 4, 5) t
      on t.ma_kh = h.ma_kh and t.nhom_san_pham = h.nhom_san_pham
     and t.ngay_tai_lieu = h.ngay_tai_lieu and t.so_tai_lieu = h.so_tai_lieu
     and t.khoa = coalesce(nullif(btrim(h.ma_vat_tu), ''), h.bo_vat_tu)
   group by 1, 2, 3, 4, 5
),
tl as (
  select ma_kh, nhom_san_pham, ten_ps,
         ty_le / sum(ty_le) over (partition by ma_kh, nhom_san_pham) as ty_le
    from app_sale.chia_ps_ty_le_tam
),
st as (
  -- số tiền ngành hàng theo tài liệu + nhóm + PS
  select ma_kh, nhom_san_pham, ngay_tai_lieu, so_tai_lieu, ten_ps, sum(so_tien) as a_ps
    from app_sale.chia_ps_so_tien
   group by 1, 2, 3, 4, 5
),
h0 as (
  select h.*, k.q, k.tot,
         -- phần chưa có phiếu (1 = cả dòng)
         case when k.q is null then 1::numeric else (k.q - k.tot) / k.q end as rf,
         coalesce(h.ngay_tai_lieu >= pv.tu_ngay
                  and exists (select 1 from app_sale.chia_ps_ty_le_tam t
                               where t.ma_kh = h.ma_kh and t.nhom_san_pham = h.nhom_san_pham),
                  false) as tam
    from app_sale.hoa_don_bovattu_hieu_luc h
    left join k
      on k.ma_kh = h.ma_kh and k.nhom_san_pham = h.nhom_san_pham
     and k.ngay_tai_lieu = h.ngay_tai_lieu and k.so_tai_lieu = h.so_tai_lieu
     and k.khoa = coalesce(nullif(btrim(h.ma_vat_tu), ''), h.bo_vat_tu)
    left join app_sale.chia_ps_pham_vi pv
      on pv.ma_kh = h.ma_kh and pv.nhom_san_pham = h.nhom_san_pham
),
doc as (
  -- tài liệu có số tiền ngành hàng: tiền còn lại sau phiếu (r) và tiền khai (a)
  select d.ma_kh, d.nhom_san_pham, d.ngay_tai_lieu, d.so_tai_lieu, d.a, r.r
    from (select ma_kh, nhom_san_pham, ngay_tai_lieu, so_tai_lieu, sum(a_ps) as a
            from st group by 1, 2, 3, 4) d
    join (select ma_kh, nhom_san_pham, ngay_tai_lieu, so_tai_lieu,
                 sum(tong_gia_ban * rf) as r
            from h0 group by 1, 2, 3, 4) r
      on r.ma_kh = d.ma_kh and r.nhom_san_pham = d.nhom_san_pham
     and r.ngay_tai_lieu = d.ngay_tai_lieu and r.so_tai_lieu = d.so_tai_lieu
   where r.r > 0 and d.a > 0
),
h as (
  select h0.*,
         doc.a, greatest(doc.r, doc.a) as den,
         h0.rf * coalesce(greatest(doc.r - doc.a, 0) / greatest(doc.r, doc.a), 1) as rest_f
    from h0
    left join doc
      on doc.ma_kh = h0.ma_kh and doc.nhom_san_pham = h0.nhom_san_pham
     and doc.ngay_tai_lieu = h0.ngay_tai_lieu and doc.so_tai_lieu = h0.so_tai_lieu
)
-- dòng không chia
select h.id, h.thang, h.ngay_tai_lieu, h.so_tai_lieu, h.so_eo, h.ma_kh, h.ten_kh, h.bu,
       h.nhom_san_pham, h.bo_vat_tu, h.san_pham, h.ma_vat_tu, h.ten_ps,
       h.so_luong, h.tong_gia_ban, 'goc'::text as chia
  from h
 where h.q is null and h.a is null and not h.tam
union all
-- 1. phần đã ghép phiếu -> PS trên phiếu
select h.id, h.thang, h.ngay_tai_lieu, h.so_tai_lieu, h.so_eo, h.ma_kh, h.ten_kh, h.bu,
       h.nhom_san_pham, h.bo_vat_tu, h.san_pham, h.ma_vat_tu, a.ten_ps,
       h.so_luong * a.sl / h.q, h.tong_gia_ban * a.sl / h.q, 'chia'
  from h
  join a
    on a.ma_kh = h.ma_kh and a.nhom_san_pham = h.nhom_san_pham
   and a.ngay_tai_lieu = h.ngay_tai_lieu and a.so_tai_lieu = h.so_tai_lieu
   and a.khoa = coalesce(nullif(btrim(h.ma_vat_tu), ''), h.bo_vat_tu)
 where h.q is not null
union all
-- 2. phần theo số tiền ngành hàng
select h.id, h.thang, h.ngay_tai_lieu, h.so_tai_lieu, h.so_eo, h.ma_kh, h.ten_kh, h.bu,
       h.nhom_san_pham, h.bo_vat_tu, h.san_pham, h.ma_vat_tu, st.ten_ps,
       h.so_luong    * h.rf * st.a_ps / h.den,
       h.tong_gia_ban * h.rf * st.a_ps / h.den,
       'so_tien'
  from h
  join st
    on st.ma_kh = h.ma_kh and st.nhom_san_pham = h.nhom_san_pham
   and st.ngay_tai_lieu = h.ngay_tai_lieu and st.so_tai_lieu = h.so_tai_lieu
 where h.a is not null and h.rf > 0 and st.a_ps > 0
union all
-- 3a. phần còn lại, không có tỷ lệ tạm -> giữ PS đứng tên
select h.id, h.thang, h.ngay_tai_lieu, h.so_tai_lieu, h.so_eo, h.ma_kh, h.ten_kh, h.bu,
       h.nhom_san_pham, h.bo_vat_tu, h.san_pham, h.ma_vat_tu, h.ten_ps,
       h.so_luong * h.rest_f, h.tong_gia_ban * h.rest_f, 'con_lai'
  from h
 where not h.tam and h.rest_f > 0 and (h.q is not null or h.a is not null)
union all
-- 3b. phần còn lại, có tỷ lệ tạm -> chia theo tỷ lệ
select h.id, h.thang, h.ngay_tai_lieu, h.so_tai_lieu, h.so_eo, h.ma_kh, h.ten_kh, h.bu,
       h.nhom_san_pham, h.bo_vat_tu, h.san_pham, h.ma_vat_tu, tl.ten_ps,
       h.so_luong * h.rest_f * tl.ty_le, h.tong_gia_ban * h.rest_f * tl.ty_le, 'tam'
  from h
  join tl on tl.ma_kh = h.ma_kh and tl.nhom_san_pham = h.nhom_san_pham
 where h.tam and h.rest_f > 0;

comment on view app_sale.hoa_don_bovattu_chia is
  'hoa_don_bovattu (trừ HĐ loại trừ) sau khi chia PS. chia: goc = không chia, chia = theo phiếu SV (v_chia_ps), so_tien = theo số tiền ngành hàng (chia_ps_so_tien) trên phần chưa có phiếu, con_lai = phần còn lại giữ PS gốc, tam = phần còn lại chia theo chia_ps_ty_le_tam. Tổng so_luong/tong_gia_ban theo id bằng dòng gốc.';

grant select on app_sale.hoa_don_bovattu_chia to service_role;  -- không cấp anon/authenticated: app_sale lộ qua PostgREST (xem 20261107110000)

-- Đối chiếu: tiền ngành hàng khai so với phần hóa đơn còn lại sau phiếu SV
create or replace view app_sale.v_chia_ps_so_tien_doi_chieu as
with st as (
  select ma_kh, nhom_san_pham, ngay_tai_lieu, so_tai_lieu, sum(so_tien) as tien_khai,
         string_agg(distinct thang_su_dung, ', ' order by thang_su_dung) as thang_su_dung
    from app_sale.chia_ps_so_tien
   group by 1, 2, 3, 4
),
hd as (
  select ma_kh, nhom_san_pham, ngay_tai_lieu, so_tai_lieu,
         sum(tong_gia_ban) as tong_hd,
         sum(tong_gia_ban) filter (where chia = 'chia') as theo_phieu
    from app_sale.hoa_don_bovattu_chia
   group by 1, 2, 3, 4
)
select st.ma_kh, st.nhom_san_pham, st.ngay_tai_lieu, st.so_tai_lieu, st.thang_su_dung,
       hd.tong_hd,
       coalesce(hd.theo_phieu, 0)                              as theo_phieu,
       hd.tong_hd - coalesce(hd.theo_phieu, 0)                 as con_lai_sau_phieu,
       st.tien_khai,
       st.tien_khai - (hd.tong_hd - coalesce(hd.theo_phieu, 0)) as vuot,
       case when hd.tong_hd is null then 'khong_thay_hd'
            when st.tien_khai > hd.tong_hd - coalesce(hd.theo_phieu, 0) + 1 then 'vuot_con_lai'
            else 'ok' end                                       as trang_thai
  from st
  left join hd
    on hd.ma_kh = st.ma_kh and hd.nhom_san_pham = st.nhom_san_pham
   and hd.ngay_tai_lieu = st.ngay_tai_lieu and hd.so_tai_lieu = st.so_tai_lieu;

comment on view app_sale.v_chia_ps_so_tien_doi_chieu is
  'Mỗi hóa đơn có số tiền ngành hàng: tổng HĐ, phần đã chia theo phiếu SV, phần còn lại, tiền khai. vuot_con_lai = khai nhiều hơn phần còn lại (đã co lại theo tỷ lệ).';

grant select on app_sale.v_chia_ps_so_tien_doi_chieu to service_role;

-- Khớp Zimmer Việt Đức: Tùng + Tuyên cùng phụ trách (chỉ chia theo số tiền ngành hàng)
insert into app_sale.chia_ps_pham_vi (ma_kh, nhom_san_pham, don_vi, tu_ngay, ghi_chu) values
  ('BV0342', 'Khớp Zimmer', 'bo', '2026-09-01', 'Tùng + Tuyên cùng phụ trách; HĐ đứng tên Tùng; chia theo số tiền ngành hàng')
on conflict (ma_kh, nhom_san_pham) do nothing;
