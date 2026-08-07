-- ════════════════════════════════════════════════════════════════════════
-- "Ngoài kế hoạch" chỉ lấy tháng CÓ TRONG KẾ HOẠCH (FY hiện tại)
--
-- app_sale.hoa_don_bovattu chứa cả hoá đơn năm trước (2025-04 → 2026-03), nên
-- v_actual_ngoai_ke_hoach trả về ~12 tháng FY25 lẫn FY26. Các dòng FY25 không
-- bao giờ khớp dòng kế hoạch nào (kế hoạch chỉ có FY26) nên rơi hết vào
-- "ngoài kế hoạch", và ở màn Tổng hợp theo PS chúng còn bị cộng vào Thực hiện
-- YTD vì isYtdMonth('2025-07') vẫn đúng.
--
-- Chặn ngay tại view: chỉ giữ tháng đang tồn tại trong shared.sale_target.
-- Tự bám theo năm tài chính đang chạy — sang FY27 có kế hoạch thì tự có, không
-- phải sửa lại view. (Muốn khoá cứng FY26 thì thay bằng
--  a.thang_ke_hoach between '2026-04' and '2027-03'.)
--
-- KHÔNG lọc ở hoa_don_actual: view đó là bản chuẩn hoá thô của hoá đơn, còn
-- dùng cho việc khác; chỗ cần cắt là "ngoài kế hoạch" của app sale.
-- Giữ nguyên tên + thứ tự cột (kể cả don_gia) → matview không phải drop.
-- ════════════════════════════════════════════════════════════════════════

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
        ), thang_ke_hoach_ref as (
         -- các tháng mà kế hoạch đang có dòng = phạm vi năm tài chính đang chạy
         select distinct s.thang_ke_hoach
           from shared.sale_target s
          where coalesce(btrim(s.thang_ke_hoach), ''::text) <> ''::text
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
  where a.thang_ke_hoach in (select thang_ke_hoach from thang_ke_hoach_ref)
    and not (exists ( select 1
           from shared.sale_target s
          where s.thang_ke_hoach = a.thang_ke_hoach
            and lower(btrim(coalesce(s.ps, ''::text))) = lower(btrim(coalesce(a.ps, ''::text)))
            and lower(btrim(coalesce(s.ma_khach_hang, ''::text))) = lower(btrim(coalesce(a.ma_khach_hang, ''::text)))
            and lower(btrim(coalesce(s.bo_vat_tu, ''::text))) = lower(btrim(coalesce(a.bo_vat_tu, ''::text)))
            and lower(btrim(coalesce(s.san_pham, ''::text))) = lower(btrim(coalesce(a.san_pham, ''::text)))));

grant select on app_sale.v_actual_ngoai_ke_hoach to service_role, anon, authenticated;
