-- HOÀN TÁC 20261107140000_phase3_classify_fy_bo_index.sql: classify phân loại mọi năm,
-- dựng lại idx_sale_target_oopkey_ws. Chạy tay qua SQL Editor; KHÔNG để file này trong
-- supabase/migrations/.

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
    AND (p_groups IS NULL OR s.nhom_san_pham = ANY(p_groups));
$function$;

CREATE INDEX IF NOT EXISTS idx_sale_target_oopkey_ws ON shared.sale_target USING btree (thang_ke_hoach, regexp_replace(lower(btrim(COALESCE(ps, ''::text))), '\s+'::text, ' '::text, 'g'::text), regexp_replace(lower(btrim(COALESCE(ma_khach_hang, ''::text))), '\s+'::text, ' '::text, 'g'::text), regexp_replace(lower(btrim(COALESCE(bo_vat_tu, ''::text))), '\s+'::text, ' '::text, 'g'::text), regexp_replace(lower(btrim(COALESCE(san_pham, ''::text))), '\s+'::text, ' '::text, 'g'::text));
