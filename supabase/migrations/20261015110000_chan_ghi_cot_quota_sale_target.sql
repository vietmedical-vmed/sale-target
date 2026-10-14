-- Chuẩn hoá quota (A2): chặn mọi đường ghi quota / tháng / thời gian thầu vào
-- sale_target. Áp SAU khi edge function đã deploy bản thôi ghi các cột này.
--   * update_sale_target_cells: từ chối patch có 6 cột quota; bỏ 6 cột khỏi SET và
--     khỏi giá trị trả về khi xung đột. Thân hàm lấy từ DB ngày 2026-10-15.
--   * Trigger trên sale_target: INSERT có giá trị, hoặc UPDATE đổi sang giá trị
--     khác NULL ở 6 cột → lỗi (bắt cả sửa tay trên dashboard / script ngoài).
--     Đổi về NULL vẫn được (để dọn cột trước khi drop).

BEGIN;

CREATE OR REPLACE FUNCTION public.update_sale_target_cells(p_updates jsonb, p_bu text, p_mien text, p_ps text, p_groups text[])
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'shared', 'app_sale'
AS $function$
DECLARE
  v_req        integer;
  v_ok         integer;
  v_done       integer;
  v_conflicts  jsonb;
BEGIN
  -- Quota / tháng / thời gian thầu không còn lưu trên sale_target (quota_thau / dot_thau).
  IF EXISTS (
    SELECT 1 FROM jsonb_array_elements(coalesce(p_updates, '[]'::jsonb)) e
    WHERE jsonb_typeof(e->'patch') = 'object'
      AND (e->'patch') ?| ARRAY['quota_thau_cu_con_lai','thang_thau_chinh','thoi_gian_thau_chinh',
                               'quota_thau_chinh','thang_thau_bo_sung','quota_bo_sung']
  ) THEN
    RAISE EXCEPTION 'cot_quota_da_bo: quota / tháng / thời gian thầu nay lưu ở quota_thau / dot_thau, không sửa trên sale_target'
      USING ERRCODE = '22023';
  END IF;

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
          AND (shared.mien_in(s.mien, p_mien))
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
    AND  (shared.mien_in(s.mien, p_mien))
    AND  (p_ps     IS NULL OR s.ps            =     p_ps)
    AND  (p_groups IS NULL OR s.nhom_san_pham = ANY(p_groups));

  GET DIAGNOSTICS v_done = ROW_COUNT;
  RETURN jsonb_build_object('updated', v_done, 'conflicts', v_conflicts);
END;
$function$;

REVOKE ALL ON FUNCTION public.update_sale_target_cells(jsonb, text, text, text, text[]) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.update_sale_target_cells(jsonb, text, text, text, text[]) TO service_role;

CREATE OR REPLACE FUNCTION shared.chan_ghi_cot_quota_sale_target()
RETURNS trigger
LANGUAGE plpgsql
SET search_path = shared, public
AS $$
BEGIN
  IF (TG_OP = 'INSERT' AND (NEW.quota_thau_cu_con_lai IS NOT NULL OR NEW.quota_thau_chinh IS NOT NULL
                            OR NEW.quota_bo_sung IS NOT NULL OR NEW.thang_thau_chinh IS NOT NULL
                            OR NEW.thang_thau_bo_sung IS NOT NULL OR NEW.thoi_gian_thau_chinh IS NOT NULL))
  OR (TG_OP = 'UPDATE' AND (
        (NEW.quota_thau_cu_con_lai IS NOT NULL AND NEW.quota_thau_cu_con_lai IS DISTINCT FROM OLD.quota_thau_cu_con_lai)
     OR (NEW.quota_thau_chinh      IS NOT NULL AND NEW.quota_thau_chinh      IS DISTINCT FROM OLD.quota_thau_chinh)
     OR (NEW.quota_bo_sung         IS NOT NULL AND NEW.quota_bo_sung         IS DISTINCT FROM OLD.quota_bo_sung)
     OR (NEW.thang_thau_chinh      IS NOT NULL AND NEW.thang_thau_chinh      IS DISTINCT FROM OLD.thang_thau_chinh)
     OR (NEW.thang_thau_bo_sung    IS NOT NULL AND NEW.thang_thau_bo_sung    IS DISTINCT FROM OLD.thang_thau_bo_sung)
     OR (NEW.thoi_gian_thau_chinh  IS NOT NULL AND NEW.thoi_gian_thau_chinh  IS DISTINCT FROM OLD.thoi_gian_thau_chinh)))
  THEN
    RAISE EXCEPTION 'cot_quota_da_bo: sale_target không còn lưu quota / tháng / thời gian thầu — ghi vào shared.quota_thau / shared.dot_thau'
      USING ERRCODE = '22023';
  END IF;
  RETURN NEW;
END;
$$;
REVOKE ALL ON FUNCTION shared.chan_ghi_cot_quota_sale_target() FROM PUBLIC, anon, authenticated;

DROP TRIGGER IF EXISTS trg_sale_target_chan_cot_quota ON shared.sale_target;
CREATE TRIGGER trg_sale_target_chan_cot_quota
  BEFORE INSERT OR UPDATE OF quota_thau_cu_con_lai, quota_thau_chinh, quota_bo_sung,
                             thang_thau_chinh, thang_thau_bo_sung, thoi_gian_thau_chinh
  ON shared.sale_target
  FOR EACH ROW EXECUTE FUNCTION shared.chan_ghi_cot_quota_sale_target();

COMMIT;
