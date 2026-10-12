-- Rollback 20261012100000_chia_ps_ty_le_tam.sql
-- Trả hoa_don_bovattu_chia về bản không có tỷ lệ tạm (bản của 20261001120000),
-- bỏ bảng chia_ps_ty_le_tam. Sau khi chạy: select public.cap_nhat_thuc_hien();

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
    from app_sale.hoa_don_bovattu_hieu_luc h
    join (select ma_kh, nhom_san_pham, ngay_tai_lieu, so_tai_lieu, khoa, sum(sl) as tot
            from a group by 1, 2, 3, 4, 5) t
      on t.ma_kh = h.ma_kh and t.nhom_san_pham = h.nhom_san_pham
     and t.ngay_tai_lieu = h.ngay_tai_lieu and t.so_tai_lieu = h.so_tai_lieu
     and t.khoa = coalesce(nullif(btrim(h.ma_vat_tu), ''), h.bo_vat_tu)
   group by 1, 2, 3, 4, 5
),
h as (
  select h.*, k.q, k.tot
    from app_sale.hoa_don_bovattu_hieu_luc h
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

drop table if exists app_sale.chia_ps_ty_le_tam;
