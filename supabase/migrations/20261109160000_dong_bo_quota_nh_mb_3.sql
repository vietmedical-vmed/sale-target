-- Đồng bộ quota thầu CH&CS Miền Bắc theo file ngành hàng bản 09/11/2026 (user chốt 09/11), buoc 'dong_bo_nh_mb_20261109c':
--   0. Sửa tháng thầu 0 đợt + chuyển 0 quota sang đợt đúng on hand/upcoming theo file.
--   1. Thêm 9 đợt thầu thiếu, tháng thầu = tháng "Ngày ký" trong file, hiệu lực = số tháng từ ngày ký
--      tới ngày hết hạn (chỉ đợt đã trúng; riêng VĐ Ulrich thêm đợt dự kiến 2027-03 theo file).
--   2. Sửa quota trên khoá kế hoạch đã có: 24 dòng đổi SL, 13 dòng xoá (SL file = 0 ở loại/đợt đó),
--      44 dòng thêm (loại/đợt file có mà HT chưa có). VĐ Ulrich giữ PS Mậu Cao; ĐHY HN gối U2 theo file.
--   3. Thêm 44 sản phẩm vào kế hoạch FY26 của PS (12 tháng, SL 0, hấp thụ dòng OOP cùng khoá như "Thêm sản phẩm"),
--      rồi nạp quota cho các sản phẩm đó.
-- File NH bỏ 4 dòng trùng BV K (dòng 52, 151, 287, 303). Log: shared.quota_chuan_hoa_log buoc 'dong_bo_nh_mb_20261109c'.
-- Rollback: supabase/rollbacks/20261109160000_dong_bo_quota_nh_mb_3_ROLLBACK.sql
BEGIN;
SET CONSTRAINTS shared.uq_sale_target_khoa DEFERRED;

CREATE TEMP TABLE _dot_moi (ps text, kh text, nhom text, loai text, dot int, thang text, hl numeric) ON COMMIT DROP;
INSERT INTO _dot_moi VALUES
  ('Tứ Nguyễn', 'BV0488', 'Cột sống Ulrich', 'chinh', 1, '2027-04', 12),
  ('Tấn Phạm', 'BV0304', 'NSK Arthrex', 'chinh', 2, '2027-02', 12),
  ('Tấn Phạm', 'BV0304', 'Cột sống Ulrich', 'chinh', 2, '2027-02', 12),
  ('Tuyên Phạm', 'BV0310', 'NSK Arthrex', 'chinh', 2, '2027-08', 12),
  ('Tứ Nguyễn', 'BV1432', 'NSK Arthrex', 'chinh', 1, '2026-05', 8),
  ('Tứ Nguyễn', 'BV1432', 'NSK Arthrex', 'chinh', 2, '2027-03', 12),
  ('Mậu Cao', 'BV0294', 'Khớp UOC', 'chinh', 1, '2026-04', 12),
  ('Mậu Cao', 'BV0294', 'Khớp UOC', 'bo_sung', 1, '2026-04', 1),
  ('Mậu Cao', 'BV0298', 'NSK Arthrex', 'chinh', 1, '2026-06', 12);
CREATE TEMP TABLE _upd (id bigint, sl_cu numeric, sl_moi numeric) ON COMMIT DROP;
INSERT INTO _upd VALUES
  (5253, 3, 23),
  (2262, 18, 20),
  (4570, 1200, 1000),
  (2084, 74, 24),
  (5249, 55, 75),
  (1976, 45, 48),
  (2142, 80, 60),
  (5252, 55, 75),
  (1726, 45, 48),
  (2025, 8, 11),
  (2135, 14, 17),
  (1972, 200, 34),
  (4823, 35, 40),
  (5248, 55, 75),
  (2007, 45, 48),
  (2439, 10, 5),
  (4539, 6, 5),
  (1781, 1200, 1000),
  (1948, 100, 50),
  (5255, 5, 11),
  (2361, 60, 30),
  (5983, 40, 50),
  (5250, 100, 50),
  (5225, 20, 26);
CREATE TEMP TABLE _del (id bigint, sl_cu numeric) ON COMMIT DROP;
INSERT INTO _del VALUES
  (3726, 20),
  (3757, 200),
  (2426, 30),
  (3756, 50),
  (2172, 50),
  (3755, 200),
  (4509, 40),
  (2427, 30),
  (5027, 70),
  (1747, 143),
  (2364, 69),
  (2270, 69),
  (1914, 69);
CREATE TEMP TABLE _ins (ps text, kh text, nhom text, bvt text, sp text, gia numeric, loai text, dot int, sl numeric, ma text, dong text) ON COMMIT DROP;
INSERT INTO _ins VALUES
  ('Tứ Nguyễn', 'BV0488', 'Cột sống Ulrich', 'Vật tư riêng lẻ - Cột sống Ulrich', 'Ốc khóa Cosmic', 840000, 'chinh', 1, 9, 'CS 2605', '941'),
  ('Tứ Nguyễn', 'BV0488', 'Cột sống Ulrich', 'Vật tư riêng lẻ - Cột sống Ulrich', 'Ốc khóa trong 01', 1000000, 'chinh', 1, 8, 'CS 3801-01', '944'),
  ('Tấn Phạm', 'BV0304', 'NSK Arthrex', 'Vật tư riêng lẻ - NSK Arthrex', 'Troca có ren', 1150000, 'chinh', 2, 15, 'AR-65xx', '1044'),
  ('Tuyên Phạm', 'BV0655', 'NSK Arthrex', 'Vật tư riêng lẻ - NSK Arthrex', 'Chỉ tròn kèm kim', 1200000, 'chinh', 1, 29, 'AR-7206', '601'),
  ('Tứ Nguyễn', 'BV0488', 'NSK Arthrex', 'Vật tư riêng lẻ - NSK Arthrex', 'Chỉ tròn kèm kim', 1200000, 'chinh', 1, 55, 'AR-7206', '927'),
  ('Tấn Phạm', 'BV0336', 'NSK Arthrex', 'Vật tư riêng lẻ - NSK Arthrex', 'Chỉ tròn kèm kim', 1200000, 'chinh', 1, 600, 'AR-7206', '1013'),
  ('Tấn Phạm', 'BV0304', 'NSK Arthrex', 'Vật tư riêng lẻ - NSK Arthrex', 'Dây nước', 1428571, 'chinh', 2, 85, 'AR-6410', '1040'),
  ('Tứ Nguyễn', 'BV0488', 'Cột sống Ulrich', 'Vật tư riêng lẻ - Cột sống Ulrich', 'Thanh dọc thường 100-180mm', 2100000, 'chinh', 1, 20, 'CS 3807-100-180', '943'),
  ('Tứ Nguyễn', 'BV0488', 'NSK Arthrex', 'Vật tư riêng lẻ - NSK Arthrex', 'Chỉ dẹt xanh', 4200000, 'chinh', 1, 60, 'AR-7500', '924'),
  ('Tấn Phạm', 'BV0304', 'NSK Arthrex', 'Vật tư riêng lẻ - NSK Arthrex', 'Chỉ dẹt xanh', 4200000, 'chinh', 2, 65, 'AR-7500', '1038'),
  ('Tấn Phạm', 'BV0304', 'NSK Arthrex', 'Vật tư riêng lẻ - NSK Arthrex', 'Lưỡi bào khớp', 4285714, 'chinh', 2, 85, 'AR-8xx0EX', '1042'),
  ('Tấn Phạm', 'BV0304', 'NSK Arthrex', 'Vật tư riêng lẻ - NSK Arthrex', 'Cây đẩy chỉ', 5000000, 'chinh', 1, 20, 'AR-13995N', '539'),
  ('Tấn Phạm', 'BV0304', 'NSK Arthrex', 'Vật tư riêng lẻ - NSK Arthrex', 'Cây đẩy chỉ', 5000000, 'chinh', 2, 10, 'AR-13995N', '1037'),
  ('Tấn Phạm', 'BV0304', 'NSK Arthrex', 'Vật tư riêng lẻ - NSK Arthrex', 'Lưỡi mài khớp', 4952381, 'chinh', 1, 20, 'AR-8xx0OBx', '567'),
  ('Tấn Phạm', 'BV0304', 'NSK Arthrex', 'Vật tư riêng lẻ - NSK Arthrex', 'Lưỡi mài khớp', 4952381, 'chinh', 2, 10, 'AR-8xx0OBx', '1043'),
  ('Tấn Phạm', 'BV0304', 'NSK Arthrex', 'Vật tư riêng lẻ - NSK Arthrex', 'Đầu đốt RF', 7333334, 'chinh', 2, 85, 'AR-9811', '1039'),
  ('Tứ Nguyễn', 'BV0488', 'Cột sống Ulrich', 'Vật tư riêng lẻ - Cột sống Ulrich', 'Vít Cosmic', 8200000, 'chinh', 1, 9, 'CS 2600', '939'),
  ('Tấn Phạm', 'BV0336', 'NSK Arthrex', 'Vật tư riêng lẻ - NSK Arthrex', 'Dụng cụ định vị khâu sụn chêm', 12100000, 'chinh', 1, 10, NULL, '1027'),
  ('Tứ Nguyễn', 'BV0488', 'Cột sống Ulrich', 'Vật tư riêng lẻ - Cột sống Ulrich', 'Pezo-P', 12992000, 'chinh', 1, 20, 'CS 330x', '945'),
  ('Tấn Phạm', 'BV0304', 'NSK Arthrex', 'Vật tư riêng lẻ - NSK Arthrex', 'Vít neo Swivelock BC kèm chỉ', 13400000, 'chinh', 1, 80, 'AR-2324BCCT', '553'),
  ('Tấn Phạm', 'BV0304', 'NSK Arthrex', 'Vật tư riêng lẻ - NSK Arthrex', 'Vít neo Swivelock BC kèm chỉ', 13400000, 'chinh', 2, 60, 'AR-2324BCCT', '1045'),
  ('Tấn Phạm', 'BV0304', 'Cột sống Ulrich', 'ADD Plus', 'ADD Plus', 45000000, 'chinh', 2, 3, 'UL.ADD2', '1029'),
  ('Tấn Phạm', 'BV0304', 'Cột sống Ulrich', 'Obelisc', 'Obelisc', 56000000, 'chinh', 2, 3, 'UL.OBL', '1030'),
  ('Tuyên Phạm', 'BV0310', 'NSK Arthrex', 'Vật tư riêng lẻ - NSK Arthrex', 'Lưỡi bào khớp', 4285714, 'chinh', 2, 600, 'AR-8xx0EX', '1060'),
  ('Tuyên Phạm', 'BV0310', 'NSK Arthrex', 'Vật tư riêng lẻ - NSK Arthrex', 'Dây nước', 1428571, 'chinh', 2, 600, 'AR-6410', '1062'),
  ('Tuyên Phạm', 'BV0310', 'NSK Arthrex', 'Vật tư riêng lẻ - NSK Arthrex', 'Đầu đốt RF', 7333334, 'chinh', 2, 600, 'AR-9811', '1061'),
  ('Tuyên Phạm', 'BV0310', 'NSK Arthrex', 'Vật tư riêng lẻ - NSK Arthrex', 'Vít neo Swivelock BC', 11100000, 'chinh', 2, 200, 'AR-2324BCC', '1067'),
  ('Tuyên Phạm', 'BV0310', 'NSK Arthrex', 'Vật tư riêng lẻ - NSK Arthrex', 'Vít neo Swivelock BC kèm chỉ', 13400000, 'chinh', 2, 200, 'AR-2324BCCTT', '1066'),
  ('Tấn Phạm', 'BV0304', 'NSK Arthrex', 'Vật tư riêng lẻ - NSK Arthrex', 'Dụng cụ định vị khâu sụn chêm', 12100000, 'chinh', 2, 30, NULL, '1041'),
  ('Tấn Phạm', 'BV0304', 'NSK Arthrex', 'Vật tư riêng lẻ - NSK Arthrex', 'Vít chốt khớp cùng đòn', 5200000, 'chinh', 2, 5, 'AR-2270', '1046'),
  ('Tấn Phạm', 'BV0304', 'Cột sống Ulrich', 'Vật tư riêng lẻ - Cột sống Ulrich', 'Vít Cosmic', 8200000, 'chinh', 1, 200, 'CS 2600', '612'),
  ('Tấn Phạm', 'BV0304', 'Cột sống Ulrich', 'Vật tư riêng lẻ - Cột sống Ulrich', 'Vít Cosmic', 8200000, 'chinh', 2, 160, 'CS 2600', '1033'),
  ('Tuyên Phạm', 'BV0655', 'Cột sống Ulrich', 'Vật tư riêng lẻ - Cột sống Ulrich', 'Vít Cosmic', 8200000, 'chinh', 2, 60, 'CS 2600', '617'),
  ('Tấn Phạm', 'BV0304', 'Cột sống Ulrich', 'Vật tư riêng lẻ - Cột sống Ulrich', 'Thanh dọc thường 100-180mm', 2100000, 'chinh', 1, 50, 'CS 3807-100-180', '619'),
  ('Tấn Phạm', 'BV0304', 'Cột sống Ulrich', 'Vật tư riêng lẻ - Cột sống Ulrich', 'Thanh dọc thường 100-180mm', 2100000, 'chinh', 2, 40, 'CS 3807-100-180', '1035'),
  ('Tấn Phạm', 'BV0304', 'Cột sống Ulrich', 'Vật tư riêng lẻ - Cột sống Ulrich', 'Ốc khóa Cosmic', 840000, 'chinh', 1, 200, 'CS 2605', '622'),
  ('Tấn Phạm', 'BV0304', 'Cột sống Ulrich', 'Vật tư riêng lẻ - Cột sống Ulrich', 'Ốc khóa Cosmic', 840000, 'chinh', 2, 160, 'CS 2605', '1034'),
  ('Tùng Phạm', 'BV0333', 'BXMCS', 'Vật tư riêng lẻ - CHCS Khác', 'Xi măng cột sống', 6500000, 'chinh', 1, 30, '01-0350', '742'),
  ('Tứ Nguyễn', 'BV1432', 'NSK Arthrex', 'Vật tư riêng lẻ - NSK Arthrex', 'Chỉ tròn kèm kim', 1200000, 'chinh', 1, 100, 'AR-7206', '767'),
  ('Tứ Nguyễn', 'BV1432', 'NSK Arthrex', 'Vật tư riêng lẻ - NSK Arthrex', 'Vít treo TightRope', 12700000, 'chinh', 1, 200, 'AR-1588RT', '768'),
  ('Tứ Nguyễn', 'BV1432', 'NSK Arthrex', 'Vật tư riêng lẻ - NSK Arthrex', 'Vít treo TightRope', 12700000, 'chinh', 2, 300, 'AR-1588RT', '860'),
  ('Tứ Nguyễn', 'BV1432', 'NSK Arthrex', 'Vật tư riêng lẻ - NSK Arthrex', 'Lưỡi bào khớp', 4285714, 'chinh', 2, 240, 'AR-8xx0EX', '856,863'),
  ('Tứ Nguyễn', 'BV1432', 'NSK Arthrex', 'Vật tư riêng lẻ - NSK Arthrex', 'Đầu đốt RF', 7333334, 'chinh', 2, 240, 'AR-9811', '857,864'),
  ('Tứ Nguyễn', 'BV1432', 'NSK Arthrex', 'Vật tư riêng lẻ - NSK Arthrex', 'Dây nước', 1428571, 'chinh', 2, 240, 'AR-6410', '858,870');
CREATE TEMP TABLE _sp (ps text, kh text, khach_hang text, mien text, bu text, nhom text, bvt text, sp text, ma_sp text, ma_bvt text, gia numeric) ON COMMIT DROP;
INSERT INTO _sp VALUES
  ('Mậu Cao', 'BV0336', 'Bệnh viện Trung Ương Quân đội 108', 'Miền Bắc', 'chcs', 'BXMCS', 'Vật tư riêng lẻ - CHCS Khác', 'Kim dò cuống sống VPL', 'V-PLASTY', 'BXM.VTRL', 1470000),
  ('Mậu Cao', 'BV0336', 'Bệnh viện Trung Ương Quân đội 108', 'Miền Bắc', 'chcs', 'BXMCS', 'Vật tư riêng lẻ - CHCS Khác', 'Kim trút', 'KSFILLER1', 'BXM.VTRL', 1712500),
  ('Mậu Cao', 'BV0336', 'Bệnh viện Trung Ương Quân đội 108', 'Miền Bắc', 'chcs', 'BXMCS', 'Vật tư riêng lẻ - CHCS Khác', 'Kim dò cuống sống Bevel', 'KSBEVEL', 'BXM.VTRL', 2000000),
  ('Mậu Cao', 'BV0336', 'Bệnh viện Trung Ương Quân đội 108', 'Miền Bắc', 'chcs', 'BXMCS', 'Vật tư riêng lẻ - CHCS Khác', 'Khoan tay', 'KSDRILL', 'BXM.VTRL', 2000000),
  ('Tuyên Phạm', 'BV0342', 'Bệnh Viện Hữu Nghị Việt Đức', 'Miền Bắc', 'chcs', 'NSK Arthrex', 'Vật tư riêng lẻ - NSK Arthrex', 'Kim hai thân', 'AR-7523', 'AR.VTRL', 5100000),
  ('Mậu Cao', 'BV0336', 'Bệnh viện Trung Ương Quân đội 108', 'Miền Bắc', 'chcs', 'BXMCS', 'Vật tư riêng lẻ - CHCS Khác', 'Xi măng cột sống', '01-0350', 'BXM.VTRL', 6825000),
  ('Mậu Cao', 'BV0336', 'Bệnh viện Trung Ương Quân đội 108', 'Miền Bắc', 'chcs', 'BXMCS', 'Vật tư riêng lẻ - CHCS Khác', 'Thiết bị bơm xi măng', '110190', 'BXM.VTRL', 6825000),
  ('Mậu Cao', 'BV0308', 'Bệnh viện Đại học Y Hà Nội', 'Miền Bắc', 'chcs', 'Cột sống Ulrich', 'Vật tư riêng lẻ - Cột sống Ulrich', 'Nẹp cổ trước Artus 3 tầng', 'CS 9102-03', 'UL.VTRL', 9680000),
  ('Tuyên Phạm', 'BV0342', 'Bệnh Viện Hữu Nghị Việt Đức', 'Miền Bắc', 'chcs', 'Khớp UOC', 'Vật tư riêng lẻ - Khớp UOC', 'Miếng ghép mâm chày', '2803-52x', 'UO.VTRL', 11600000),
  ('Tuyên Phạm', 'BV0342', 'Bệnh Viện Hữu Nghị Việt Đức', 'Miền Bắc', 'chcs', 'Khớp UOC', 'Vật tư riêng lẻ - Khớp UOC', 'Miếng ghép lồi cầu đùi', '2603-2803', 'UO.VTRL', 11600000),
  ('Mậu Cao', 'BV0336', 'Bệnh viện Trung Ương Quân đội 108', 'Miền Bắc', 'chcs', 'BXMCS', 'Vật tư riêng lẻ - CHCS Khác', 'Bóng nong', 'KSBAL', 'BXM.VTRL', 12000000),
  ('Tuyên Phạm', 'BV0342', 'Bệnh Viện Hữu Nghị Việt Đức', 'Miền Bắc', 'chcs', 'Khớp UOC', 'Vật tư riêng lẻ - Khớp UOC', 'Chuôi thẳng nối dài PSA', '2703 thang', 'UO.VTRL', 12960000),
  ('Tuyên Phạm', 'BV0342', 'Bệnh Viện Hữu Nghị Việt Đức', 'Miền Bắc', 'chcs', 'Khớp UOC', 'Vật tư riêng lẻ - Khớp UOC', 'Đầu chuyển trục chuôi', '2903', 'UO.VTRL', 9680000),
  ('Tứ Nguyễn', 'BV1432', 'Bệnh Viện Chấn Thương Chỉnh Hình Nghệ An (1115142)', 'Miền Bắc', 'chcs', 'NSK Arthrex', 'Vật tư riêng lẻ - NSK Arthrex', 'Mũi khoan ngược', 'AR-1204AF-xx', 'AR.VTRL', 4500000),
  ('Tứ Nguyễn', 'BV1432', 'Bệnh Viện Chấn Thương Chỉnh Hình Nghệ An (1115142)', 'Miền Bắc', 'chcs', 'NSK Arthrex', 'Vật tư riêng lẻ - NSK Arthrex', 'Vít Biocomposit ACL', 'AR-5035TC-xx', 'AR.VTRL', 6800000),
  ('Tứ Nguyễn', 'BV1432', 'Bệnh Viện Chấn Thương Chỉnh Hình Nghệ An (1115142)', 'Miền Bắc', 'chcs', 'NSK Arthrex', 'Vật tư riêng lẻ - NSK Arthrex', 'Vít neo Swivelock BC kèm chỉ', 'AR-2324BCCT', 'AR.VTRL', 13400000),
  ('Tứ Nguyễn', 'BV1432', 'Bệnh Viện Chấn Thương Chỉnh Hình Nghệ An (1115142)', 'Miền Bắc', 'chcs', 'NSK Arthrex', 'Vật tư riêng lẻ - NSK Arthrex', 'Vít neo Swivelock BC', 'AR-2324BCC', 'AR.VTRL', 11100000),
  ('Tứ Nguyễn', 'BV1432', 'Bệnh Viện Chấn Thương Chỉnh Hình Nghệ An (1115142)', 'Miền Bắc', 'chcs', 'NSK Arthrex', 'Vật tư riêng lẻ - NSK Arthrex', 'Lưỡi mài khớp', 'AR-8xx0OBx', 'AR.VTRL', 5200000),
  ('Tứ Nguyễn', 'BV1432', 'Bệnh Viện Chấn Thương Chỉnh Hình Nghệ An (1115142)', 'Miền Bắc', 'chcs', 'NSK Arthrex', 'Vật tư riêng lẻ - NSK Arthrex', 'Troca có ren', 'AR-65xx', 'AR.VTRL', 1150000),
  ('Tuyên Phạm', 'BV0310', 'Bệnh Viện Đa Khoa Bắc Ninh Số 1', 'Miền Bắc', 'chcs', 'NSK Arthrex', 'Vật tư riêng lẻ - NSK Arthrex', 'Troca có ren', 'AR-65xx', 'AR.VTRL', 1150000),
  ('Tuyên Phạm', 'BV0310', 'Bệnh Viện Đa Khoa Bắc Ninh Số 1', 'Miền Bắc', 'chcs', 'NSK Arthrex', 'Vật tư riêng lẻ - NSK Arthrex', 'Chỉ tròn kèm kim', 'AR-7200', 'AR.VTRL', 1200000),
  ('Tuyên Phạm', 'BV0310', 'Bệnh Viện Đa Khoa Bắc Ninh Số 1', 'Miền Bắc', 'chcs', 'NSK Arthrex', 'Vật tư riêng lẻ - NSK Arthrex', 'Vít treo TightRope', 'AR-1588RT', 'AR.VTRL', 12700000),
  ('Tuyên Phạm', 'BV0310', 'Bệnh Viện Đa Khoa Bắc Ninh Số 1', 'Miền Bắc', 'chcs', 'NSK Arthrex', 'Vật tư riêng lẻ - NSK Arthrex', 'TightRope khớp chày mác', 'AR-8926T', 'AR.VTRL', 36400000),
  ('Tứ Nguyễn', 'BV0488', 'Bệnh viện Bưu Điện', 'Miền Bắc', 'chcs', 'Cột sống Ulrich', 'Vật tư riêng lẻ - Cột sống Ulrich', 'Nẹp Cosmic 100-120mm', 'CS 2608-100-120', 'UL.VTRL', 1650000),
  ('Tứ Nguyễn', 'BV0488', 'Bệnh viện Bưu Điện', 'Miền Bắc', 'chcs', 'Cột sống Ulrich', 'Vật tư riêng lẻ - Cột sống Ulrich', 'Thanh dọc thường 500mm', 'CS 3807-500mm', 'UL.VTRL', 5500000),
  ('Tuyên Phạm', 'BV0310', 'Bệnh Viện Đa Khoa Bắc Ninh Số 1', 'Miền Bắc', 'chcs', 'NSK Arthrex', 'Vật tư riêng lẻ - NSK Arthrex', 'Lưỡi mài khớp', 'AR-8xx0OBx', 'AR.VTRL', 5200000),
  ('Tuyên Phạm', 'BV0310', 'Bệnh Viện Đa Khoa Bắc Ninh Số 1', 'Miền Bắc', 'chcs', 'NSK Arthrex', 'Vật tư riêng lẻ - NSK Arthrex', 'Mũi khoan ngược', 'AR-1204AF-xx', 'AR.VTRL', 4500000),
  ('Tuyên Phạm', 'BV0310', 'Bệnh Viện Đa Khoa Bắc Ninh Số 1', 'Miền Bắc', 'chcs', 'NSK Arthrex', 'Vật tư riêng lẻ - NSK Arthrex', 'Vít neo Pushlock', 'AR-2923BC', 'AR.VTRL', 8900000),
  ('Tuyên Phạm', 'BV0310', 'Bệnh Viện Đa Khoa Bắc Ninh Số 1', 'Miền Bắc', 'chcs', 'NSK Arthrex', 'Vật tư riêng lẻ - NSK Arthrex', 'Cây móc chỉ', 'AR-4068-xxx', 'AR.VTRL', 5900000);
INSERT INTO _ins VALUES
  ('Tứ Nguyễn', 'BV0368', 'Cột sống Ulrich', 'Vật tư riêng lẻ - Cột sống Ulrich', 'Ốc khóa trong 01', 1000000, 'cu', 1, 0, 'CS 3801-01', '20'),
  ('Tùng Phạm', 'BV0523', 'NSK Arthrex', 'Vật tư riêng lẻ - NSK Arthrex', 'Chỉ tròn kèm kim', 1200000, 'cu', 1, 200, 'AR-7200', '38'),
  ('Tùng Phạm', 'BV0458', 'NSK Arthrex', 'Vật tư riêng lẻ - NSK Arthrex', 'Chỉ tròn kèm kim', 1200000, 'cu', 1, 1, 'AR-7200', '43'),
  ('Tùng Phạm', 'BV0458', 'NSK Arthrex', 'Vật tư riêng lẻ - NSK Arthrex', 'Chỉ tròn kèm kim', 1200000, 'chinh', 1, 1, 'AR-7200', '729'),
  ('Mậu Cao', 'BV0336', 'BXMCS', 'Vật tư riêng lẻ - CHCS Khác', 'Kim dò cuống sống VPL', 1470000, 'cu', 1, 100, 'V-PLASTY', '59'),
  ('Mậu Cao', 'BV0336', 'BXMCS', 'Vật tư riêng lẻ - CHCS Khác', 'Kim trút', 1712500, 'cu', 1, 200, 'KSFILLER1', '73'),
  ('Mậu Cao', 'BV0336', 'BXMCS', 'Vật tư riêng lẻ - CHCS Khác', 'Kim dò cuống sống Bevel', 2000000, 'cu', 1, 100, 'KSBEVEL', '81'),
  ('Mậu Cao', 'BV0336', 'BXMCS', 'Vật tư riêng lẻ - CHCS Khác', 'Khoan tay', 2000000, 'cu', 1, 100, 'KSDRILL', '82'),
  ('Tuyên Phạm', 'BV0342', 'NSK Arthrex', 'Vật tư riêng lẻ - NSK Arthrex', 'Kim hai thân', 5100000, 'cu', 1, 10, 'AR-7523', '155'),
  ('Tứ Nguyễn', 'BV0368', 'Cột sống Ulrich', 'Vật tư riêng lẻ - Cột sống Ulrich', 'Vít đa trục thường', 5500000, 'cu', 1, 0, 'CS 3882', '178'),
  ('Mậu Cao', 'BV0336', 'BXMCS', 'Vật tư riêng lẻ - CHCS Khác', 'Xi măng cột sống', 6825000, 'cu', 1, 100, '01-0350', '205'),
  ('Mậu Cao', 'BV0336', 'BXMCS', 'Vật tư riêng lẻ - CHCS Khác', 'Thiết bị bơm xi măng', 6825000, 'cu', 1, 100, '110190', '206'),
  ('Mậu Cao', 'BV0308', 'Cột sống Ulrich', 'Vật tư riêng lẻ - Cột sống Ulrich', 'Nẹp cổ trước Artus 3 tầng', 9680000, 'cu', 1, 40, 'CS 9102-03', '299'),
  ('Tuyên Phạm', 'BV0342', 'Khớp UOC', 'Vật tư riêng lẻ - Khớp UOC', 'Miếng ghép mâm chày', 11600000, 'cu', 1, 50, '2803-52x', '337'),
  ('Tuyên Phạm', 'BV0342', 'Khớp UOC', 'Vật tư riêng lẻ - Khớp UOC', 'Miếng ghép lồi cầu đùi', 11600000, 'cu', 1, 50, '2603-2803', '338'),
  ('Mậu Cao', 'BV0336', 'BXMCS', 'Vật tư riêng lẻ - CHCS Khác', 'Bóng nong', 12000000, 'cu', 1, 100, 'KSBAL', '347'),
  ('Tuyên Phạm', 'BV0342', 'Khớp UOC', 'Vật tư riêng lẻ - Khớp UOC', 'Chuôi thẳng nối dài PSA', 12960000, 'cu', 1, 50, '2703 thang', '369'),
  ('Tứ Nguyễn', 'BV0368', 'BXMCS', 'BXM có bóng', 'BXM có bóng', 52500000, 'cu', 1, 0, 'BI.KYP1', '468'),
  ('Mậu Cao', 'BV0294', 'Khớp UOC', 'Bipolar dài - UOC', 'Bipolar dài - UOC', 58290000, 'chinh', 1, 25, 'UO.HBPD1', '547'),
  ('Mậu Cao', 'BV0294', 'Khớp UOC', 'Bipolar dài - UOC', 'Bipolar dài - UOC', 58290000, 'bo_sung', 1, 1, 'UO.HBPD1', '579'),
  ('Mậu Cao', 'BV0298', 'NSK Arthrex', 'Vật tư riêng lẻ - NSK Arthrex', 'Vít neo Swivelock PEEK', 8100000, 'chinh', 1, 44, 'AR-2324PCT', '555'),
  ('Mậu Cao', 'BV0342', 'BXMCS', 'Vật tư riêng lẻ - CHCS Khác', 'Xi măng cột sống', 6500000, 'chinh', 1, 700, '01-0350', '641'),
  ('Tùng Phạm', 'BV0458', 'NSK Arthrex', 'Vít treo TightRope (bộ cố định vỏ xương chày)', 'Vít treo TightRope (bộ cố định vỏ xương chày)', 11450000, 'chinh', 1, 40, 'AR.KNEE.1', '713'),
  ('Tuyên Phạm', 'BV0342', 'Khớp UOC', 'Vật tư riêng lẻ - Khớp UOC', 'Đầu chuyển trục chuôi', 9680000, 'bo_sung', 1, 50, '2903', '814'),
  ('Tứ Nguyễn', 'BV1432', 'NSK Arthrex', 'Vật tư riêng lẻ - NSK Arthrex', 'Chỉ tròn kèm kim', 1200000, 'chinh', 2, 150, 'AR-7200', '859'),
  ('Tứ Nguyễn', 'BV1432', 'NSK Arthrex', 'Vật tư riêng lẻ - NSK Arthrex', 'Mũi khoan ngược', 4500000, 'chinh', 2, 5, 'AR-1204AF-xx', '861'),
  ('Tứ Nguyễn', 'BV1432', 'NSK Arthrex', 'Vật tư riêng lẻ - NSK Arthrex', 'Vít Biocomposit ACL', 6800000, 'chinh', 2, 5, 'AR-5035TC-xx', '862'),
  ('Tứ Nguyễn', 'BV1432', 'NSK Arthrex', 'Vật tư riêng lẻ - NSK Arthrex', 'Vít neo Swivelock BC kèm chỉ', 13400000, 'chinh', 2, 180, 'AR-2324BCCT', '865'),
  ('Tứ Nguyễn', 'BV1432', 'NSK Arthrex', 'Vật tư riêng lẻ - NSK Arthrex', 'Vít neo Swivelock BC', 11100000, 'chinh', 2, 180, 'AR-2324BCC', '866'),
  ('Tứ Nguyễn', 'BV1432', 'NSK Arthrex', 'Vật tư riêng lẻ - NSK Arthrex', 'Lưỡi mài khớp', 5200000, 'chinh', 2, 20, 'AR-8xx0OBx', '867'),
  ('Tứ Nguyễn', 'BV1432', 'NSK Arthrex', 'Vật tư riêng lẻ - NSK Arthrex', 'Troca có ren', 1150000, 'chinh', 2, 10, 'AR-65xx', '869'),
  ('Tuyên Phạm', 'BV0310', 'NSK Arthrex', 'Vật tư riêng lẻ - NSK Arthrex', 'Troca có ren', 1150000, 'chinh', 2, 24, 'AR-65xx', '897'),
  ('Tuyên Phạm', 'BV0310', 'NSK Arthrex', 'Vật tư riêng lẻ - NSK Arthrex', 'Chỉ tròn kèm kim', 1200000, 'chinh', 2, 125, 'AR-7200', '898'),
  ('Tuyên Phạm', 'BV0310', 'NSK Arthrex', 'Vật tư riêng lẻ - NSK Arthrex', 'Vít treo TightRope', 12700000, 'chinh', 2, 430, 'AR-1588RT', '899,1063'),
  ('Tuyên Phạm', 'BV0310', 'NSK Arthrex', 'Vật tư riêng lẻ - NSK Arthrex', 'TightRope khớp chày mác', 36400000, 'chinh', 2, 20, 'AR-8926T', '900'),
  ('Tứ Nguyễn', 'BV0488', 'NSK Arthrex', 'Vật tư riêng lẻ - NSK Arthrex', 'Vít treo TightRope', 12700000, 'chinh', 1, 93, 'AR-1588RT', '926'),
  ('Tứ Nguyễn', 'BV0488', 'Cột sống Ulrich', 'Vật tư riêng lẻ - Cột sống Ulrich', 'Nẹp Cosmic 100-120mm', 1650000, 'chinh', 1, 3, 'CS 2608-100-120', '940'),
  ('Tứ Nguyễn', 'BV0488', 'Cột sống Ulrich', 'Vật tư riêng lẻ - Cột sống Ulrich', 'Thanh dọc thường 500mm', 5500000, 'chinh', 1, 8, 'CS 3807-500mm', '942'),
  ('Mậu Cao', 'BV0336', 'Cột sống Ulrich', 'ADD Plus', 'ADD Plus', 45000000, 'chinh', 1, 5, 'UL.ADD2', '967'),
  ('Mậu Cao', 'BV0336', 'Cột sống Ulrich', 'Obelisc', 'Obelisc', 56000000, 'chinh', 1, 5, 'UL.OBL', '969'),
  ('Tấn Phạm', 'BV0336', 'NSK Arthrex', 'Vật tư riêng lẻ - NSK Arthrex', 'Vít treo TightRope', 12700000, 'chinh', 1, 700, 'AR-1588RT', '1022'),
  ('Tấn Phạm', 'BV0304', 'NSK Arthrex', 'Vật tư riêng lẻ - NSK Arthrex', 'Vít treo TightRope', 12700000, 'chinh', 2, 60, 'AR-1588RT', '1036'),
  ('Tuyên Phạm', 'BV0310', 'NSK Arthrex', 'Vật tư riêng lẻ - NSK Arthrex', 'Lưỡi mài khớp', 5200000, 'chinh', 2, 140, 'AR-8xx0OBx', '1064'),
  ('Tuyên Phạm', 'BV0310', 'NSK Arthrex', 'Vật tư riêng lẻ - NSK Arthrex', 'Mũi khoan ngược', 4500000, 'chinh', 2, 300, 'AR-1204AF-xx', '1065'),
  ('Tuyên Phạm', 'BV0310', 'NSK Arthrex', 'Vật tư riêng lẻ - NSK Arthrex', 'Vít neo Pushlock', 8900000, 'chinh', 2, 8, 'AR-2923BC', '1068'),
  ('Tuyên Phạm', 'BV0310', 'NSK Arthrex', 'Vật tư riêng lẻ - NSK Arthrex', 'Cây móc chỉ', 5900000, 'chinh', 2, 8, 'AR-4068-xxx', '1069');
CREATE TEMP TABLE _mv (id bigint, dot_cu int, dot_moi int) ON COMMIT DROP;

CREATE TEMP TABLE _dot_sua (ps text, kh text, nhom text, loai text, dot int, thang_cu text, thang_moi text) ON COMMIT DROP;


DO $$
DECLARE v_n int;
BEGIN
  -- đợt mới chưa tồn tại
  SELECT count(*) INTO v_n FROM _dot_moi m JOIN shared.dot_thau d
    ON d.nam_tai_chinh = 'FY26' AND d.ps = m.ps AND d.ma_khach_hang = m.kh AND d.nhom_san_pham = m.nhom AND d.loai = m.loai AND d.dot = m.dot;
  IF v_n > 0 THEN RAISE EXCEPTION 'dong_bo: % đợt mới đã tồn tại', v_n; END IF;
  -- dòng sửa / xoá còn đúng SL lúc lập kế hoạch
  SELECT count(*) INTO v_n FROM _upd u LEFT JOIN shared.quota_thau q ON q.id = u.id WHERE q.id IS NULL OR q.so_luong <> u.sl_cu;
  IF v_n > 0 THEN RAISE EXCEPTION 'dong_bo: % dòng cần sửa đã đổi từ lúc lập kế hoạch', v_n; END IF;
  SELECT count(*) INTO v_n FROM _del u LEFT JOIN shared.quota_thau q ON q.id = u.id WHERE q.id IS NULL OR q.so_luong <> u.sl_cu;
  IF v_n > 0 THEN RAISE EXCEPTION 'dong_bo: % dòng cần xoá đã đổi từ lúc lập kế hoạch', v_n; END IF;
  -- sản phẩm mới chưa có trong kế hoạch (kể cả OOP cùng giá)
  SELECT count(*) INTO v_n FROM _sp p JOIN shared.sale_target s
    ON s.nam_tai_chinh = 'FY26' AND s.ps = p.ps AND s.ma_khach_hang = p.kh AND s.nhom_san_pham = p.nhom
   AND s.bo_vat_tu = p.bvt AND s.san_pham = p.sp AND s.don_gia = p.gia AND NOT coalesce(s.ngoai_ke_hoach, false);
  IF v_n > 0 THEN RAISE EXCEPTION 'dong_bo: % sản phẩm mới đã có trong kế hoạch', v_n; END IF;
END $$;

-- 0a. sửa tháng thầu đợt
DO $$
DECLARE v_n int;
BEGIN
  SELECT count(*) INTO v_n FROM _dot_sua x LEFT JOIN shared.dot_thau d
    ON d.nam_tai_chinh = 'FY26' AND d.ps = x.ps AND d.ma_khach_hang = x.kh AND d.nhom_san_pham = x.nhom AND d.loai = x.loai AND d.dot = x.dot
  WHERE d.id IS NULL OR d.thang_thau IS DISTINCT FROM x.thang_cu;
  IF v_n > 0 THEN RAISE EXCEPTION 'dong_bo: % đợt cần sửa tháng đã đổi', v_n; END IF;
  SELECT count(*) INTO v_n FROM _mv m LEFT JOIN shared.quota_thau q ON q.id = m.id WHERE q.id IS NULL OR q.dot <> m.dot_cu;
  IF v_n > 0 THEN RAISE EXCEPTION 'dong_bo: % quota cần chuyển đợt đã đổi', v_n; END IF;
END $$;
WITH o AS (SELECT d.* FROM shared.dot_thau d JOIN _dot_sua x
             ON d.nam_tai_chinh = 'FY26' AND d.ps = x.ps AND d.ma_khach_hang = x.kh AND d.nhom_san_pham = x.nhom AND d.loai = x.loai AND d.dot = x.dot),
u AS (UPDATE shared.dot_thau d SET thang_thau = x.thang_moi, updated_at = now(), updated_by = 'dong_bo_nh_mb_20261109c'
      FROM _dot_sua x WHERE d.nam_tai_chinh = 'FY26' AND d.ps = x.ps AND d.ma_khach_hang = x.kh AND d.nhom_san_pham = x.nhom
        AND d.loai = x.loai AND d.dot = x.dot RETURNING d.*)
INSERT INTO shared.quota_chuan_hoa_log (buoc, bang, ban_ghi_id, truoc, sau)
SELECT 'dong_bo_nh_mb_20261109c', 'dot_thau', u.id, to_jsonb(o), to_jsonb(u) FROM u JOIN o ON o.id = u.id;

-- 1. đợt mới
WITH n AS (
  INSERT INTO shared.dot_thau (nam_tai_chinh, bu, mien, ps, ma_khach_hang, nhom_san_pham, loai, dot, thang_thau, thoi_gian,
                               updated_by, trang_thai, nguon)
  SELECT 'FY26', 'chcs', 'Miền Bắc', m.ps, m.kh, m.nhom, m.loai, m.dot, m.thang, m.hl, 'dong_bo_nh_mb_20261109c', 'chinh_thuc', 'dong_bo_nh_mb_20261109c'
  FROM _dot_moi m RETURNING *)
INSERT INTO shared.quota_chuan_hoa_log (buoc, bang, ban_ghi_id, truoc, sau)
SELECT 'dong_bo_nh_mb_20261109c', 'dot_thau', n.id, NULL, to_jsonb(n) FROM n;

-- 2a. sửa SL
WITH o AS (SELECT q.* FROM shared.quota_thau q JOIN _upd u ON u.id = q.id),
u AS (UPDATE shared.quota_thau q SET so_luong = x.sl_moi, updated_at = now(), updated_by = 'dong_bo_nh_mb_20261109c'
      FROM _upd x WHERE q.id = x.id RETURNING q.*)
INSERT INTO shared.quota_chuan_hoa_log (buoc, bang, ban_ghi_id, truoc, sau)
SELECT 'dong_bo_nh_mb_20261109c', 'quota_thau', u.id, to_jsonb(o), to_jsonb(u) FROM u JOIN o ON o.id = u.id;

-- 2a'. chuyển quota sang đợt đúng (sau khi đã có đợt mới)
DO $$
DECLARE v_n int;
BEGIN
  SELECT count(*) INTO v_n FROM _mv m JOIN shared.quota_thau q ON q.id = m.id JOIN shared.quota_thau x
    ON x.nam_tai_chinh = q.nam_tai_chinh AND x.ps = q.ps AND x.ma_khach_hang = q.ma_khach_hang AND x.nhom_san_pham = q.nhom_san_pham
   AND x.bo_vat_tu = q.bo_vat_tu AND x.san_pham = q.san_pham AND x.don_gia = q.don_gia AND x.loai = q.loai AND x.dot = m.dot_moi;
  IF v_n > 0 THEN RAISE EXCEPTION 'dong_bo: % quota chuyển đợt bị trùng khoá', v_n; END IF;
END $$;
WITH o AS (SELECT q.* FROM shared.quota_thau q JOIN _mv m ON m.id = q.id),
u AS (UPDATE shared.quota_thau q SET dot = m.dot_moi, updated_at = now(), updated_by = 'dong_bo_nh_mb_20261109c'
      FROM _mv m WHERE q.id = m.id RETURNING q.*)
INSERT INTO shared.quota_chuan_hoa_log (buoc, bang, ban_ghi_id, truoc, sau)
SELECT 'dong_bo_nh_mb_20261109c', 'quota_thau', u.id, to_jsonb(o), to_jsonb(u) FROM u JOIN o ON o.id = u.id;

-- 2b. xoá
WITH d AS (DELETE FROM shared.quota_thau q USING _del x WHERE q.id = x.id RETURNING q.*)
INSERT INTO shared.quota_chuan_hoa_log (buoc, bang, ban_ghi_id, truoc, sau)
SELECT 'dong_bo_nh_mb_20261109c', 'quota_thau', d.id, to_jsonb(d), NULL FROM d;

-- 3a. sản phẩm mới vào kế hoạch (12 tháng)
CREATE TEMP TABLE _st_moi ON COMMIT DROP AS SELECT * FROM shared.sale_target WHERE false;
WITH n AS (
  INSERT INTO shared.sale_target (nam_tai_chinh, thang_ke_hoach, mien, ps, khach_hang, ma_khach_hang, nhom_san_pham, san_pham,
                                  bo_vat_tu, ma_san_pham, ma_bo_vat_tu, don_gia, bu, sl_ke_hoach_dau_nam, sl_thuc_hien)
  SELECT 'FY26', m.t, p.mien, p.ps, p.khach_hang, p.kh, p.nhom, p.sp, p.bvt, p.ma_sp, p.ma_bvt, p.gia, p.bu, 0, 0
  FROM _sp p CROSS JOIN (VALUES ('2026-04'), ('2026-05'), ('2026-06'), ('2026-07'), ('2026-08'), ('2026-09'), ('2026-10'), ('2026-11'), ('2026-12'), ('2027-01'), ('2027-02'), ('2027-03')) m(t)
  RETURNING *)
INSERT INTO _st_moi SELECT * FROM n;
INSERT INTO shared.quota_chuan_hoa_log (buoc, bang, ban_ghi_id, truoc, sau)
SELECT 'dong_bo_nh_mb_20261109c', 'sale_target', s.id, NULL, to_jsonb(s) FROM _st_moi s;

-- 3b. hấp thụ dòng OOP cùng tháng × PS × KH × bộ vật tư × SP (như absorbOop của "Thêm sản phẩm")
CREATE TEMP TABLE _oop ON COMMIT DROP AS
SELECT o.*, (SELECT min(s.id) FROM _st_moi s
             WHERE s.thang_ke_hoach = o.thang_ke_hoach AND lower(trim(s.ps)) = lower(trim(o.ps))
               AND lower(trim(s.ma_khach_hang)) = lower(trim(o.ma_khach_hang))
               AND lower(trim(s.bo_vat_tu)) = lower(trim(o.bo_vat_tu)) AND lower(trim(s.san_pham)) = lower(trim(o.san_pham))) AS dich
FROM shared.sale_target o
WHERE o.ngoai_ke_hoach AND o.ma_khach_hang IN (SELECT kh FROM _sp);
DELETE FROM _oop WHERE dich IS NULL;
INSERT INTO shared.quota_chuan_hoa_log (buoc, bang, ban_ghi_id, truoc, sau)
SELECT 'dong_bo_nh_mb_20261109c_oop', 'sale_target', o.id, to_jsonb(o) - 'dich', jsonb_build_object('hap_thu_vao', o.dich) FROM _oop o;
UPDATE shared.sale_target s SET sl_thuc_hien = a.sl, doanh_thu_thuc_hien = a.dt, updated_at = now()
FROM (SELECT dich, sum(coalesce(sl_thuc_hien, 0)) sl, sum(coalesce(doanh_thu_thuc_hien, 0)) dt FROM _oop GROUP BY dich) a
WHERE s.id = a.dich;
DELETE FROM shared.sale_target s USING _oop o WHERE s.id = o.id;

-- 2c + 3c. thêm quota
DO $$
DECLARE v_n int;
BEGIN
  SELECT count(*) INTO v_n FROM _ins n
  WHERE NOT EXISTS (SELECT 1 FROM shared.sale_target s
                    WHERE s.nam_tai_chinh = 'FY26' AND s.ps = n.ps AND s.ma_khach_hang = n.kh AND s.nhom_san_pham = n.nhom
                      AND s.bo_vat_tu = n.bvt AND s.san_pham = n.sp AND s.don_gia = n.gia AND NOT coalesce(s.ngoai_ke_hoach, false));
  IF v_n > 0 THEN RAISE EXCEPTION 'dong_bo: % quota thêm không có dòng kế hoạch', v_n; END IF;
  SELECT count(*) INTO v_n FROM _ins n JOIN shared.quota_thau q
    ON q.nam_tai_chinh = 'FY26' AND q.ps = n.ps AND q.ma_khach_hang = n.kh AND q.nhom_san_pham = n.nhom AND q.bo_vat_tu = n.bvt
   AND q.san_pham = n.sp AND q.don_gia = n.gia AND q.loai = n.loai AND q.dot = n.dot;
  IF v_n > 0 THEN RAISE EXCEPTION 'dong_bo: % quota thêm trùng khoá đang có', v_n; END IF;
  SELECT count(*) INTO v_n FROM _ins n
  WHERE n.loai <> 'cu' AND NOT EXISTS (SELECT 1 FROM shared.dot_thau d
    WHERE d.nam_tai_chinh = 'FY26' AND d.ps = n.ps AND d.ma_khach_hang = n.kh AND d.nhom_san_pham = n.nhom
      AND d.loai = n.loai AND d.dot = n.dot AND d.thang_thau IS NOT NULL AND d.thoi_gian > 0);
  IF v_n > 0 THEN RAISE EXCEPTION 'dong_bo: % quota thêm thiếu đợt hợp lệ', v_n; END IF;
END $$;
WITH i AS (
  INSERT INTO shared.quota_thau (nam_tai_chinh, ps, ma_khach_hang, nhom_san_pham, bo_vat_tu, san_pham, don_gia, loai, dot,
                                 so_luong, bu, mien, khach_hang, updated_by, trang_thai, nguon, ma_san_pham)
  SELECT 'FY26', n.ps, n.kh, n.nhom, n.bvt, n.sp, n.gia, n.loai, n.dot, n.sl, s.bu, s.mien, s.khach_hang,
         'dong_bo_nh_mb_20261109c', 'chinh_thuc', 'dong_bo_nh_mb_20261109c', n.ma
  FROM _ins n CROSS JOIN LATERAL (
    SELECT s.bu, s.mien, s.khach_hang FROM shared.sale_target s
    WHERE s.nam_tai_chinh = 'FY26' AND s.ps = n.ps AND s.ma_khach_hang = n.kh AND s.nhom_san_pham = n.nhom
      AND s.bo_vat_tu = n.bvt AND s.san_pham = n.sp AND s.don_gia = n.gia AND NOT coalesce(s.ngoai_ke_hoach, false)
    ORDER BY s.id LIMIT 1) s
  RETURNING *)
INSERT INTO shared.quota_chuan_hoa_log (buoc, bang, ban_ghi_id, truoc, sau)
SELECT 'dong_bo_nh_mb_20261109c', 'quota_thau', i.id, NULL, to_jsonb(i) FROM i;

SET CONSTRAINTS shared.uq_sale_target_khoa IMMEDIATE;
COMMIT;
