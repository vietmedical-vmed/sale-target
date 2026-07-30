-- ════════════════════════════════════════════════════════════════════════
-- CẤU HÌNH ĐỊA BÀN — dm_dia_ban
--
-- Trả lời câu hỏi "ngành hàng X của khách hàng Y do PS nào phụ trách" bằng một
-- DANH MỤC KHAI BÁO TRƯỚC, thay vì suy ra từ dữ liệu kế hoạch như hiện nay
-- (dropdown PS/Miền trong form thêm KH/SP đang lấy distinct từ sale_target →
-- KH hoặc ngành hàng chưa từng có dòng kế hoạch thì không gợi ý được gì, và gõ
-- sai PS thì không ai chặn).
--
-- Độ mịn: (team, khách hàng, nhom_san_pham) → PS. KHÔNG xuống tới bo_vat_tu.
-- Một (KH × ngành hàng) VẪN được phép có nhiều PS: khoá unique gồm cả ps, đúng
-- như quy tắc nghiệp vụ "1 khách hàng có thể do nhiều PS phụ trách" và đúng cách
-- màn Chi tiết đang tách dòng theo (nhóm SP, PS).
--
-- Gồm:
--   1) Bảng dm_dia_ban (+ cust_key sinh tự động, index, grant)
--   2) Seed 1 lần từ chính sale_target → có ngay toàn bộ địa bàn đang chạy
--   3) upsert_dm_dia_ban()     — ghi hàng loạt trong 1 giao dịch, có kiểm phạm vi
--   4) apply_dia_ban_to_plan() — đẩy PS/Miền đã khai báo xuống dòng kế hoạch
--
-- Idempotent: chạy lại nhiều lần vô hại (seed dùng ON CONFLICT DO NOTHING).
-- ════════════════════════════════════════════════════════════════════════

-- 1) Bảng ─────────────────────────────────────────────────────────────────
-- cust_key: khoá khách hàng dùng để đối chiếu với sale_target. Ưu tiên mã KH;
-- mã rỗng thì rơi về tên. Sinh tự động (STORED) để khoá unique và mọi câu join
-- luôn dùng CÙNG một cách tính, không phụ thuộc caller nhớ coalesce hay không.
CREATE TABLE IF NOT EXISTS public.dm_dia_ban (
  id            bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  bu            text NOT NULL,
  ma_khach_hang text NOT NULL DEFAULT '',
  khach_hang    text,
  nhom_san_pham text NOT NULL,
  mien          text,
  ps            text NOT NULL,
  active        boolean NOT NULL DEFAULT true,
  updated_at    timestamptz NOT NULL DEFAULT now(),
  cust_key      text GENERATED ALWAYS AS
                  (coalesce(nullif(btrim(ma_khach_hang), ''), btrim(khach_hang))) STORED
);

COMMENT ON TABLE public.dm_dia_ban IS
  'Cấu hình địa bàn: (team, khách hàng, nhóm sản phẩm) -> PS phụ trách. Nguồn khai báo; sale_target chỉ đổi theo khi gọi apply_dia_ban_to_plan().';

-- Một địa bàn = (team, KH, ngành hàng, PS). Trùng cả 4 = cùng một khai báo.
CREATE UNIQUE INDEX IF NOT EXISTS uq_dm_dia_ban
  ON public.dm_dia_ban (bu, cust_key, nhom_san_pham, ps);
-- Tra theo KH (màn cấu hình, form thêm KH tự điền PS/Miền) và theo PS (phân quyền).
CREATE INDEX IF NOT EXISTS idx_dm_dia_ban_cust ON public.dm_dia_ban (bu, cust_key);
CREATE INDEX IF NOT EXISTS idx_dm_dia_ban_ps   ON public.dm_dia_ban (ps);

ALTER TABLE public.dm_dia_ban ENABLE ROW LEVEL SECURITY;

-- config.toml không bật auto_expose_new_tables → bảng mới KHÔNG tự lộ qua Data
-- API, kể cả cho service_role (edge function). Phải grant tay.
-- anon/authenticated CỐ Ý không có quyền gì: mọi truy cập đi qua edge function.
GRANT SELECT, INSERT, UPDATE, DELETE ON TABLE public.dm_dia_ban TO service_role;

-- 2) Seed từ dữ liệu kế hoạch đang chạy ───────────────────────────────────
-- Lấy mọi (bu, KH, ngành hàng, PS) đang thật sự có dòng kế hoạch. Miền lấy theo
-- dòng id nhỏ nhất của tổ hợp đó (1 PS gần như luôn thuộc 1 miền).
INSERT INTO public.dm_dia_ban (bu, ma_khach_hang, khach_hang, nhom_san_pham, mien, ps)
SELECT DISTINCT ON (s.bu, s.cust_key, s.nhom_san_pham, s.ps)
       s.bu, s.ma_khach_hang, s.khach_hang, s.nhom_san_pham, s.mien, s.ps
FROM (
  SELECT bu, coalesce(ma_khach_hang, '') AS ma_khach_hang, khach_hang, nhom_san_pham,
         mien, ps, id,
         coalesce(nullif(btrim(coalesce(ma_khach_hang, '')), ''), btrim(khach_hang)) AS cust_key
  FROM   public.sale_target
) s
WHERE  s.bu IS NOT NULL
  AND  s.ps IS NOT NULL AND btrim(s.ps) <> ''
  AND  s.nhom_san_pham IS NOT NULL AND btrim(s.nhom_san_pham) <> ''
  AND  s.cust_key IS NOT NULL AND s.cust_key <> ''
ORDER  BY s.bu, s.cust_key, s.nhom_san_pham, s.ps, s.id
ON CONFLICT DO NOTHING;

-- 3) Ghi hàng loạt ────────────────────────────────────────────────────────
-- p_rows: [{ "id": <bigint|null>, "bu":…, "ma_khach_hang":…, "khach_hang":…,
--            "nhom_san_pham":…, "mien":…, "ps":…, "active": true }, …]
--   id có  → SỬA dòng đó (đổi PS/Miền của một địa bàn đã khai báo)
--   id null→ THÊM mới (trùng khoá thì cập nhật Miền/tên KH, không nhân bản)
--
-- 4 tham số phạm vi khớp đúng applyScope()/scopeParams() của edge function:
-- NULL = không giới hạn theo cột đó. CỐ Ý không có DEFAULT để không ai "quên"
-- mà thành không giới hạn. Có bất kỳ dòng nào ngoài phạm vi → 42501, cả lô huỷ.
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
         coalesce(nullif(btrim(coalesce(e->>'ma_khach_hang', '')), ''),
                  btrim(coalesce(e->>'khach_hang', '')))         AS cust_key
  FROM   jsonb_array_elements(coalesce(p_rows, '[]'::jsonb)) e;

  SELECT count(*) INTO v_in FROM _rows;
  IF v_in = 0 THEN
    RETURN jsonb_build_object('inserted', 0, 'updated', 0);
  END IF;

  -- bu CHỈ bắt buộc với dòng thêm mới; dòng sửa giữ nguyên bu đang có trong DB
  -- (caller không phải tra lại team của dòng cũ).
  IF EXISTS (SELECT 1 FROM _rows
              WHERE nhom_san_pham = '' OR ps = '' OR coalesce(cust_key, '') = ''
                 OR (id IS NULL AND bu = '')) THEN
    RAISE EXCEPTION 'thieu_du_lieu: bu / khach_hang / nhom_san_pham / ps không được rỗng'
      USING ERRCODE = '22023';
  END IF;

  -- Phạm vi của DỮ LIỆU GHI VÀO (không cho ghi sang team/miền/PS/ngành hàng khác)
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

  -- Phạm vi của DÒNG BỊ SỬA: id phải tồn tại VÀ đang trong phạm vi
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
        updated_at    = now()
      FROM   _rows r
      WHERE  d.id = r.id
      RETURNING d.id
    ) SELECT count(*) INTO v_upd FROM u;

    -- DISTINCT ON: hai dòng cùng khoá trong CÙNG một lô sẽ làm ON CONFLICT DO
    -- UPDATE chạm cùng một dòng 2 lần (lỗi cardinality) → gom trước.
    WITH i AS (
      INSERT INTO dm_dia_ban (bu, ma_khach_hang, khach_hang, nhom_san_pham, mien, ps, active)
      SELECT DISTINCT ON (r.bu, r.cust_key, r.nhom_san_pham, r.ps)
             r.bu, r.ma_khach_hang, r.khach_hang, r.nhom_san_pham, r.mien, r.ps, r.active
      FROM   _rows r
      WHERE  r.id IS NULL
      ORDER  BY r.bu, r.cust_key, r.nhom_san_pham, r.ps
      ON CONFLICT (bu, cust_key, nhom_san_pham, ps) DO UPDATE SET
        ma_khach_hang = excluded.ma_khach_hang,
        khach_hang    = coalesce(excluded.khach_hang, dm_dia_ban.khach_hang),
        mien          = excluded.mien,
        active        = excluded.active,
        updated_at    = now()
      RETURNING id
    ) SELECT count(*) INTO v_ins FROM i;
  EXCEPTION WHEN unique_violation THEN
    -- Đổi PS của một địa bàn thành PS đã được khai báo cho cùng (KH, ngành hàng).
    RAISE EXCEPTION 'dup_dia_ban: địa bàn này đã được khai báo cho PS đó'
      USING ERRCODE = '23505';
  END;

  RETURN jsonb_build_object('inserted', v_ins, 'updated', v_upd);
END;
$$;

-- 4) Đẩy cấu hình xuống kế hoạch ──────────────────────────────────────────
-- p_ids: các dòng dm_dia_ban muốn áp dụng.
-- p_from_month: chỉ ghi các tháng >= giá trị này ('2026-07'); NULL = cả năm.
--   Mặc định app gửi tháng hiện tại: đổi PS của các tháng ĐÃ QUA sẽ làm lệch
--   khoá khớp actual (tháng|PS|maKH|boVT|sanPham) → số thực hiện cũ rơi ra
--   "ngoài kế hoạch". Ai cần sửa cả năm thì phải chủ động chọn.
-- Tổ hợp (team, KH, ngành hàng) đang khai báo cho NHIỀU PS thì BỎ QUA: không
-- có cách nào đoán dòng kế hoạch nào thuộc PS nào; thà báo lại còn hơn gán bừa.
CREATE OR REPLACE FUNCTION public.apply_dia_ban_to_plan(
  p_ids        bigint[],
  p_from_month text
) RETURNS jsonb
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
    UPDATE sale_target s SET
      ps         = c.ps,
      mien       = coalesce(c.mien, s.mien),
      updated_at = now()
    FROM  (SELECT * FROM _cfg WHERE so_ps = 1) c
    WHERE s.bu            = c.bu
      AND s.nhom_san_pham = c.nhom_san_pham
      AND coalesce(nullif(btrim(coalesce(s.ma_khach_hang, '')), ''), btrim(s.khach_hang)) = c.cust_key
      AND (p_from_month IS NULL OR s.thang_ke_hoach >= p_from_month)
      AND (s.ps IS DISTINCT FROM c.ps
           OR s.mien IS DISTINCT FROM coalesce(c.mien, s.mien));
    GET DIAGNOSTICS v_upd = ROW_COUNT;
  END IF;

  RETURN jsonb_build_object('applied', v_cfg, 'ambiguous', v_amb, 'updated_rows', v_upd);
END;
$$;

-- Postgres mặc định cấp EXECUTE cho PUBLIC → thu hồi, chỉ edge function (service_role) gọi.
REVOKE ALL ON FUNCTION public.upsert_dm_dia_ban(jsonb, text, text, text, text[]) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.upsert_dm_dia_ban(jsonb, text, text, text, text[]) FROM anon, authenticated;
GRANT EXECUTE ON FUNCTION public.upsert_dm_dia_ban(jsonb, text, text, text, text[]) TO service_role;

REVOKE ALL ON FUNCTION public.apply_dia_ban_to_plan(bigint[], text) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.apply_dia_ban_to_plan(bigint[], text) FROM anon, authenticated;
GRANT EXECUTE ON FUNCTION public.apply_dia_ban_to_plan(bigint[], text) TO service_role;

COMMENT ON FUNCTION public.upsert_dm_dia_ban(jsonb, text, text, text, text[]) IS
  'Ghi hàng loạt cấu hình địa bàn trong 1 giao dịch. id có = sửa, id null = thêm. Kiểm phạm vi quyền như update_sale_target_cells.';
COMMENT ON FUNCTION public.apply_dia_ban_to_plan(bigint[], text) IS
  'Đẩy PS/Miền từ dm_dia_ban xuống sale_target (mặc định chỉ từ tháng hiện tại trở đi). Tổ hợp nhiều PS bị bỏ qua.';

ANALYZE public.dm_dia_ban;
