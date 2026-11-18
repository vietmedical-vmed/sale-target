-- V3 liên kết quota ↔ hợp đồng: sửa phân loại Quota 1.4 ↔ thầu chính (user duyệt 18/11/2026
-- quy tắc R1 + R4; R2, R3 KHÔNG áp). Danh sách đề xuất đầy đủ:
-- bao-cao/de-xuat-V3-phan-loai-1.4-chinh-2026-11-18.xlsx.
--
-- R1 (21 khoá): tổng (1.4 + chính/BS on hand) = tổng (SL HĐ cũ còn lại 1/4 + SL HĐ ký trong
--    năm) nhưng chia sai loại → chia lại theo HĐ.
--      1.4 → chính (15 khoá): vào đợt chính cùng nhóm có tháng thầu = tháng ký HĐ; chưa có thì
--      tạo đợt chính mới (tháng = tháng ký, hiệu lực = số tháng từ ký tới hạn HĐ) — 3 đợt mới.
--      chính/BS → 1.4 (6 khoá): lấy từ đợt có tháng thầu muộn nhất trước.
-- R4 (10 khoá): quota chính có tháng thầu trước 04/2026 và không có HĐ ký trong năm → 1.4 theo
--    định nghĩa (chuyển nguyên dòng). Để làm tay: 4 khoá bộ Zimmer bung linh kiện; 6 khoá mà
--    Quota 1.4 đã khớp HĐ cũ (BV1432 UO.HBPD1 / UO.HTPD.MOP1, BV1827 Ulrich ×4) — nghi nhập trùng.
--
-- Cách chuyển 1 thao tác (quota_id, SL, loại/đợt đích): nếu đã có dòng đích cùng khoá duy nhất
-- (năm, PS, KH, nhóm, BVT, SP, giá, loại, đợt) thì cộng SL vào dòng đó; chưa có thì đổi loại/đợt
-- của dòng nguồn (chuyển hết) hoặc tách dòng mới (chuyển một phần). Dòng nguồn hết SL thì xoá.
-- Kế hoạch (sale_target) không đổi. Mỗi dòng bị chạm ghi log app_sale.quota_chuan_hoa_log
-- buoc 'v3_phan_loai_1_4_chinh_20261118' (truoc/sau). Sau khi áp: chạy lại
-- app_sale.chay_gan_quota_hop_dong(). Rollback:
-- supabase/rollbacks/20261118130000_v3_phan_loai_1_4_chinh_ROLLBACK.sql
BEGIN;

CREATE TEMP TABLE _op (
  stt int, quota_id bigint, loai_goc text, dot_goc int, sl_goc numeric,
  sl numeric, loai_dich text, dot_dich int, quy_tac text, ghi_chu text
) ON COMMIT DROP;
INSERT INTO _op VALUES
  (1, 5333, 'cu', 1, 50, 50, 'chinh', 1, 'R1', 'đợt chính 1 mới tháng 2026-07, HL 6'),
  (2, 5335, 'cu', 1, 100, 100, 'chinh', 1, 'R1', 'đợt chính 1 mới tháng 2026-07, HL 6'),
  (3, 5313, 'cu', 1, 100, 100, 'chinh', 1, 'R1', 'đợt chính 1 mới tháng 2026-07, HL 6'),
  (4, 5306, 'cu', 1, 100, 100, 'chinh', 1, 'R1', 'đợt chính 1 mới tháng 2026-07, HL 6'),
  (5, 5314, 'cu', 1, 150, 150, 'chinh', 1, 'R1', 'đợt chính 1 mới tháng 2026-07, HL 6'),
  (6, 5311, 'cu', 1, 20, 20, 'chinh', 1, 'R1', 'đợt chính 1 mới tháng 2026-07, HL 6'),
  (7, 5625, 'chinh', 1, 200, 200, 'cu', 1, 'R4', 'đợt tháng 2026-03 trước FY'),
  (8, 4777, 'cu', 1, 600, 600, 'chinh', 1, 'R1', 'đợt chính 1 mới tháng 2026-04, HL 24'),
  (9, 1957, 'cu', 1, 400, 400, 'chinh', 1, 'R1', 'đợt chính 1 mới tháng 2026-04, HL 24'),
  (10, 2320, 'cu', 1, 400, 400, 'chinh', 1, 'R1', 'đợt chính 1 mới tháng 2026-04, HL 24'),
  (11, 2492, 'cu', 1, 400, 400, 'chinh', 1, 'R1', 'đợt chính 1 mới tháng 2026-04, HL 24'),
  (12, 2109, 'cu', 1, 400, 400, 'chinh', 1, 'R1', 'đợt chính 1 mới tháng 2026-04, HL 24'),
  (13, 2069, 'cu', 1, 100, 100, 'chinh', 1, 'R1', 'đợt chính 1 mới tháng 2026-04, HL 24'),
  (14, 4647, 'cu', 1, 100, 100, 'chinh', 1, 'R1', 'đợt chính 1 mới tháng 2026-04, HL 24'),
  (15, 4650, 'cu', 1, 100, 100, 'chinh', 1, 'R1', 'đợt chính 1 mới tháng 2026-04, HL 24'),
  (16, 7468, 'cu', 1, 200, 200, 'chinh', 1, 'R1', 'đợt chính 1 sẵn có tháng 2026-04'),
  (17, 3825, 'chinh', 1, 60, 60, 'cu', 1, 'R1', 'HĐ cũ còn SL, không có HĐ trong năm tương ứng'),
  (18, 2656, 'chinh', 1, 50, 50, 'cu', 1, 'R4', 'đợt tháng 2026-03 trước FY'),
  (19, 4667, 'chinh', 1, 34, 34, 'cu', 1, 'R1', 'HĐ cũ còn SL, không có HĐ trong năm tương ứng'),
  (20, 5771, 'chinh', 1, 20, 20, 'cu', 1, 'R1', 'HĐ cũ còn SL, không có HĐ trong năm tương ứng'),
  (21, 3522, 'chinh', 1, 15, 15, 'cu', 1, 'R4', 'đợt tháng 2026-01 trước FY'),
  (22, 3251, 'chinh', 1, 60, 60, 'cu', 1, 'R4', 'đợt tháng 2026-03 trước FY'),
  (23, 2797, 'chinh', 1, 70, 70, 'cu', 1, 'R1', 'HĐ cũ còn SL, không có HĐ trong năm tương ứng'),
  (24, 2855, 'chinh', 1, 80, 80, 'cu', 1, 'R1', 'HĐ cũ còn SL, không có HĐ trong năm tương ứng'),
  (25, 6787, 'chinh', 2, 3, 3, 'cu', 1, 'R4', 'đợt tháng 2025-05 trước FY'),
  (26, 6781, 'chinh', 2, 88, 88, 'cu', 1, 'R4', 'đợt tháng 2025-05 trước FY'),
  (27, 6783, 'chinh', 2, 10, 10, 'cu', 1, 'R4', 'đợt tháng 2025-05 trước FY'),
  (28, 6894, 'chinh', 2, 6, 6, 'cu', 1, 'R4', 'đợt tháng 2025-05 trước FY'),
  (29, 7390, 'chinh', 2, 6, 6, 'cu', 1, 'R4', 'đợt tháng 2025-05 trước FY'),
  (30, 5505, 'chinh', 1, 3, 2, 'cu', 1, 'R1', 'HĐ cũ còn SL, không có HĐ trong năm tương ứng'),
  (31, 5243, 'chinh', 1, 58, 58, 'cu', 1, 'R4', 'đợt tháng 2025-11 trước FY');

CREATE TEMP TABLE _dot_moi (ps text, kh text, nhom text, dot int, thang text, hl numeric) ON COMMIT DROP;
INSERT INTO _dot_moi VALUES
  ('Dung Trần', 'BV0004', 'BXMCS', 1, '2026-07', 6),
  ('Dung Trần', 'BV0004', 'Cột sống Ulrich', 1, '2026-07', 6),
  ('Pháp Nguyễn', 'BV0036', 'NSK Arthrex', 1, '2026-04', 24);

DO $$
DECLARE v_n int;
BEGIN
  SELECT count(*) INTO v_n FROM _op o JOIN shared.quota_thau q ON q.id = o.quota_id
  WHERE q.nam_tai_chinh = 'FY26' AND q.loai = o.loai_goc AND q.dot = o.dot_goc AND q.so_luong = o.sl_goc;
  IF v_n <> (SELECT count(*) FROM _op) THEN
    RAISE EXCEPTION 'v3: % / % dòng nguồn còn đúng trạng thái lúc lập đề xuất', v_n, (SELECT count(*) FROM _op);
  END IF;
  SELECT count(*) INTO v_n FROM _dot_moi m JOIN shared.dot_thau d
    ON d.nam_tai_chinh = 'FY26' AND d.ps = m.ps AND d.ma_khach_hang = m.kh AND d.nhom_san_pham = m.nhom
   AND d.loai = 'chinh' AND d.dot = m.dot;
  IF v_n > 0 THEN RAISE EXCEPTION 'v3: % đợt mới đã tồn tại', v_n; END IF;
  -- mọi thao tác sang chính phải có đợt đích (sẵn có hoặc tạo dưới đây)
  SELECT count(*) INTO v_n FROM _op o JOIN shared.quota_thau q ON q.id = o.quota_id
  WHERE o.loai_dich = 'chinh'
    AND NOT EXISTS (SELECT 1 FROM shared.dot_thau d WHERE d.nam_tai_chinh = q.nam_tai_chinh AND d.ps = q.ps
                    AND d.ma_khach_hang = q.ma_khach_hang AND d.nhom_san_pham = q.nhom_san_pham
                    AND d.loai = 'chinh' AND d.dot = o.dot_dich)
    AND NOT EXISTS (SELECT 1 FROM _dot_moi m WHERE m.ps = q.ps AND m.kh = q.ma_khach_hang
                    AND m.nhom = q.nhom_san_pham AND m.dot = o.dot_dich);
  IF v_n > 0 THEN RAISE EXCEPTION 'v3: % thao tác thiếu đợt đích', v_n; END IF;
END $$;

WITH moi AS (
  INSERT INTO shared.dot_thau
    (nam_tai_chinh, ps, ma_khach_hang, nhom_san_pham, loai, dot, thang_thau, thoi_gian, bu, mien,
     trang_thai, nguon, updated_at, updated_by)
  SELECT 'FY26', m.ps, m.kh, m.nhom, 'chinh', m.dot, m.thang, m.hl,
         (SELECT q.bu FROM shared.quota_thau q WHERE q.nam_tai_chinh = 'FY26' AND q.ps = m.ps
            AND q.ma_khach_hang = m.kh AND q.nhom_san_pham = m.nhom LIMIT 1),
         (SELECT q.mien FROM shared.quota_thau q WHERE q.nam_tai_chinh = 'FY26' AND q.ps = m.ps
            AND q.ma_khach_hang = m.kh AND q.nhom_san_pham = m.nhom LIMIT 1),
         'chinh_thuc', 'v3_phan_loai_1_4_chinh_20261118', now(), 'v3_phan_loai_1_4_chinh_20261118'
  FROM _dot_moi m
  RETURNING *
)
INSERT INTO app_sale.quota_chuan_hoa_log (buoc, bang, ban_ghi_id, truoc, sau)
SELECT 'v3_phan_loai_1_4_chinh_20261118', 'dot_thau', moi.id, NULL, to_jsonb(moi) FROM moi;

DO $$
DECLARE
  o record; src shared.quota_thau; dst shared.quota_thau; moi shared.quota_thau;
  b text := 'v3_phan_loai_1_4_chinh_20261118';
BEGIN
  FOR o IN SELECT * FROM _op ORDER BY stt LOOP
    SELECT * INTO src FROM shared.quota_thau WHERE id = o.quota_id FOR UPDATE;
    IF src.so_luong < o.sl THEN RAISE EXCEPTION 'v3: dòng % chỉ còn % < %', src.id, src.so_luong, o.sl; END IF;
    SELECT * INTO dst FROM shared.quota_thau q
    WHERE q.nam_tai_chinh = src.nam_tai_chinh AND q.ps = src.ps AND q.ma_khach_hang = src.ma_khach_hang
      AND q.nhom_san_pham = src.nhom_san_pham AND q.bo_vat_tu = src.bo_vat_tu AND q.san_pham = src.san_pham
      AND q.don_gia = src.don_gia AND q.loai = o.loai_dich AND q.dot = o.dot_dich AND q.id <> src.id
    FOR UPDATE;
    IF FOUND THEN
      -- cộng vào dòng đích sẵn có
      UPDATE shared.quota_thau SET so_luong = so_luong + o.sl, updated_at = now(), updated_by = b
      WHERE id = dst.id RETURNING * INTO moi;
      INSERT INTO app_sale.quota_chuan_hoa_log (buoc, bang, ban_ghi_id, truoc, sau)
      VALUES (b, 'quota_thau', dst.id, to_jsonb(dst), to_jsonb(moi));
      IF src.so_luong = o.sl THEN
        DELETE FROM shared.quota_thau WHERE id = src.id;
        INSERT INTO app_sale.quota_chuan_hoa_log (buoc, bang, ban_ghi_id, truoc, sau)
        VALUES (b, 'quota_thau', src.id, to_jsonb(src), NULL);
      ELSE
        UPDATE shared.quota_thau SET so_luong = so_luong - o.sl, updated_at = now(), updated_by = b
        WHERE id = src.id RETURNING * INTO moi;
        INSERT INTO app_sale.quota_chuan_hoa_log (buoc, bang, ban_ghi_id, truoc, sau)
        VALUES (b, 'quota_thau', src.id, to_jsonb(src), to_jsonb(moi));
      END IF;
    ELSIF src.so_luong = o.sl THEN
      -- chuyển nguyên dòng
      UPDATE shared.quota_thau SET loai = o.loai_dich, dot = o.dot_dich, updated_at = now(), updated_by = b
      WHERE id = src.id RETURNING * INTO moi;
      INSERT INTO app_sale.quota_chuan_hoa_log (buoc, bang, ban_ghi_id, truoc, sau)
      VALUES (b, 'quota_thau', src.id, to_jsonb(src), to_jsonb(moi));
    ELSE
      -- tách dòng
      UPDATE shared.quota_thau SET so_luong = so_luong - o.sl, updated_at = now(), updated_by = b
      WHERE id = src.id RETURNING * INTO moi;
      INSERT INTO app_sale.quota_chuan_hoa_log (buoc, bang, ban_ghi_id, truoc, sau)
      VALUES (b, 'quota_thau', src.id, to_jsonb(src), to_jsonb(moi));
      INSERT INTO shared.quota_thau
        (nam_tai_chinh, ps, ma_khach_hang, nhom_san_pham, bo_vat_tu, san_pham, don_gia, loai, dot,
         so_luong, bu, mien, khach_hang, updated_by, trang_thai, nguon, ma_san_pham)
      VALUES (src.nam_tai_chinh, src.ps, src.ma_khach_hang, src.nhom_san_pham, src.bo_vat_tu, src.san_pham,
              src.don_gia, o.loai_dich, o.dot_dich, o.sl, src.bu, src.mien, src.khach_hang, b,
              src.trang_thai, b, src.ma_san_pham)
      RETURNING * INTO moi;
      INSERT INTO app_sale.quota_chuan_hoa_log (buoc, bang, ban_ghi_id, truoc, sau)
      VALUES (b, 'quota_thau', moi.id, NULL, to_jsonb(moi));
    END IF;
  END LOOP;
END $$;

COMMIT;
