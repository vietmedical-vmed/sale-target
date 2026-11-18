-- V3 (tiếp) liên kết quota ↔ hợp đồng: quy tắc R2, user chốt 18/11/2026.
-- R2: quota ghi Quota 1.4 nhưng không còn HĐ cũ (SL còn lại 1/4 = 0) và HĐ ký trong năm lớn hơn
--     quota chính/BS on hand → chuyển phần thiếu = min(SL 1.4, SL HĐ trong năm − on hand) từ 1.4
--     sang thầu chính, vào đợt chính cùng nhóm có tháng thầu = tháng ký HĐ; chưa có thì tạo đợt
--     chính mới (tháng = tháng ký, hiệu lực = số tháng từ ký tới hạn HĐ).
--     11 thao tác (9,27 tỷ), 5 đợt mới. Để tay: BV0074 MC.UL.CT1.120 (HĐ ghi hạn 2017-12-07, sai năm).
-- R3 chưa chốt (user xem chi tiết trước).
-- Cách chuyển giống 20261118130000: cộng vào dòng đích cùng khoá nếu có, không thì đổi loại/đợt dòng
-- nguồn (chuyển hết) hoặc tách dòng (chuyển một phần). Kế hoạch không đổi.
-- Log: app_sale.quota_chuan_hoa_log buoc 'v3_r2_1_4_sang_chinh_20261118'. Sau khi áp: chạy lại
-- app_sale.chay_gan_quota_hop_dong(). Rollback:
-- supabase/rollbacks/20261118150000_v3_r2_1_4_sang_chinh_ROLLBACK.sql
BEGIN;

CREATE TEMP TABLE _op (
  stt int, quota_id bigint, loai_goc text, dot_goc int, sl_goc numeric,
  sl numeric, loai_dich text, dot_dich int, quy_tac text, ghi_chu text
) ON COMMIT DROP;
INSERT INTO _op VALUES
  (1, 5312, 'cu', 1, 200, 100, 'chinh', 1, 'R2', 'đợt chính 1 sẵn có tháng 2026-07'),
  (2, 5310, 'cu', 1, 40, 20, 'chinh', 1, 'R2', 'đợt chính 1 sẵn có tháng 2026-07'),
  (3, 5308, 'cu', 1, 450, 250, 'chinh', 1, 'R2', 'đợt chính 1 sẵn có tháng 2026-07'),
  (4, 1855, 'cu', 1, 50, 40, 'chinh', 2, 'R2', 'đợt chính 2 mới tháng 2026-09, HL 18'),
  (5, 7520, 'cu', 1, 40, 20, 'chinh', 2, 'R2', 'đợt chính 2 mới tháng 2026-09, HL 18'),
  (6, 2429, 'cu', 1, 800, 400, 'chinh', 1, 'R2', 'đợt chính 1 sẵn có tháng 2026-04'),
  (7, 2123, 'cu', 1, 50, 50, 'chinh', 1, 'R2', 'đợt chính 1 sẵn có tháng 2026-04'),
  (8, 2395, 'cu', 1, 20, 20, 'chinh', 2, 'R2', 'đợt chính 2 mới tháng 2026-07, HL 12'),
  (9, 5549, 'cu', 1, 70, 70, 'chinh', 2, 'R2', 'đợt chính 2 mới tháng 2026-04, HL 12'),
  (10, 5546, 'cu', 1, 20, 13, 'chinh', 2, 'R2', 'đợt chính 2 mới tháng 2026-04, HL 12'),
  (11, 5697, 'cu', 1, 56, 50, 'chinh', 2, 'R2', 'đợt chính 2 mới tháng 2026-09, HL 12');

CREATE TEMP TABLE _dot_moi (ps text, kh text, nhom text, dot int, thang text, hl numeric) ON COMMIT DROP;
INSERT INTO _dot_moi VALUES
  ('Ly Đào', 'BV0026', 'Khớp UOC', 2, '2026-09', 18),
  ('Ly Đào', 'BV0026', 'Cột sống Ulrich', 2, '2026-09', 18),
  ('Pháp Nguyễn', 'BV0078', 'NSK Arthrex', 2, '2026-07', 12),
  ('Dung Trần', 'BV0189', 'NSK Arthrex', 2, '2026-04', 12),
  ('Mai Trịnh', 'BV0336', 'CSVT - S&N', 2, '2026-09', 12);

DO $$
DECLARE v_n int;
BEGIN
  SELECT count(*) INTO v_n FROM _op o JOIN shared.quota_thau q ON q.id = o.quota_id
  WHERE q.nam_tai_chinh = 'FY26' AND q.loai = o.loai_goc AND q.dot = o.dot_goc AND q.so_luong = o.sl_goc;
  IF v_n <> (SELECT count(*) FROM _op) THEN
    RAISE EXCEPTION 'v3_r2: % / % dòng nguồn còn đúng trạng thái lúc lập đề xuất', v_n, (SELECT count(*) FROM _op);
  END IF;
  SELECT count(*) INTO v_n FROM _dot_moi m JOIN shared.dot_thau d
    ON d.nam_tai_chinh = 'FY26' AND d.ps = m.ps AND d.ma_khach_hang = m.kh AND d.nhom_san_pham = m.nhom
   AND d.loai = 'chinh' AND d.dot = m.dot;
  IF v_n > 0 THEN RAISE EXCEPTION 'v3_r2: % đợt mới đã tồn tại', v_n; END IF;
  -- mọi thao tác sang chính phải có đợt đích (sẵn có hoặc tạo dưới đây)
  SELECT count(*) INTO v_n FROM _op o JOIN shared.quota_thau q ON q.id = o.quota_id
  WHERE o.loai_dich = 'chinh'
    AND NOT EXISTS (SELECT 1 FROM shared.dot_thau d WHERE d.nam_tai_chinh = q.nam_tai_chinh AND d.ps = q.ps
                    AND d.ma_khach_hang = q.ma_khach_hang AND d.nhom_san_pham = q.nhom_san_pham
                    AND d.loai = 'chinh' AND d.dot = o.dot_dich)
    AND NOT EXISTS (SELECT 1 FROM _dot_moi m WHERE m.ps = q.ps AND m.kh = q.ma_khach_hang
                    AND m.nhom = q.nhom_san_pham AND m.dot = o.dot_dich);
  IF v_n > 0 THEN RAISE EXCEPTION 'v3_r2: % thao tác thiếu đợt đích', v_n; END IF;
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
         'chinh_thuc', 'v3_r2_1_4_sang_chinh_20261118', now(), 'v3_r2_1_4_sang_chinh_20261118'
  FROM _dot_moi m
  RETURNING *
)
INSERT INTO app_sale.quota_chuan_hoa_log (buoc, bang, ban_ghi_id, truoc, sau)
SELECT 'v3_r2_1_4_sang_chinh_20261118', 'dot_thau', moi.id, NULL, to_jsonb(moi) FROM moi;

DO $$
DECLARE
  o record; src shared.quota_thau; dst shared.quota_thau; moi shared.quota_thau;
  b text := 'v3_r2_1_4_sang_chinh_20261118';
BEGIN
  FOR o IN SELECT * FROM _op ORDER BY stt LOOP
    SELECT * INTO src FROM shared.quota_thau WHERE id = o.quota_id FOR UPDATE;
    IF src.so_luong < o.sl THEN RAISE EXCEPTION 'v3_r2: dòng % chỉ còn % < %', src.id, src.so_luong, o.sl; END IF;
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
