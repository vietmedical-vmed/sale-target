-- Đổi tên SP (và mã, giá nếu cần) cho các dòng kế hoạch FY26 CH&CS còn "Chưa có" mã
-- vì tên trên kế hoạch lệch danh mục. Ánh xạ do user chỉ định 28/10:
--   Kim chọc dò cuống sống VPL @2.000.000 → Kim dò cuống sống VPL [V-PLASTY] @1.400.000
--   Kim chọc dò cuống sống VPL @2.500.000 → Khoan tay [KSDRILL]
--   Cột sống Ulrich, SP trống @6.500.000  → Xi măng cột sống [01-0350] — danh mục xếp ở
--                                          nhóm BXMCS / "Vật tư riêng lẻ - CHCS Khác"
--   Miếng ghép cầu lồi                    → Miếng ghép lồi cầu đùi [2603-2803]
--   Vít chốt cố định khớp cùng đòn        → Vít chốt khớp cùng đòn [AR-2270]
--   Vít neo Swivelock @11.100.000         → Vít neo Swivelock BC [AR-2324BCC]
--   Vít neo Swivelock @13.400.000         → Vít neo Swivelock BC kèm chỉ — 2 mã cùng giá
--                                          (AR-2324BCCT / AR-2324BCCTT): mã KH đó mua nhiều
--                                          nhất, chưa mua thì mã bán nhiều nhất (như 20261028130000)
-- Đổi giá thì DThu KH đầu năm tính lại = SL đầu năm × giá mới (quy tắc của app).
-- Dòng về cùng khoá → hoãn uq_sale_target_khoa, gộp bằng gop_dong_trung_sale_target.
-- Quota đi theo khoá mới nhờ trg_sale_target_giu_khoa_quota (giá Kim VPL đổi theo);
-- quota trigger để lại vì khoá đích đã có cùng loại × đợt thì cộng vào quota đích.
-- Hoàn tác: supabase/rollbacks/20261028140000_map_ten_sp_chua_co_ROLLBACK.sql

BEGIN;

CREATE TABLE backup.map_ten_sp_20261028 (
  nhom_cu text, san_pham_cu text, gia_cu numeric,
  nhom_moi text, bo_vat_tu_moi text, san_pham_moi text, gia_moi numeric, ma_moi text);
INSERT INTO backup.map_ten_sp_20261028 VALUES
  ('BXMCS', 'Kim chọc dò cuống sống VPL', 2000000, 'BXMCS', NULL, 'Kim dò cuống sống VPL', 1400000, 'V-PLASTY'),
  ('BXMCS', 'Kim chọc dò cuống sống VPL', 2500000, 'BXMCS', NULL, 'Khoan tay', 2500000, 'KSDRILL'),
  ('Cột sống Ulrich', '', 6500000, 'BXMCS', 'Vật tư riêng lẻ - CHCS Khác', 'Xi măng cột sống', 6500000, '01-0350'),
  ('Khớp UOC', 'Miếng ghép cầu lồi', 11600000, 'Khớp UOC', NULL, 'Miếng ghép lồi cầu đùi', 11600000, '2603-2803'),
  ('NSK Arthrex', 'Vít chốt cố định khớp cùng đòn', 5200000, 'NSK Arthrex', NULL, 'Vít chốt khớp cùng đòn', 5200000, 'AR-2270'),
  ('NSK Arthrex', 'Vít neo Swivelock', 11100000, 'NSK Arthrex', NULL, 'Vít neo Swivelock BC', 11100000, 'AR-2324BCC'),
  ('NSK Arthrex', 'Vít neo Swivelock', 13400000, 'NSK Arthrex', NULL, 'Vít neo Swivelock BC kèm chỉ', 13400000, NULL);
ALTER TABLE backup.map_ten_sp_20261028 ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON backup.map_ten_sp_20261028 FROM PUBLIC, anon, authenticated;

CREATE TABLE backup.bak_20261028_map_ten_sp_sale_target AS
SELECT s.* FROM shared.sale_target s
JOIN backup.map_ten_sp_20261028 m
  ON m.nhom_cu = s.nhom_san_pham AND m.san_pham_cu = coalesce(s.san_pham, '') AND m.gia_cu = coalesce(s.don_gia, 0)
WHERE s.nam_tai_chinh = 'FY26' AND NOT coalesce(s.ngoai_ke_hoach, false)
  AND shared.ma_sp_hop_le(s.ma_san_pham) IS NULL;
ALTER TABLE backup.bak_20261028_map_ten_sp_sale_target ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON backup.bak_20261028_map_ten_sp_sale_target FROM PUBLIC, anon, authenticated;

CREATE TABLE backup.bak_20261028_map_ten_sp_quota AS
SELECT q.* FROM shared.quota_thau q
JOIN backup.map_ten_sp_20261028 m
  ON (m.nhom_cu = q.nhom_san_pham AND m.san_pham_cu = q.san_pham AND m.gia_cu = q.don_gia)
  OR (m.nhom_moi = q.nhom_san_pham AND m.san_pham_moi = q.san_pham AND m.gia_moi = q.don_gia)
WHERE q.nam_tai_chinh = 'FY26';
ALTER TABLE backup.bak_20261028_map_ten_sp_quota ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON backup.bak_20261028_map_ten_sp_quota FROM PUBLIC, anon, authenticated;

-- Mã cho từng KH (Vít neo Swivelock BC kèm chỉ: theo hoá đơn).
CREATE TEMP TABLE _ma_kh ON COMMIT DROP AS
WITH hd AS (
  SELECT h.ma_kh, shared.ma_sp_hop_le(v.ma_san_pham) AS ma, sum(h.so_luong) AS sl
  FROM app_sale.hoa_don_bovattu h
  JOIN shared.dm_vat_tu v ON v.ma_bravo = h.ma_vat_tu
  WHERE v.nhom_san_pham = 'NSK Arthrex' AND v.san_pham = 'Vít neo Swivelock BC kèm chỉ'
  GROUP BY 1, 2)
SELECT b.id,
  coalesce(m.ma_moi,
    (SELECT hd.ma FROM hd WHERE hd.ma_kh = b.ma_khach_hang AND hd.sl > 0 ORDER BY hd.sl DESC, hd.ma LIMIT 1),
    (SELECT hd.ma FROM hd GROUP BY hd.ma HAVING sum(hd.sl) > 0 ORDER BY sum(hd.sl) DESC, hd.ma LIMIT 1),
    'AR-2324BCCT') AS ma
FROM backup.bak_20261028_map_ten_sp_sale_target b
JOIN backup.map_ten_sp_20261028 m
  ON m.nhom_cu = b.nhom_san_pham AND m.san_pham_cu = coalesce(b.san_pham, '') AND m.gia_cu = coalesce(b.don_gia, 0);

SET CONSTRAINTS shared.uq_sale_target_khoa DEFERRED;

UPDATE shared.sale_target s SET
  nhom_san_pham        = m.nhom_moi,
  bo_vat_tu            = coalesce(m.bo_vat_tu_moi, s.bo_vat_tu),
  san_pham             = m.san_pham_moi,
  don_gia              = m.gia_moi,
  ma_san_pham          = k.ma,
  doanh_thu_kh_dau_nam = CASE WHEN m.gia_moi <> m.gia_cu
                              THEN coalesce(s.sl_ke_hoach_dau_nam, 0) * m.gia_moi
                              ELSE s.doanh_thu_kh_dau_nam END,
  updated_at           = now()
FROM backup.bak_20261028_map_ten_sp_sale_target b
JOIN backup.map_ten_sp_20261028 m
  ON m.nhom_cu = b.nhom_san_pham AND m.san_pham_cu = coalesce(b.san_pham, '') AND m.gia_cu = coalesce(b.don_gia, 0)
JOIN _ma_kh k ON k.id = b.id
WHERE s.id = b.id;

SELECT shared.gop_dong_trung_sale_target(
  (SELECT array_agg(id) FROM backup.bak_20261028_map_ten_sp_sale_target));

SET CONSTRAINTS shared.uq_sale_target_khoa IMMEDIATE;

-- Quota trigger để lại (khoá cũ hết dòng kế hoạch): cộng vào quota đích cùng loại × đợt,
-- chưa có đích thì chuyển thẳng.
CREATE TEMP TABLE _q_con ON COMMIT DROP AS
SELECT DISTINCT q.id, q.so_luong, m.nhom_moi, b.bo_vat_tu AS bvt_cu,
       coalesce(m.bo_vat_tu_moi, b.bo_vat_tu) AS bvt_moi, m.san_pham_moi, m.gia_moi
FROM shared.quota_thau q
JOIN backup.map_ten_sp_20261028 m
  ON m.nhom_cu = q.nhom_san_pham AND m.san_pham_cu = q.san_pham AND m.gia_cu = q.don_gia
JOIN backup.bak_20261028_map_ten_sp_sale_target b
  ON b.nam_tai_chinh = q.nam_tai_chinh AND b.ps = q.ps AND b.ma_khach_hang = q.ma_khach_hang
 AND b.nhom_san_pham = q.nhom_san_pham AND b.bo_vat_tu = q.bo_vat_tu
 AND coalesce(b.san_pham, '') = q.san_pham AND coalesce(b.don_gia, 0) = q.don_gia
WHERE q.nam_tai_chinh = 'FY26'
  AND NOT EXISTS (SELECT 1 FROM shared.sale_target s
                  WHERE s.nam_tai_chinh = q.nam_tai_chinh AND s.ps = q.ps
                    AND s.ma_khach_hang = q.ma_khach_hang AND s.nhom_san_pham = q.nhom_san_pham
                    AND s.bo_vat_tu = q.bo_vat_tu AND coalesce(s.san_pham, '') = q.san_pham
                    AND coalesce(s.don_gia, 0) = q.don_gia AND NOT coalesce(s.ngoai_ke_hoach, false));

CREATE TEMP TABLE _q_dich ON COMMIT DROP AS
SELECT c.id, d.id AS dich_id, c.so_luong
FROM _q_con c
JOIN shared.quota_thau q ON q.id = c.id
JOIN shared.quota_thau d
  ON d.nam_tai_chinh = q.nam_tai_chinh AND d.ps = q.ps AND d.ma_khach_hang = q.ma_khach_hang
 AND d.nhom_san_pham = c.nhom_moi AND d.bo_vat_tu = c.bvt_moi
 AND d.san_pham = c.san_pham_moi AND d.don_gia = c.gia_moi
 AND d.loai = q.loai AND d.dot IS NOT DISTINCT FROM q.dot;

INSERT INTO shared.quota_chuan_hoa_log (buoc, bang, ban_ghi_id, truoc, sau)
SELECT 'map_ten_sp_cong_quota', 'quota_thau', q.id, to_jsonb(q), jsonb_build_object('cong_vao', g.dich_id)
FROM _q_dich g JOIN shared.quota_thau q ON q.id = g.id;

UPDATE shared.quota_thau d SET so_luong = d.so_luong + t.sl, updated_at = now()
FROM (SELECT dich_id, sum(so_luong) AS sl FROM _q_dich GROUP BY 1) t
WHERE d.id = t.dich_id;

DELETE FROM shared.quota_thau WHERE id IN (SELECT id FROM _q_dich);

INSERT INTO shared.quota_chuan_hoa_log (buoc, bang, ban_ghi_id, truoc, sau)
SELECT 'map_ten_sp_chuyen_quota', 'quota_thau', q.id, to_jsonb(q),
       jsonb_build_object('nhom', c.nhom_moi, 'bo_vat_tu', c.bvt_moi, 'san_pham', c.san_pham_moi, 'don_gia', c.gia_moi)
FROM _q_con c JOIN shared.quota_thau q ON q.id = c.id
WHERE c.id NOT IN (SELECT id FROM _q_dich);

UPDATE shared.quota_thau q SET
  nhom_san_pham = c.nhom_moi, bo_vat_tu = c.bvt_moi, san_pham = c.san_pham_moi,
  don_gia = c.gia_moi, updated_at = now()
FROM _q_con c
WHERE q.id = c.id AND c.id NOT IN (SELECT id FROM _q_dich);

COMMIT;
