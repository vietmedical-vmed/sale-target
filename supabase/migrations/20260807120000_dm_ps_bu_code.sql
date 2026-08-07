-- ════════════════════════════════════════════════════════════════════════
-- shared.dm_ps: thêm bu_code — mã team dùng trong dữ liệu kế hoạch
--
-- VẤN ĐỀ
-- dm_ps.bu là tên đầy đủ của BU ('CH&CS', 'CTTM & CTUT', 'THNS & CSVT'), còn
-- sale_target.bu / token đăng nhập dùng mã ngắn ('chcs', 'cttm', 'thnk').
-- Không quy đổi được bằng lower()+bỏ ký tự đặc biệt:
--   'CH&CS'       -> 'chcs'      ✔ trùng
--   'CTTM & CTUT' -> 'cttmctut'  ✘ (kế hoạch dùng 'cttm')
--   'THNS & CSVT' -> 'thnscsvt'  ✘ (kế hoạch dùng 'thnk')
-- Nên nếu lấy thẳng dm_ps.bu để gắn team cho dòng mới thì gắn SAI TEAM.
--
-- CÁCH LÀM
-- Thêm cột bu_code và điền theo THỨ TỰ ƯU TIÊN:
--   1) Suy từ chính dữ liệu kế hoạch (bu của PS đó trong sale_target) — đây là
--      giá trị mà báo cáo đang thực sự dùng, nên nó là chân lý.
--   2) PS chưa có dòng kế hoạch nào → ánh xạ theo tên BU đầy đủ.
-- Ánh xạ ở bước 2 đã được đối chiếu với dữ liệu thật (20 PS có dòng kế hoạch,
-- 0 mâu thuẫn): CH&CS=chcs (10 PS), CTTM & CTUT=cttm (1 PS), THNS & CSVT=thnk (9 PS).
--
-- Idempotent: chạy lại chỉ điền cho dòng còn trống + in lại cảnh báo.
-- ════════════════════════════════════════════════════════════════════════

ALTER TABLE shared.dm_ps ADD COLUMN IF NOT EXISTS bu_code text;

COMMENT ON COLUMN shared.dm_ps.bu_code IS
  'Mã team khớp sale_target.bu / token (chcs, cttm, thnk…). dm_ps.bu là tên đầy đủ, KHÔNG dùng trực tiếp để gắn team.';

-- 1) Suy từ dữ liệu kế hoạch: bu xuất hiện nhiều nhất của PS đó.
WITH tu_ke_hoach AS (
  SELECT ps_n, bu, row_number() OVER (PARTITION BY ps_n ORDER BY n DESC, bu) AS rn
  FROM (
    SELECT lower(btrim(s.ps)) AS ps_n, s.bu, count(*) AS n
    FROM   shared.sale_target s
    WHERE  coalesce(btrim(s.ps), '') <> '' AND coalesce(btrim(s.bu), '') <> ''
    GROUP  BY 1, 2
  ) t
)
UPDATE shared.dm_ps d
   SET bu_code = k.bu
  FROM tu_ke_hoach k
 WHERE k.rn = 1
   AND lower(btrim(d.ps)) = k.ps_n
   AND d.bu_code IS DISTINCT FROM k.bu;

-- 2) PS chưa có dòng kế hoạch nào → theo tên BU đầy đủ.
UPDATE shared.dm_ps SET bu_code = CASE btrim(bu)
    WHEN 'CH&CS'       THEN 'chcs'
    WHEN 'CTTM & CTUT' THEN 'cttm'
    WHEN 'THNS & CSVT' THEN 'thnk'
  END
 WHERE bu_code IS NULL;

-- 3) Cảnh báo: BU chưa có trong bảng ánh xạ, hoặc ps trùng nhau.
DO $$
DECLARE
  v_missing text;
  v_dup     text;
BEGIN
  SELECT string_agg(DISTINCT bu, ', ') INTO v_missing
    FROM shared.dm_ps WHERE bu_code IS NULL;
  IF v_missing IS NOT NULL THEN
    RAISE WARNING 'dm_ps.bu_code: chưa ánh xạ được BU [%] — bổ sung vào migration này rồi chạy lại', v_missing;
  END IF;

  SELECT string_agg(k, ', ') INTO v_dup FROM (
    SELECT lower(btrim(ps)) k FROM shared.dm_ps GROUP BY 1 HAVING count(*) > 1
  ) t;
  IF v_dup IS NOT NULL THEN
    RAISE WARNING 'dm_ps: có ps trùng [%] — tra PS theo tên sẽ nhân dòng', v_dup;
  END IF;
END $$;

-- Tra PS theo tên rút gọn (edge function dùng cho mọi lượt gán PS/miền/team).
CREATE INDEX IF NOT EXISTS idx_dm_ps_ps ON shared.dm_ps (lower(btrim(ps)));

-- ── Đối chiếu: PS lệch tên giữa dm_ps và kế hoạch ────────────────────────
-- Lệch tên = hoá đơn của PS đó KHÔNG BAO GIỜ khớp dòng kế hoạch (khoá khớp có
-- cột ps), toàn bộ số rơi sang "ngoài kế hoạch" mà không có lỗi nào báo ra.
-- View này để soi bằng mắt; KHÔNG tự sửa vì phải người có nghiệp vụ quyết định
-- bên nào là tên đúng.
CREATE OR REPLACE VIEW shared.v_dm_ps_lech_ten AS
SELECT 'chỉ có trong kế hoạch'::text AS tinh_trang,
       s.ps, NULL::text AS ten_ps, s.bu AS bu_code, NULL::text AS trang_thai,
       count(*) AS so_dong_ke_hoach
FROM   shared.sale_target s
WHERE  coalesce(btrim(s.ps), '') <> ''
  AND  NOT EXISTS (SELECT 1 FROM shared.dm_ps d
                    WHERE lower(btrim(d.ps)) = lower(btrim(s.ps)))
GROUP  BY s.ps, s.bu
UNION ALL
SELECT 'chỉ có trong dm_ps'::text,
       d.ps, d.ten_ps, d.bu_code, d.trang_thai, 0
FROM   shared.dm_ps d
WHERE  NOT EXISTS (SELECT 1 FROM shared.sale_target s
                    WHERE lower(btrim(s.ps)) = lower(btrim(d.ps)));

GRANT SELECT ON shared.v_dm_ps_lech_ten TO service_role;

COMMENT ON VIEW shared.v_dm_ps_lech_ten IS
  'PS lệch tên giữa dm_ps và sale_target. "chỉ có trong kế hoạch" + số dòng > 0 = hoá đơn của PS đó đang rơi hết sang ngoài kế hoạch.';

ANALYZE shared.dm_ps;
