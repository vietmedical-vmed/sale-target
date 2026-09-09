-- ════════════════════════════════════════════════════════════════════════
-- Phân loại lý do cho dòng OOP trong sale_target
--
-- Khi map function insert dòng thực hiện ngoài kế hoạch vào sale_target
-- (ngoai_ke_hoach = true), view v_actual_ngoai_ke_hoach trả 0 dòng (vì
-- NOT EXISTS tìm thấy chính dòng OOP đó). Thay vì sửa view, tạo RPC
-- function phân loại trực tiếp trên sale_target — cùng logic CASE như
-- view cũ, nhưng đọc từ sale_target thay vì hoa_don_actual.
--
-- Edge function gọi rpc('classify_oop_sale_target') rồi match theo id.
-- ════════════════════════════════════════════════════════════════════════

create or replace function public.classify_oop_sale_target()
returns table (target_id bigint, ly_do text, ps_dia_ban text)
language sql stable security definer
set search_path to 'public', 'shared', 'app_sale'
as $$
  select s.id as target_id,
    case
      -- ps_la: PS trong dòng OOP không có trong danh mục PS
      when not exists (
        select 1 from shared.dm_ps dp
        where lower(btrim(dp.ps)) = lower(btrim(s.ps))
      ) then 'ps_la'

      -- chua_co_dia_ban: không có bản khai báo địa bàn phủ tháng đó
      when not exists (
        select 1 from shared.dm_dia_ban d
        where d.active
          and d.bu = s.bu
          and d.cust_key = coalesce(nullif(btrim(s.ma_khach_hang), ''), btrim(s.khach_hang))
          and d.nhom_san_pham = s.nhom_san_pham
          and d.tu_thang <= s.thang_ke_hoach
          and (d.den_thang is null or d.den_thang >= s.thang_ke_hoach)
      ) then 'chua_co_dia_ban'

      -- sai_ps: có địa bàn nhưng PS địa bàn khác PS trong dòng OOP
      when not exists (
        select 1 from shared.dm_dia_ban d
        where d.active
          and d.bu = s.bu
          and d.cust_key = coalesce(nullif(btrim(s.ma_khach_hang), ''), btrim(s.khach_hang))
          and d.nhom_san_pham = s.nhom_san_pham
          and d.tu_thang <= s.thang_ke_hoach
          and (d.den_thang is null or d.den_thang >= s.thang_ke_hoach)
          and lower(btrim(d.ps)) = lower(btrim(s.ps))
      ) then 'sai_ps'

      -- sai_bo_vat_tu: có dòng kế hoạch cho (tháng, KH, SP) nhưng khác bộ vật tư
      when exists (
        select 1 from shared.sale_target s2
        where s2.ngoai_ke_hoach is not true
          and s2.thang_ke_hoach = s.thang_ke_hoach
          and lower(btrim(coalesce(s2.ma_khach_hang, ''))) = lower(btrim(coalesce(s.ma_khach_hang, '')))
          and lower(btrim(coalesce(s2.san_pham, ''))) = lower(btrim(coalesce(s.san_pham, '')))
      ) then 'sai_bo_vat_tu'

      else 'thieu_dong_ke_hoach'
    end as ly_do,

    -- PS đúng theo địa bàn (cho action "Sửa PS")
    (select d.ps from shared.dm_dia_ban d
      where d.active
        and d.bu = s.bu
        and d.cust_key = coalesce(nullif(btrim(s.ma_khach_hang), ''), btrim(s.khach_hang))
        and d.nhom_san_pham = s.nhom_san_pham
        and d.tu_thang <= s.thang_ke_hoach
        and (d.den_thang is null or d.den_thang >= s.thang_ke_hoach)
      limit 1
    ) as ps_dia_ban

  from shared.sale_target s
  where s.ngoai_ke_hoach = true;
$$;

revoke all on function public.classify_oop_sale_target() from public, anon, authenticated;
grant execute on function public.classify_oop_sale_target() to service_role;

comment on function public.classify_oop_sale_target() is
  'Phân loại lý do (ps_la / chua_co_dia_ban / sai_ps / sai_bo_vat_tu / thieu_dong_ke_hoach) cho dòng OOP trong sale_target. Edge function gọi rồi match theo target_id = sale_target.id.';
