-- GĐ 2.2: Optimistic locking per row
-- update_sale_target_cells now checks _rev per row.
-- Rows with matching _rev are updated; mismatched rows are returned as conflicts.
-- Return type: jsonb {updated, conflicts: [{id, _rev, values}]}

DROP FUNCTION IF EXISTS public.update_sale_target_cells(jsonb, text, text, text, text[]);

CREATE OR REPLACE FUNCTION public.update_sale_target_cells(
  p_updates jsonb,
  p_bu text,
  p_mien text,
  p_ps text,
  p_groups text[]
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'shared', 'app_sale'
AS $$
DECLARE
  v_req        integer;
  v_ok         integer;
  v_done       integer;
  v_conflicts  jsonb;
BEGIN
  -- 1) Scope check
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
    RETURN jsonb_build_object('updated', 0, 'conflicts', '[]'::jsonb);
  END IF;

  IF v_ok <> v_req THEN
    RAISE EXCEPTION 'out_of_scope: % / % dòng nằm ngoài phạm vi quyền hoặc không còn tồn tại',
                    v_req - v_ok, v_req
      USING ERRCODE = '42501';
  END IF;

  -- 2) Collect conflicts: rows where client _rev doesn't match server _rev
  SELECT coalesce(jsonb_agg(jsonb_build_object(
    'id', s.id,
    '_rev', s._rev,
    'values', jsonb_build_object(
      'quota_thau_cu_con_lai', s.quota_thau_cu_con_lai,
      'thang_thau_chinh',      s.thang_thau_chinh,
      'thoi_gian_thau_chinh',  s.thoi_gian_thau_chinh,
      'quota_thau_chinh',      s.quota_thau_chinh,
      'thang_thau_bo_sung',    s.thang_thau_bo_sung,
      'quota_bo_sung',         s.quota_bo_sung,
      'sl_ke_hoach_update',    s.sl_ke_hoach_update,
      'don_gia',               s.don_gia,
      'bo_vat_tu',             s.bo_vat_tu,
      'san_pham',              s.san_pham,
      'sl_ke_hoach_dau_nam',   s.sl_ke_hoach_dau_nam,
      'doanh_thu_kh_dau_nam',  s.doanh_thu_kh_dau_nam
    )
  )), '[]'::jsonb)
  INTO v_conflicts
  FROM (
    SELECT (e->>'id')::bigint AS id,
           (e->>'_rev')::bigint AS client_rev
    FROM   jsonb_array_elements(coalesce(p_updates, '[]'::jsonb)) e
    WHERE  jsonb_typeof(e->'patch') = 'object'
      AND  e ? '_rev'
  ) u
  JOIN sale_target s ON s.id = u.id
  WHERE s._rev <> u.client_rev;

  -- 3) Update only rows with matching _rev (or rows without _rev = no check)
  WITH u AS (
    SELECT (e->>'id')::bigint AS id,
           e->'patch'         AS patch,
           (e->>'_rev')::bigint AS client_rev
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
    AND  (u.client_rev IS NULL OR s._rev = u.client_rev)
    AND  (p_bu     IS NULL OR s.bu            =     p_bu)
    AND  (p_mien   IS NULL OR s.mien          =     p_mien)
    AND  (p_ps     IS NULL OR s.ps            =     p_ps)
    AND  (p_groups IS NULL OR s.nhom_san_pham = ANY(p_groups));

  GET DIAGNOSTICS v_done = ROW_COUNT;
  RETURN jsonb_build_object('updated', v_done, 'conflicts', v_conflicts);
END;
$$;
