-- Rollback 20261001100000_chia_hoa_don_theo_phieu_sv.sql
-- Trả hoa_don_actual về đọc thẳng hoa_don_bovattu, bỏ view/bảng chia PS.
-- Sau khi chạy: select public.map_hoadon_to_sale_target(); để sale_target về số cũ.

create or replace view app_sale.hoa_don_actual as
with base as (
  select h.thang                                  as thang_ke_hoach,
         coalesce(d.ps, h.ten_ps)                 as ps,
         h.ma_kh                                  as ma_khach_hang,
         h.bo_vat_tu,
         h.san_pham,
         h.so_luong,
         h.tong_gia_ban,
         d.area                                   as mien,
         coalesce(d.bu, nullif(btrim(h.bu), ''))  as bu,
         h.nhom_san_pham,
         h.ten_kh                                 as khach_hang
  from app_sale.hoa_don_bovattu h
  left join lateral (
    select ps, area, bu
    from shared.dm_ps
    where lower(btrim(ten_ps)) = lower(btrim(h.ten_ps))
    order by (trang_thai = 'Active') desc
    limit 1
  ) d on true
)
select thang_ke_hoach,
       max(mien)          as mien,
       ps,
       ma_khach_hang,
       max(khach_hang)    as khach_hang,
       max(bu)            as bu,
       max(nhom_san_pham) as nhom_san_pham,
       bo_vat_tu,
       san_pham,
       sum(so_luong)      as sl_thuc_hien,
       sum(tong_gia_ban)::numeric / nullif(sum(so_luong), 0)::numeric as don_gia,
       sum(tong_gia_ban)::numeric as doanh_thu_thuc_hien
from base
group by thang_ke_hoach, ps, ma_khach_hang, bo_vat_tu, san_pham;

drop view if exists app_sale.hoa_don_bovattu_chia;
drop view if exists app_sale.v_chia_ps;
drop table if exists app_sale.phieu_su_dung;
drop table if exists app_sale.chia_ps_pham_vi;
