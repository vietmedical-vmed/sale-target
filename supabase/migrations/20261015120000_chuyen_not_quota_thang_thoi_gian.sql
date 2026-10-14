-- Chuẩn hoá quota (B): chuyển nốt thông tin quota còn sót trên sale_target.
--   B1. Quota cột cũ mà quota_thau chưa có khoá × loại đó (app đang ẩn) → quota
--       CHỜ DUYỆT. Bỏ dòng trùng quota cũ user đã chốt xoá (log xoa_quota_cu_xung_dot).
--       Khoá trùng loại với quota_thau đang có (số khác) không chèn được → duyệt tay.
--   B2. Tháng thầu chỉ có tháng, chưa có đợt cùng tháng và không kèm quota tháng đó
--       → đợt CHỜ DUYỆT (không lên app cho tới khi admin duyệt ở tab Quota chờ duyệt).
--   B3. Thời gian (hiệu lực) thầu chính → điền vào đợt chính cùng tháng đang trống
--       thời gian, khi cột cũ chỉ có đúng 1 giá trị cho nhóm × tháng đó.
-- Mọi thay đổi ghi vào shared.quota_chuan_hoa_log (buoc = chuyen_not_*).

BEGIN;

CREATE TEMP TABLE _st ON COMMIT DROP AS
SELECT s.nam_tai_chinh fy, coalesce(s.ps,'') ps, coalesce(s.ma_khach_hang,'') cust, coalesce(s.nhom_san_pham,'') grp,
       coalesce(s.bo_vat_tu,'') mset, coalesce(s.san_pham,'') prod, coalesce(s.don_gia,0) gia,
       x.loai, x.thang, sum(x.sl) sl, max(x.tg) tg, min(s.bu) bu, min(s.mien) mien, min(s.khach_hang) khach_hang
FROM shared.sale_target s
CROSS JOIN LATERAL (VALUES
  ('cu', NULL::text, coalesce(s.quota_thau_cu_con_lai,0), NULL::numeric),
  ('chinh', shared.thang_thau_hop_le(s.thang_thau_chinh), coalesce(s.quota_thau_chinh,0), s.thoi_gian_thau_chinh),
  ('bo_sung', shared.thang_thau_hop_le(s.thang_thau_bo_sung), coalesce(s.quota_bo_sung,0), NULL::numeric)) x(loai, thang, sl, tg)
WHERE x.sl <> 0 AND coalesce(s.bu,'') <> 'test' AND s.nam_tai_chinh IS NOT NULL
GROUP BY 1,2,3,4,5,6,7,8,9;

-- B1: khoá × loại cột cũ chưa có trong quota_thau (và không phải bản sao sync)
CREATE TEMP TABLE _b1 ON COMMIT DROP AS
WITH stk AS (SELECT fy,ps,cust,grp,mset,prod,gia,loai, sum(sl) sl FROM _st GROUP BY 1,2,3,4,5,6,7,8),
qt  AS (SELECT nam_tai_chinh fy, ps, ma_khach_hang cust, nhom_san_pham grp, bo_vat_tu mset, san_pham prod, don_gia gia, loai, sum(so_luong) sl FROM shared.quota_thau GROUP BY 1,2,3,4,5,6,7,8),
qp  AS (SELECT nam_tai_chinh fy, ps, ma_khach_hang cust, nhom_san_pham grp, bo_vat_tu mset, san_pham prod, loai, sum(so_luong) sl FROM shared.quota_thau GROUP BY 1,2,3,4,5,6,7),
qpa AS (SELECT nam_tai_chinh fy, ps, ma_khach_hang cust, nhom_san_pham grp, bo_vat_tu mset, san_pham prod, sum(so_luong) sl FROM shared.quota_thau GROUP BY 1,2,3,4,5,6),
spa AS (SELECT fy,ps,cust,grp,mset,prod, sum(sl) sl FROM stk GROUP BY 1,2,3,4,5,6)
SELECT stk.* FROM stk
LEFT JOIN qt  USING (fy,ps,cust,grp,mset,prod,gia,loai)
LEFT JOIN qp  USING (fy,ps,cust,grp,mset,prod,loai)
LEFT JOIN qpa USING (fy,ps,cust,grp,mset,prod)
JOIN spa USING (fy,ps,cust,grp,mset,prod)
WHERE qt.sl IS NULL
  AND coalesce(qp.sl,-1) <> stk.sl
  AND spa.sl <> coalesce(qpa.sl,-1)
  AND NOT EXISTS (SELECT 1 FROM shared.quota_chuan_hoa_log l
                  WHERE l.buoc = 'xoa_quota_cu_xung_dot' AND l.truoc->>'ps' = stk.ps
                    AND l.truoc->>'ma_khach_hang' = stk.cust AND l.truoc->>'san_pham' = stk.prod
                    AND l.truoc->>'loai' = stk.loai AND (l.truoc->>'so_luong')::numeric = stk.sl);

-- Đợt đích: B1 (theo tháng của quota) + B2 (tháng không kèm quota, chưa có đợt cùng tháng)
CREATE TEMP TABLE _can_dot ON COMMIT DROP AS
SELECT s.fy, s.ps, s.cust, s.grp, s.loai, s.thang, max(s.tg) tg, min(s.bu) bu, min(s.mien) mien
FROM _st s JOIN _b1 b USING (fy,ps,cust,grp,mset,prod,gia,loai)
WHERE s.loai <> 'cu'
GROUP BY 1,2,3,4,5,6
UNION ALL
SELECT t.fy, t.ps, t.cust, t.grp, t.loai, t.thang, max(t.tg), min(t.bu), min(t.mien)
FROM (
  SELECT s.nam_tai_chinh fy, coalesce(s.ps,'') ps, coalesce(s.ma_khach_hang,'') cust, coalesce(s.nhom_san_pham,'') grp,
         x.loai, x.thang, x.tg, s.bu, s.mien
  FROM shared.sale_target s
  CROSS JOIN LATERAL (VALUES
    ('chinh', shared.thang_thau_hop_le(s.thang_thau_chinh), s.thoi_gian_thau_chinh),
    ('bo_sung', shared.thang_thau_hop_le(s.thang_thau_bo_sung), NULL::numeric)) x(loai, thang, tg)
  WHERE x.thang IS NOT NULL AND coalesce(s.bu,'') <> 'test' AND s.nam_tai_chinh IS NOT NULL
) t
WHERE NOT EXISTS (SELECT 1 FROM _st q WHERE q.fy=t.fy AND q.ps=t.ps AND q.cust=t.cust AND q.grp=t.grp
                                        AND q.loai=t.loai AND q.thang=t.thang)
GROUP BY 1,2,3,4,5,6;

CREATE TEMP TABLE _dot ON COMMIT DROP AS
WITH g AS (
  SELECT fy, ps, cust, grp, loai, thang, max(tg) tg, min(bu) bu, min(mien) mien FROM _can_dot GROUP BY 1,2,3,4,5,6),
co AS (
  SELECT g.*, (SELECT min(d.dot) FROM shared.dot_thau d
               WHERE d.nam_tai_chinh=g.fy AND d.ps=g.ps AND d.ma_khach_hang=g.cust AND d.nhom_san_pham=g.grp
                 AND d.loai=g.loai AND d.thang_thau IS NOT DISTINCT FROM g.thang) dot_co FROM g),
mx AS (
  SELECT fy, ps, cust, grp, loai, max(dot) max_dot FROM (
    SELECT nam_tai_chinh fy, ps, ma_khach_hang cust, nhom_san_pham grp, loai, dot FROM shared.dot_thau
    UNION ALL SELECT nam_tai_chinh, ps, ma_khach_hang, nhom_san_pham, loai, dot FROM shared.quota_thau WHERE loai <> 'cu') u
  GROUP BY 1,2,3,4,5)
SELECT co.*, coalesce(co.dot_co, coalesce(mx.max_dot,0)
         + row_number() OVER (PARTITION BY co.fy, co.ps, co.cust, co.grp, co.loai, (co.dot_co IS NULL) ORDER BY co.thang NULLS FIRST)) dot,
       co.dot_co IS NULL tao_moi
FROM co LEFT JOIN mx ON mx.fy=co.fy AND mx.ps=co.ps AND mx.cust=co.cust AND mx.grp=co.grp AND mx.loai=co.loai;

WITH moi AS (
  INSERT INTO shared.dot_thau (nam_tai_chinh, bu, mien, ps, ma_khach_hang, nhom_san_pham, loai, dot, thang_thau, thoi_gian,
                               updated_by, trang_thai, nguon)
  SELECT fy, bu, mien, ps, cust, grp, loai, dot, thang, tg, 'chuan_hoa_20261015', 'cho_duyet', 'cot_cu_20261015'
  FROM _dot WHERE tao_moi
  RETURNING *)
INSERT INTO shared.quota_chuan_hoa_log (buoc, bang, ban_ghi_id, sau)
SELECT 'chuyen_not_dot', 'dot_thau', id, to_jsonb(moi) FROM moi;

WITH moi AS (
  INSERT INTO shared.quota_thau (nam_tai_chinh, bu, mien, ps, ma_khach_hang, khach_hang, nhom_san_pham, bo_vat_tu, san_pham,
                                 don_gia, loai, dot, so_luong, updated_by, trang_thai, nguon)
  SELECT s.fy, min(s.bu), min(s.mien), s.ps, s.cust, min(s.khach_hang), s.grp, s.mset, s.prod, s.gia, s.loai,
         coalesce(d.dot, 1), sum(s.sl), 'chuan_hoa_20261015', 'cho_duyet', 'cot_cu_20261015'
  FROM _st s
  JOIN _b1 b USING (fy,ps,cust,grp,mset,prod,gia,loai)
  LEFT JOIN _dot d ON d.fy=s.fy AND d.ps=s.ps AND d.cust=s.cust AND d.grp=s.grp AND d.loai=s.loai
                  AND d.thang IS NOT DISTINCT FROM s.thang AND s.loai <> 'cu'
  GROUP BY s.fy, s.ps, s.cust, s.grp, s.mset, s.prod, s.gia, s.loai, coalesce(d.dot, 1)
  RETURNING *)
INSERT INTO shared.quota_chuan_hoa_log (buoc, bang, ban_ghi_id, sau)
SELECT 'chuyen_not_quota', 'quota_thau', id, to_jsonb(moi) FROM moi;

-- B3: thời gian thầu chính → đợt chính cùng tháng đang trống thời gian
CREATE TEMP TABLE _tg ON COMMIT DROP AS
SELECT s.nam_tai_chinh fy, coalesce(s.ps,'') ps, coalesce(s.ma_khach_hang,'') cust, coalesce(s.nhom_san_pham,'') grp,
       shared.thang_thau_hop_le(s.thang_thau_chinh) thang, min(s.thoi_gian_thau_chinh) tg
FROM shared.sale_target s
WHERE s.thoi_gian_thau_chinh IS NOT NULL AND coalesce(s.bu,'') <> 'test' AND s.nam_tai_chinh IS NOT NULL
GROUP BY 1,2,3,4,5 HAVING count(DISTINCT s.thoi_gian_thau_chinh) = 1;

WITH truoc AS (
  SELECT d.* FROM shared.dot_thau d
  JOIN _tg t ON t.fy=d.nam_tai_chinh AND t.ps=d.ps AND t.cust=d.ma_khach_hang AND t.grp=d.nhom_san_pham
            AND d.loai='chinh' AND d.thang_thau IS NOT DISTINCT FROM t.thang
  WHERE d.thoi_gian IS NULL),
doi AS (
  UPDATE shared.dot_thau d SET thoi_gian = t.tg, updated_at = now(), updated_by = 'chuan_hoa_20261015'
  FROM _tg t
  WHERE t.fy=d.nam_tai_chinh AND t.ps=d.ps AND t.cust=d.ma_khach_hang AND t.grp=d.nhom_san_pham
    AND d.loai='chinh' AND d.thang_thau IS NOT DISTINCT FROM t.thang AND d.thoi_gian IS NULL
  RETURNING d.*)
INSERT INTO shared.quota_chuan_hoa_log (buoc, bang, ban_ghi_id, truoc, sau)
SELECT 'chuyen_not_thoi_gian', 'dot_thau', d.id, to_jsonb(t), to_jsonb(d) FROM doi d JOIN truoc t ON t.id = d.id;

COMMIT;
