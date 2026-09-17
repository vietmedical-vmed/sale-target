-- GĐ 2.4a: upsert_quota_thau / delete_dot_thau cập nhật luôn cột quota
-- cũ trên sale_target trong cùng transaction (B4).
-- ============================================================================

-- Helper: tính tổng quota từ bảng quota_thau rồi ghi vào sale_target.
-- p_keys: [{fy, ps, cust, grp, mset, prod}]
-- Dòng sale_target đầu tiên (ORDER BY id) nhận giá trị tổng; các dòng còn lại = 0.
CREATE OR REPLACE FUNCTION shared.sync_quota_to_sale_target(p_keys jsonb)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, shared
AS $$
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
$$;

-- ---------------------------------------------------------------------------
-- Cập nhật upsert_quota_thau: gọi sync ở cuối.
-- ---------------------------------------------------------------------------
DROP FUNCTION IF EXISTS public.upsert_quota_thau(jsonb, text, text, text, text[], text);

CREATE OR REPLACE FUNCTION public.upsert_quota_thau(
  p_rows   jsonb,
  p_bu     text,
  p_mien   text,
  p_ps     text,
  p_groups text[],
  p_actor  text DEFAULT NULL
)
RETURNS integer
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, shared
AS $$
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
$$;

-- ---------------------------------------------------------------------------
-- Cập nhật delete_dot_thau: capture affected products, then sync.
-- ---------------------------------------------------------------------------
DROP FUNCTION IF EXISTS public.delete_dot_thau(text, text, text, text, text, int, text, text, text, text[]);

CREATE OR REPLACE FUNCTION public.delete_dot_thau(
  p_fy     text,
  p_ps_row text,
  p_cust   text,
  p_grp    text,
  p_loai   text,
  p_dot    int,
  p_bu     text,
  p_mien   text,
  p_ps     text,
  p_groups text[]
)
RETURNS integer
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, shared
AS $$
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

  IF v_keys IS NOT NULL THEN
    PERFORM shared.sync_quota_to_sale_target(v_keys);
  END IF;

  RETURN v_n;
END;
$$;

-- ---------------------------------------------------------------------------
-- Quyền
-- ---------------------------------------------------------------------------
REVOKE ALL ON FUNCTION shared.sync_quota_to_sale_target(jsonb) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION shared.sync_quota_to_sale_target(jsonb) TO service_role;
REVOKE ALL ON FUNCTION public.upsert_quota_thau(jsonb, text, text, text, text[], text) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.upsert_quota_thau(jsonb, text, text, text, text[], text) TO service_role;
REVOKE ALL ON FUNCTION public.delete_dot_thau(text, text, text, text, text, int, text, text, text, text[]) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.delete_dot_thau(text, text, text, text, text, int, text, text, text, text[]) TO service_role;
