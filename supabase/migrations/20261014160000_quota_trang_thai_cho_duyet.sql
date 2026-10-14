-- P2a chuẩn hoá quota: trạng thái "chờ duyệt" cho quota / đợt thầu.
--
-- Quota chuyển từ cột cũ sale_target mà app ĐANG ẨN (nhóm đã khai đợt nhưng sản
-- phẩm chưa có quota_thau) được đưa vào quota_thau với trang_thai = 'cho_duyet':
-- không lên app, không vào sync cột cũ, admin xem và duyệt ở tab riêng.
--   * get_quota_thau / sync_quota_to_sale_target: chỉ lấy 'chinh_thuc'.
--   * upsert_quota_thau / upsert_dot_thau: user nhập đè đúng khoá thì thành chính thức.
--   * duyet_quota_thau(): duyệt (→ chính thức, kèm đợt) hoặc loại (xoá) theo id.
-- Thân hàm lấy từ DB (pg_get_functiondef) ngày 2026-10-14, chỉ thêm điều kiện trạng thái.

BEGIN;

ALTER TABLE shared.quota_thau
  ADD COLUMN IF NOT EXISTS trang_thai text NOT NULL DEFAULT 'chinh_thuc',
  ADD COLUMN IF NOT EXISTS nguon      text;
ALTER TABLE shared.dot_thau
  ADD COLUMN IF NOT EXISTS trang_thai text NOT NULL DEFAULT 'chinh_thuc',
  ADD COLUMN IF NOT EXISTS nguon      text;
ALTER TABLE shared.quota_thau ADD CONSTRAINT quota_thau_trang_thai_check CHECK (trang_thai IN ('chinh_thuc', 'cho_duyet'));
ALTER TABLE shared.dot_thau   ADD CONSTRAINT dot_thau_trang_thai_check   CHECK (trang_thai IN ('chinh_thuc', 'cho_duyet'));
COMMENT ON COLUMN shared.quota_thau.trang_thai IS 'chinh_thuc = hiện trên app; cho_duyet = chờ admin duyệt (tab Quota chờ duyệt), không tính vào app.';
COMMENT ON COLUMN shared.quota_thau.nguon IS 'Nguồn nạp (vd cot_cu_20261014 = chuyển từ cột quota cũ của sale_target).';

CREATE OR REPLACE FUNCTION public.get_quota_thau(p_fy text, p_bu text, p_mien text, p_ps text, p_groups text[])
 RETURNS TABLE(kind text, fy text, ps text, cust_id text, grp text, mset text, prod text, price numeric, loai text, dot integer, thang text, thoi_gian numeric, qty numeric)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'shared'
AS $function$

  SELECT * FROM (

    SELECT 'dot'::text AS kind, d.nam_tai_chinh, d.ps, d.ma_khach_hang, d.nhom_san_pham,

           NULL::text, NULL::text, NULL::numeric, d.loai, d.dot, d.thang_thau, d.thoi_gian, NULL::numeric

    FROM   shared.dot_thau d

    WHERE  (p_fy     IS NULL OR d.nam_tai_chinh = p_fy)

      AND  (p_bu     IS NULL OR d.bu            =     p_bu)

      AND  (shared.mien_in(d.mien, p_mien))

      AND  (p_ps     IS NULL OR d.ps            =     p_ps)

      AND  (p_groups IS NULL OR d.nhom_san_pham = ANY(p_groups))

      AND  (p_bu IS NOT NULL OR d.bu IS NULL OR d.bu <> 'test')
      AND  d.trang_thai = 'chinh_thuc'

    UNION ALL

    SELECT 'quota'::text, q.nam_tai_chinh, q.ps, q.ma_khach_hang, q.nhom_san_pham,

           q.bo_vat_tu, q.san_pham, q.don_gia, q.loai, q.dot, NULL::text, NULL::numeric, q.so_luong

    FROM   shared.quota_thau q

    WHERE  (p_fy     IS NULL OR q.nam_tai_chinh = p_fy)

      AND  (p_bu     IS NULL OR q.bu            =     p_bu)

      AND  (shared.mien_in(q.mien, p_mien))

      AND  (p_ps     IS NULL OR q.ps            =     p_ps)

      AND  (p_groups IS NULL OR q.nhom_san_pham = ANY(p_groups))

      AND  (p_bu IS NOT NULL OR q.bu IS NULL OR q.bu <> 'test')
      AND  q.trang_thai = 'chinh_thuc'

  ) t

  ORDER BY 1, 2, 3, 4, 5, 6, 7, 8, 9, 10;

$function$;

CREATE OR REPLACE FUNCTION shared.sync_quota_to_sale_target(p_keys jsonb)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'shared'
AS $function$
BEGIN
  WITH keys AS (
    SELECT DISTINCT
      k->>'fy'   AS fy,
      k->>'ps'   AS ps,
      k->>'cust' AS cust,
      k->>'grp'  AS grp,
      k->>'mset' AS mset,
      k->>'prod' AS prod
    FROM jsonb_array_elements(p_keys) k
  ),
  totals AS (
    SELECT k.fy, k.ps, k.cust, k.grp, k.mset, k.prod,
      coalesce(SUM(q.so_luong) FILTER (WHERE q.loai = 'cu'), 0)      AS tong_cu,
      coalesce(SUM(q.so_luong) FILTER (WHERE q.loai = 'chinh'), 0)   AS tong_chinh,
      coalesce(SUM(q.so_luong) FILTER (WHERE q.loai = 'bo_sung'), 0) AS tong_bo_sung
    FROM keys k
    LEFT JOIN shared.quota_thau q
      ON  q.nam_tai_chinh  = k.fy
      AND q.ps             = k.ps
      AND q.ma_khach_hang  = k.cust
      AND q.nhom_san_pham  = k.grp
      AND q.bo_vat_tu      = k.mset
      AND q.san_pham       = k.prod
      AND q.trang_thai     = 'chinh_thuc'
    GROUP BY k.fy, k.ps, k.cust, k.grp, k.mset, k.prod
  ),
  ranked AS (
    SELECT s.id,
      t.tong_cu, t.tong_chinh, t.tong_bo_sung,
      ROW_NUMBER() OVER (
        PARTITION BY s.nam_tai_chinh, s.ps, s.ma_khach_hang,
                     s.nhom_san_pham, s.bo_vat_tu, s.san_pham
        ORDER BY s.id
      ) AS rn
    FROM shared.sale_target s
    JOIN totals t
      ON  s.nam_tai_chinh  = t.fy
      AND s.ps             = t.ps
      AND s.ma_khach_hang  = t.cust
      AND s.nhom_san_pham  = t.grp
      AND s.bo_vat_tu      = t.mset
      AND s.san_pham       = t.prod
  )
  UPDATE shared.sale_target s SET
    quota_thau_cu_con_lai = CASE WHEN r.rn = 1 THEN r.tong_cu      ELSE 0 END,
    quota_thau_chinh      = CASE WHEN r.rn = 1 THEN r.tong_chinh   ELSE 0 END,
    quota_bo_sung         = CASE WHEN r.rn = 1 THEN r.tong_bo_sung ELSE 0 END
  FROM ranked r
  WHERE s.id = r.id
    AND (s.quota_thau_cu_con_lai IS DISTINCT FROM (CASE WHEN r.rn = 1 THEN r.tong_cu      ELSE 0 END)
      OR s.quota_thau_chinh      IS DISTINCT FROM (CASE WHEN r.rn = 1 THEN r.tong_chinh   ELSE 0 END)
      OR s.quota_bo_sung         IS DISTINCT FROM (CASE WHEN r.rn = 1 THEN r.tong_bo_sung ELSE 0 END));
END;
$function$;

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

  IF v_done > 0 THEN
    PERFORM shared.sync_quota_to_sale_target(v_keys);
  END IF;

  RETURN v_done;
END;
$function$;

CREATE OR REPLACE FUNCTION public.upsert_dot_thau(p_rows jsonb, p_bu text, p_mien text, p_ps text, p_groups text[], p_actor text DEFAULT NULL::text)
 RETURNS integer
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'shared'
AS $function$
DECLARE
  r      jsonb;
  v_bu   text;
  v_mien text;
  v_fy   text;
  v_ps   text;
  v_cust text;
  v_grp  text;
  v_loai text;
  v_dot  int;
  v_thang text;
  v_done int := 0;
BEGIN
  FOR r IN SELECT * FROM jsonb_array_elements(coalesce(p_rows, '[]'::jsonb))
  LOOP
    v_fy   := r->>'fy';
    v_ps   := r->>'ps';
    v_cust := coalesce(r->>'custId', '');
    v_grp  := coalesce(r->>'grp', '');
    v_loai := r->>'loai';
    v_thang := nullif(r->>'thang', '');

    IF v_loai NOT IN ('chinh', 'bo_sung') THEN
      RAISE EXCEPTION 'loai_khong_hop_le: %', v_loai USING ERRCODE = '22023';
    END IF;
    IF v_thang IS NOT NULL AND v_thang !~ '^\d{4}-\d{2}$' THEN
      RAISE EXCEPTION 'thang_sai_dinh_dang: % (cần yyyy-mm)', v_thang USING ERRCODE = '22023';
    END IF;

    SELECT s.bu, s.mien INTO v_bu, v_mien
    FROM shared.scope_nhom_sp(v_fy, v_ps, v_cust, v_grp, p_bu, p_mien, p_ps, p_groups) s;

    IF NOT FOUND THEN
      RAISE EXCEPTION 'out_of_scope: nhóm % / KH % / PS % nằm ngoài phạm vi quyền hoặc không tồn tại',
                      v_grp, v_cust, v_ps USING ERRCODE = '42501';
    END IF;

    v_dot := nullif(r->>'dot', '')::int;
    IF v_dot IS NULL THEN
      SELECT coalesce(max(d.dot), 0) + 1 INTO v_dot
      FROM   shared.dot_thau d
      WHERE  d.nam_tai_chinh = v_fy AND d.ps = v_ps
        AND  d.ma_khach_hang = v_cust AND d.nhom_san_pham = v_grp
        AND  d.loai = v_loai;
    END IF;

    INSERT INTO shared.dot_thau
      (nam_tai_chinh, bu, mien, ps, ma_khach_hang, nhom_san_pham,
       loai, dot, thang_thau, thoi_gian, updated_by)
    VALUES
      (v_fy, v_bu, v_mien, v_ps, v_cust, v_grp,
       v_loai, v_dot, v_thang, nullif(r->>'thoiGian', '')::numeric, p_actor)
    ON CONFLICT (nam_tai_chinh, ps, ma_khach_hang, nhom_san_pham, loai, dot)
    DO UPDATE SET
      trang_thai = 'chinh_thuc',
      thang_thau = EXCLUDED.thang_thau,
      thoi_gian  = CASE WHEN r ? 'thoiGian' THEN EXCLUDED.thoi_gian
                        ELSE shared.dot_thau.thoi_gian END,
      updated_at = now(),
      updated_by = p_actor;

    v_done := v_done + 1;
  END LOOP;

  RETURN v_done;
END;
$function$;

-- Duyệt / loại quota chờ duyệt theo id. Chỉ edge function (admin) gọi.
CREATE OR REPLACE FUNCTION public.duyet_quota_thau(p_ids bigint[], p_duyet boolean, p_actor text DEFAULT NULL)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, shared
AS $$
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

    IF v_keys IS NOT NULL THEN
      PERFORM shared.sync_quota_to_sale_target(v_keys);
    END IF;
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
$$;

REVOKE ALL ON FUNCTION public.duyet_quota_thau(bigint[], boolean, text) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.duyet_quota_thau(bigint[], boolean, text) TO service_role;
REVOKE ALL ON FUNCTION public.get_quota_thau(text, text, text, text, text[]) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.get_quota_thau(text, text, text, text, text[]) TO service_role;
REVOKE ALL ON FUNCTION public.upsert_quota_thau(jsonb, text, text, text, text[], text) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.upsert_quota_thau(jsonb, text, text, text, text[], text) TO service_role;
REVOKE ALL ON FUNCTION public.upsert_dot_thau(jsonb, text, text, text, text[], text) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.upsert_dot_thau(jsonb, text, text, text, text[], text) TO service_role;
REVOKE ALL ON FUNCTION shared.sync_quota_to_sale_target(jsonb) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION shared.sync_quota_to_sale_target(jsonb) TO service_role;

COMMIT;
