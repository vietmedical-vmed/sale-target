-- GĐ 2.4b: classify_oop_sale_target nhận tham số phạm vi.
-- Trước đây quét toàn bộ dòng OOP; giờ chỉ phân loại dòng trong scope user.
-- ============================================================================

-- Xoá bản cũ không tham số
DROP FUNCTION IF EXISTS public.classify_oop_sale_target();

CREATE OR REPLACE FUNCTION public.classify_oop_sale_target(
  p_bu     text    DEFAULT NULL,
  p_mien   text    DEFAULT NULL,
  p_ps     text    DEFAULT NULL,
  p_groups text[]  DEFAULT NULL
)
RETURNS TABLE (target_id bigint, ly_do text, ps_dia_ban text)
LANGUAGE sql STABLE SECURITY DEFINER
SET search_path TO 'public', 'shared', 'app_sale'
AS $$
  SELECT s.id AS target_id,
    CASE
      WHEN NOT EXISTS (
        SELECT 1 FROM shared.dm_ps dp
        WHERE lower(btrim(dp.ps)) = lower(btrim(s.ps))
      ) THEN 'ps_la'

      WHEN NOT EXISTS (
        SELECT 1 FROM shared.dm_dia_ban d
        WHERE d.active
          AND d.bu = s.bu
          AND d.cust_key = coalesce(nullif(btrim(s.ma_khach_hang), ''), btrim(s.khach_hang))
          AND d.nhom_san_pham = s.nhom_san_pham
          AND d.tu_thang <= s.thang_ke_hoach
          AND (d.den_thang IS NULL OR d.den_thang >= s.thang_ke_hoach)
      ) THEN 'chua_co_dia_ban'

      WHEN NOT EXISTS (
        SELECT 1 FROM shared.dm_dia_ban d
        WHERE d.active
          AND d.bu = s.bu
          AND d.cust_key = coalesce(nullif(btrim(s.ma_khach_hang), ''), btrim(s.khach_hang))
          AND d.nhom_san_pham = s.nhom_san_pham
          AND d.tu_thang <= s.thang_ke_hoach
          AND (d.den_thang IS NULL OR d.den_thang >= s.thang_ke_hoach)
          AND lower(btrim(d.ps)) = lower(btrim(s.ps))
      ) THEN 'sai_ps'

      WHEN EXISTS (
        SELECT 1 FROM shared.sale_target s2
        WHERE s2.ngoai_ke_hoach IS NOT TRUE
          AND s2.thang_ke_hoach = s.thang_ke_hoach
          AND lower(btrim(coalesce(s2.ma_khach_hang, ''))) = lower(btrim(coalesce(s.ma_khach_hang, '')))
          AND lower(btrim(coalesce(s2.san_pham, ''))) = lower(btrim(coalesce(s.san_pham, '')))
      ) THEN 'sai_bo_vat_tu'

      ELSE 'thieu_dong_ke_hoach'
    END AS ly_do,

    (SELECT d.ps FROM shared.dm_dia_ban d
      WHERE d.active
        AND d.bu = s.bu
        AND d.cust_key = coalesce(nullif(btrim(s.ma_khach_hang), ''), btrim(s.khach_hang))
        AND d.nhom_san_pham = s.nhom_san_pham
        AND d.tu_thang <= s.thang_ke_hoach
        AND (d.den_thang IS NULL OR d.den_thang >= s.thang_ke_hoach)
      LIMIT 1
    ) AS ps_dia_ban

  FROM shared.sale_target s
  WHERE s.ngoai_ke_hoach = true
    AND (p_bu IS NULL OR s.bu = p_bu)
    AND (p_mien IS NULL OR s.mien = p_mien)
    AND (p_ps IS NULL OR s.ps = p_ps)
    AND (p_groups IS NULL OR s.nhom_san_pham = ANY(p_groups));
$$;

REVOKE ALL ON FUNCTION public.classify_oop_sale_target(text, text, text, text[])
  FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.classify_oop_sale_target(text, text, text, text[])
  TO service_role;

COMMENT ON FUNCTION public.classify_oop_sale_target(text, text, text, text[]) IS
  'Phân loại lý do OOP trong sale_target, lọc theo phạm vi (bu/mien/ps/groups). Params NULL = không lọc.';
