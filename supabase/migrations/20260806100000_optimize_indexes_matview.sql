-- ════════════════════════════════════════════════════════════════════════
-- TỐI ƯU TRUY VẤN — Index biểu thức + Materialized view
--
-- Căn cứ: điểm nóng là view app_sale.v_actual_ngoai_ke_hoach (đọc mỗi lần
-- getData). Nó chạy NOT EXISTS với lower(btrim(coalesce(...))) trên 5 cột của
-- shared.sale_target (~25k dòng) cho từng dòng sv_bovattu_actual (~2k) →
-- index THƯỜNG vô dụng (vì có hàm bọc quanh cột). Cần INDEX BIỂU THỨC khớp
-- đúng biểu thức trong truy vấn.
--
-- 2 PHẦN chạy độc lập được:
--   PHẦN 1 — Index biểu thức (an toàn tuyệt đối, chỉ thêm, real-time, KHÔNG đổi
--            hành vi). ĐÂY LÀ TỐI ƯU CHÍNH cho app + pipeline.
--   PHẦN 2 — Materialized view cho 2 báo cáo v_th_theo_ps/sp (app KHÔNG đọc;
--            phục vụ BI/Export). Có đánh đổi "mới tới lần refresh gần nhất".
-- ════════════════════════════════════════════════════════════════════════


-- ════════════════════════════════════════════════════════════════════════
-- PHẦN 1 — INDEX BIỂU THỨC  (chạy phần này trước; đủ để app nhanh hẳn)
-- ════════════════════════════════════════════════════════════════════════

-- 1a) Khớp v_actual_ngoai_ke_hoach (dùng COALESCE) — ĐIỂM NÓNG của app.
--     Biểu thức PHẢI trùng khít mới được optimizer dùng.
create index if not exists idx_sale_target_oopkey
  on shared.sale_target (
    thang_ke_hoach,
    lower(btrim(coalesce(ps,            ''))),
    lower(btrim(coalesce(ma_khach_hang, ''))),
    lower(btrim(coalesce(bo_vat_tu,     ''))),
    lower(btrim(coalesce(san_pham,      '')))
  );

-- 1b) Khớp map_actual_to_sale_target() + v_actual_unmatched (KHÔNG coalesce) —
--     tăng tốc pipeline map actual → sale_target.
create index if not exists idx_sale_target_mapkey
  on shared.sale_target (
    thang_ke_hoach,
    lower(btrim(ps)),
    lower(btrim(ma_khach_hang)),
    lower(btrim(bo_vat_tu)),
    lower(btrim(san_pham))
  );

analyze shared.sale_target;

-- Kiểm chứng (chạy riêng, nên thấy "Index Scan using idx_sale_target_oopkey"):
--   explain analyze select count(*) from app_sale.v_actual_ngoai_ke_hoach;


-- ════════════════════════════════════════════════════════════════════════
-- PHẦN 2 — MATERIALIZED VIEW cho báo cáo tổng hợp (tuỳ chọn, cho BI/Export)
--
-- LƯU Ý: app KHÔNG đọc v_th_theo_ps/sp (tab Tổng hợp dựng client-side). Phần
-- này chỉ có ích nếu bạn query 2 view đó từ BI/Export/SQL. Matview = nhanh
-- nhưng dữ liệu "đóng băng" tới lần refresh (khác view thường luôn real-time).
--
-- Refresh: gọi public.refresh_bao_cao_sale() — pipeline đã được nối để gọi sau
-- khi nạp actual (xem sv_bo_vat_tu_pipeline.py). Sửa kế hoạch (updateCells) KHÔNG
-- tự refresh → nếu cần báo cáo tức thời sau khi sửa tay thì gọi refresh thủ công.
--
-- ĐỔI HÀNH VI: view cũ có security_invoker=on (áp RLS người gọi); matview chạy
-- theo owner, KHÔNG áp RLS người gọi. Vì app dùng service_role + tự lọc phạm vi
-- ở edge function nên không ảnh hưởng; chỉ lưu ý nếu có ai đọc trực tiếp bằng
-- anon/authenticated.
-- ════════════════════════════════════════════════════════════════════════

-- 2a) Tổng hợp theo PS
drop view if exists app_sale.v_th_theo_ps;
create materialized view app_sale.v_th_theo_ps as
  select s.thang_ke_hoach, s.mien, s.ps, s.ma_khach_hang, s.khach_hang,
         sum(s.sl_ke_hoach_dau_nam) as sl_ke_hoach_dau_nam,
         sum(s.sl_ke_hoach_update)  as sl_ke_hoach_update,
         sum(s.doanh_thu_kh_update) as doanh_thu_ke_hoach,
         sum(s.sl_thuc_hien)        as sl_thuc_hien,
         false as la_ngoai_ke_hoach, 0 as thu_tu
  from shared.sale_target s
  group by s.thang_ke_hoach, s.mien, s.ps, s.ma_khach_hang, s.khach_hang
  union all
  select o.thang_ke_hoach, o.mien, o.ps, null::text, 'Ngoài kế hoạch'::text,
         null::numeric, null::numeric, null::numeric,
         sum(o.sl_thuc_hien), true, 1
  from app_sale.v_actual_ngoai_ke_hoach o
  group by o.thang_ke_hoach, o.mien, o.ps;
grant select on app_sale.v_th_theo_ps to anon, authenticated, service_role;

-- 2b) Tổng hợp theo SP
drop view if exists app_sale.v_th_theo_sp;
create materialized view app_sale.v_th_theo_sp as
  select s.thang_ke_hoach, s.bu, s.nhom_san_pham, s.bo_vat_tu, s.san_pham,
         s.ma_khach_hang, s.khach_hang,
         sum(s.sl_ke_hoach_dau_nam) as sl_ke_hoach_dau_nam,
         sum(s.sl_ke_hoach_update)  as sl_ke_hoach_update,
         sum(s.doanh_thu_kh_update) as doanh_thu_ke_hoach,
         sum(s.sl_thuc_hien)        as sl_thuc_hien,
         false as la_ngoai_ke_hoach, 0 as thu_tu
  from shared.sale_target s
  group by s.thang_ke_hoach, s.bu, s.nhom_san_pham, s.bo_vat_tu, s.san_pham,
           s.ma_khach_hang, s.khach_hang
  union all
  select o.thang_ke_hoach, o.bu, o.nhom_san_pham, o.bo_vat_tu, o.san_pham,
         null::text, 'Ngoài kế hoạch'::text,
         null::numeric, null::numeric, null::numeric,
         sum(o.sl_thuc_hien), true, 1
  from app_sale.v_actual_ngoai_ke_hoach o
  group by o.thang_ke_hoach, o.bu, o.nhom_san_pham, o.bo_vat_tu, o.san_pham;
grant select on app_sale.v_th_theo_sp to anon, authenticated, service_role;

-- 2c) Index lọc theo tháng trên matview (report hay lọc thang_ke_hoach)
create index if not exists idx_mv_th_ps_thang on app_sale.v_th_theo_ps (thang_ke_hoach);
create index if not exists idx_mv_th_sp_thang on app_sale.v_th_theo_sp (thang_ke_hoach);

-- 2d) RPC refresh (ở public theo nguyên tắc — pipeline gọi .rpc("refresh_bao_cao_sale"))
create or replace function public.refresh_bao_cao_sale()
returns void
language plpgsql
security definer
set search_path = public, shared, app_sale
as $$
begin
  refresh materialized view app_sale.v_th_theo_ps;
  refresh materialized view app_sale.v_th_theo_sp;
end;
$$;
grant execute on function public.refresh_bao_cao_sale() to service_role;
