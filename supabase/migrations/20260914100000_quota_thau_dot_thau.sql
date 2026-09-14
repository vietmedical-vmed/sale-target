-- Hoàn thiện 2 bảng shared.dot_thau / shared.quota_thau và backfill từ sale_target.
--
-- Hai bảng đã được tạo tay trên dashboard (đang rỗng). Migration này bổ sung
-- phần còn thiếu bằng ALTER TABLE, không DROP, rồi nạp dữ liệu từ sale_target.
--
-- Lý do tách bảng: sale_target có grain là THÁNG (mỗi sản phẩm 12 dòng/năm),
-- trong khi quota thầu là dữ liệu cấp GÓI THẦU (không đổi theo tháng). Hệ quả
-- của việc nhét chung:
--   * quota nằm rải trên nhiều dòng, phải sum() mới ra tổng -> dễ nhân đôi;
--   * tháng thầu bị ghi lặp vào mọi dòng của nhóm SP;
--   * chỉ chứa được 1 đợt thầu bổ sung / năm, trong khi nghiệp vụ mới cho phép
--     nhiều đợt bổ sung trong cùng 1 năm.
--
-- Quota gắn với MỨC GIÁ (= gói thầu), không phải với sản phẩm: khảo sát FY26
-- cho thấy 82/99 nhóm SP nhiều giá có quota nằm trên từ 2 mức giá trở lên.
-- Vì vậy don_gia nằm trong khoá của quota_thau (khoá này đã có sẵn).
--
-- Migration này KHÔNG xoá cột cũ trên sale_target. Cột cũ giữ nguyên để app và
-- report hiện tại chạy bình thường cho tới khi chuyển xong.

-- ---------------------------------------------------------------------------
-- 1. Bổ sung cột cho shared.dot_thau
--    (đợt thầu cấp NHÓM SẢN PHẨM theo chốt nghiệp vụ, mỗi đợt 1 dòng)
-- ---------------------------------------------------------------------------
ALTER TABLE shared.dot_thau
  ADD COLUMN IF NOT EXISTS bu         text,
  ADD COLUMN IF NOT EXISTS mien       text,
  ADD COLUMN IF NOT EXISTS created_at timestamptz NOT NULL DEFAULT now(),
  ADD COLUMN IF NOT EXISTS updated_at timestamptz NOT NULL DEFAULT now(),
  ADD COLUMN IF NOT EXISTS updated_by text;

-- thoi_gian đang là text; sale_target.thoi_gian_thau_chinh là numeric.
-- Bảng rỗng nên đổi kiểu an toàn.
ALTER TABLE shared.dot_thau
  ALTER COLUMN thoi_gian TYPE numeric USING nullif(thoi_gian, '')::numeric;

ALTER TABLE shared.dot_thau
  ALTER COLUMN ma_khach_hang SET DEFAULT '',
  ALTER COLUMN nhom_san_pham SET DEFAULT '',
  ALTER COLUMN dot           SET DEFAULT 1;

DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'dot_thau_thang_fmt') THEN
    ALTER TABLE shared.dot_thau ADD CONSTRAINT dot_thau_thang_fmt
      CHECK (thang_thau IS NULL OR thang_thau ~ '^\d{4}-\d{2}$');
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'dot_thau_dot_duong') THEN
    ALTER TABLE shared.dot_thau ADD CONSTRAINT dot_thau_dot_duong CHECK (dot >= 1);
  END IF;
END $$;

COMMENT ON TABLE  shared.dot_thau IS 'Đợt thầu (chính / bổ sung) theo nhóm SP. Nhiều đợt bổ sung trong 1 năm = nhiều dòng.';
COMMENT ON COLUMN shared.dot_thau.dot IS 'Số thứ tự đợt trong cùng loai, bắt đầu từ 1.';

CREATE INDEX IF NOT EXISTS idx_dot_thau_lookup
  ON shared.dot_thau (nam_tai_chinh, ps, ma_khach_hang, nhom_san_pham);

-- ---------------------------------------------------------------------------
-- 2. Bổ sung cột cho shared.quota_thau
--    (quota cấp SẢN PHẨM x MỨC GIÁ x ĐỢT; loai='cu' không thuộc đợt -> dot=1)
-- ---------------------------------------------------------------------------
ALTER TABLE shared.quota_thau
  ADD COLUMN IF NOT EXISTS bu         text,
  ADD COLUMN IF NOT EXISTS mien       text,
  ADD COLUMN IF NOT EXISTS khach_hang text,
  ADD COLUMN IF NOT EXISTS created_at timestamptz NOT NULL DEFAULT now(),
  ADD COLUMN IF NOT EXISTS updated_at timestamptz NOT NULL DEFAULT now(),
  ADD COLUMN IF NOT EXISTS updated_by text;

ALTER TABLE shared.quota_thau
  ALTER COLUMN ma_khach_hang SET DEFAULT '',
  ALTER COLUMN nhom_san_pham SET DEFAULT '',
  ALTER COLUMN bo_vat_tu     SET DEFAULT '',
  ALTER COLUMN san_pham      SET DEFAULT '',
  ALTER COLUMN don_gia       SET DEFAULT 0,
  ALTER COLUMN dot           SET DEFAULT 1,
  ALTER COLUMN so_luong      SET DEFAULT 0;

DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'quota_thau_dot_duong') THEN
    ALTER TABLE shared.quota_thau ADD CONSTRAINT quota_thau_dot_duong CHECK (dot >= 1);
  END IF;
END $$;

COMMENT ON TABLE  shared.quota_thau IS 'Quota thầu theo sản phẩm x mức giá x đợt. don_gia nằm trong khoá vì quota gắn với gói thầu.';
COMMENT ON COLUMN shared.quota_thau.loai IS 'cu = thầu cũ còn lại đầu năm; chinh = thầu chính; bo_sung = thầu bổ sung.';

CREATE INDEX IF NOT EXISTS idx_quota_thau_lookup
  ON shared.quota_thau (nam_tai_chinh, ps, ma_khach_hang, nhom_san_pham);
CREATE INDEX IF NOT EXISTS idx_quota_thau_dot
  ON shared.quota_thau (nam_tai_chinh, ps, ma_khach_hang, nhom_san_pham, loai, dot);

-- ---------------------------------------------------------------------------
-- 3. Quyền: RLS đã bật sẵn trên cả 2 bảng. Chặn hẳn anon/authenticated,
--    chỉ service_role (edge function) đi qua.
-- ---------------------------------------------------------------------------
REVOKE ALL ON shared.dot_thau   FROM anon, authenticated;
REVOKE ALL ON shared.quota_thau FROM anon, authenticated;

-- ---------------------------------------------------------------------------
-- 4. Backfill từ sale_target. Chỉ lấy dòng đã gắn năm tài chính.
-- ---------------------------------------------------------------------------

-- Chuẩn hoá tháng thầu: dữ liệu cũ có 1008 dòng mang thang_thau_bo_sung = '0'
-- (rác, nghĩa là chưa có tháng) -> quy về NULL.
CREATE OR REPLACE FUNCTION shared.thang_thau_hop_le(v text)
RETURNS text LANGUAGE sql IMMUTABLE AS $$
  SELECT CASE WHEN v ~ '^\d{4}-\d{2}$' THEN v END;
$$;

-- 4a. Đợt thầu chính. Trong DB hiện có nhóm SP mang nhiều tháng thầu chính khác
--     nhau (14 nhóm ở FY26) -> mỗi tháng riêng biệt thành 1 đợt, đánh số theo
--     thứ tự tháng tăng dần. Dòng chưa có tháng gom vào 1 đợt riêng (thang NULL).
INSERT INTO shared.dot_thau
  (nam_tai_chinh, bu, mien, ps, ma_khach_hang, nhom_san_pham, loai, dot, thang_thau, thoi_gian)
SELECT nam_tai_chinh, bu, mien, ps, ma_khach_hang, nhom_san_pham, 'chinh', dot, thang_thau, thoi_gian
FROM (
  SELECT s.nam_tai_chinh,
         min(s.bu)   AS bu,
         min(s.mien) AS mien,
         s.ps,
         coalesce(s.ma_khach_hang, '') AS ma_khach_hang,
         coalesce(s.nhom_san_pham, '') AS nhom_san_pham,
         shared.thang_thau_hop_le(s.thang_thau_chinh) AS thang_thau,
         max(s.thoi_gian_thau_chinh) AS thoi_gian,
         row_number() OVER (
           PARTITION BY s.nam_tai_chinh, s.ps,
                        coalesce(s.ma_khach_hang, ''), coalesce(s.nhom_san_pham, '')
           ORDER BY shared.thang_thau_hop_le(s.thang_thau_chinh) NULLS FIRST
         ) AS dot
  FROM shared.sale_target s
  WHERE s.nam_tai_chinh IS NOT NULL
    AND (s.thang_thau_chinh IS NOT NULL OR coalesce(s.quota_thau_chinh, 0) <> 0)
  GROUP BY s.nam_tai_chinh, s.ps,
           coalesce(s.ma_khach_hang, ''), coalesce(s.nhom_san_pham, ''),
           shared.thang_thau_hop_le(s.thang_thau_chinh)
) t
ON CONFLICT (nam_tai_chinh, ps, ma_khach_hang, nhom_san_pham, loai, dot) DO NOTHING;

-- 4b. Đợt thầu bổ sung. Hiện mỗi nhóm nhiều nhất 1 tháng -> backfill ra đợt 1.
INSERT INTO shared.dot_thau
  (nam_tai_chinh, bu, mien, ps, ma_khach_hang, nhom_san_pham, loai, dot, thang_thau)
SELECT nam_tai_chinh, bu, mien, ps, ma_khach_hang, nhom_san_pham, 'bo_sung', dot, thang_thau
FROM (
  SELECT s.nam_tai_chinh,
         min(s.bu)   AS bu,
         min(s.mien) AS mien,
         s.ps,
         coalesce(s.ma_khach_hang, '') AS ma_khach_hang,
         coalesce(s.nhom_san_pham, '') AS nhom_san_pham,
         shared.thang_thau_hop_le(s.thang_thau_bo_sung) AS thang_thau,
         row_number() OVER (
           PARTITION BY s.nam_tai_chinh, s.ps,
                        coalesce(s.ma_khach_hang, ''), coalesce(s.nhom_san_pham, '')
           ORDER BY shared.thang_thau_hop_le(s.thang_thau_bo_sung) NULLS FIRST
         ) AS dot
  FROM shared.sale_target s
  WHERE s.nam_tai_chinh IS NOT NULL
    AND (s.thang_thau_bo_sung IS NOT NULL OR coalesce(s.quota_bo_sung, 0) <> 0)
  GROUP BY s.nam_tai_chinh, s.ps,
           coalesce(s.ma_khach_hang, ''), coalesce(s.nhom_san_pham, ''),
           shared.thang_thau_hop_le(s.thang_thau_bo_sung)
) t
ON CONFLICT (nam_tai_chinh, ps, ma_khach_hang, nhom_san_pham, loai, dot) DO NOTHING;

-- 4c. Quota thầu cũ còn lại. Không thuộc đợt nào -> dot = 1.
INSERT INTO shared.quota_thau
  (nam_tai_chinh, bu, mien, ps, ma_khach_hang, khach_hang, nhom_san_pham,
   bo_vat_tu, san_pham, don_gia, loai, dot, so_luong)
SELECT s.nam_tai_chinh, min(s.bu), min(s.mien), s.ps,
       coalesce(s.ma_khach_hang, ''), min(s.khach_hang),
       coalesce(s.nhom_san_pham, ''), coalesce(s.bo_vat_tu, ''),
       coalesce(s.san_pham, ''), coalesce(s.don_gia, 0),
       'cu', 1, sum(s.quota_thau_cu_con_lai)
FROM shared.sale_target s
WHERE s.nam_tai_chinh IS NOT NULL
  AND coalesce(s.quota_thau_cu_con_lai, 0) <> 0
GROUP BY s.nam_tai_chinh, s.ps, coalesce(s.ma_khach_hang, ''),
         coalesce(s.nhom_san_pham, ''), coalesce(s.bo_vat_tu, ''),
         coalesce(s.san_pham, ''), coalesce(s.don_gia, 0)
ON CONFLICT (nam_tai_chinh, ps, ma_khach_hang, nhom_san_pham, bo_vat_tu,
             san_pham, don_gia, loai, dot) DO NOTHING;

-- 4d. Quota thầu chính, gắn về đúng đợt qua tháng thầu của chính dòng đó.
INSERT INTO shared.quota_thau
  (nam_tai_chinh, bu, mien, ps, ma_khach_hang, khach_hang, nhom_san_pham,
   bo_vat_tu, san_pham, don_gia, loai, dot, so_luong)
SELECT s.nam_tai_chinh, min(s.bu), min(s.mien), s.ps,
       coalesce(s.ma_khach_hang, ''), min(s.khach_hang),
       coalesce(s.nhom_san_pham, ''), coalesce(s.bo_vat_tu, ''),
       coalesce(s.san_pham, ''), coalesce(s.don_gia, 0),
       'chinh', coalesce(d.dot, 1), sum(s.quota_thau_chinh)
FROM shared.sale_target s
LEFT JOIN shared.dot_thau d
       ON d.nam_tai_chinh = s.nam_tai_chinh
      AND d.ps            = s.ps
      AND d.ma_khach_hang = coalesce(s.ma_khach_hang, '')
      AND d.nhom_san_pham = coalesce(s.nhom_san_pham, '')
      AND d.loai          = 'chinh'
      AND d.thang_thau IS NOT DISTINCT FROM shared.thang_thau_hop_le(s.thang_thau_chinh)
WHERE s.nam_tai_chinh IS NOT NULL
  AND coalesce(s.quota_thau_chinh, 0) <> 0
GROUP BY s.nam_tai_chinh, s.ps, coalesce(s.ma_khach_hang, ''),
         coalesce(s.nhom_san_pham, ''), coalesce(s.bo_vat_tu, ''),
         coalesce(s.san_pham, ''), coalesce(s.don_gia, 0), coalesce(d.dot, 1)
ON CONFLICT (nam_tai_chinh, ps, ma_khach_hang, nhom_san_pham, bo_vat_tu,
             san_pham, don_gia, loai, dot) DO NOTHING;

-- 4e. Quota thầu bổ sung, tương tự 4d.
INSERT INTO shared.quota_thau
  (nam_tai_chinh, bu, mien, ps, ma_khach_hang, khach_hang, nhom_san_pham,
   bo_vat_tu, san_pham, don_gia, loai, dot, so_luong)
SELECT s.nam_tai_chinh, min(s.bu), min(s.mien), s.ps,
       coalesce(s.ma_khach_hang, ''), min(s.khach_hang),
       coalesce(s.nhom_san_pham, ''), coalesce(s.bo_vat_tu, ''),
       coalesce(s.san_pham, ''), coalesce(s.don_gia, 0),
       'bo_sung', coalesce(d.dot, 1), sum(s.quota_bo_sung)
FROM shared.sale_target s
LEFT JOIN shared.dot_thau d
       ON d.nam_tai_chinh = s.nam_tai_chinh
      AND d.ps            = s.ps
      AND d.ma_khach_hang = coalesce(s.ma_khach_hang, '')
      AND d.nhom_san_pham = coalesce(s.nhom_san_pham, '')
      AND d.loai          = 'bo_sung'
      AND d.thang_thau IS NOT DISTINCT FROM shared.thang_thau_hop_le(s.thang_thau_bo_sung)
WHERE s.nam_tai_chinh IS NOT NULL
  AND coalesce(s.quota_bo_sung, 0) <> 0
GROUP BY s.nam_tai_chinh, s.ps, coalesce(s.ma_khach_hang, ''),
         coalesce(s.nhom_san_pham, ''), coalesce(s.bo_vat_tu, ''),
         coalesce(s.san_pham, ''), coalesce(s.don_gia, 0), coalesce(d.dot, 1)
ON CONFLICT (nam_tai_chinh, ps, ma_khach_hang, nhom_san_pham, bo_vat_tu,
             san_pham, don_gia, loai, dot) DO NOTHING;

-- ---------------------------------------------------------------------------
-- 5. View tương thích ngược cho report đang đọc quota từ sale_target.
--    Trả đúng 3 con số cũ, cộng thêm quota tiền tính theo từng mức giá.
-- ---------------------------------------------------------------------------
CREATE OR REPLACE VIEW shared.v_quota_thau_tong AS
SELECT nam_tai_chinh, bu, mien, ps, ma_khach_hang, khach_hang, nhom_san_pham,
       bo_vat_tu, san_pham,
       sum(so_luong) FILTER (WHERE loai = 'cu')      AS quota_thau_cu_con_lai,
       sum(so_luong) FILTER (WHERE loai = 'chinh')   AS quota_thau_chinh,
       sum(so_luong) FILTER (WHERE loai = 'bo_sung') AS quota_bo_sung,
       sum(so_luong)                                  AS quota_tong,
       sum(so_luong * don_gia)                        AS quota_tong_tien
FROM shared.quota_thau
GROUP BY nam_tai_chinh, bu, mien, ps, ma_khach_hang, khach_hang, nhom_san_pham,
         bo_vat_tu, san_pham;

COMMENT ON VIEW shared.v_quota_thau_tong IS 'Tổng quota theo sản phẩm, giữ tên cột như sale_target cũ. quota_tong_tien nhân đúng theo từng mức giá.';
