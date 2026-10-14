-- Chuẩn hoá quota (A1): quota chỉ còn ở shared.quota_thau / shared.dot_thau.
-- Bỏ đồng bộ ngược tổng quota về cột cũ của sale_target: upsert_quota_thau,
-- delete_dot_thau, duyet_quota_thau thôi gọi sync_quota_to_sale_target, rồi drop
-- hàm đó. Thân hàm lấy từ DB (pg_get_functiondef) ngày 2026-10-15, chỉ bỏ lệnh sync.

BEGIN;

CREATE OR REPLACE FUNCTION public.upsert_quota_thau(p_rows jsonb, p_bu text, p_mien text, p_ps text, p_groups text[], p_actor text DEFAULT NULL::text)
 RETURNS integer
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'shared'
AS $function$
DECLARE
  r       jsonb;
  v_bu    text;
  v_mien  text;
  v_fy    text;
  v_ps    text;
  v_cust  text;
  v_grp   text;
  v_mset  text;
  v_prod  text;
  v_price numeric;
  v_loai  text;
  v_dot   int;
  v_qty   numeric;
  v_done  int := 0;
  v_keys  jsonb := '[]'::jsonb;
BEGIN
  FOR r IN SELECT * FROM jsonb_array_elements(coalesce(p_rows, '[]'::jsonb))
  LOOP
    v_fy    := r->>'fy';
    v_ps    := r->>'ps';
    v_cust  := coalesce(r->>'custId', '');
    v_grp   := coalesce(r->>'grp', '');
    v_mset  := coalesce(r->>'mset', '');
    v_prod  := coalesce(r->>'prod', '');
    v_price := coalesce(nullif(r->>'price', '')::numeric, 0);
    v_loai  := r->>'loai';
    v_qty   := nullif(r->>'qty', '')::numeric;

    IF v_loai NOT IN ('cu', 'chinh', 'bo_sung') THEN
      RAISE EXCEPTION 'loai_khong_hop_le: %', v_loai USING ERRCODE = '22023';
    END IF;

    SELECT s.bu, s.mien INTO v_bu, v_mien
    FROM shared.scope_nhom_sp(v_fy, v_ps, v_cust, v_grp, p_bu, p_mien, p_ps, p_groups) s;

    IF NOT FOUND THEN
      RAISE EXCEPTION 'out_of_scope: nhóm % / KH % / PS % nằm ngoài phạm vi quyền hoặc không tồn tại',
                      v_grp, v_cust, v_ps USING ERRCODE = '42501';
    END IF;

    IF v_loai = 'cu' THEN
      v_dot := 1;
    ELSE
      v_dot := coalesce(nullif(r->>'dot', '')::int, 1);
      PERFORM 1 FROM shared.dot_thau d
       WHERE d.nam_tai_chinh = v_fy AND d.ps = v_ps
         AND d.ma_khach_hang = v_cust AND d.nhom_san_pham = v_grp
         AND d.loai = v_loai AND d.dot = v_dot;
      IF NOT FOUND THEN
        RAISE EXCEPTION 'dot_khong_ton_tai: % đợt % của nhóm % — tạo đợt trước khi nhập quota',
                        v_loai, v_dot, v_grp USING ERRCODE = '23503';
      END IF;
    END IF;

    IF v_qty IS NULL OR v_qty = 0 THEN
      DELETE FROM shared.quota_thau q
      WHERE q.nam_tai_chinh = v_fy AND q.ps = v_ps
        AND q.ma_khach_hang = v_cust AND q.nhom_san_pham = v_grp
        AND q.bo_vat_tu = v_mset AND q.san_pham = v_prod
        AND q.don_gia = v_price AND q.loai = v_loai AND q.dot = v_dot;
    ELSE
      INSERT INTO shared.quota_thau
        (nam_tai_chinh, bu, mien, ps, ma_khach_hang, khach_hang, nhom_san_pham,
         bo_vat_tu, san_pham, don_gia, loai, dot, so_luong, updated_by)
      VALUES
        (v_fy, v_bu, v_mien, v_ps, v_cust, nullif(r->>'cust', ''), v_grp,
         v_mset, v_prod, v_price, v_loai, v_dot, v_qty, p_actor)
      ON CONFLICT (nam_tai_chinh, ps, ma_khach_hang, nhom_san_pham, bo_vat_tu,
                   san_pham, don_gia, loai, dot)
      DO UPDATE SET
        trang_thai = 'chinh_thuc',
        so_luong   = EXCLUDED.so_luong,
        khach_hang = coalesce(EXCLUDED.khach_hang, shared.quota_thau.khach_hang),
        updated_at = now(),
        updated_by = p_actor;
    END IF;

    v_keys := v_keys || jsonb_build_object(
      'fy', v_fy, 'ps', v_ps, 'cust', v_cust,
      'grp', v_grp, 'mset', v_mset, 'prod', v_prod
    );
    v_done := v_done + 1;
  END LOOP;

  RETURN v_done;
END;
$function$;

CREATE OR REPLACE FUNCTION public.delete_dot_thau(p_fy text, p_ps_row text, p_cust text, p_grp text, p_loai text, p_dot integer, p_bu text, p_mien text, p_ps text, p_groups text[])
 RETURNS integer
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'shared'
AS $function$
DECLARE
  v_cust text := coalesce(p_cust, '');
  v_grp  text := coalesce(p_grp, '');
  v_n    int;
  v_keys jsonb;
BEGIN
  PERFORM 1 FROM shared.scope_nhom_sp(p_fy, p_ps_row, v_cust, v_grp,
                                      p_bu, p_mien, p_ps, p_groups);
  IF NOT FOUND THEN
    RAISE EXCEPTION 'out_of_scope: nhóm % / KH % / PS % nằm ngoài phạm vi quyền hoặc không tồn tại',
                    v_grp, v_cust, p_ps_row USING ERRCODE = '42501';
  END IF;

  WITH deleted_quotas AS (
    DELETE FROM shared.quota_thau q
    WHERE q.nam_tai_chinh = p_fy AND q.ps = p_ps_row
      AND q.ma_khach_hang = v_cust AND q.nhom_san_pham = v_grp
      AND q.loai = p_loai AND q.dot = p_dot
    RETURNING q.bo_vat_tu, q.san_pham
  )
  SELECT jsonb_agg(DISTINCT jsonb_build_object(
    'fy', p_fy, 'ps', p_ps_row, 'cust', v_cust, 'grp', v_grp,
    'mset', bo_vat_tu, 'prod', san_pham
  ))
  FROM deleted_quotas INTO v_keys;

  DELETE FROM shared.dot_thau d
  WHERE d.nam_tai_chinh = p_fy AND d.ps = p_ps_row
    AND d.ma_khach_hang = v_cust AND d.nhom_san_pham = v_grp
    AND d.loai = p_loai AND d.dot = p_dot;

  GET DIAGNOSTICS v_n = ROW_COUNT;

  RETURN v_n;
END;
$function$;

CREATE OR REPLACE FUNCTION public.duyet_quota_thau(p_ids bigint[], p_duyet boolean, p_actor text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'shared'
AS $function$
DECLARE
  v_quota int := 0;
  v_dot   int := 0;
  v_keys  jsonb;
BEGIN
  IF p_duyet THEN
    WITH doi AS (
      UPDATE shared.quota_thau q SET trang_thai = 'chinh_thuc', updated_at = now(), updated_by = p_actor
      WHERE q.id = ANY(p_ids) AND q.trang_thai = 'cho_duyet'
      RETURNING q.*)
    , log AS (
      INSERT INTO shared.quota_chuan_hoa_log (buoc, bang, ban_ghi_id, sau)
      SELECT 'duyet', 'quota_thau', id, to_jsonb(doi) FROM doi RETURNING 1)
    SELECT count(*), jsonb_agg(DISTINCT jsonb_build_object('fy', nam_tai_chinh, 'ps', ps, 'cust', ma_khach_hang,
                                                          'grp', nhom_san_pham, 'mset', bo_vat_tu, 'prod', san_pham))
      INTO v_quota, v_keys FROM doi;

    -- Đợt mà quota vừa duyệt đang dùng cũng thành chính thức
    UPDATE shared.dot_thau d SET trang_thai = 'chinh_thuc', updated_at = now(), updated_by = p_actor
    WHERE d.trang_thai = 'cho_duyet'
      AND EXISTS (SELECT 1 FROM shared.quota_thau q
                  WHERE q.id = ANY(p_ids) AND q.loai <> 'cu'
                    AND q.nam_tai_chinh = d.nam_tai_chinh AND q.ps = d.ps AND q.ma_khach_hang = d.ma_khach_hang
                    AND q.nhom_san_pham = d.nhom_san_pham AND q.loai = d.loai AND q.dot = d.dot);
    GET DIAGNOSTICS v_dot = ROW_COUNT;
  ELSE
    WITH xoa AS (
      DELETE FROM shared.quota_thau q WHERE q.id = ANY(p_ids) AND q.trang_thai = 'cho_duyet'
      RETURNING q.*)
    , log AS (
      INSERT INTO shared.quota_chuan_hoa_log (buoc, bang, ban_ghi_id, truoc)
      SELECT 'loai', 'quota_thau', id, to_jsonb(xoa) FROM xoa RETURNING 1)
    SELECT count(*) INTO v_quota FROM xoa;

    -- Đợt chờ duyệt không còn quota nào dùng → xoá
    DELETE FROM shared.dot_thau d
    WHERE d.trang_thai = 'cho_duyet'
      AND NOT EXISTS (SELECT 1 FROM shared.quota_thau q
                      WHERE q.nam_tai_chinh = d.nam_tai_chinh AND q.ps = d.ps AND q.ma_khach_hang = d.ma_khach_hang
                        AND q.nhom_san_pham = d.nhom_san_pham AND q.loai = d.loai AND q.dot = d.dot);
    GET DIAGNOSTICS v_dot = ROW_COUNT;
  END IF;

  RETURN jsonb_build_object('quota', v_quota, 'dot', v_dot);
END;
$function$;

DROP FUNCTION shared.sync_quota_to_sale_target(jsonb);

REVOKE ALL ON FUNCTION public.upsert_quota_thau(jsonb, text, text, text, text[], text) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.upsert_quota_thau(jsonb, text, text, text, text[], text) TO service_role;
REVOKE ALL ON FUNCTION public.delete_dot_thau(text, text, text, text, text, int, text, text, text, text[]) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.delete_dot_thau(text, text, text, text, text, int, text, text, text, text[]) TO service_role;
REVOKE ALL ON FUNCTION public.duyet_quota_thau(bigint[], boolean, text) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.duyet_quota_thau(bigint[], boolean, text) TO service_role;

COMMIT;
