-- ════════════════════════════════════════════════════════════════════════
-- LUỒNG SL THỰC HIỆN MỚI — nguồn app_sale.hoa_don_bovattu (song song, KHÔNG
-- đụng sv_bovattu_actual để app_order vẫn dùng bảng cũ như cũ).
--
-- Chuỗi: hoa_don_bovattu ──(view hoa_don_actual: chuẩn hoá ten_ps→ps + gộp 5 khoá)──►
--        map_hoadon_to_sale_target() ──► shared.sale_target.sl_thuc_hien
--        v_actual_ngoai_ke_hoach / v_actual_unmatched đọc hoa_don_actual (khớp số).
--
-- GIỮ NGUYÊN: app_sale.sv_bovattu_actual, public.map_actual_to_sale_target().
-- Pipeline app sale từ nay gọi map_hoadon_to_sale_target() thay cho map_actual…().
--
-- Phụ thuộc: đã seed shared.dm_ps (migration 20260807100000_seed_dm_ps.sql).
--
-- CHUẨN HOÁ KHOÁ: lower + btrim + GỘP KHOẢNG TRẮNG (regexp_replace ...'\s+' ' ').
--   Gộp khoảng trắng bắt các ca lệch cách viết kiểu "Gối thay lại␣␣- UOC" (2 dấu
--   cách). Đo trên DB: chỉ cứu thêm ~9 khoá — phần trượt còn lại là OOP thật
--   (dịch vụ / vật tư riêng lẻ / KH không lập KH theo tháng), KHÔNG dịch được.
--   2 index biểu thức *_ws bên dưới để join này vẫn nhanh (getData đọc OOP liên tục).
-- ════════════════════════════════════════════════════════════════════════


-- ── 0) Index biểu thức khớp CHUẨN HOÁ MỚI (gộp khoảng trắng) ───────────────
--    _ws_oop: bản coalesce (dùng cho v_actual_ngoai_ke_hoach).
--    _ws_map: bản không coalesce (dùng cho map + v_actual_unmatched).
create index if not exists idx_sale_target_oopkey_ws
  on shared.sale_target (
    thang_ke_hoach,
    regexp_replace(lower(btrim(coalesce(ps,            ''))), '\s+', ' ', 'g'),
    regexp_replace(lower(btrim(coalesce(ma_khach_hang, ''))), '\s+', ' ', 'g'),
    regexp_replace(lower(btrim(coalesce(bo_vat_tu,     ''))), '\s+', ' ', 'g'),
    regexp_replace(lower(btrim(coalesce(san_pham,      ''))), '\s+', ' ', 'g')
  );

create index if not exists idx_sale_target_mapkey_ws
  on shared.sale_target (
    thang_ke_hoach,
    regexp_replace(lower(btrim(ps)),            '\s+', ' ', 'g'),
    regexp_replace(lower(btrim(ma_khach_hang)), '\s+', ' ', 'g'),
    regexp_replace(lower(btrim(bo_vat_tu)),     '\s+', ' ', 'g'),
    regexp_replace(lower(btrim(san_pham)),      '\s+', ' ', 'g')
  );

analyze shared.sale_target;


-- ── 1) VIEW chuẩn hoá: hoa_don_bovattu → cùng bộ cột như sv_bovattu_actual ──
--    - ten_ps (đầy đủ) → ps (rút gọn) qua shared.dm_ps; area → mien.
--    - LATERAL limit 1 (ưu tiên Active): phòng khi dm_ps có ten_ps trùng, không nhân dòng.
--    - PS lạ (không có trong dm_ps): giữ nguyên ten_ps (coalesce) → rơi sang "ngoài
--      kế hoạch" thay vì mất số.
--    - Gộp về đúng 5 khoá (thang, ps, ma_kh, bo_vat_tu, san_pham); cột hiển thị
--      (mien/khach_hang/bu/nhom) lấy max trong nhóm.
--    - sl_thuc_hien = sum(so_luong): GIỮ NGUYÊN, không lọc (kể cả SL âm/nghi_van).
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
    where regexp_replace(lower(btrim(ten_ps)), '\s+', ' ', 'g')
        = regexp_replace(lower(btrim(h.ten_ps)), '\s+', ' ', 'g')
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
       sum(tong_gia_ban)  as doanh_thu_thuc_hien   -- thành tiền thực từ hoá đơn
from base
group by thang_ke_hoach, ps, ma_khach_hang, bo_vat_tu, san_pham;

grant select on app_sale.hoa_don_actual to service_role, anon, authenticated;


-- ── 2) MAP mới: hoa_don_actual → sale_target.sl_thuc_hien ──────────────────
--    Bản sao logic map_actual_to_sale_target() nhưng đọc hoa_don_actual +
--    chuẩn hoá khoá có gộp khoảng trắng (khớp idx_sale_target_mapkey_ws).
create or replace function public.map_hoadon_to_sale_target()
returns jsonb
language plpgsql
security definer
set search_path to 'public', 'shared', 'app_sale'
as $function$
declare
  v_months  text[];
  v_zeroed  int := 0;
  v_set     int := 0;
  v_matched int := 0;
  v_total   int := 0;
begin
  select array_agg(distinct thang_ke_hoach) into v_months from hoa_don_actual;
  if v_months is null then
    return jsonb_build_object('months', 0, 'zeroed', 0, 'set_rows', 0,
                              'matched_keys', 0, 'total_keys', 0, 'unmatched_keys', 0);
  end if;

  -- (1) Zero các tháng CÓ trong hoa_don. LƯU Ý: tháng không có trong hoa_don
  --     (vd 2026-07) sẽ KHÔNG bị zero — số cũ trong sale_target còn nguyên.
  update sale_target set sl_thuc_hien = 0
   where thang_ke_hoach = any(v_months)
     and sl_thuc_hien is distinct from 0;
  get diagnostics v_zeroed = row_count;

  -- (2) Gộp theo khoá chuẩn hoá (gộp khoảng trắng) + tìm dòng plan id nhỏ nhất
  create temp table _agg on commit drop as
  with a as (
    select thang_ke_hoach,
           regexp_replace(lower(btrim(ps)),            '\s+', ' ', 'g') as ps_n,
           regexp_replace(lower(btrim(ma_khach_hang)), '\s+', ' ', 'g') as kh_n,
           regexp_replace(lower(btrim(bo_vat_tu)),     '\s+', ' ', 'g') as bo_n,
           regexp_replace(lower(btrim(san_pham)),      '\s+', ' ', 'g') as sp_n,
           sum(sl_thuc_hien)                                            as sl
      from hoa_don_actual
     group by 1, 2, 3, 4, 5
  )
  select a.*, t.id as target_id
    from a
    left join lateral (
      select s.id from sale_target s
       where s.thang_ke_hoach = a.thang_ke_hoach
         and regexp_replace(lower(btrim(s.ps)),            '\s+', ' ', 'g') = a.ps_n
         and regexp_replace(lower(btrim(s.ma_khach_hang)), '\s+', ' ', 'g') = a.kh_n
         and regexp_replace(lower(btrim(s.bo_vat_tu)),     '\s+', ' ', 'g') = a.bo_n
         and regexp_replace(lower(btrim(s.san_pham)),      '\s+', ' ', 'g') = a.sp_n
       order by s.id
       limit 1
    ) t on true;

  -- (3) Ghi SL vào dòng khớp
  update sale_target s
     set sl_thuc_hien = a.sl
    from _agg a
   where a.target_id = s.id;
  get diagnostics v_set = row_count;

  select count(*), count(*) filter (where target_id is not null)
    into v_total, v_matched
    from _agg;

  return jsonb_build_object(
    'months',         array_length(v_months, 1),
    'zeroed',         v_zeroed,
    'set_rows',       v_set,
    'matched_keys',   v_matched,
    'total_keys',     v_total,
    'unmatched_keys', v_total - v_matched
  );
end;
$function$;

grant execute on function public.map_hoadon_to_sale_target() to service_role;


-- ── 3) Trỏ 2 view OOP/unmatched sang hoa_don_actual (+ khoá gộp khoảng trắng) ──
--    Giữ NGUYÊN tên/thứ tự cột → v_th_theo_ps/sp (matview) không phải drop.
--    NOT EXISTS dùng chuẩn hoá gộp khoảng trắng, ĐỒNG BỘ với map ở trên
--    (để dòng đã map không lọt vào OOP và ngược lại).
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
    -- Đơn giá đại diện (bình quân gia quyền) để app tính DThu = SL × đơn giá
    -- khớp đúng thành tiền hoá đơn. NULL khi SL = 0 (tránh chia 0).
    (a.doanh_thu_thuc_hien / nullif(a.sl_thuc_hien, 0)) as don_gia
   from app_sale.hoa_don_actual a
     left join ps_ref p on p.ps_n = lower(btrim(a.ps))
     left join bu_ref b on b.bu_n = regexp_replace(lower(btrim(a.bu)), '[^a-z0-9]'::text, ''::text, 'g'::text)
     left join sp_ref g on g.sp_n = lower(btrim(a.san_pham))
  where not (exists ( select 1
           from shared.sale_target s
          where s.thang_ke_hoach = a.thang_ke_hoach
            and regexp_replace(lower(btrim(coalesce(s.ps, ''::text))), '\s+', ' ', 'g') = regexp_replace(lower(btrim(coalesce(a.ps, ''::text))), '\s+', ' ', 'g')
            and regexp_replace(lower(btrim(coalesce(s.ma_khach_hang, ''::text))), '\s+', ' ', 'g') = regexp_replace(lower(btrim(coalesce(a.ma_khach_hang, ''::text))), '\s+', ' ', 'g')
            and regexp_replace(lower(btrim(coalesce(s.bo_vat_tu, ''::text))), '\s+', ' ', 'g') = regexp_replace(lower(btrim(coalesce(a.bo_vat_tu, ''::text))), '\s+', ' ', 'g')
            and regexp_replace(lower(btrim(coalesce(s.san_pham, ''::text))), '\s+', ' ', 'g') = regexp_replace(lower(btrim(coalesce(a.san_pham, ''::text))), '\s+', ' ', 'g')));

grant select on app_sale.v_actual_ngoai_ke_hoach to service_role, anon, authenticated;

create or replace view app_sale.v_actual_unmatched as
 select thang_ke_hoach, mien, ps, ma_khach_hang, khach_hang, bo_vat_tu, san_pham,
    sum(sl_thuc_hien) as sl_thuc_hien
   from app_sale.hoa_don_actual a
  where not (exists ( select 1
           from shared.sale_target s
          where s.thang_ke_hoach = a.thang_ke_hoach
            and regexp_replace(lower(btrim(s.ps)),            '\s+', ' ', 'g') = regexp_replace(lower(btrim(a.ps)),            '\s+', ' ', 'g')
            and regexp_replace(lower(btrim(s.ma_khach_hang)), '\s+', ' ', 'g') = regexp_replace(lower(btrim(a.ma_khach_hang)), '\s+', ' ', 'g')
            and regexp_replace(lower(btrim(s.bo_vat_tu)),     '\s+', ' ', 'g') = regexp_replace(lower(btrim(a.bo_vat_tu)),     '\s+', ' ', 'g')
            and regexp_replace(lower(btrim(s.san_pham)),      '\s+', ' ', 'g') = regexp_replace(lower(btrim(a.san_pham)),      '\s+', ' ', 'g')))
  group by thang_ke_hoach, mien, ps, ma_khach_hang, khach_hang, bo_vat_tu, san_pham
  order by (sum(sl_thuc_hien)) desc;

grant select on app_sale.v_actual_unmatched to service_role;
