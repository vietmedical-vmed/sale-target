-- Backup cho shared.sale_target
--
-- Vì sao cần: shared.audit_log chỉ ghi HÀNH ĐỘNG (ai, làm gì, mấy dòng), không lưu
-- giá trị trước/sau của từng dòng. Khi kế hoạch bị sửa làm mất khớp với thực hiện
-- thì không truy được dòng nào đã đổi, cũng không khôi phục lại được.
--
-- Cách dùng:
--   select * from public.backup_sale_target('truoc-khi-sua-thang-9');  -- chụp 1 bản
--   select * from public.sale_target_backup_ds();                      -- liệt kê bản chụp
--   select * from public.diff_sale_target_backup('ban-cu','ban-moi');  -- so 2 bản
--   select public.cleanup_sale_target_backup(12);                      -- giữ 12 bản gần nhất
--
-- Quy ước repo: BẢNG ở schema shared, RPC ở public (giống sale_target_agg).

-- ---------------------------------------------------------------------------
-- 1) Bảng backup
--    Tạo bằng CTAS để cột luôn khớp sale_target tại thời điểm chạy migration.
--    KHÔNG đặt khoá chính: một id xuất hiện ở nhiều bản chụp là bình thường.
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS shared.sale_target_backup AS
  SELECT * FROM shared.sale_target WITH NO DATA;

ALTER TABLE shared.sale_target_backup
  ADD COLUMN IF NOT EXISTS snapshot_at    timestamptz NOT NULL DEFAULT now(),
  ADD COLUMN IF NOT EXISTS snapshot_label text;

CREATE INDEX IF NOT EXISTS idx_stb_label_id ON shared.sale_target_backup (snapshot_label, id);
CREATE INDEX IF NOT EXISTS idx_stb_at       ON shared.sale_target_backup (snapshot_at DESC);

ALTER TABLE shared.sale_target_backup ENABLE ROW LEVEL SECURITY;  -- service_role bypass
GRANT ALL ON shared.sale_target_backup TO service_role;

-- ---------------------------------------------------------------------------
-- 2) Chụp 1 bản
--    Danh sách cột dựng ĐỘNG theo giao của 2 bảng, nên sau này sale_target
--    thêm/bớt cột thì hàm vẫn chạy (cột mới chưa chụp cho tới khi thêm vào
--    bảng backup bằng ALTER TABLE tương ứng).
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.backup_sale_target(p_label text DEFAULT NULL)
RETURNS TABLE (nhan text, thoi_diem timestamptz, so_dong bigint)
LANGUAGE plpgsql SECURITY DEFINER
SET search_path = shared, public
AS $fn$
DECLARE
  v_at    timestamptz := now();
  v_label text;
  v_cols  text;
  v_n     bigint;
BEGIN
  v_label := coalesce(nullif(btrim(p_label), ''),
                      to_char(v_at AT TIME ZONE 'Asia/Ho_Chi_Minh', 'YYYY-MM-DD HH24:MI:SS'));

  IF EXISTS (SELECT 1 FROM shared.sale_target_backup WHERE snapshot_label = v_label) THEN
    RAISE EXCEPTION 'Ban chup nhan "%" da ton tai - dat nhan khac', v_label;
  END IF;

  SELECT string_agg(quote_ident(c.column_name), ', ' ORDER BY c.ordinal_position)
    INTO v_cols
  FROM information_schema.columns c
  WHERE c.table_schema = 'shared' AND c.table_name = 'sale_target'
    AND EXISTS (SELECT 1 FROM information_schema.columns b
                WHERE b.table_schema = 'shared' AND b.table_name = 'sale_target_backup'
                  AND b.column_name = c.column_name);

  EXECUTE format(
    'INSERT INTO shared.sale_target_backup (%s, snapshot_at, snapshot_label)
     SELECT %s, $1, $2 FROM shared.sale_target', v_cols, v_cols)
    USING v_at, v_label;
  GET DIAGNOSTICS v_n = ROW_COUNT;

  RETURN QUERY SELECT v_label, v_at, v_n;
END
$fn$;

-- ---------------------------------------------------------------------------
-- 3) Liệt kê các bản chụp
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.sale_target_backup_ds()
RETURNS TABLE (nhan text, thoi_diem timestamptz, so_dong bigint)
LANGUAGE sql STABLE SECURITY DEFINER
SET search_path = shared, public
AS $fn$
  SELECT snapshot_label, min(snapshot_at), count(*)
  FROM   shared.sale_target_backup
  GROUP  BY snapshot_label
  ORDER  BY 2 DESC;
$fn$;

-- ---------------------------------------------------------------------------
-- 4) So sánh 2 bản chụp, trả về TỪNG Ô đã đổi
--    loai: THEM (chỉ có ở bản mới) / XOA (chỉ có ở bản cũ) / SUA (khác giá trị)
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.diff_sale_target_backup(p_cu text, p_moi text)
RETURNS TABLE (id bigint, loai text, truong text, gia_tri_cu text, gia_tri_moi text)
LANGUAGE sql STABLE SECURITY DEFINER
SET search_path = shared, public
AS $fn$
  WITH cu AS (
    SELECT b.id, to_jsonb(b) - 'snapshot_at' - 'snapshot_label' AS d
    FROM shared.sale_target_backup b WHERE b.snapshot_label = p_cu
  ), moi AS (
    SELECT b.id, to_jsonb(b) - 'snapshot_at' - 'snapshot_label' AS d
    FROM shared.sale_target_backup b WHERE b.snapshot_label = p_moi
  ), j AS (
    SELECT coalesce(cu.id, moi.id) AS id, cu.d AS dcu, moi.d AS dmoi
    FROM cu FULL OUTER JOIN moi ON moi.id = cu.id
  )
  SELECT j.id, 'XOA'::text, NULL::text, NULL::text, NULL::text
  FROM j WHERE j.dmoi IS NULL
  UNION ALL
  SELECT j.id, 'THEM', NULL, NULL, NULL
  FROM j WHERE j.dcu IS NULL
  UNION ALL
  SELECT j.id, 'SUA', k.key, j.dcu ->> k.key, j.dmoi ->> k.key
  FROM   j CROSS JOIN LATERAL jsonb_object_keys(j.dcu) AS k(key)
  WHERE  j.dcu IS NOT NULL AND j.dmoi IS NOT NULL
    AND  (j.dcu -> k.key) IS DISTINCT FROM (j.dmoi -> k.key);
$fn$;

-- ---------------------------------------------------------------------------
-- 5) Dọn bản chụp cũ, giữ N bản gần nhất (mặc định 12)
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.cleanup_sale_target_backup(p_keep int DEFAULT 12)
RETURNS int
LANGUAGE plpgsql SECURITY DEFINER
SET search_path = shared, public
AS $fn$
DECLARE deleted int;
BEGIN
  DELETE FROM shared.sale_target_backup
  WHERE snapshot_label NOT IN (
    SELECT snapshot_label FROM shared.sale_target_backup
    GROUP BY snapshot_label ORDER BY min(snapshot_at) DESC LIMIT p_keep
  );
  GET DIAGNOSTICS deleted = ROW_COUNT;
  RETURN deleted;
END
$fn$;

-- ---------------------------------------------------------------------------
-- 6) Quyền: CHỈ service_role.
--    Không mở cho anon/authenticated vì bảng backup chứa kế hoạch của mọi team
--    và không đi qua RLS.
-- ---------------------------------------------------------------------------
REVOKE ALL ON FUNCTION public.backup_sale_target(text)           FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.sale_target_backup_ds()            FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.diff_sale_target_backup(text,text) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.cleanup_sale_target_backup(int)    FROM PUBLIC, anon, authenticated;

GRANT EXECUTE ON FUNCTION public.backup_sale_target(text)           TO service_role;
GRANT EXECUTE ON FUNCTION public.sale_target_backup_ds()            TO service_role;
GRANT EXECUTE ON FUNCTION public.diff_sale_target_backup(text,text) TO service_role;
GRANT EXECUTE ON FUNCTION public.cleanup_sale_target_backup(int)    TO service_role;

-- ---------------------------------------------------------------------------
-- KHÔI PHỤC: cố ý KHÔNG gói thành hàm một-nút-bấm, vì đây là thao tác ghi đè.
-- Xem diff trước, rồi chạy tay đúng phạm vi cần. Ví dụ trả lại 1 tháng:
--
--   UPDATE shared.sale_target s SET
--     sl_ke_hoach_update = b.sl_ke_hoach_update,
--     don_gia            = b.don_gia
--   FROM shared.sale_target_backup b
--   WHERE b.snapshot_label = 'ban-can-tra-lai'
--     AND b.id = s.id
--     AND s.thang_ke_hoach = '2026-09';
-- ---------------------------------------------------------------------------
