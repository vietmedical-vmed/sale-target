-- ════════════════════════════════════════════════════════════════════════
-- Thêm đơn giá cho dòng thực hiện NGOÀI KẾ HOẠCH
--
-- Dòng ngoài kế hoạch không có dòng sale_target nào nên không có đơn giá →
-- app không tính được doanh thu cho chúng. Hoá đơn có sẵn tiền thật
-- (hoa_don_bovattu.tong_gia_ban) nên lấy ngay từ đó:
--     don_gia = tổng tiền / tổng số lượng  (bình quân theo doanh thu của nhóm)
-- Chia cho 0 (SL cộng lại = 0, vd bán rồi trả hết) → NULL, app hiển thị "—".
--
-- CHỈ THÊM CỘT VÀO CUỐI: create or replace view không cho đổi tên/thứ tự cột
-- đang có, và giữ nguyên đầu danh sách cũng là để matview v_th_theo_ps/_sp
-- không phải drop. Thân view sao nguyên từ 20260807110000_hoa_don_actual_flow.sql.
--
-- ⚠ Muốn BỎ cột này về sau phải drop + tạo lại view (create or replace không
--   xoá được cột) → phải xử lý cả các đối tượng phụ thuộc, đừng dùng cascade bừa.
-- ════════════════════════════════════════════════════════════════════════

-- ── 1) hoa_don_actual: gom thêm tổng tiền để suy đơn giá ───────────────────
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
       -- ép numeric: nếu 2 cột nguồn là kiểu nguyên thì phép chia sẽ cắt cụt phần lẻ
       sum(tong_gia_ban)::numeric / nullif(sum(so_luong), 0)::numeric as don_gia
from base
group by thang_ke_hoach, ps, ma_khach_hang, bo_vat_tu, san_pham;

grant select on app_sale.hoa_don_actual to service_role, anon, authenticated;

-- ── 2) v_actual_ngoai_ke_hoach: đưa đơn giá ra ngoài cho edge function ─────
create or replace view app_sale.v_actual_ngoai_ke_hoach as
 with ps_ref as (
         select t.ps_n, t.ps_canon, t.bu, t.mien
           from ( select lower(btrim(s.ps)) as ps_n, s.ps as ps_canon, s.bu, s.mien,
                    row_number() over (partition by (lower(btrim(s.ps))) order by (coalesce(btrim(s.bu), ''::text) <> ''::text) desc, (coalesce(btrim(s.mien), ''::text) <> ''::text) desc, (count(*)) desc) as rn
                   from shared.sale_target s
                  where coalesce(btrim(s.ps), ''::text) <> ''::text
                  group by (lower(btrim(s.ps))), s.ps, s.bu, s.mien) t
          where t.rn = 1
        ), bu_ref as (
         select t.bu_n, t.bu_canon
           from ( select regexp_replace(lower(btrim(s.bu)), '[^a-z0-9]'::text, ''::text, 'g'::text) as bu_n, s.bu as bu_canon,
                    row_number() over (partition by (regexp_replace(lower(btrim(s.bu)), '[^a-z0-9]'::text, ''::text, 'g'::text)) order by (count(*)) desc) as rn
                   from shared.sale_target s
                  where coalesce(btrim(s.bu), ''::text) <> ''::text
                  group by (regexp_replace(lower(btrim(s.bu)), '[^a-z0-9]'::text, ''::text, 'g'::text)), s.bu) t
          where t.rn = 1
        ), sp_ref as (
         select t.sp_n, t.nhom_san_pham
           from ( select lower(btrim(s.san_pham)) as sp_n, s.nhom_san_pham,
                    row_number() over (partition by (lower(btrim(s.san_pham))) order by (count(*)) desc) as rn
                   from shared.sale_target s
                  where coalesce(btrim(s.san_pham), ''::text) <> ''::text and coalesce(btrim(s.nhom_san_pham), ''::text) <> ''::text
                  group by (lower(btrim(s.san_pham))), s.nhom_san_pham) t
          where t.rn = 1
        )
 select a.thang_ke_hoach,
    coalesce(nullif(btrim(a.mien), ''::text), p.mien) as mien,
    coalesce(p.ps_canon, a.ps) as ps,
    a.ma_khach_hang,
    a.khach_hang,
    coalesce(p.bu, b.bu_canon, nullif(btrim(a.bu), ''::text)) as bu,
    coalesce(g.nhom_san_pham, nullif(btrim(a.nhom_san_pham), ''::text)) as nhom_san_pham,
    a.bo_vat_tu,
    a.san_pham,
    a.sl_thuc_hien,
    a.don_gia
   from app_sale.hoa_don_actual a
     left join ps_ref p on p.ps_n = lower(btrim(a.ps))
     left join bu_ref b on b.bu_n = regexp_replace(lower(btrim(a.bu)), '[^a-z0-9]'::text, ''::text, 'g'::text)
     left join sp_ref g on g.sp_n = lower(btrim(a.san_pham))
  where not (exists ( select 1
           from shared.sale_target s
          where s.thang_ke_hoach = a.thang_ke_hoach
            and lower(btrim(coalesce(s.ps, ''::text))) = lower(btrim(coalesce(a.ps, ''::text)))
            and lower(btrim(coalesce(s.ma_khach_hang, ''::text))) = lower(btrim(coalesce(a.ma_khach_hang, ''::text)))
            and lower(btrim(coalesce(s.bo_vat_tu, ''::text))) = lower(btrim(coalesce(a.bo_vat_tu, ''::text)))
            and lower(btrim(coalesce(s.san_pham, ''::text))) = lower(btrim(coalesce(a.san_pham, ''::text)))));

grant select on app_sale.v_actual_ngoai_ke_hoach to service_role, anon, authenticated;
