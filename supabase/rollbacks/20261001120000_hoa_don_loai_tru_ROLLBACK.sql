-- Rollback 20261001120000_hoa_don_loai_tru.sql
-- Trả v_chia_ps / hoa_don_bovattu_chia về đọc thẳng hoa_don_bovattu, bỏ cấu hình
-- loại trừ hóa đơn. MẤT danh sách khai báo trong app_sale.hoa_don_loai_tru.
-- Sau khi chạy: select public.cap_nhat_thuc_hien(); để sale_target về số cũ.

create or replace view app_sale.v_chia_ps as
with hd as (
  -- đơn vị hóa đơn trong phạm vi, khoá theo 1 tài liệu (ngày + số + KH)
  select h.ma_kh, h.nhom_san_pham, h.ngay_tai_lieu, h.so_tai_lieu,
         coalesce(nullif(btrim(h.ma_vat_tu), ''), h.bo_vat_tu) as khoa,
         sum(h.so_luong) as sl,
         pv.tu_ngay
    from app_sale.hoa_don_bovattu h
    join app_sale.chia_ps_pham_vi pv
      on pv.ma_kh = h.ma_kh and pv.nhom_san_pham = h.nhom_san_pham
   group by 1, 2, 3, 4, 5, 7
  having sum(h.so_luong) > 0
),
sv as (
  -- đơn vị phiếu: 'bo' -> 1/phiếu; 'vat_tu' -> tổng SL theo mã
  select p.ma_kh, p.nhom_san_pham, p.so_phieu, p.ngay, p.ten_ps, p.so_tai_lieu_ghi,
         case when pv.don_vi = 'bo' then p.bo_vat_tu else p.ma_vat_tu end as khoa,
         case when pv.don_vi = 'bo' then 1 else sum(p.so_luong) end       as sl
    from app_sale.phieu_su_dung p
    join app_sale.chia_ps_pham_vi pv
      on pv.ma_kh = p.ma_kh and pv.nhom_san_pham = p.nhom_san_pham
   where pv.don_vi = 'vat_tu' or p.bo_vat_tu is not null
   group by 1, 2, 3, 4, 5, 6, 7, pv.don_vi
  having pv.don_vi = 'bo' or sum(p.so_luong) > 0
),
-- Bước 1: phiếu ghi số HĐ -> đúng dòng HĐ đó (gần ngày phiếu nhất nếu số trùng)
gan as (
  select s.*, h.ngay_tai_lieu, h.so_tai_lieu, h.sl as h_sl
    from sv s
    join lateral (
      select h.*
        from hd h
       where h.ma_kh = s.ma_kh and h.nhom_san_pham = s.nhom_san_pham
         and h.khoa = s.khoa and h.so_tai_lieu = s.so_tai_lieu_ghi
         and h.ngay_tai_lieu between s.ngay - 366 and s.ngay + 31
       order by abs(h.ngay_tai_lieu - s.ngay)
       limit 1
    ) h on true
),
gan_cum as (
  select g.*,
         sum(g.sl) over (partition by g.ma_kh, g.nhom_san_pham, g.ngay_tai_lieu,
                                      g.so_tai_lieu, g.khoa
                         order by g.ngay, g.so_phieu) - g.sl as c0
    from gan g
),
b1 as (
  select ma_kh, nhom_san_pham, ngay_tai_lieu, so_tai_lieu, khoa, ten_ps, so_phieu, ngay,
         least(c0 + sl, h_sl) - c0 as sl
    from gan_cum
   where c0 < h_sl
),
-- Phần còn lại cho bước 2
sv_con as (
  select s.ma_kh, s.nhom_san_pham, s.khoa, s.so_phieu, s.ngay, s.ten_ps,
         s.sl - coalesce(sum(b.sl), 0) as sl
    from sv s
    left join b1 b
      on b.ma_kh = s.ma_kh and b.nhom_san_pham = s.nhom_san_pham
     and b.khoa = s.khoa and b.so_phieu = s.so_phieu
   group by 1, 2, 3, 4, 5, 6, s.sl
  having s.sl - coalesce(sum(b.sl), 0) > 0
),
hd_con as (
  select h.ma_kh, h.nhom_san_pham, h.khoa, h.ngay_tai_lieu, h.so_tai_lieu,
         h.sl - coalesce(sum(b.sl), 0) as sl
    from hd h
    left join b1 b
      on b.ma_kh = h.ma_kh and b.nhom_san_pham = h.nhom_san_pham and b.khoa = h.khoa
     and b.ngay_tai_lieu = h.ngay_tai_lieu and b.so_tai_lieu = h.so_tai_lieu
   where h.ngay_tai_lieu >= h.tu_ngay
   group by 1, 2, 3, 4, 5, h.sl
  having h.sl - coalesce(sum(b.sl), 0) > 0
),
-- Bước 2: FIFO theo khoảng cộng dồn
sv_cum as (
  select s.*,
         sum(s.sl) over (partition by ma_kh, nhom_san_pham, khoa
                         order by ngay, so_phieu) as c1
    from sv_con s
),
hd_cum as (
  select h.*,
         sum(h.sl) over (partition by ma_kh, nhom_san_pham, khoa
                         order by ngay_tai_lieu, so_tai_lieu) as c1
    from hd_con h
),
b2 as (
  select h.ma_kh, h.nhom_san_pham, h.ngay_tai_lieu, h.so_tai_lieu, h.khoa,
         s.ten_ps, s.so_phieu, s.ngay,
         least(h.c1, s.c1) - greatest(h.c1 - h.sl, s.c1 - s.sl) as sl
    from hd_cum h
    join sv_cum s
      on s.ma_kh = h.ma_kh and s.nhom_san_pham = h.nhom_san_pham and s.khoa = h.khoa
     and s.c1 - s.sl < h.c1 and h.c1 - h.sl < s.c1
)
select ma_kh, nhom_san_pham, ngay_tai_lieu, so_tai_lieu, khoa, ten_ps,
       so_phieu, ngay as ngay_phieu, sl, 'so_hd'::text as buoc
  from b1
union all
select ma_kh, nhom_san_pham, ngay_tai_lieu, so_tai_lieu, khoa, ten_ps,
       so_phieu, ngay, sl, 'fifo'
  from b2;

comment on view app_sale.v_chia_ps is
  'Ghép phiếu SV vào hóa đơn: mỗi dòng = phần số lượng của 1 phiếu nằm trên 1 hóa đơn (ngày + số tài liệu + khoa). buoc: so_hd = ghép theo số HĐ ghi trên phiếu, fifo = ghép theo thứ tự ngày.';

-- 4) Hóa đơn sau khi chia ------------------------------------------------
create or replace view app_sale.hoa_don_bovattu_chia as
with a as (
  select ma_kh, nhom_san_pham, ngay_tai_lieu, so_tai_lieu, khoa, ten_ps, sum(sl) as sl
    from app_sale.v_chia_ps
   group by 1, 2, 3, 4, 5, 6
),
k as (
  -- tổng SL hóa đơn + tổng đã chia theo từng khoá có chia
  select h.ma_kh, h.nhom_san_pham, h.ngay_tai_lieu, h.so_tai_lieu,
         coalesce(nullif(btrim(h.ma_vat_tu), ''), h.bo_vat_tu) as khoa,
         sum(h.so_luong) as q,
         max(t.tot) as tot
    from app_sale.hoa_don_bovattu h
    join (select ma_kh, nhom_san_pham, ngay_tai_lieu, so_tai_lieu, khoa, sum(sl) as tot
            from a group by 1, 2, 3, 4, 5) t
      on t.ma_kh = h.ma_kh and t.nhom_san_pham = h.nhom_san_pham
     and t.ngay_tai_lieu = h.ngay_tai_lieu and t.so_tai_lieu = h.so_tai_lieu
     and t.khoa = coalesce(nullif(btrim(h.ma_vat_tu), ''), h.bo_vat_tu)
   group by 1, 2, 3, 4, 5
),
h as (
  select h.*, k.q, k.tot
    from app_sale.hoa_don_bovattu h
    left join k
      on k.ma_kh = h.ma_kh and k.nhom_san_pham = h.nhom_san_pham
     and k.ngay_tai_lieu = h.ngay_tai_lieu and k.so_tai_lieu = h.so_tai_lieu
     and k.khoa = coalesce(nullif(btrim(h.ma_vat_tu), ''), h.bo_vat_tu)
)
-- dòng không chia
select h.id, h.thang, h.ngay_tai_lieu, h.so_tai_lieu, h.so_eo, h.ma_kh, h.ten_kh, h.bu,
       h.nhom_san_pham, h.bo_vat_tu, h.san_pham, h.ma_vat_tu, h.ten_ps,
       h.so_luong, h.tong_gia_ban, 'goc'::text as chia
  from h
 where h.q is null
union all
-- phần đã ghép phiếu -> PS trên phiếu
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
-- phần chưa có phiếu -> giữ PS đứng tên
select h.id, h.thang, h.ngay_tai_lieu, h.so_tai_lieu, h.so_eo, h.ma_kh, h.ten_kh, h.bu,
       h.nhom_san_pham, h.bo_vat_tu, h.san_pham, h.ma_vat_tu, h.ten_ps,
       h.so_luong * (h.q - h.tot) / h.q, h.tong_gia_ban * (h.q - h.tot) / h.q, 'con_lai'
  from h
 where h.q is not null and h.q > h.tot;

comment on view app_sale.hoa_don_bovattu_chia is
  'hoa_don_bovattu sau khi chia PS theo phiếu SV (v_chia_ps). chia: goc = không chia, chia = phần ghép phiếu (ten_ps lấy từ phiếu), con_lai = phần chưa có phiếu (giữ PS gốc). Tổng so_luong/tong_gia_ban theo id bằng dòng gốc.';

grant select on app_sale.v_chia_ps, app_sale.hoa_don_bovattu_chia
  to service_role, anon, authenticated;

drop function if exists public.get_hoa_don_loai_tru();
drop function if exists public.tim_hoa_don(text, int);
drop function if exists public.luu_hoa_don_loai_tru(text, date, boolean, text, text);
drop function if exists public.xoa_hoa_don_loai_tru(bigint);
drop view if exists app_sale.hoa_don_bovattu_hieu_luc;
drop table if exists app_sale.hoa_don_loai_tru;
