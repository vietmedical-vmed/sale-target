-- View xuất quota thầu gộp 2 nguồn: shared.quota_thau (nguồn mới) và các cột
-- quota cũ trên shared.sale_target. Mỗi dòng = sản phẩm × mức giá × loại × đợt.
--
-- Quy tắc chọn nguồn (giống app):
--   * Nhóm SP đã khai đợt (shared.dot_thau) hoặc sản phẩm đã có dòng
--     shared.quota_thau → lấy quota_thau, tháng thầu theo TỪNG ĐỢT. Bỏ qua cột
--     cũ: cột cũ chỉ nhận số tổng đồng bộ một chiều và không có tháng của đợt.
--   * Còn lại → cột cũ trên sale_target (bỏ dòng ngoài kế hoạch), cộng theo
--     sản phẩm × mức giá × tháng thầu.
-- trang_thai so với shared.app_config.current_month: thầu cũ luôn On hand,
-- đợt chưa điền tháng tính Upcoming.
-- canh_bao: quota mà kế hoạch không còn dòng khớp (app không hiện các dòng này).
--
-- Tạm thời chỉ admin dùng: không cấp cho anon/authenticated, edge function
-- (service_role) đọc và tự kiểm role admin.

CREATE OR REPLACE VIEW shared.v_quota_thau_xuat
WITH (security_invoker = true) AS
WITH
cur AS (
  SELECT value #>> '{}' AS thang FROM shared.app_config WHERE key = 'current_month'
),
ke_hoach AS (
  SELECT * FROM shared.sale_target
  WHERE nam_tai_chinh IS NOT NULL AND NOT coalesce(ngoai_ke_hoach, false)
),
nhom_co_dot AS (
  SELECT DISTINCT nam_tai_chinh, ps, ma_khach_hang, nhom_san_pham FROM shared.dot_thau
),
sp_co_quota AS (
  SELECT DISTINCT nam_tai_chinh, ps, ma_khach_hang, nhom_san_pham, bo_vat_tu, san_pham
  FROM shared.quota_thau
),
-- Khoá sản phẩm × mức giá đang có trên kế hoạch. Gom DISTINCT trước rồi hash
-- join: EXISTS tương quan trên CTE quét lại cả sale_target cho từng dòng quota.
kh_gia AS (
  SELECT DISTINCT nam_tai_chinh, ps, coalesce(ma_khach_hang, '') AS ma_khach_hang,
         coalesce(nhom_san_pham, '') AS nhom_san_pham, coalesce(bo_vat_tu, '') AS bo_vat_tu,
         coalesce(san_pham, '') AS san_pham, coalesce(don_gia, 0) AS don_gia
  FROM ke_hoach
),
kh_sp AS (
  SELECT DISTINCT nam_tai_chinh, ps, ma_khach_hang, nhom_san_pham, bo_vat_tu, san_pham
  FROM kh_gia
),
-- A. Nguồn mới
moi AS (
  SELECT q.nam_tai_chinh, q.bu, q.mien, q.ps, q.ma_khach_hang, q.khach_hang,
         q.nhom_san_pham, q.bo_vat_tu, q.san_pham, q.don_gia, q.loai, q.dot,
         d.thang_thau, q.so_luong,
         'quota_thau'::text AS nguon,
         CASE
           WHEN g.san_pham IS NOT NULL THEN NULL
           WHEN p.san_pham IS NOT NULL THEN 'Mức giá không còn trên kế hoạch'
           ELSE 'Sản phẩm không còn trên kế hoạch'
         END AS canh_bao
  FROM shared.quota_thau q
  LEFT JOIN shared.dot_thau d
         ON d.nam_tai_chinh = q.nam_tai_chinh AND d.ps = q.ps
        AND d.ma_khach_hang = q.ma_khach_hang AND d.nhom_san_pham = q.nhom_san_pham
        AND d.loai = q.loai AND d.dot = q.dot AND q.loai <> 'cu'
  LEFT JOIN kh_gia g
         ON g.nam_tai_chinh = q.nam_tai_chinh AND g.ps = q.ps
        AND g.ma_khach_hang = q.ma_khach_hang AND g.nhom_san_pham = q.nhom_san_pham
        AND g.bo_vat_tu = q.bo_vat_tu AND g.san_pham = q.san_pham AND g.don_gia = q.don_gia
  LEFT JOIN kh_sp p
         ON p.nam_tai_chinh = q.nam_tai_chinh AND p.ps = q.ps
        AND p.ma_khach_hang = q.ma_khach_hang AND p.nhom_san_pham = q.nhom_san_pham
        AND p.bo_vat_tu = q.bo_vat_tu AND p.san_pham = q.san_pham
  WHERE q.so_luong <> 0
),
-- B. Cột cũ: chỉ sản phẩm chưa chuyển sang nguồn mới
cu_raw AS (
  SELECT s.* FROM ke_hoach s
  WHERE NOT EXISTS (SELECT 1 FROM nhom_co_dot g
                    WHERE g.nam_tai_chinh = s.nam_tai_chinh AND g.ps = s.ps
                      AND g.ma_khach_hang = coalesce(s.ma_khach_hang, '')
                      AND g.nhom_san_pham = coalesce(s.nhom_san_pham, ''))
    AND NOT EXISTS (SELECT 1 FROM sp_co_quota p
                    WHERE p.nam_tai_chinh = s.nam_tai_chinh AND p.ps = s.ps
                      AND p.ma_khach_hang = coalesce(s.ma_khach_hang, '')
                      AND p.nhom_san_pham = coalesce(s.nhom_san_pham, '')
                      AND p.bo_vat_tu = coalesce(s.bo_vat_tu, '')
                      AND p.san_pham = coalesce(s.san_pham, ''))
),
cu AS (
  SELECT s.nam_tai_chinh, min(s.bu) AS bu, min(s.mien) AS mien, s.ps,
         coalesce(s.ma_khach_hang, '') AS ma_khach_hang, min(s.khach_hang) AS khach_hang,
         coalesce(s.nhom_san_pham, '') AS nhom_san_pham, coalesce(s.bo_vat_tu, '') AS bo_vat_tu,
         coalesce(s.san_pham, '') AS san_pham, coalesce(s.don_gia, 0) AS don_gia,
         x.loai, NULL::int AS dot, x.thang AS thang_thau, sum(x.sl) AS so_luong,
         'sale_target (cột cũ)'::text AS nguon, NULL::text AS canh_bao
  FROM cu_raw s
  CROSS JOIN LATERAL (VALUES
    ('cu',      NULL::text,                                     coalesce(s.quota_thau_cu_con_lai, 0)),
    ('chinh',   shared.thang_thau_hop_le(s.thang_thau_chinh),   coalesce(s.quota_thau_chinh, 0)),
    ('bo_sung', shared.thang_thau_hop_le(s.thang_thau_bo_sung), coalesce(s.quota_bo_sung, 0))
  ) x(loai, thang, sl)
  WHERE x.sl <> 0
  GROUP BY s.nam_tai_chinh, s.ps, coalesce(s.ma_khach_hang, ''), coalesce(s.nhom_san_pham, ''),
           coalesce(s.bo_vat_tu, ''), coalesce(s.san_pham, ''), coalesce(s.don_gia, 0),
           x.loai, x.thang
)
SELECT
  -- stt duy nhất và ổn định để edge function phân trang theo .order('stt').
  row_number() OVER (ORDER BY u.nam_tai_chinh, u.bu, u.ps, u.ma_khach_hang, u.nhom_san_pham,
                              u.bo_vat_tu, u.san_pham, u.don_gia, u.loai, u.dot,
                              u.thang_thau, u.nguon) AS stt,
  u.*,
  u.so_luong * u.don_gia AS thanh_tien,
  CASE WHEN u.loai = 'cu' OR (u.thang_thau IS NOT NULL AND u.thang_thau <= cur.thang)
       THEN 'On hand' ELSE 'Upcoming' END AS trang_thai
FROM (SELECT * FROM moi UNION ALL SELECT * FROM cu) u
LEFT JOIN cur ON true;

COMMENT ON VIEW shared.v_quota_thau_xuat IS
  'Quota thầu gộp quota_thau + cột cũ sale_target, theo SP × mức giá × loại × đợt. Chỉ admin (qua edge function).';

REVOKE ALL ON shared.v_quota_thau_xuat FROM PUBLIC, anon, authenticated, service_role;
GRANT SELECT ON shared.v_quota_thau_xuat TO service_role;
