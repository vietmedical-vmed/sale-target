-- Nạp quota thầu CH&CS Miền Bắc từ file ngành hàng gửi ngày 06/11/2026
-- ("Tổng hợp thông tin quota thầu Miền Bắc.xlsx"), chỉ các dòng:
--   * chưa có quota trên hệ thống (KH × mã chung × giá),
--   * có đúng 1 dòng kế hoạch (sale_target, không phải ngoài kế hoạch) cùng PS × KH × SP,
--     giá kế hoạch = giá file, hoặc = giá file / 1,05 (VAT) → lấy GIÁ KẾ HOẠCH (user chốt 06/11),
--   * thầu chính/bổ sung: gắn vào đợt đã có đủ tháng thầu + hiệu lực; dòng "Dự kiến" chỉ gắn đợt
--     có tháng thầu > 2026-11 (upcoming), dòng còn lại chỉ gắn đợt đã vào hiệu lực.
-- 47 khoá quota (48 dòng file). nguon = 'nh_mb_20261106', log ở shared.quota_chuan_hoa_log.
-- Rollback: supabase/rollbacks/20261106170000_nap_quota_nh_chcs_mb_ROLLBACK.sql
BEGIN;

CREATE TEMP TABLE _nap (ps text, kh text, nhom text, bvt text, sp text, gia numeric, loai text, dot int,
                        sl numeric, ma text, dong text) ON COMMIT DROP;
INSERT INTO _nap VALUES
  ('Tùng Phạm', 'BV0338', 'NSK Arthrex', 'Vật tư riêng lẻ - NSK Arthrex', 'Vít treo TightRope', 12700000, 'cu', 1, 150, 'AR-1588RT', '5'),
  ('Tứ Nguyễn', 'BV0488', 'NSK Arthrex', 'Vật tư riêng lẻ - NSK Arthrex', 'Mũi khoan ngược', 4285714, 'cu', 1, 61, 'AR-1204AF-xxx', '8'),
  ('Tùng Phạm', 'BV0338', 'NSK Arthrex', 'Vật tư riêng lẻ - NSK Arthrex', 'Vít neo Swivelock BC kèm chỉ', 13400000, 'cu', 1, 96, 'AR-2324BCCTT', '19'),
  ('Tùng Phạm', 'BV0338', 'NSK Arthrex', 'Vật tư riêng lẻ - NSK Arthrex', 'Lưỡi mài khớp', 4952381, 'cu', 1, 199, 'AR-8xx0OBx', '34'),
  ('Tứ Nguyễn', 'BV1432', 'Cột sống Ulrich', 'Vật tư riêng lẻ - Cột sống Ulrich', 'Kim nối bơm xi măng', 2500000, 'cu', 1, 42, 'CS 3850-02', '59'),
  ('Tứ Nguyễn', 'BV1432', 'Cột sống Ulrich', 'Vật tư riêng lẻ - Cột sống Ulrich', 'Kim nối bơm xi măng', 2500000, 'chinh', 1, 60, 'CS 3850-02', '853'),
  ('Tùng Phạm', 'BV0338', 'NSK Arthrex', 'Vật tư riêng lẻ - NSK Arthrex', 'Đầu đốt RF', 7333334, 'cu', 1, 197, 'AR-9811', '81'),
  ('Tấn Phạm', 'BV0304', 'Khớp UOC', 'Bipolar thường - UOC', 'Bipolar thường - UOC', 39790000, 'cu', 1, 0, 'UO.HBPT1', '96'),
  ('Tùng Phạm', 'BV0338', 'NSK Arthrex', 'Vật tư riêng lẻ - NSK Arthrex', 'Lưỡi bào khớp', 4285714, 'cu', 1, 198, 'AR-8xx0EX', '99'),
  ('Tùng Phạm', 'BV0523', 'NSK Arthrex', 'Vật tư riêng lẻ - NSK Arthrex', 'Vít treo TightRope luồn chỉ', 11500000, 'cu', 1, 200, 'AR-1588RT-J', '104'),
  ('Tùng Phạm', 'BV0523', 'NSK Arthrex', 'Vật tư riêng lẻ - NSK Arthrex', 'Dây nước', 1428571, 'cu', 1, 200, 'AR-6410', '111'),
  ('Tùng Phạm', 'BV0523', 'NSK Arthrex', 'Vật tư riêng lẻ - NSK Arthrex', 'Vít neo Swivelock BC kèm chỉ', 13400000, 'cu', 1, 100, 'AR-2324BCCTT', '129'),
  ('Tùng Phạm', 'BV0523', 'NSK Arthrex', 'Vật tư riêng lẻ - NSK Arthrex', 'Lưỡi bào khớp', 4285714, 'cu', 1, 200, 'AR-8xx0EX', '167'),
  ('Tùng Phạm', 'BV0523', 'NSK Arthrex', 'Vật tư riêng lẻ - NSK Arthrex', 'Đầu đốt RF', 7333334, 'cu', 1, 200, 'AR-9811', '170'),
  ('Tùng Phạm', 'BV0523', 'NSK Arthrex', 'Vật tư riêng lẻ - NSK Arthrex', 'Vít neo Swivelock BC', 11100000, 'cu', 1, 100, 'AR-2324BCC', '213'),
  ('Tấn Phạm', 'BV0336', 'NSK Arthrex', 'Vật tư riêng lẻ - NSK Arthrex', 'Mũi khoan ngược', 4285714, 'cu', 1, 148, 'AR-1204AF-xxx', '224,249'),
  ('Tấn Phạm', 'BV0336', 'NSK Arthrex', 'Vật tư riêng lẻ - NSK Arthrex', 'Mũi khoan ngược', 4285714, 'chinh', 1, 130, 'AR-1204AF-xxx', '1030'),
  ('Tấn Phạm', 'BV0336', 'NSK Arthrex', 'Vít treo TightRope (bộ cố định vỏ xương chày)', 'Vít treo TightRope (bộ cố định vỏ xương chày)', 11450000, 'cu', 1, 44, 'AR.KNEE.1', '260'),
  ('Tấn Phạm', 'BV0336', 'NSK Arthrex', 'Vít treo TightRope (bộ cố định vỏ xương chày)', 'Vít treo TightRope (bộ cố định vỏ xương chày)', 11450000, 'chinh', 1, 30, 'AR.KNEE.1', '1036'),
  ('Tứ Nguyễn', 'BV0308', 'Khớp UOC', 'MOP dài - UOC', 'MOP dài - UOC', 73500000, 'cu', 1, 20, 'UO.HTPD.MOP1', '316'),
  ('Tùng Phạm', 'DN2753', 'NSK Arthrex', 'Vật tư riêng lẻ - NSK Arthrex', 'Dây nước', 1428571, 'cu', 1, 0, 'AR-6410', '414'),
  ('Tùng Phạm', 'DN2753', 'NSK Arthrex', 'Vật tư riêng lẻ - NSK Arthrex', 'Lưỡi bào khớp', 4285714, 'cu', 1, 0, 'AR-8xx0EX', '418'),
  ('Tùng Phạm', 'DN2753', 'NSK Arthrex', 'Vật tư riêng lẻ - NSK Arthrex', 'Đầu đốt RF', 7333334, 'cu', 1, 0, 'AR-9811', '423'),
  ('Tùng Phạm', 'BV0458', 'NSK Arthrex', 'Vật tư riêng lẻ - NSK Arthrex', 'Lưỡi bào khớp', 4285714, 'cu', 1, 0, 'AR-8xx0EX', '432'),
  ('Tùng Phạm', 'BV0458', 'NSK Arthrex', 'Vật tư riêng lẻ - NSK Arthrex', 'Dây nước', 1428571, 'cu', 1, 0, 'AR-6410', '433'),
  ('Tùng Phạm', 'BV0458', 'NSK Arthrex', 'Vật tư riêng lẻ - NSK Arthrex', 'Vít treo TightRope', 12700000, 'cu', 1, 0, 'AR-1588RT', '434'),
  ('Tùng Phạm', 'BV0458', 'NSK Arthrex', 'Vật tư riêng lẻ - NSK Arthrex', 'Vít nút treo TightRope rời', 11450000, 'cu', 1, 1, 'AR-1588TB-x', '435'),
  ('Tùng Phạm', 'BV0458', 'NSK Arthrex', 'Vật tư riêng lẻ - NSK Arthrex', 'Vít neo Swivelock BC kèm chỉ', 13400000, 'cu', 1, 0, 'AR-2324BCCTT', '436'),
  ('Tùng Phạm', 'BV0458', 'NSK Arthrex', 'Vật tư riêng lẻ - NSK Arthrex', 'Lưỡi mài khớp', 4952381, 'cu', 1, 0, 'AR-8xx0OBx', '437'),
  ('Tùng Phạm', 'BV0458', 'NSK Arthrex', 'Vật tư riêng lẻ - NSK Arthrex', 'Đầu đốt RF', 7333334, 'cu', 1, 0, 'AR-9811', '438'),
  ('Tùng Phạm', 'BV0458', 'NSK Arthrex', 'Vật tư riêng lẻ - NSK Arthrex', 'Vít neo Pushlock', 8900000, 'cu', 1, 0, 'AR-2923BC', '440'),
  ('Tùng Phạm', 'BV0458', 'NSK Arthrex', 'Vật tư riêng lẻ - NSK Arthrex', 'Vít Biocomposit ACL', 6800000, 'cu', 1, 0, 'AR-5035TC-xx', '441'),
  ('Tùng Phạm', 'BV0458', 'NSK Arthrex', 'Vật tư riêng lẻ - NSK Arthrex', 'Vít neo Swivelock BC', 11100000, 'cu', 1, 1, 'AR-2324BCC', '445'),
  ('Tứ Nguyễn', 'BV0368', 'Cột sống Ulrich', 'Vật tư riêng lẻ - Cột sống Ulrich', 'Thanh dọc thường 100-180mm', 2100000, 'cu', 1, 0, 'CS 3807-100-180', '492'),
  ('Tứ Nguyễn', 'BV0368', 'Cột sống Ulrich', 'Vật tư riêng lẻ - Cột sống Ulrich', 'Pezo-P', 12992000, 'cu', 1, 0, 'CS 330x', '498'),
  ('Tấn Phạm', 'BV0354', 'Khớp UOC', 'Bipolar dài - UOC', 'Bipolar dài - UOC', 58290000, 'cu', 1, 1, 'UO.HBPD1', '514'),
  ('Tấn Phạm', 'BV1446', 'Khớp UOC', 'Gối thường - UOC', 'Gối thường - UOC', 58000000, 'cu', 1, 1, 'UO.GTPT1', '522'),
  ('Tuyên Phạm', 'BV0310', 'NSK Arthrex', 'Vật tư riêng lẻ - NSK Arthrex', 'Lưỡi bào khớp', 4285714, 'chinh', 1, 50, 'AR-8xx0EX', '529'),
  ('Tùng Phạm', 'BV0628', 'NSK Arthrex', 'Vật tư riêng lẻ - NSK Arthrex', 'Mũi khoan ngược', 4285714, 'chinh', 1, 30, 'AR-1204AF-xxx', '532'),
  ('Tuyên Phạm', 'BV0310', 'NSK Arthrex', 'Vật tư riêng lẻ - NSK Arthrex', 'Dây nước', 1428571, 'chinh', 1, 50, 'AR-6410', '543'),
  ('Tuyên Phạm', 'BV0310', 'NSK Arthrex', 'Vật tư riêng lẻ - NSK Arthrex', 'Vít neo Swivelock BC', 11100000, 'chinh', 1, 50, 'AR-2324BCC', '573'),
  ('Tuyên Phạm', 'BV0310', 'NSK Arthrex', 'Vật tư riêng lẻ - NSK Arthrex', 'Vít neo Swivelock BC kèm chỉ', 13400000, 'chinh', 1, 100, 'AR-2324BCCTT', '584'),
  ('Tùng Phạm', 'BV0449', 'NSK Arthrex', 'Vật tư riêng lẻ - NSK Arthrex', 'Vít neo Swivelock BC kèm chỉ', 13400000, 'chinh', 1, 50, 'AR-2324BCCT', '626'),
  ('Tùng Phạm', 'BV0333', 'Cột sống Ulrich', 'Vật tư riêng lẻ - Cột sống Ulrich', 'Nẹp cổ trước Artus 1 tầng', 7300000, 'chinh', 1, 5, 'CS 9102-01', '739'),
  ('Tứ Nguyễn', 'BV0488', 'NSK Arthrex', 'Vật tư riêng lẻ - NSK Arthrex', 'Vít treo TightRope', 12700000, 'chinh', 1, 93, 'AR-1588RT', '939'),
  ('Tứ Nguyễn', 'BV0625', 'Cột sống Ulrich', 'Vật tư riêng lẻ - Cột sống Ulrich', 'Thanh dọc thường 100-180mm', 2000000, 'chinh', 1, 14, 'CS 3807-100-180', '965'),
  ('Tấn Phạm', 'BV0336', 'NSK Arthrex', 'Vật tư riêng lẻ - NSK Arthrex', 'Vít treo TightRope', 12700000, 'chinh', 1, 700, 'AR-1588RT', '1035');

DO $$
DECLARE v_n int;
BEGIN
  -- Mỗi khoá phải có dòng kế hoạch (không phải ngoài kế hoạch)
  SELECT count(*) INTO v_n FROM _nap n
  WHERE NOT EXISTS (SELECT 1 FROM shared.sale_target s
                    WHERE s.nam_tai_chinh = 'FY26' AND s.ps = n.ps AND s.ma_khach_hang = n.kh
                      AND s.nhom_san_pham = n.nhom AND s.bo_vat_tu = n.bvt AND s.san_pham = n.sp
                      AND s.don_gia = n.gia AND NOT coalesce(s.ngoai_ke_hoach, false));
  IF v_n > 0 THEN RAISE EXCEPTION 'nap_nh: % khoá không có dòng kế hoạch', v_n; END IF;
  -- Không đè quota đang có
  SELECT count(*) INTO v_n FROM _nap n JOIN shared.quota_thau q
    ON q.nam_tai_chinh = 'FY26' AND q.ps = n.ps AND q.ma_khach_hang = n.kh AND q.nhom_san_pham = n.nhom
   AND q.bo_vat_tu = n.bvt AND q.san_pham = n.sp AND q.don_gia = n.gia AND q.loai = n.loai AND q.dot = n.dot;
  IF v_n > 0 THEN RAISE EXCEPTION 'nap_nh: % khoá đã có quota', v_n; END IF;
  -- Thầu chính/bổ sung phải trỏ vào đợt đủ tháng thầu + hiệu lực
  SELECT count(*) INTO v_n FROM _nap n
  WHERE n.loai <> 'cu' AND NOT EXISTS (
    SELECT 1 FROM shared.dot_thau d
    WHERE d.nam_tai_chinh = 'FY26' AND d.ps = n.ps AND d.ma_khach_hang = n.kh AND d.nhom_san_pham = n.nhom
      AND d.loai = n.loai AND d.dot = n.dot AND d.thang_thau IS NOT NULL AND d.thoi_gian > 0);
  IF v_n > 0 THEN RAISE EXCEPTION 'nap_nh: % khoá thiếu đợt hợp lệ', v_n; END IF;
END $$;

WITH ins AS (
  INSERT INTO shared.quota_thau (nam_tai_chinh, ps, ma_khach_hang, nhom_san_pham, bo_vat_tu, san_pham, don_gia,
                                 loai, dot, so_luong, bu, mien, khach_hang, updated_by, trang_thai, nguon, ma_san_pham)
  SELECT 'FY26', n.ps, n.kh, n.nhom, n.bvt, n.sp, n.gia, n.loai, n.dot, n.sl, s.bu, s.mien, s.khach_hang,
         'nap_nh_mb_20261106', 'chinh_thuc', 'nh_mb_20261106', n.ma
  FROM _nap n
  CROSS JOIN LATERAL (
    SELECT s.bu, s.mien, s.khach_hang FROM shared.sale_target s
    WHERE s.nam_tai_chinh = 'FY26' AND s.ps = n.ps AND s.ma_khach_hang = n.kh AND s.nhom_san_pham = n.nhom
      AND s.bo_vat_tu = n.bvt AND s.san_pham = n.sp AND s.don_gia = n.gia AND NOT coalesce(s.ngoai_ke_hoach, false)
    ORDER BY s.id LIMIT 1) s
  RETURNING *
)
INSERT INTO shared.quota_chuan_hoa_log (buoc, bang, ban_ghi_id, truoc, sau)
SELECT 'nap_nh_mb_20261106', 'quota_thau', i.id, NULL, to_jsonb(i) FROM ins i;

COMMIT;
