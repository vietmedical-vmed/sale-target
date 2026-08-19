-- Cho phép admin sửa SL kế hoạch đầu năm + doanh thu KH đầu năm
-- qua RPC update_sale_target_cells (thêm 2 cột vào câu UPDATE).

DROP FUNCTION IF EXISTS public.update_sale_target_cells(jsonb, text, text, text, text[]);

CREATE OR REPLACE FUNCTION public.update_sale_target_cells(
  p_updates jsonb,
  p_bu      text,
  p_mien    text,
  p_ps      text,
  p_groups  text[]
)
RETURNS integer
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, shared, app_sale
AS $$
DECLARE
  v_req  integer;
  v_ok   integer;
  v_done integer;
BEGIN
  SELECT count(*), count(s.id)
    INTO v_req, v_ok
    FROM (
      SELECT (e->>'id')::bigint AS id
      FROM   jsonb_array_elements(coalesce(p_updates, '[]'::jsonb)) e
      WHERE  jsonb_typeof(e->'patch') = 'object'
    ) u
    LEFT JOIN sale_target s
           ON s.id = u.id
          AND (p_bu     IS NULL OR s.bu            =     p_bu)
          AND (p_mien   IS NULL OR s.mien          =     p_mien)
          AND (p_ps     IS NULL OR s.ps            =     p_ps)
          AND (p_groups IS NULL OR s.nhom_san_pham = ANY(p_groups));

  IF v_req = 0 THEN
    RETURN 0;
  END IF;

  IF v_ok <> v_req THEN
    RAISE EXCEPTION 'out_of_scope: % / % dòng nằm ngoài phạm vi quyền hoặc không còn tồn tại',
                    v_req - v_ok, v_req
      USING ERRCODE = '42501';
  END IF;

  WITH u AS (
    SELECT (e->>'id')::bigint AS id,
           e->'patch'         AS patch
    FROM   jsonb_array_elements(coalesce(p_updates, '[]'::jsonb)) e
    WHERE  jsonb_typeof(e->'patch') = 'object'
  )
  UPDATE sale_target s SET
    quota_thau_cu_con_lai = CASE WHEN u.patch ? 'quota_thau_cu_con_lai'
           THEN nullif(u.patch->>'quota_thau_cu_con_lai', '')::numeric
           ELSE s.quota_thau_cu_con_lai END,
    thang_thau_chinh      = CASE WHEN u.patch ? 'thang_thau_chinh'
           THEN u.patch->>'thang_thau_chinh'
           ELSE s.thang_thau_chinh END,
    thoi_gian_thau_chinh  = CASE WHEN u.patch ? 'thoi_gian_thau_chinh'
           THEN nullif(u.patch->>'thoi_gian_thau_chinh', '')::numeric
           ELSE s.thoi_gian_thau_chinh END,
    quota_thau_chinh      = CASE WHEN u.patch ? 'quota_thau_chinh'
           THEN nullif(u.patch->>'quota_thau_chinh', '')::numeric
           ELSE s.quota_thau_chinh END,
    thang_thau_bo_sung    = CASE WHEN u.patch ? 'thang_thau_bo_sung'
           THEN u.patch->>'thang_thau_bo_sung'
           ELSE s.thang_thau_bo_sung END,
    quota_bo_sung         = CASE WHEN u.patch ? 'quota_bo_sung'
           THEN nullif(u.patch->>'quota_bo_sung', '')::numeric
           ELSE s.quota_bo_sung END,
    sl_ke_hoach_update    = CASE WHEN u.patch ? 'sl_ke_hoach_update'
           THEN nullif(u.patch->>'sl_ke_hoach_update', '')::numeric
           ELSE s.sl_ke_hoach_update END,
    don_gia               = CASE WHEN u.patch ? 'don_gia'
           THEN nullif(u.patch->>'don_gia', '')::numeric
           ELSE s.don_gia END,
    giai_trinh            = CASE WHEN u.patch ? 'giai_trinh'
           THEN u.patch->>'giai_trinh'
           ELSE s.giai_trinh END,
    bo_vat_tu             = CASE WHEN u.patch ? 'bo_vat_tu'
           THEN u.patch->>'bo_vat_tu'
           ELSE s.bo_vat_tu END,
    san_pham              = CASE WHEN u.patch ? 'san_pham'
           THEN u.patch->>'san_pham'
           ELSE s.san_pham END,
    sl_ke_hoach_dau_nam   = CASE WHEN u.patch ? 'sl_ke_hoach_dau_nam'
           THEN nullif(u.patch->>'sl_ke_hoach_dau_nam', '')::numeric
           ELSE s.sl_ke_hoach_dau_nam END,
    doanh_thu_kh_dau_nam  = CASE WHEN u.patch ? 'doanh_thu_kh_dau_nam'
           THEN nullif(u.patch->>'doanh_thu_kh_dau_nam', '')::numeric
           ELSE s.doanh_thu_kh_dau_nam END
  FROM   u
  WHERE  s.id = u.id
    AND  (p_bu     IS NULL OR s.bu            =     p_bu)
    AND  (p_mien   IS NULL OR s.mien          =     p_mien)
    AND  (p_ps     IS NULL OR s.ps            =     p_ps)
    AND  (p_groups IS NULL OR s.nhom_san_pham = ANY(p_groups));

  GET DIAGNOSTICS v_done = ROW_COUNT;
  RETURN v_done;
END;
$$;

REVOKE ALL ON FUNCTION public.update_sale_target_cells(jsonb, text, text, text, text[]) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.update_sale_target_cells(jsonb, text, text, text, text[]) FROM anon, authenticated;
GRANT EXECUTE ON FUNCTION public.update_sale_target_cells(jsonb, text, text, text, text[]) TO service_role;
