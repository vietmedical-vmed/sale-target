-- ════════════════════════════════════════════════════════════════════════
-- Phase 3 (hiệu năng, bản nhanh)
--
-- 1) classify_oop_sale_target chỉ phân loại dòng OOP của năm tài chính đang chạy
--    (FY của app_config.current_month). 5.805/6.406 dòng OOP là FY25, app không còn tải
--    (edge lọc 12 tháng kế hoạch). Đo 07/11 khi cache ấm: 133 ms → 10 ms; cache nguội
--    trước đây ~1–7 s mỗi lần getData. Sang FY mới chỉ cần đổi current_month.
--    CREATE OR REPLACE giữ nguyên chữ ký + quyền.
-- 2) Bỏ idx_sale_target_oopkey_ws: 0 lần dùng (pg_stat_user_indexes), 8 MB, không hàm nào
--    dùng biểu thức này; mỗi lần ghi sale_target (đồng bộ thực hiện cập nhật hàng nghìn
--    dòng) phải cập nhật thêm index này. idx_sale_target_mapkey_ws (đang dùng) giữ nguyên.
--
-- Hoàn tác: supabase/rollbacks/20261107140000_phase3_classify_fy_bo_index_ROLLBACK.sql
-- ════════════════════════════════════════════════════════════════════════

CREATE OR REPLACE FUNCTION public.classify_oop_sale_target(p_bu text DEFAULT NULL::text, p_mien text DEFAULT NULL::text, p_ps text DEFAULT NULL::text, p_groups text[] DEFAULT NULL::text[])
 RETURNS TABLE(target_id bigint, ly_do text, ps_dia_ban text)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'shared', 'app_sale'
AS $function$
  SELECT s.id AS target_id,
    CASE
      WHEN NOT EXISTS (SELECT 1 FROM shared.dm_ps dp WHERE lower(btrim(dp.ps)) = lower(btrim(s.ps))) THEN 'ps_la'
      WHEN NOT EXISTS (SELECT 1 FROM shared.dm_dia_ban d WHERE d.active AND d.bu = s.bu AND d.cust_key = coalesce(nullif(btrim(s.ma_khach_hang), ''), btrim(s.khach_hang)) AND d.nhom_san_pham = s.nhom_san_pham AND d.tu_thang <= s.thang_ke_hoach AND (d.den_thang IS NULL OR d.den_thang >= s.thang_ke_hoach)) THEN 'chua_co_dia_ban'
      WHEN NOT EXISTS (SELECT 1 FROM shared.dm_dia_ban d WHERE d.active AND d.bu = s.bu AND d.cust_key = coalesce(nullif(btrim(s.ma_khach_hang), ''), btrim(s.khach_hang)) AND d.nhom_san_pham = s.nhom_san_pham AND d.tu_thang <= s.thang_ke_hoach AND (d.den_thang IS NULL OR d.den_thang >= s.thang_ke_hoach) AND lower(btrim(d.ps)) = lower(btrim(s.ps))) THEN 'sai_ps'
      WHEN EXISTS (SELECT 1 FROM shared.sale_target s2 WHERE s2.ngoai_ke_hoach IS NOT TRUE AND s2.thang_ke_hoach = s.thang_ke_hoach AND lower(btrim(coalesce(s2.ma_khach_hang, ''))) = lower(btrim(coalesce(s.ma_khach_hang, ''))) AND lower(btrim(coalesce(s2.san_pham, ''))) = lower(btrim(coalesce(s.san_pham, '')))) THEN 'sai_bo_vat_tu'
      ELSE 'thieu_dong_ke_hoach'
    END AS ly_do,
    (SELECT d.ps FROM shared.dm_dia_ban d WHERE d.active AND d.bu = s.bu AND d.cust_key = coalesce(nullif(btrim(s.ma_khach_hang), ''), btrim(s.khach_hang)) AND d.nhom_san_pham = s.nhom_san_pham AND d.tu_thang <= s.thang_ke_hoach AND (d.den_thang IS NULL OR d.den_thang >= s.thang_ke_hoach) LIMIT 1) AS ps_dia_ban
  FROM shared.sale_target s
  WHERE s.ngoai_ke_hoach = true
    AND (p_bu IS NULL OR s.bu = p_bu)
    AND (shared.mien_in(s.mien, p_mien))
    AND (p_ps IS NULL OR s.ps = p_ps)
    AND (p_groups IS NULL OR s.nhom_san_pham = ANY(p_groups))
    -- Chỉ năm tài chính đang chạy (theo app_config.current_month): dòng OOP năm trước
    -- không còn hiện ở app, phân loại chúng chỉ tốn thời gian (~90% số dòng OOP).
    AND s.nam_tai_chinh = public.fy_from_thang(
      (SELECT c.value #>> '{}' FROM shared.app_config c WHERE c.key = 'current_month'));
$function$;

DROP INDEX IF EXISTS shared.idx_sale_target_oopkey_ws;

DO $$
BEGIN
  IF has_function_privilege('anon', 'public.classify_oop_sale_target(text,text,text,text[])', 'EXECUTE')
     OR has_function_privilege('anon', 'public.classify_oop_sale_target_json(text,text,text,text[])', 'EXECUTE') THEN
    RAISE EXCEPTION 'classify_mo_cho_anon';
  END IF;
  IF public.fy_from_thang((SELECT c.value #>> '{}' FROM shared.app_config c WHERE c.key = 'current_month')) IS NULL THEN
    RAISE EXCEPTION 'current_month_khong_hop_le';
  END IF;
END $$;
