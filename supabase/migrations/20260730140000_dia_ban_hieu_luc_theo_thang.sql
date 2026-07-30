-- ════════════════════════════════════════════════════════════════════════
-- ĐỊA BÀN CÓ THỜI GIAN HIỆU LỰC (version theo THÁNG)
--
-- VẤN ĐỀ
-- dm_dia_ban đang là "trạng thái hiện tại": đổi PS = ghi đè, mất dấu ai phụ
-- trách tháng nào. Muốn quá khứ giữ nguyên PS của nó thì phải dựa vào việc
-- người dùng nhớ tick "chỉ áp dụng từ tháng hiện tại" — dựa vào kỷ luật thao
-- tác chứ không phải vào dữ liệu.
--
-- CÁCH SỬA
-- Mỗi khai báo mang khoảng hiệu lực [tu_thang, den_thang] theo THÁNG
-- ('YYYY-MM', so sánh chuỗi = so sánh thời gian, khớp thẳng
-- sale_target.thang_ke_hoach). den_thang NULL = còn hiệu lực.
-- Đổi PS giữa năm KHÔNG sửa bản cũ mà ĐÓNG bản cũ + MỞ bản mới
-- (chuyen_dia_ban) → tháng cũ vẫn thuộc bản cũ, vĩnh viễn.
-- apply_dia_ban_to_plan vì thế bỏ tham số p_from_month: mỗi dòng kế hoạch lấy
-- đúng bản hiệu lực của tháng nó.
--
-- TOÀN VẸN: KHÔNG ĐƯỢC CÓ KHOẢNG TRỐNG
-- Tổ hợp (team, KH, ngành hàng) đã có khai báo thì MỌI tháng đang có dòng kế
-- hoạch phải được một bản nào đó phủ. Mọi đường ghi (upsert / chuyển / xóa)
-- đều kiểm tra sau khi ghi và huỷ cả lô nếu sinh khoảng trống.
-- Tổ hợp CHƯA có khai báo nào không tính là khoảng trống (đó là mục "chưa khai
-- báo" trên giao diện) — nếu không thì mọi lần lưu đều bị chặn oan.
--
-- Idempotent: chạy lại nhiều lần vô hại.
-- ════════════════════════════════════════════════════════════════════════

-- 1) Cột khoảng hiệu lực ──────────────────────────────────────────────────
-- DEFAULT = đầu FY26: dữ liệu đang có (seed từ sale_target) trở thành "hiệu lực
-- từ đầu năm tài chính, chưa kết thúc" → hành vi trước migration không đổi.
ALTER TABLE public.dm_dia_ban
  ADD COLUMN IF NOT EXISTS tu_thang  text NOT NULL DEFAULT '2026-04',
  ADD COLUMN IF NOT EXISTS den_thang text;

ALTER TABLE public.dm_dia_ban DROP CONSTRAINT IF EXISTS ck_dia_ban_thang;
ALTER TABLE public.dm_dia_ban ADD CONSTRAINT ck_dia_ban_thang CHECK (
  tu_thang ~ '^[0-9]{4}-[0-9]{2}$'
  AND (den_thang IS NULL OR (den_thang ~ '^[0-9]{4}-[0-9]{2}$' AND den_thang >= tu_thang))
);

COMMENT ON COLUMN public.dm_dia_ban.tu_thang  IS 'Hiệu lực từ tháng (YYYY-MM), khớp sale_target.thang_ke_hoach';
COMMENT ON COLUMN public.dm_dia_ban.den_thang IS 'Hiệu lực đến hết tháng này; NULL = còn hiệu lực';

-- Cùng (team, KH, ngành hàng, PS) được lặp lại ở NHIỀU khoảng thời gian khác
-- nhau → khoá unique phải có tu_thang.
DROP INDEX IF EXISTS public.uq_dm_dia_ban;
CREATE UNIQUE INDEX IF NOT EXISTS uq_dm_dia_ban
  ON public.dm_dia_ban (bu, cust_key, nhom_san_pham, ps, tu_thang);

-- 2) Tháng liền trước ('2026-10' -> '2026-09') ────────────────────────────
-- STABLE (không IMMUTABLE): to_char phụ thuộc cấu hình phiên. Chỉ dùng trong
-- thân function, không dùng cho index/generated column nên không sao.
CREATE OR REPLACE FUNCTION public.thang_truoc(p_thang text)
RETURNS text LANGUAGE sql STABLE STRICT AS $$
  SELECT to_char(to_date(p_thang || '-01', 'YYYY-MM-DD') - interval '1 month', 'YYYY-MM');
$$;

-- 3) Ai phụ trách gì trong MỘT tháng ──────────────────────────────────────
-- Dùng cho pipeline import (suy PS theo đúng tháng của dòng actual) và cho mọi
-- chỗ cần "trạng thái địa bàn tại thời điểm T".
CREATE OR REPLACE FUNCTION public.dia_ban_hieu_luc(p_thang text)
RETURNS TABLE (
  id bigint, bu text, ma_khach_hang text, khach_hang text, cust_key text,
  nhom_san_pham text, mien text, ps text, tu_thang text, den_thang text
) LANGUAGE sql STABLE SET search_path = public AS $$
  SELECT d.id, d.bu, d.ma_khach_hang, d.khach_hang, d.cust_key,
         d.nhom_san_pham, d.mien, d.ps, d.tu_thang, d.den_thang
  FROM   dm_dia_ban d
  WHERE  d.active
    AND  d.tu_thang <= p_thang
    AND  (d.den_thang IS NULL OR d.den_thang >= p_thang);
$$;

-- 4) Khoảng trống: tháng CÓ kế hoạch mà KHÔNG bản nào phủ ─────────────────
CREATE OR REPLACE VIEW public.v_dia_ban_khoang_trong AS
WITH plan AS (
  SELECT bu, cust_key, nhom_san_pham, thang_ke_hoach
  FROM (
    SELECT bu, nhom_san_pham, thang_ke_hoach,
           coalesce(nullif(btrim(coalesce(ma_khach_hang, '')), ''), btrim(khach_hang)) AS cust_key
    FROM   public.sale_target
  ) s
  WHERE bu IS NOT NULL AND nhom_san_pham IS NOT NULL
    AND cust_key IS NOT NULL AND cust_key <> ''
  GROUP BY 1, 2, 3, 4
)
SELECT p.bu, p.cust_key, p.nhom_san_pham, p.thang_ke_hoach AS thang_thieu
FROM   plan p
-- chỉ soi tổ hợp ĐÃ khai báo; chưa khai báo gì là chuyện khác (mục "chưa khai báo")
WHERE  EXISTS (
         SELECT 1 FROM public.dm_dia_ban d
          WHERE d.bu = p.bu AND d.cust_key = p.cust_key
            AND d.nhom_san_pham = p.nhom_san_pham AND d.active)
  AND  NOT EXISTS (
         SELECT 1 FROM public.dm_dia_ban d
          WHERE d.bu = p.bu AND d.cust_key = p.cust_key
            AND d.nhom_san_pham = p.nhom_san_pham AND d.active
            AND d.tu_thang <= p.thang_ke_hoach
            AND (d.den_thang IS NULL OR d.den_thang >= p.thang_ke_hoach));

GRANT SELECT ON public.v_dia_ban_khoang_trong TO service_role;

-- p_keys: [{"bu":…,"cust_key":…,"nhom_san_pham":…}, …] — các tổ hợp vừa bị ghi.
-- Có khoảng trống → ném lỗi (huỷ cả giao dịch của caller).
CREATE OR REPLACE FUNCTION public.kiem_tra_khoang_trong(p_keys jsonb)
RETURNS void LANGUAGE plpgsql STABLE SET search_path = public AS $$
DECLARE v_msg text;
BEGIN
  SELECT string_agg(t.line, '; ') INTO v_msg
  FROM (
    SELECT g.cust_key || ' / ' || g.nhom_san_pham || ': thiếu ' ||
           string_agg(g.thang_thieu, ', ' ORDER BY g.thang_thieu) AS line
    FROM   v_dia_ban_khoang_trong g
    JOIN   jsonb_to_recordset(coalesce(p_keys, '[]'::jsonb))
             AS k(bu text, cust_key text, nhom_san_pham text)
        ON k.bu = g.bu AND k.cust_key = g.cust_key AND k.nhom_san_pham = g.nhom_san_pham
    GROUP  BY g.cust_key, g.nhom_san_pham
    LIMIT  3
  ) t;
  IF v_msg IS NOT NULL THEN
    RAISE EXCEPTION 'khoang_trong: % — mỗi tháng đang có kế hoạch phải có người phụ trách', v_msg
      USING ERRCODE = '23514';
  END IF;
END;
$$;

-- 5) Ghi hàng loạt (bản có khoảng hiệu lực) ───────────────────────────────
-- Thay bản ở migration 20260730100000: thêm tu_thang/den_thang, đổi khoá
-- ON CONFLICT, và kiểm tra khoảng trống trước khi cho commit.
--   id có   → SỬA CHÍNH BẢN ĐÓ (giữ nguyên khoảng hiệu lực nếu không gửi lại).
--             Dùng cho việc sửa sai; đổi PS giữa năm phải dùng chuyen_dia_ban().
--   id null → THÊM bản mới; tu_thang không gửi thì mặc định đầu FY26.
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
  v_keys jsonb;
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

  -- Tổ hợp CŨ của các dòng sắp bị sửa: phải chụp TRƯỚC khi ghi, vì sửa KH/ngành
  -- hàng có thể để lại khoảng trống ở chính tổ hợp cũ.
  CREATE TEMP TABLE _keys ON COMMIT DROP AS
  SELECT DISTINCT d.bu, d.cust_key, d.nhom_san_pham
    FROM dm_dia_ban d JOIN _rows r ON r.id = d.id;

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
    RAISE EXCEPTION 'dup_dia_ban: địa bàn này đã được khai báo cho PS đó từ cùng một tháng'
      USING ERRCODE = '23505';
  END;

  -- Tổ hợp MỚI của dòng vừa sửa + tổ hợp của dòng vừa thêm.
  INSERT INTO _keys
  SELECT DISTINCT d.bu, d.cust_key, d.nhom_san_pham
    FROM dm_dia_ban d JOIN _rows r ON r.id = d.id;
  INSERT INTO _keys
  SELECT DISTINCT r.bu, r.cust_key, r.nhom_san_pham FROM _rows r WHERE r.id IS NULL;

  SELECT jsonb_agg(DISTINCT jsonb_build_object(
           'bu', k.bu, 'cust_key', k.cust_key, 'nhom_san_pham', k.nhom_san_pham))
    INTO v_keys
    FROM _keys k;
  PERFORM kiem_tra_khoang_trong(coalesce(v_keys, '[]'::jsonb));

  RETURN jsonb_build_object('inserted', v_ins, 'updated', v_upd);
END;
$$;

-- 6) Chuyển địa bàn sang PS khác TỪ MỘT THÁNG ─────────────────────────────
-- Đóng bản đang chạy ở tháng liền trước + mở bản mới từ p_tu_thang, trong đúng
-- 1 giao dịch. Đây là đường DUY NHẤT nên dùng khi đổi người phụ trách giữa năm:
-- bản cũ (và các tháng nó phủ) giữ nguyên vĩnh viễn.
CREATE OR REPLACE FUNCTION public.chuyen_dia_ban(
  p_id       bigint,
  p_ps_moi   text,
  p_mien     text,
  p_tu_thang text,
  p_bu       text,
  p_mien_scope text,
  p_ps_scope text,
  p_groups   text[]
) RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  d      dm_dia_ban;
  v_new  bigint;
  v_dong text;
BEGIN
  SELECT * INTO d FROM dm_dia_ban WHERE id = p_id;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'khong_ton_tai: không còn bản khai báo này' USING ERRCODE = '02000';
  END IF;
  IF (p_bu         IS NOT NULL AND d.bu            <>     p_bu)
  OR (p_mien_scope IS NOT NULL AND d.mien          <>     p_mien_scope)
  OR (p_ps_scope   IS NOT NULL AND d.ps            <>     p_ps_scope)
  OR (p_groups     IS NOT NULL AND NOT (d.nhom_san_pham = ANY(p_groups))) THEN
    RAISE EXCEPTION 'out_of_scope: bản khai báo nằm ngoài phạm vi quyền' USING ERRCODE = '42501';
  END IF;

  IF coalesce(btrim(p_ps_moi), '') = '' THEN
    RAISE EXCEPTION 'thieu_du_lieu: chưa chọn PS mới' USING ERRCODE = '22023';
  END IF;
  IF p_tu_thang !~ '^[0-9]{4}-[0-9]{2}$' THEN
    RAISE EXCEPTION 'thang_khong_hop_le: tháng phải dạng YYYY-MM' USING ERRCODE = '22023';
  END IF;
  -- Phải nằm TRONG khoảng của bản cũ và không phải tháng bắt đầu của nó (chuyển
  -- ngay từ tháng đầu = sửa sai, dùng đường sửa để không tạo bản rỗng).
  IF p_tu_thang <= d.tu_thang THEN
    RAISE EXCEPTION 'thang_khong_hop_le: tháng chuyển phải sau tháng bắt đầu (%) của bản đang chạy — sửa PS tại chỗ nếu chỉ muốn sửa sai', d.tu_thang
      USING ERRCODE = '22023';
  END IF;
  IF d.den_thang IS NOT NULL AND p_tu_thang > d.den_thang THEN
    RAISE EXCEPTION 'thang_khong_hop_le: tháng chuyển vượt quá tháng kết thúc (%) của bản đang chạy', d.den_thang
      USING ERRCODE = '22023';
  END IF;
  IF btrim(p_ps_moi) = d.ps THEN
    RAISE EXCEPTION 'trung_ps: PS mới trùng PS đang phụ trách' USING ERRCODE = '22023';
  END IF;

  v_dong := thang_truoc(p_tu_thang);

  BEGIN
    -- Bản mới thừa hưởng đuôi khoảng cũ (NULL = còn hiệu lực).
    INSERT INTO dm_dia_ban (bu, ma_khach_hang, khach_hang, nhom_san_pham, mien, ps,
                            active, tu_thang, den_thang)
    VALUES (d.bu, d.ma_khach_hang, d.khach_hang, d.nhom_san_pham,
            nullif(btrim(coalesce(p_mien, '')), ''), btrim(p_ps_moi),
            true, p_tu_thang, d.den_thang)
    RETURNING id INTO v_new;
  EXCEPTION WHEN unique_violation THEN
    RAISE EXCEPTION 'dup_dia_ban: đã có bản khai báo cho PS đó từ tháng %', p_tu_thang
      USING ERRCODE = '23505';
  END;

  UPDATE dm_dia_ban SET den_thang = v_dong, updated_at = now() WHERE id = p_id;

  -- Đóng+mở liền mạch nên không sinh khoảng trống, nhưng vẫn soi lại: tổ hợp có
  -- thể đã lệch từ trước và không được để lần ghi này đi qua âm thầm.
  PERFORM kiem_tra_khoang_trong(jsonb_build_array(jsonb_build_object(
    'bu', d.bu, 'cust_key', d.cust_key, 'nhom_san_pham', d.nhom_san_pham)));

  RETURN jsonb_build_object('id_cu', p_id, 'den_thang_cu', v_dong, 'id_moi', v_new);
END;
$$;

-- 7) Xóa khai báo (qua RPC để kiểm khoảng trống trong cùng giao dịch) ──────
CREATE OR REPLACE FUNCTION public.delete_dm_dia_ban(
  p_ids    bigint[],
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
  v_req  integer;
  v_ok   integer;
  v_del  integer := 0;
  v_keys jsonb;
BEGIN
  SELECT count(*), count(d.id) INTO v_req, v_ok
    FROM unnest(coalesce(p_ids, '{}'::bigint[])) AS u(id)
    LEFT JOIN dm_dia_ban d
           ON d.id = u.id
          AND (p_bu     IS NULL OR d.bu            =     p_bu)
          AND (p_mien   IS NULL OR d.mien          =     p_mien)
          AND (p_ps     IS NULL OR d.ps            =     p_ps)
          AND (p_groups IS NULL OR d.nhom_san_pham = ANY(p_groups));
  IF v_req = 0 THEN
    RETURN jsonb_build_object('deleted', 0);
  END IF;
  IF v_ok <> v_req THEN
    RAISE EXCEPTION 'out_of_scope: % / % dòng nằm ngoài phạm vi quyền hoặc không còn tồn tại',
                    v_req - v_ok, v_req
      USING ERRCODE = '42501';
  END IF;

  SELECT jsonb_agg(DISTINCT jsonb_build_object(
           'bu', d.bu, 'cust_key', d.cust_key, 'nhom_san_pham', d.nhom_san_pham))
    INTO v_keys
    FROM dm_dia_ban d WHERE d.id = ANY(p_ids);

  DELETE FROM dm_dia_ban WHERE id = ANY(p_ids);
  GET DIAGNOSTICS v_del = ROW_COUNT;

  PERFORM kiem_tra_khoang_trong(coalesce(v_keys, '[]'::jsonb));

  RETURN jsonb_build_object('deleted', v_del);
END;
$$;

-- 8) Áp dụng xuống kế hoạch THEO ĐÚNG KHOẢNG HIỆU LỰC ─────────────────────
-- Bỏ p_from_month: mỗi bản chỉ ghi vào các tháng nó phủ, nên tháng cũ không bao
-- giờ bị bản mới ghi đè — không còn phải nhớ tick "áp dụng cả tháng đã qua".
-- "Nhiều PS" xét theo CHỒNG LẤN THỜI GIAN: chỉ bỏ qua khi có bản khác cùng tổ
-- hợp, khác PS, và khoảng thời gian giao nhau (địa bàn chia đôi trong cùng tháng).
DROP FUNCTION IF EXISTS public.apply_dia_ban_to_plan(bigint[], text);

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
         d.tu_thang, d.den_thang,
         (SELECT count(DISTINCT d2.ps)
            FROM dm_dia_ban d2
           WHERE d2.bu            = d.bu
             AND d2.cust_key      = d.cust_key
             AND d2.nhom_san_pham = d.nhom_san_pham
             AND d2.active
             AND d2.tu_thang                       <= coalesce(d.den_thang,  '9999-12')
             AND coalesce(d2.den_thang, '9999-12') >= d.tu_thang) AS so_ps
  FROM   dm_dia_ban d
  WHERE  d.id = ANY(coalesce(p_ids, '{}'::bigint[]))
    AND  d.active;

  SELECT count(*) FILTER (WHERE so_ps > 1), count(*) FILTER (WHERE so_ps = 1)
    INTO v_amb, v_cfg
    FROM _cfg;

  IF v_cfg > 0 THEN
    UPDATE sale_target s SET
      ps         = c.ps,
      mien       = coalesce(c.mien, s.mien),
      updated_at = now()
    FROM  (SELECT * FROM _cfg WHERE so_ps = 1) c
    WHERE s.bu            = c.bu
      AND s.nhom_san_pham = c.nhom_san_pham
      AND coalesce(nullif(btrim(coalesce(s.ma_khach_hang, '')), ''), btrim(s.khach_hang)) = c.cust_key
      AND s.thang_ke_hoach >= c.tu_thang
      AND (c.den_thang IS NULL OR s.thang_ke_hoach <= c.den_thang)
      AND (s.ps IS DISTINCT FROM c.ps
           OR s.mien IS DISTINCT FROM coalesce(c.mien, s.mien));
    GET DIAGNOSTICS v_upd = ROW_COUNT;
  END IF;

  RETURN jsonb_build_object('applied', v_cfg, 'ambiguous', v_amb, 'updated_rows', v_upd);
END;
$$;

-- 9) Quyền ────────────────────────────────────────────────────────────────
REVOKE ALL ON FUNCTION public.thang_truoc(text) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.dia_ban_hieu_luc(text) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.kiem_tra_khoang_trong(jsonb) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.chuyen_dia_ban(bigint, text, text, text, text, text, text, text[]) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.delete_dm_dia_ban(bigint[], text, text, text, text[]) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.apply_dia_ban_to_plan(bigint[]) FROM PUBLIC, anon, authenticated;

GRANT EXECUTE ON FUNCTION public.thang_truoc(text) TO service_role;
GRANT EXECUTE ON FUNCTION public.dia_ban_hieu_luc(text) TO service_role;
GRANT EXECUTE ON FUNCTION public.kiem_tra_khoang_trong(jsonb) TO service_role;
GRANT EXECUTE ON FUNCTION public.chuyen_dia_ban(bigint, text, text, text, text, text, text, text[]) TO service_role;
GRANT EXECUTE ON FUNCTION public.delete_dm_dia_ban(bigint[], text, text, text, text[]) TO service_role;
GRANT EXECUTE ON FUNCTION public.apply_dia_ban_to_plan(bigint[]) TO service_role;

COMMENT ON FUNCTION public.dia_ban_hieu_luc(text) IS
  'Địa bàn đang hiệu lực trong 1 tháng (YYYY-MM). Dùng cho pipeline import để suy PS đúng theo tháng.';
COMMENT ON FUNCTION public.chuyen_dia_ban(bigint, text, text, text, text, text, text, text[]) IS
  'Chuyển địa bàn sang PS khác từ 1 tháng: đóng bản cũ ở tháng liền trước + mở bản mới, 1 giao dịch.';
COMMENT ON VIEW public.v_dia_ban_khoang_trong IS
  'Tháng đang có dòng kế hoạch mà không bản khai báo địa bàn nào phủ. Mọi đường ghi đều bị chặn nếu sinh khoảng trống.';

ANALYZE public.dm_dia_ban;
