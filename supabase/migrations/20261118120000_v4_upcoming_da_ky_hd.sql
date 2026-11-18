-- V4 liên kết quota ↔ hợp đồng: quota đang upcoming nhưng HĐ đã ký trong FY26.
-- User chốt 18/11/2026 (3 trường hợp, theo đối chiếu shared.doi_chieu_quota_hop_dong):
--
-- 1. BV0074 ĐHYD HCM × PS Pháp Nguyễn: gói IB2600430376 ký 27/10/2026, hạn 24 tháng, chỉ có
--    3 SP của đợt chính 1 (tháng 12/2026). Tách 3 SP sang đợt chính 2 MỚI (tháng 2026-10,
--    HL 24), SL theo HĐ:
--      Cột sống Ulrich: Vít prefixation (id 5370) 40 → 80; Ốc khóa trong 02 (id 5362) 40 → 120
--      NSK Arthrex:     Cây móc chỉ (id 5383) 18 → 27
--    32 SP còn lại giữ ở đợt chính 1 tháng 12/2026 (upcoming).
-- 2. BV0074 × Ốc khóa trong 01 (id 5398, 50): HĐ HDB.A22.0626.013 gói IB2600036887 ký
--    08/06/2026 (thời hạn trên HĐ ghi 2017-12-07 — sai năm, báo bên hợp đồng). Chuyển từ
--    chính đợt 1 sang bổ sung đợt 2 MỚI (tháng 2026-06, HL 18 tạm), SL giữ 50.
-- 3. BV0298 Bạch Mai × PS Hương Đồng × Coil đẩy (id 4953, 384): HĐ HDB.A06.0626.012 gói
--    IB2600013331 ký 18/06/2026, hạn 12 tháng, SL 384 = quota 1.4. Chuyển từ Quota 1.4 (cu)
--    sang chính đợt 2 MỚI (tháng 2026-06, HL 12). Chính 420 tháng 12/2026 giữ (thầu mới).
--
-- Kế hoạch (sale_target) không đổi: khoá quota ↔ kế hoạch không gồm loại / đợt.
-- Log: app_sale.quota_chuan_hoa_log buoc 'v4_upcoming_da_ky_hd_20261118'.
-- Rollback: supabase/rollbacks/20261118120000_v4_upcoming_da_ky_hd_ROLLBACK.sql
BEGIN;

CREATE TEMP TABLE _v4 (id bigint, loai text, dot int, so_luong numeric) ON COMMIT DROP;
INSERT INTO _v4 VALUES
  (5370, 'chinh',   2,  80),
  (5362, 'chinh',   2, 120),
  (5383, 'chinh',   2,  27),
  (5398, 'bo_sung', 2,  50),
  (4953, 'chinh',   2, 384);

CREATE TEMP TABLE _cu ON COMMIT DROP AS
SELECT q.* FROM shared.quota_thau q JOIN _v4 v ON v.id = q.id;

-- Kiểm trạng thái gốc đúng như lúc đối chiếu, đợt đích chưa có.
DO $$
DECLARE v_n int;
BEGIN
  SELECT count(*) INTO v_n FROM _cu c WHERE
       (c.id = 5370 AND c.ma_khach_hang = 'BV0074' AND c.loai = 'chinh' AND c.dot = 1 AND c.so_luong = 40)
    OR (c.id = 5362 AND c.ma_khach_hang = 'BV0074' AND c.loai = 'chinh' AND c.dot = 1 AND c.so_luong = 40)
    OR (c.id = 5383 AND c.ma_khach_hang = 'BV0074' AND c.loai = 'chinh' AND c.dot = 1 AND c.so_luong = 18)
    OR (c.id = 5398 AND c.ma_khach_hang = 'BV0074' AND c.loai = 'chinh' AND c.dot = 1 AND c.so_luong = 50)
    OR (c.id = 4953 AND c.ma_khach_hang = 'BV0298' AND c.loai = 'cu'    AND c.dot = 1 AND c.so_luong = 384);
  IF v_n <> 5 THEN RAISE EXCEPTION 'v4: mong đợi 5 dòng quota ở trạng thái gốc, thấy %', v_n; END IF;
  SELECT count(*) INTO v_n FROM shared.dot_thau d WHERE d.nam_tai_chinh = 'FY26' AND (
       (d.ps = 'Pháp Nguyễn' AND d.ma_khach_hang = 'BV0074' AND d.nhom_san_pham IN ('Cột sống Ulrich', 'NSK Arthrex') AND d.loai = 'chinh' AND d.dot = 2)
    OR (d.ps = 'Pháp Nguyễn' AND d.ma_khach_hang = 'BV0074' AND d.nhom_san_pham = 'Cột sống Ulrich' AND d.loai = 'bo_sung' AND d.dot = 2)
    OR (d.ps = 'Hương Đồng' AND d.ma_khach_hang = 'BV0298' AND d.nhom_san_pham = 'BSC - IO' AND d.loai = 'chinh' AND d.dot = 2));
  IF v_n > 0 THEN RAISE EXCEPTION 'v4: % đợt đích đã tồn tại', v_n; END IF;
END $$;

-- Đợt mới (bu / mien chép từ đợt chính 1 cùng nhóm).
WITH moi AS (
  INSERT INTO shared.dot_thau
    (nam_tai_chinh, ps, ma_khach_hang, nhom_san_pham, loai, dot, thang_thau, thoi_gian, bu, mien,
     trang_thai, nguon, updated_at, updated_by)
  SELECT d.nam_tai_chinh, d.ps, d.ma_khach_hang, d.nhom_san_pham, x.loai, 2, x.thang, x.hl, d.bu, d.mien,
         'chinh_thuc', 'v4_upcoming_da_ky_hd_20261118', now(), 'v4_upcoming_da_ky_hd_20261118'
  FROM (VALUES
          ('Pháp Nguyễn', 'BV0074', 'Cột sống Ulrich', 'chinh',   '2026-10', 24),
          ('Pháp Nguyễn', 'BV0074', 'NSK Arthrex',     'chinh',   '2026-10', 24),
          ('Pháp Nguyễn', 'BV0074', 'Cột sống Ulrich', 'bo_sung', '2026-06', 18),
          ('Hương Đồng',  'BV0298', 'BSC - IO',        'chinh',   '2026-06', 12)
       ) AS x(ps, kh, nhom, loai, thang, hl)
  JOIN shared.dot_thau d
    ON d.nam_tai_chinh = 'FY26' AND d.ps = x.ps AND d.ma_khach_hang = x.kh
   AND d.nhom_san_pham = x.nhom AND d.loai = 'chinh' AND d.dot = 1
  RETURNING *
)
INSERT INTO app_sale.quota_chuan_hoa_log (buoc, bang, ban_ghi_id, truoc, sau)
SELECT 'v4_upcoming_da_ky_hd_20261118', 'dot_thau', m.id, NULL, to_jsonb(m) FROM moi m;

DO $$
BEGIN
  IF (SELECT count(*) FROM shared.dot_thau WHERE nguon = 'v4_upcoming_da_ky_hd_20261118') <> 4 THEN
    RAISE EXCEPTION 'v4: không tạo đủ 4 đợt mới';
  END IF;
END $$;

WITH upd AS (
  UPDATE shared.quota_thau q
  SET loai = v.loai, dot = v.dot, so_luong = v.so_luong,
      updated_at = now(), updated_by = 'v4_upcoming_da_ky_hd_20261118'
  FROM _v4 v WHERE q.id = v.id
  RETURNING q.*
)
INSERT INTO app_sale.quota_chuan_hoa_log (buoc, bang, ban_ghi_id, truoc, sau)
SELECT 'v4_upcoming_da_ky_hd_20261118', 'quota_thau', u.id, to_jsonb(c), to_jsonb(u)
FROM upd u JOIN _cu c ON c.id = u.id;

COMMIT;
