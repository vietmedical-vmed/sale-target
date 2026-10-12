-- ════════════════════════════════════════════════════════════════════════
-- TỶ LỆ TẠM CHO PHẦN HÓA ĐƠN CHƯA CÓ PHIẾU SV
--
-- Bộ phận chưa chia kịp phiếu SV (vd tháng 9) -> phần hóa đơn chưa ghép được
-- phiếu nào tạm chia theo tỷ lệ cố định giữa các PS. Khi phiếu được nạp sau
-- này, v_chia_ps ghép phiếu trước, chỉ phần còn thiếu mới theo tỷ lệ tạm.
--
-- Áp cho: phạm vi có dòng trong chia_ps_ty_le_tam, hóa đơn từ tu_ngay của
-- phạm vi, phần 'goc' (khoá chưa có phiếu nào) + 'con_lai' (phần dư sau
-- ghép phiếu). Hóa đơn trước tu_ngay giữ PS đứng tên như cũ.
-- Tỷ lệ được chuẩn hoá theo tổng của phạm vi (khai 60/40 hay 0.6/0.4 đều được).
--
-- hoa_don_bovattu_chia thêm nhãn chia = 'tam'. Tổng theo id dòng HĐ giữ nguyên.
-- ════════════════════════════════════════════════════════════════════════

create table if not exists app_sale.chia_ps_ty_le_tam (
  ma_kh          text not null,
  nhom_san_pham  text not null,
  ten_ps         text not null,
  ty_le          numeric not null check (ty_le > 0),
  ghi_chu        text,
  updated_at     timestamptz not null default now(),
  primary key (ma_kh, nhom_san_pham, ten_ps),
  foreign key (ma_kh, nhom_san_pham)
    references app_sale.chia_ps_pham_vi (ma_kh, nhom_san_pham) on delete cascade
);

comment on table app_sale.chia_ps_ty_le_tam is
  'Tỷ lệ tạm chia doanh thu cho phần hóa đơn chưa ghép được phiếu SV. ten_ps = tên đầy đủ như hoa_don_bovattu.ten_ps (tra dm_ps). Xoá dòng của phạm vi để tắt.';

alter table app_sale.chia_ps_ty_le_tam enable row level security;
grant select, insert, update, delete on app_sale.chia_ps_ty_le_tam to service_role;

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
tl as (
  select ma_kh, nhom_san_pham, ten_ps,
         ty_le / sum(ty_le) over (partition by ma_kh, nhom_san_pham) as ty_le
    from app_sale.chia_ps_ty_le_tam
),
h as (
  select h.*, k.q, k.tot,
         -- phần chưa có phiếu được chia theo tỷ lệ tạm?
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
)
-- dòng không chia
select h.id, h.thang, h.ngay_tai_lieu, h.so_tai_lieu, h.so_eo, h.ma_kh, h.ten_kh, h.bu,
       h.nhom_san_pham, h.bo_vat_tu, h.san_pham, h.ma_vat_tu, h.ten_ps,
       h.so_luong, h.tong_gia_ban, 'goc'::text as chia
  from h
 where h.q is null and not h.tam
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
-- phần chưa có phiếu, không có tỷ lệ tạm -> giữ PS đứng tên
select h.id, h.thang, h.ngay_tai_lieu, h.so_tai_lieu, h.so_eo, h.ma_kh, h.ten_kh, h.bu,
       h.nhom_san_pham, h.bo_vat_tu, h.san_pham, h.ma_vat_tu, h.ten_ps,
       h.so_luong * (h.q - h.tot) / h.q, h.tong_gia_ban * (h.q - h.tot) / h.q, 'con_lai'
  from h
 where h.q is not null and h.q > h.tot and not h.tam
union all
-- phần chưa có phiếu, có tỷ lệ tạm -> chia theo tỷ lệ
select h.id, h.thang, h.ngay_tai_lieu, h.so_tai_lieu, h.so_eo, h.ma_kh, h.ten_kh, h.bu,
       h.nhom_san_pham, h.bo_vat_tu, h.san_pham, h.ma_vat_tu, tl.ten_ps,
       h.so_luong    * coalesce((h.q - h.tot) / h.q, 1) * tl.ty_le,
       h.tong_gia_ban * coalesce((h.q - h.tot) / h.q, 1) * tl.ty_le,
       'tam'
  from h
  join tl on tl.ma_kh = h.ma_kh and tl.nhom_san_pham = h.nhom_san_pham
 where h.tam and (h.q is null or h.q > h.tot);

comment on view app_sale.hoa_don_bovattu_chia is
  'hoa_don_bovattu (trừ HĐ loại trừ) sau khi chia PS theo phiếu SV (v_chia_ps). chia: goc = không chia, chia = phần ghép phiếu (ten_ps lấy từ phiếu), con_lai = phần chưa có phiếu (giữ PS gốc), tam = phần chưa có phiếu chia theo chia_ps_ty_le_tam. Tổng so_luong/tong_gia_ban theo id bằng dòng gốc.';

grant select on app_sale.hoa_don_bovattu_chia to service_role, anon, authenticated;

-- Tỷ lệ tạm cho BV0342 (chờ phiếu SV từ tháng 9)
insert into app_sale.chia_ps_ty_le_tam (ma_kh, nhom_san_pham, ten_ps, ty_le, ghi_chu) values
  ('BV0342', 'Khớp UOC',    'Phạm Ngọc Tùng', 50, 'Tạm chia 50/50 khi chưa có phiếu SV'),
  ('BV0342', 'Khớp UOC',    'Phạm Văn Tuyên', 50, 'Tạm chia 50/50 khi chưa có phiếu SV'),
  ('BV0342', 'NSK Arthrex', 'Phạm Văn Tuyên', 60, 'Tạm chia Tuyên 60 / Tùng 40 khi chưa có phiếu SV'),
  ('BV0342', 'NSK Arthrex', 'Phạm Ngọc Tùng', 40, 'Tạm chia Tuyên 60 / Tùng 40 khi chưa có phiếu SV')
on conflict (ma_kh, nhom_san_pham, ten_ps) do nothing;
