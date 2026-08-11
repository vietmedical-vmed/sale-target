-- ════════════════════════════════════════════════════════════════════════
-- Phân loại LÝ DO của dòng thực hiện "ngoài kế hoạch"
--
-- Trước đây "ngoài kế hoạch" chỉ là "không khớp dòng kế hoạch nào" — người
-- dùng thấy số nhưng không biết vì sao và phải làm gì. Phân bổ thực tế trên
-- 938 dòng (đo tại app 2026-08-07):
--   43.6% chua_co_dia_ban       — (KH × nhóm) chưa có bản khai báo địa bàn
--   37.0% thieu_dong_ke_hoach   — địa bàn đúng PS, nhưng kế hoạch chưa có SP đó
--   12.3% sai_bo_vat_tu         — kế hoạch có SP nhưng khác bộ vật tư
--    4.7% sai_ps                — hoá đơn ghi PS khác PS địa bàn
--    2.4% ps_la                 — PS trong hoá đơn không có trong dm_ps
-- Hơn 80% rơi vào 2 nhóm sửa được bằng 1 click.
--
-- Chuẩn hoá bu về bu_code
-- hoa_don_actual đang lấy `d.bu` = tên BU đầy đủ ('CH&CS'/'CTTM & CTUT'/…),
-- không khớp sale_target.bu / dm_dia_ban.bu (là mã ngắn 'chcs'/'cttm'/'thnk')
-- → dòng CTTM & CTUT/THNS & CSVT trong v_actual_ngoai_ke_hoach hiện bị lệch bu
-- và không đối chiếu được với địa bàn. Sửa hoa_don_actual dùng bu_code.
--
-- Thêm cột vào v_actual_ngoai_ke_hoach (đặt cuối, KHÔNG đổi tên/thứ tự cột
-- cũ) để matview v_th_theo_ps/_sp không bị vỡ.
-- ════════════════════════════════════════════════════════════════════════

-- ── 1) hoa_don_actual: bu = bu_code (mã ngắn), tương thích sale_target ────
create or replace view app_sale.hoa_don_actual as
with base as (
  select h.thang                                       as thang_ke_hoach,
         coalesce(d.ps, h.ten_ps)                      as ps,
         h.ma_kh                                       as ma_khach_hang,
         h.bo_vat_tu,
         h.san_pham,
         h.so_luong,
         h.tong_gia_ban,
         d.area                                        as mien,
         -- KHÁC BẢN CŨ: bu_code (mã ngắn) thay cho bu (tên đầy đủ)
         coalesce(d.bu_code, nullif(btrim(h.bu), ''))  as bu,
         h.nhom_san_pham,
         h.ten_kh                                      as khach_hang
  from app_sale.hoa_don_bovattu h
  left join lateral (
    select ps, area, bu_code
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
       sum(tong_gia_ban)::numeric / nullif(sum(so_luong), 0)::numeric as don_gia
from base
group by thang_ke_hoach, ps, ma_khach_hang, bo_vat_tu, san_pham;

grant select on app_sale.hoa_don_actual to service_role, anon, authenticated;


-- ── 2) v_actual_ngoai_ke_hoach: thêm ly_do + ps_dia_ban ở CUỐI ────────────
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
         select distinct s.thang_ke_hoach
           from shared.sale_target s
          where coalesce(btrim(s.thang_ke_hoach), ''::text) <> ''::text
        ), base as (
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
              and lower(btrim(coalesce(s.san_pham, ''::text))) = lower(btrim(coalesce(a.san_pham, ''::text)))))
 )
 select b.*,
   -- ── LÝ DO — theo thứ tự ưu tiên, first match wins ─────────────────────
   -- ps_la:              hoá đơn có PS không có trong danh mục PS
   -- chua_co_dia_ban:    (bu, KH, nhóm) không có bản khai báo nào phủ tháng đó
   -- sai_ps:             có địa bàn, ps địa bàn ≠ ps hoá đơn
   -- sai_bo_vat_tu:      địa bàn khớp PS, kế hoạch có SP đó cho KH này ở tháng này
   --                     nhưng khác bo_vat_tu → hoặc hoá đơn ghi sai, hoặc thiếu bộ
   -- thieu_dong_ke_hoach: mọi thứ đúng, chỉ chưa có dòng kế hoạch cho SP đó
   case
     when not exists (select 1 from shared.dm_ps dp
                       where lower(btrim(dp.ps)) = lower(btrim(b.ps)))
       then 'ps_la'
     when not exists (select 1 from shared.dm_dia_ban d
                       where d.active
                         and d.bu = b.bu
                         and d.cust_key = coalesce(nullif(btrim(b.ma_khach_hang), ''), btrim(b.khach_hang))
                         and d.nhom_san_pham = b.nhom_san_pham
                         and d.tu_thang <= b.thang_ke_hoach
                         and (d.den_thang is null or d.den_thang >= b.thang_ke_hoach))
       then 'chua_co_dia_ban'
     when not exists (select 1 from shared.dm_dia_ban d
                       where d.active
                         and d.bu = b.bu
                         and d.cust_key = coalesce(nullif(btrim(b.ma_khach_hang), ''), btrim(b.khach_hang))
                         and d.nhom_san_pham = b.nhom_san_pham
                         and d.tu_thang <= b.thang_ke_hoach
                         and (d.den_thang is null or d.den_thang >= b.thang_ke_hoach)
                         and lower(btrim(d.ps)) = lower(btrim(b.ps)))
       then 'sai_ps'
     when exists (select 1 from shared.sale_target s
                   where s.thang_ke_hoach = b.thang_ke_hoach
                     and lower(btrim(coalesce(s.ma_khach_hang, ''))) = lower(btrim(coalesce(b.ma_khach_hang, '')))
                     and lower(btrim(coalesce(s.san_pham, '')))       = lower(btrim(coalesce(b.san_pham, ''))))
       then 'sai_bo_vat_tu'
     else 'thieu_dong_ke_hoach'
   end as ly_do,
   -- PS đang được khai báo cho tổ hợp đó tại tháng đó (để app hiện "PS đúng phải là …").
   (select d.ps from shared.dm_dia_ban d
     where d.active
       and d.bu = b.bu
       and d.cust_key = coalesce(nullif(btrim(b.ma_khach_hang), ''), btrim(b.khach_hang))
       and d.nhom_san_pham = b.nhom_san_pham
       and d.tu_thang <= b.thang_ke_hoach
       and (d.den_thang is null or d.den_thang >= b.thang_ke_hoach)
     limit 1) as ps_dia_ban
 from base b;

grant select on app_sale.v_actual_ngoai_ke_hoach to service_role, anon, authenticated;

comment on view app_sale.v_actual_ngoai_ke_hoach is
  'Dòng thực hiện không khớp dòng kế hoạch, kèm ly_do (ps_la / chua_co_dia_ban / sai_ps / sai_bo_vat_tu / thieu_dong_ke_hoach) và ps_dia_ban để app biết hành động sửa nào là phù hợp.';
