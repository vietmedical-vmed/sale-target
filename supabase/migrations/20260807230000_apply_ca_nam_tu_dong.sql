-- ════════════════════════════════════════════════════════════════════════
-- Bỏ chia theo tháng, tự động apply sau khi lưu cấu hình
--
-- YÊU CẦU NGHIỆP VỤ (2026-08-07)
--   Cấu hình địa bàn là chân lý — sau khi lưu, kế hoạch phải tự update theo,
--   và áp dụng CHO CẢ NĂM (không giới hạn theo khoảng tu_thang..den_thang của
--   bản khai báo). Bỏ khái niệm khoảng hiệu lực theo tháng ở tầng nghiệp vụ.
--
-- GIỮ LẠI CHUYỂN GÌ
--   - Cột tu_thang / den_thang / RPC chuyen_dia_ban / v_dia_ban_khoang_trong /
--     kiem_tra_khoang_trong: GIỮ NGUYÊN để không đụng lịch sử migration và
--     dữ liệu cũ (58 bản có den_thang, 91 bản có tu_thang ≠ 2026-04). Chỉ đổi
--     HÀNH VI: apply bỏ qua điều kiện tháng; upsert không kiểm khoảng trống
--     nữa (đây là ràng buộc cứng, không hợp với mức nghiêm ngặt 1).
--
-- KHOÁ UNIQUE
--   Vẫn cho phép nhiều PS cho cùng (bu, cust_key, nhom_san_pham) — dữ liệu hiện
--   có 38 tổ hợp như vậy (chia đôi thật). Apply sẽ bỏ qua các tổ hợp này (giữ
--   logic "so_ps > 1 -> ambiguous").
-- ════════════════════════════════════════════════════════════════════════

-- ── 1) apply_dia_ban_to_plan: apply cả năm, bỏ điều kiện tháng ───────────
-- Thay đổi so với 20260730140000: bỏ 2 dòng
--   AND s.thang_ke_hoach >= c.tu_thang
--   AND (c.den_thang IS NULL OR s.thang_ke_hoach <= c.den_thang)
DROP FUNCTION IF EXISTS public.apply_dia_ban_to_plan(bigint[]);

CREATE OR REPLACE FUNCTION public.apply_dia_ban_to_plan(p_ids bigint[])
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_upd integer := 0;
  v_amb integer := 0;
  v_cfg integer := 0;
BEGIN
  CREATE TEMP TABLE _cfg ON COMMIT DROP AS
  SELECT d.id, d.bu, d.cust_key, d.nhom_san_pham, d.mien, d.ps,
         (SELECT count(DISTINCT d2.ps)
            FROM dm_dia_ban d2
           WHERE d2.bu            = d.bu
             AND d2.cust_key      = d.cust_key
             AND d2.nhom_san_pham = d.nhom_san_pham
             AND d2.active) AS so_ps
  FROM   dm_dia_ban d
  WHERE  d.id = ANY(coalesce(p_ids, '{}'::bigint[]))
    AND  d.active;

  SELECT count(*) FILTER (WHERE so_ps > 1), count(*) FILTER (WHERE so_ps = 1)
    INTO v_amb, v_cfg
    FROM _cfg;

  IF v_cfg > 0 THEN
    -- Ghi cho MỌI dòng kế hoạch của tổ hợp (bu, KH, ngành hàng), không giới
    -- hạn theo tháng. Tổ hợp chồng lấn nhiều PS -> bỏ qua ở filter so_ps=1.
    UPDATE sale_target s SET
      ps         = c.ps,
      mien       = coalesce(c.mien, s.mien),
      updated_at = now()
    FROM  (SELECT * FROM _cfg WHERE so_ps = 1) c
    WHERE s.bu            = c.bu
      AND s.nhom_san_pham = c.nhom_san_pham
      AND coalesce(nullif(btrim(coalesce(s.ma_khach_hang, '')), ''), btrim(s.khach_hang)) = c.cust_key
      AND (s.ps IS DISTINCT FROM c.ps
           OR s.mien IS DISTINCT FROM coalesce(c.mien, s.mien));
    GET DIAGNOSTICS v_upd = ROW_COUNT;
  END IF;

  RETURN jsonb_build_object('applied', v_cfg, 'ambiguous', v_amb, 'updated_rows', v_upd);
END;
$$;

REVOKE ALL ON FUNCTION public.apply_dia_ban_to_plan(bigint[]) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.apply_dia_ban_to_plan(bigint[]) TO service_role;

COMMENT ON FUNCTION public.apply_dia_ban_to_plan(bigint[]) IS
  'Ghi PS/Miền từ dm_dia_ban xuống sale_target CHO CẢ NĂM (bỏ giới hạn theo tu_thang/den_thang từ 2026-08-07). Tổ hợp có nhiều PS chồng lấn vẫn bị bỏ qua.';


-- ── 2) upsert_dm_dia_ban: tự apply sau khi ghi, không kiểm khoảng trống ──
-- Giữ phần kiểm phạm vi quyền + duplicate + validate. Bỏ PERFORM
-- kiem_tra_khoang_trong. Thêm PERFORM apply_dia_ban_to_plan cho các bản vừa
-- ghi (cả insert lẫn update, bao gồm tổ hợp cũ khi sửa KH/nhóm).
CREATE OR REPLACE FUNCTION public.upsert_dm_dia_ban(
  p_rows   jsonb,
  p_bu     text,
  p_mien   text,
  p_ps     text,
  p_groups text[]
) RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_in   integer;
  v_ids  integer;
  v_okid integer;
  v_ins  integer := 0;
  v_upd  integer := 0;
  v_ids_touched bigint[];
  v_apply jsonb;
BEGIN
  CREATE TEMP TABLE _rows ON COMMIT DROP AS
  SELECT nullif(e->>'id', '')::bigint                            AS id,
         btrim(coalesce(e->>'bu', ''))                           AS bu,
         btrim(coalesce(e->>'ma_khach_hang', ''))                AS ma_khach_hang,
         nullif(btrim(coalesce(e->>'khach_hang', '')), '')       AS khach_hang,
         btrim(coalesce(e->>'nhom_san_pham', ''))                AS nhom_san_pham,
         nullif(btrim(coalesce(e->>'mien', '')), '')             AS mien,
         btrim(coalesce(e->>'ps', ''))                           AS ps,
         coalesce((e->>'active')::boolean, true)                 AS active,
         nullif(btrim(coalesce(e->>'tu_thang', '')), '')         AS tu_thang,
         nullif(btrim(coalesce(e->>'den_thang', '')), '')        AS den_thang,
         coalesce(nullif(btrim(coalesce(e->>'ma_khach_hang', '')), ''),
                  btrim(coalesce(e->>'khach_hang', '')))         AS cust_key
  FROM   jsonb_array_elements(coalesce(p_rows, '[]'::jsonb)) e;

  SELECT count(*) INTO v_in FROM _rows;
  IF v_in = 0 THEN
    RETURN jsonb_build_object('inserted', 0, 'updated', 0);
  END IF;

  IF EXISTS (SELECT 1 FROM _rows
              WHERE nhom_san_pham = '' OR ps = '' OR coalesce(cust_key, '') = ''
                 OR (id IS NULL AND bu = '')) THEN
    RAISE EXCEPTION 'thieu_du_lieu: bu / khach_hang / nhom_san_pham / ps không được rỗng'
      USING ERRCODE = '22023';
  END IF;

  IF EXISTS (
    SELECT 1 FROM _rows r
     WHERE (p_bu     IS NOT NULL AND r.id IS NULL AND r.bu <> p_bu)
        OR (p_mien   IS NOT NULL AND coalesce(r.mien, '') <> p_mien)
        OR (p_ps     IS NOT NULL AND r.ps <> p_ps)
        OR (p_groups IS NOT NULL AND NOT (r.nhom_san_pham = ANY(p_groups)))
  ) THEN
    RAISE EXCEPTION 'out_of_scope: dòng ghi vào nằm ngoài phạm vi quyền'
      USING ERRCODE = '42501';
  END IF;

  SELECT count(*), count(d.id) INTO v_ids, v_okid
    FROM _rows r
    LEFT JOIN dm_dia_ban d
           ON d.id = r.id
          AND (p_bu     IS NULL OR d.bu            =     p_bu)
          AND (p_mien   IS NULL OR d.mien          =     p_mien)
          AND (p_ps     IS NULL OR d.ps            =     p_ps)
          AND (p_groups IS NULL OR d.nhom_san_pham = ANY(p_groups))
   WHERE r.id IS NOT NULL;
  IF v_okid <> v_ids THEN
    RAISE EXCEPTION 'out_of_scope: % / % dòng sửa nằm ngoài phạm vi quyền hoặc không còn tồn tại',
                    v_ids - v_okid, v_ids
      USING ERRCODE = '42501';
  END IF;

  BEGIN
    WITH u AS (
      UPDATE dm_dia_ban d SET
        ma_khach_hang = r.ma_khach_hang,
        khach_hang    = coalesce(r.khach_hang, d.khach_hang),
        nhom_san_pham = r.nhom_san_pham,
        mien          = r.mien,
        ps            = r.ps,
        active        = r.active,
        tu_thang      = coalesce(r.tu_thang, d.tu_thang),
        den_thang     = CASE WHEN r.tu_thang IS NULL THEN d.den_thang ELSE r.den_thang END,
        updated_at    = now()
      FROM   _rows r
      WHERE  d.id = r.id
      RETURNING d.id
    ) SELECT count(*) INTO v_upd FROM u;

    WITH i AS (
      INSERT INTO dm_dia_ban (bu, ma_khach_hang, khach_hang, nhom_san_pham, mien, ps,
                              active, tu_thang, den_thang)
      SELECT DISTINCT ON (r.bu, r.cust_key, r.nhom_san_pham, r.ps, coalesce(r.tu_thang, '2026-04'))
             r.bu, r.ma_khach_hang, r.khach_hang, r.nhom_san_pham, r.mien, r.ps,
             r.active, coalesce(r.tu_thang, '2026-04'), r.den_thang
      FROM   _rows r
      WHERE  r.id IS NULL
      ORDER  BY r.bu, r.cust_key, r.nhom_san_pham, r.ps, coalesce(r.tu_thang, '2026-04')
      ON CONFLICT (bu, cust_key, nhom_san_pham, ps, tu_thang) DO UPDATE SET
        ma_khach_hang = excluded.ma_khach_hang,
        khach_hang    = coalesce(excluded.khach_hang, dm_dia_ban.khach_hang),
        mien          = excluded.mien,
        active        = excluded.active,
        den_thang     = excluded.den_thang,
        updated_at    = now()
      RETURNING id
    ) SELECT count(*) INTO v_ins FROM i;
  EXCEPTION WHEN unique_violation THEN
    RAISE EXCEPTION 'dup_dia_ban: địa bàn này đã được khai báo cho PS đó'
      USING ERRCODE = '23505';
  END;

  -- Tự apply cho các bản vừa động vào: 1 chuyến, không cần user bấm nút.
  -- Ambiguous (nhiều PS cho cùng tổ hợp) vẫn bị bỏ qua, số trả về để UI báo.
  SELECT array_agg(DISTINCT d.id)
    INTO v_ids_touched
    FROM dm_dia_ban d
    JOIN (
      -- dòng vừa update
      SELECT d2.id FROM dm_dia_ban d2 JOIN _rows r ON r.id = d2.id
      UNION
      -- dòng vừa insert / bị đè bởi ON CONFLICT (khớp theo khoá + tổ hợp)
      SELECT d3.id FROM dm_dia_ban d3
        JOIN _rows r ON r.id IS NULL
                    AND r.bu = d3.bu
                    AND r.cust_key = d3.cust_key
                    AND r.nhom_san_pham = d3.nhom_san_pham
                    AND r.ps = d3.ps
      -- Và cả tổ hợp CŨ của dòng bị sửa (khi sửa cust_key/nhom → tổ hợp cũ
      -- có thể cần apply lại). Lấy các bản khác của tổ hợp cũ.
      UNION
      SELECT d4.id FROM dm_dia_ban d4
        JOIN dm_dia_ban dOld ON dOld.bu = d4.bu
                            AND dOld.cust_key = d4.cust_key
                            AND dOld.nhom_san_pham = d4.nhom_san_pham
        JOIN _rows r ON r.id = dOld.id
                    AND (r.cust_key <> dOld.cust_key OR r.nhom_san_pham <> dOld.nhom_san_pham)
    ) t ON t.id = d.id;

  IF v_ids_touched IS NOT NULL AND array_length(v_ids_touched, 1) > 0 THEN
    v_apply := public.apply_dia_ban_to_plan(v_ids_touched);
  END IF;

  RETURN jsonb_build_object(
    'inserted',    v_ins,
    'updated',     v_upd,
    'apply',       v_apply,
    'auto_apply',  true
  );
END;
$$;
