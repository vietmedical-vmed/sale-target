-- Đồng bộ quota thầu CH&CS Miền Bắc theo file ngành hàng bản 09/11/2026 (user chốt 09/11):
--   1. Thêm 6 đợt thầu thiếu, tháng thầu = tháng "Ngày ký" trong file, hiệu lực = số tháng từ ngày ký
--      tới ngày hết hạn (chỉ đợt đã trúng; riêng VĐ Ulrich thêm đợt dự kiến 2027-03 theo file).
--   2. Sửa quota trên khoá kế hoạch đã có: 88 dòng đổi SL, 57 dòng xoá (SL file = 0 ở loại/đợt đó),
--      115 dòng thêm (loại/đợt file có mà HT chưa có). VĐ Ulrich giữ PS Mậu Cao; ĐHY HN gối U2 theo file.
--   3. Thêm 99 sản phẩm vào kế hoạch FY26 của PS (12 tháng, SL 0, hấp thụ dòng OOP cùng khoá như "Thêm sản phẩm"),
--      rồi nạp quota cho các sản phẩm đó.
-- File NH bỏ 4 dòng trùng BV K (dòng 52, 151, 287, 303). Log: shared.quota_chuan_hoa_log buoc 'dong_bo_nh_mb_20261109'.
-- Rollback: supabase/rollbacks/20261109110000_dong_bo_quota_nh_mb_ROLLBACK.sql
BEGIN;
SET CONSTRAINTS shared.uq_sale_target_khoa DEFERRED;

CREATE TEMP TABLE _dot_moi (ps text, kh text, nhom text, loai text, dot int, thang text, hl numeric) ON COMMIT DROP;
INSERT INTO _dot_moi VALUES
  ('Tuyên Phạm', 'BV0655', 'Cột sống Ulrich', 'chinh', 2, '2026-08', 12),
  ('Tấn Phạm', 'BV0313', 'Cột sống Ulrich', 'chinh', 2, '2026-10', 24),
  ('Tùng Phạm', 'BV0458', 'NSK Arthrex', 'chinh', 1, '2026-04', 12),
  ('Tứ Nguyễn', 'BV1432', 'Khớp UOC', 'chinh', 2, '2025-05', 20),
  ('Tứ Nguyễn', 'BV0488', 'Khớp UOC', 'chinh', 2, '2026-07', 12),
  ('Mậu Cao', 'BV0342', 'Cột sống Ulrich', 'chinh', 2, '2027-03', 12);
CREATE TEMP TABLE _upd (id bigint, sl_cu numeric, sl_moi numeric) ON COMMIT DROP;
INSERT INTO _upd VALUES
  (2036, 270, 780),
  (3705, 100, 210),
  (3710, 800, 920),
  (1854, 108, 300),
  (2237, 102, 120),
  (1910, 86, 72),
  (2344, 452, 270),
  (1806, 40, 250),
  (1796, 1000, 800),
  (4844, 6, 4),
  (2471, 12, 1),
  (2050, 12, 15),
  (3707, 25, 35),
  (3711, 200, 220),
  (4774, 10, 235),
  (4603, 7, 1),
  (2091, 196, 392),
  (2450, 1000, 800),
  (4710, 10, 40),
  (1863, 10, 34),
  (2064, 75, 55),
  (2357, 56, 116),
  (3706, 100, 210),
  (2166, 102, 120),
  (2096, 80, 60),
  (2490, 48, 52),
  (2452, 1200, 1000),
  (2030, 25, 20),
  (2171, 1000, 800),
  (4517, 321, 326),
  (2205, 300, 780),
  (2028, 400, 300),
  (1738, 320, 350),
  (1982, 400, 300),
  (2352, 14, 12),
  (2346, 20, 14),
  (1924, 15, 10),
  (5104, 350, 250),
  (5038, 89, 149),
  (1858, 648, 408),
  (3708, 10, 25),
  (5055, 523, 643),
  (5132, 350, 250),
  (2261, 10, 1),
  (1851, 10, 18),
  (1812, 10, 30),
  (2848, 20, 25),
  (1814, 68, 65),
  (1998, 50, 5),
  (2716, 10, 7),
  (2230, 4, 10),
  (2234, 10, 30),
  (2098, 8, 4),
  (2402, 16, 110),
  (2281, 62, 61),
  (1878, 10, 89),
  (2369, 12, 14),
  (1866, 8, 5),
  (1853, 12, 13),
  (2383, 50, 48),
  (1791, 19, 25),
  (2308, 83, 84),
  (5227, 200, 260),
  (5232, 10, 13),
  (5231, 50, 65),
  (5226, 400, 520),
  (5237, 43, 69),
  (6089, 10, 16),
  (5229, 50, 65),
  (5236, 37, 53),
  (3254, 70, 45),
  (5233, 250, 325),
  (2708, 22, 23),
  (2045, 1, 14),
  (5239, 24, 22),
  (5228, 200, 260),
  (5234, 23, 26),
  (5230, 5, 6),
  (5238, 1, 2),
  (5240, 10, 5),
  (5219, 100, 50),
  (2214, 13000, 12100),
  (1717, 10, 75),
  (2176, 10, 30),
  (1959, 10, 30),
  (2070, 85, 86),
  (2995, 20, 120),
  (3042, 20, 120);
CREATE TEMP TABLE _del (id bigint, sl_cu numeric) ON COMMIT DROP;
INSERT INTO _del VALUES
  (1832, 102),
  (5259, 210),
  (5241, 500),
  (5260, 30),
  (2455, 102),
  (3724, 20),
  (5257, 15),
  (5258, 15),
  (6228, 93),
  (6230, 700),
  (2539, 20),
  (2488, 4),
  (3378, 10),
  (3754, 6),
  (2341, 60),
  (1943, 6),
  (2325, 60),
  (2422, 11),
  (2253, 60),
  (2327, 10),
  (1884, 1),
  (2374, 70),
  (1922, 10),
  (5156, 5),
  (2197, 10),
  (2257, 10),
  (2157, 270),
  (2428, 60),
  (1774, 150),
  (2504, 40),
  (1742, 420),
  (4522, 30),
  (1750, 2),
  (2430, 9),
  (4615, 35),
  (2392, 45),
  (1867, 10),
  (3340, 10),
  (2420, 3),
  (3739, 20),
  (2113, 2),
  (1852, 2),
  (2456, 16),
  (2006, 1),
  (2354, 2),
  (1764, 2),
  (2175, 2),
  (1793, 4),
  (2078, 3),
  (2037, 3),
  (2332, 3),
  (1883, 5),
  (2182, 4),
  (2191, 1),
  (2360, 12),
  (2475, 30),
  (2010, 452);
CREATE TEMP TABLE _ins (ps text, kh text, nhom text, bvt text, sp text, gia numeric, loai text, dot int, sl numeric, ma text, dong text) ON COMMIT DROP;
INSERT INTO _ins VALUES
  ('Mậu Cao', 'BV0336', 'Cột sống Ulrich', 'Vật tư riêng lẻ - Cột sống Ulrich', 'Ốc khóa Cosmic', 840000, 'chinh', 1, 200, 'CS 2605', '980'),
  ('Mậu Cao', 'BV0336', 'Cột sống Ulrich', 'Vật tư riêng lẻ - Cột sống Ulrich', 'Ốc khóa trong 01', 1000000, 'chinh', 1, 150, 'CS 3801-01', '981'),
  ('Tứ Nguyễn', 'BV0625', 'Cột sống Ulrich', 'Vật tư riêng lẻ - Cột sống Ulrich', 'Ốc khóa trong 01', 1000000, 'chinh', 1, 80, 'CS 3801-01', '953'),
  ('Tứ Nguyễn', 'BV0488', 'NSK Arthrex', 'Vật tư riêng lẻ - NSK Arthrex', 'Troca có ren', 1150000, 'chinh', 1, 113, 'AR-65xx', '920'),
  ('Tấn Phạm', 'BV0336', 'NSK Arthrex', 'Vật tư riêng lẻ - NSK Arthrex', 'Troca có ren', 1150000, 'chinh', 1, 100, 'AR-65xx', '1028'),
  ('Tuyên Phạm', 'BV0655', 'Cột sống Ulrich', 'Vật tư riêng lẻ - Cột sống Ulrich', 'Vít Artus', 1400000, 'chinh', 2, 10, 'CS91', '603'),
  ('Mậu Cao', 'BV0336', 'Cột sống Ulrich', 'Vật tư riêng lẻ - Cột sống Ulrich', 'Vít Artus', 1400000, 'chinh', 1, 120, 'CS91', '978'),
  ('Tấn Phạm', 'BV0313', 'Cột sống Ulrich', 'Vật tư riêng lẻ - Cột sống Ulrich', 'Vít Artus', 1400000, 'chinh', 2, 92, 'CS91', '698'),
  ('Tuyên Phạm', 'BV0655', 'NSK Arthrex', 'Vật tư riêng lẻ - NSK Arthrex', 'Dây nước', 1428571, 'chinh', 1, 29, 'AR-6410', '598'),
  ('Tứ Nguyễn', 'BV0488', 'NSK Arthrex', 'Vật tư riêng lẻ - NSK Arthrex', 'Dây nước', 1428571, 'chinh', 1, 231, 'AR-6410', '913'),
  ('Tấn Phạm', 'BV0336', 'NSK Arthrex', 'Vật tư riêng lẻ - NSK Arthrex', 'Dây nước', 1428571, 'chinh', 1, 600, 'AR-6410', '1024'),
  ('Tùng Phạm', 'BV0458', 'NSK Arthrex', 'Vật tư riêng lẻ - NSK Arthrex', 'Dây nước', 1428571, 'chinh', 1, 100, 'AR-6410', '717'),
  ('Tuyên Phạm', 'BV0655', 'Cột sống Ulrich', 'Vật tư riêng lẻ - Cột sống Ulrich', 'Nẹp dọc Neon3 240mm', 1900000, 'chinh', 2, 5, 'CS 3910-240 (mm)', '564'),
  ('Tứ Nguyễn', 'BV0308', 'NSK Arthrex', 'Vật tư riêng lẻ - NSK Arthrex', 'Troca mềm', 1809524, 'cu', 1, 500, 'AR-6592-xx-xx', '76'),
  ('Tứ Nguyễn', 'BV1432', 'Cột sống Ulrich', 'Vật tư riêng lẻ - Cột sống Ulrich', 'Thanh dọc thường 100-180mm', 2100000, 'cu', 1, 37, 'CS 3807-100-180', '86'),
  ('Mậu Cao', 'BV0336', 'Cột sống Ulrich', 'Vật tư riêng lẻ - Cột sống Ulrich', 'Thanh dọc thường 100-180mm', 2100000, 'chinh', 1, 80, 'CS 3807-100-180', '972'),
  ('Tuyên Phạm', 'BV0655', 'NSK Arthrex', 'Vật tư riêng lẻ - NSK Arthrex', 'Lưỡi bào khớp', 4285714, 'chinh', 1, 29, 'AR-8xx0EX', '615'),
  ('Tứ Nguyễn', 'BV1432', 'Cột sống Ulrich', 'Vật tư riêng lẻ - Cột sống Ulrich', 'Xương nhân tạo 1cc', 4500000, 'cu', 1, 10, 'CS 6604-010', '119'),
  ('Tứ Nguyễn', 'BV0488', 'NSK Arthrex', 'Vật tư riêng lẻ - NSK Arthrex', 'Lưỡi bào khớp', 4500000, 'chinh', 1, 223, 'AR-8xx0EX', '914,925'),
  ('Tấn Phạm', 'BV0336', 'NSK Arthrex', 'Vật tư riêng lẻ - NSK Arthrex', 'Lưỡi bào khớp', 4285714, 'chinh', 1, 600, 'AR-8xx0EX', '1015'),
  ('Mậu Cao', 'BV0336', 'Cột sống Ulrich', 'Vật tư riêng lẻ - Cột sống Ulrich', 'Xương nhân tạo 1cc', 4500000, 'chinh', 1, 40, 'CS 6604-010', '971'),
  ('Tấn Phạm', 'BV0313', 'Cột sống Ulrich', 'Vật tư riêng lẻ - Cột sống Ulrich', 'Xương nhân tạo 1cc', 4500000, 'chinh', 2, 14, 'CS 6604-010', '684'),
  ('Tùng Phạm', 'BV0458', 'NSK Arthrex', 'Vật tư riêng lẻ - NSK Arthrex', 'Lưỡi bào khớp', 4285714, 'chinh', 1, 30, 'AR-8xx0EX', '721'),
  ('Tấn Phạm', 'BV0336', 'NSK Arthrex', 'Vật tư riêng lẻ - NSK Arthrex', 'Cây đẩy chỉ', 5000000, 'chinh', 1, 110, 'AR-13995N', '1025'),
  ('Tuyên Phạm', 'BV0655', 'Cột sống Ulrich', 'Vật tư riêng lẻ - Cột sống Ulrich', 'Vít cổ sau Neon3', 5100000, 'chinh', 2, 30, 'CS 390x', '562'),
  ('Tứ Nguyễn', 'BV0488', 'NSK Arthrex', 'Vật tư riêng lẻ - NSK Arthrex', 'Lưỡi mài khớp', 4952381, 'chinh', 1, 119, 'AR-8xx0OBx', '916'),
  ('Tấn Phạm', 'BV0336', 'NSK Arthrex', 'Vật tư riêng lẻ - NSK Arthrex', 'Lưỡi mài khớp', 4952381, 'chinh', 1, 60, 'AR-8xx0OBx', '1016'),
  ('Tùng Phạm', 'BV0458', 'NSK Arthrex', 'Vật tư riêng lẻ - NSK Arthrex', 'Lưỡi mài khớp', 4952381, 'chinh', 1, 10, 'AR-8xx0OBx', '724'),
  ('Tứ Nguyễn', 'BV0488', 'NSK Arthrex', 'Vật tư riêng lẻ - NSK Arthrex', 'Cây móc chỉ', 5900000, 'chinh', 1, 26, 'AR-4068-xxx', '923'),
  ('Tấn Phạm', 'BV0336', 'NSK Arthrex', 'Vật tư riêng lẻ - NSK Arthrex', 'Cây móc chỉ', 5619048, 'chinh', 1, 30, 'AR-4068-xxx', '1026'),
  ('Tấn Phạm', 'BV0336', 'NSK Arthrex', 'Vật tư riêng lẻ - NSK Arthrex', 'Vít Biocomposit ACL', 6800000, 'chinh', 1, 20, 'AR-5035TC-xx', '1020'),
  ('Tùng Phạm', 'BV0458', 'NSK Arthrex', 'Vật tư riêng lẻ - NSK Arthrex', 'Vít Biocomposit ACL', 6800000, 'chinh', 1, 35, 'AR-5035TC-xx', '718'),
  ('Tuyên Phạm', 'BV0655', 'Cột sống Ulrich', 'Vật tư riêng lẻ - Cột sống Ulrich', 'Nẹp cổ trước Artus 1 tầng', 7300000, 'chinh', 2, 1, 'CS 9102-01', '608'),
  ('Mậu Cao', 'BV0336', 'Cột sống Ulrich', 'Vật tư riêng lẻ - Cột sống Ulrich', 'Nẹp cổ trước Artus 1 tầng', 7300000, 'chinh', 1, 20, 'CS 9102-01', '973'),
  ('Tuyên Phạm', 'BV0655', 'NSK Arthrex', 'Vật tư riêng lẻ - NSK Arthrex', 'Đầu đốt RF', 7333334, 'chinh', 1, 29, 'AR-9811', '616'),
  ('Tứ Nguyễn', 'BV0488', 'NSK Arthrex', 'Vật tư riêng lẻ - NSK Arthrex', 'Đầu đốt RF', 7333334, 'chinh', 1, 176, 'AR-9811', '915'),
  ('Tấn Phạm', 'BV0336', 'NSK Arthrex', 'Vật tư riêng lẻ - NSK Arthrex', 'Đầu đốt RF', 7333334, 'chinh', 1, 600, 'AR-9811', '1014'),
  ('Tùng Phạm', 'BV0458', 'NSK Arthrex', 'Vật tư riêng lẻ - NSK Arthrex', 'Đầu đốt RF', 7333334, 'chinh', 1, 100, 'AR-9811', '726'),
  ('Tứ Nguyễn', 'BV1432', 'Cột sống Ulrich', 'Vật tư riêng lẻ - Cột sống Ulrich', 'Vít đa trục qua da', 8200000, 'chinh', 1, 120, 'CS 3802', '850'),
  ('Mậu Cao', 'BV0336', 'Cột sống Ulrich', 'Vật tư riêng lẻ - Cột sống Ulrich', 'Vít Cosmic', 8200000, 'chinh', 1, 200, 'CS 2600', '976'),
  ('Tứ Nguyễn', 'BV1432', 'Cột sống Ulrich', 'Vật tư riêng lẻ - Cột sống Ulrich', 'Thanh ngang uCentum', 8500000, 'chinh', 1, 12, 'CS 3810', '836'),
  ('Tứ Nguyễn', 'BV0488', 'NSK Arthrex', 'Vật tư riêng lẻ - NSK Arthrex', 'Vít neo Suturetak', 8600000, 'chinh', 1, 55, 'AR-1934BCF-2', '921'),
  ('Tứ Nguyễn', 'BV0488', 'NSK Arthrex', 'Vật tư riêng lẻ - NSK Arthrex', 'Vít neo Pushlock', 8900000, 'chinh', 1, 40, 'AR-2923BC', '922'),
  ('Tấn Phạm', 'BV0336', 'NSK Arthrex', 'Vật tư riêng lẻ - NSK Arthrex', 'Vít neo Pushlock', 8900000, 'chinh', 1, 150, 'AR-2923BC', '1019'),
  ('Tùng Phạm', 'BV0458', 'NSK Arthrex', 'Vật tư riêng lẻ - NSK Arthrex', 'Vít neo Pushlock', 8900000, 'chinh', 1, 60, 'AR-2923BC', '719'),
  ('Tứ Nguyễn', 'BV1432', 'Cột sống Ulrich', 'Vật tư riêng lẻ - Cột sống Ulrich', 'Cerv-X', 9000000, 'cu', 1, 29, 'CS 820x', '270'),
  ('Tuyên Phạm', 'BV0655', 'Cột sống Ulrich', 'Vật tư riêng lẻ - Cột sống Ulrich', 'Nẹp cổ trước Artus 2 tầng', 9172000, 'chinh', 2, 1, 'CS 9102-02', '607'),
  ('Mậu Cao', 'BV0336', 'Cột sống Ulrich', 'Vật tư riêng lẻ - Cột sống Ulrich', 'Nẹp cổ trước Artus 2 tầng', 9172000, 'chinh', 1, 10, 'CS 9102-02', '974'),
  ('Tấn Phạm', 'BV0313', 'Cột sống Ulrich', 'Vật tư riêng lẻ - Cột sống Ulrich', 'Nẹp cổ trước Artus 2 tầng', 9172000, 'chinh', 2, 10, 'CS 9102-02', '694'),
  ('Tấn Phạm', 'BV0313', 'Cột sống Ulrich', 'Vật tư riêng lẻ - Cột sống Ulrich', 'Nẹp cổ trước Artus 2 tầng', 9172000, 'cu', 1, 15, 'CS 9102-02', '290'),
  ('Mậu Cao', 'BV0336', 'Cột sống Ulrich', 'Vật tư riêng lẻ - Cột sống Ulrich', 'Nẹp cổ trước Artus 3 tầng', 10700000, 'chinh', 1, 5, 'CS 9102-03', '975'),
  ('Tấn Phạm', 'BV0313', 'Cột sống Ulrich', 'Vật tư riêng lẻ - Cột sống Ulrich', 'Nẹp cổ trước Artus 3 tầng', 10700000, 'chinh', 2, 4, 'CS 9102-03', '687'),
  ('Tấn Phạm', 'BV0313', 'Cột sống Ulrich', 'Vật tư riêng lẻ - Cột sống Ulrich', 'Nẹp cổ trước Artus 3 tầng', 10700000, 'cu', 1, 15, 'CS 9102-03', '307'),
  ('Tứ Nguyễn', 'BV0488', 'NSK Arthrex', 'Vật tư riêng lẻ - NSK Arthrex', 'Vít neo Swivelock BC', 11100000, 'chinh', 1, 269, 'AR-2324BCC', '919'),
  ('Tứ Nguyễn', 'BV0308', 'NSK Arthrex', 'Vật tư riêng lẻ - NSK Arthrex', 'Vít neo Swivelock BC', 11100000, 'cu', 1, 5, 'AR-2324BCC', '314,320'),
  ('Tấn Phạm', 'BV0336', 'NSK Arthrex', 'Vật tư riêng lẻ - NSK Arthrex', 'Vít neo Swivelock BC', 11100000, 'chinh', 1, 300, 'AR-2324BCC', '1021'),
  ('Tùng Phạm', 'BV0458', 'NSK Arthrex', 'Vật tư riêng lẻ - NSK Arthrex', 'Vít neo Swivelock BC', 11100000, 'chinh', 1, 60, 'AR-2324BCC', '712'),
  ('Tuyên Phạm', 'BV0655', 'NSK Arthrex', 'Vật tư riêng lẻ - NSK Arthrex', 'Vít treo TightRope', 12700000, 'chinh', 1, 58, 'AR-1588RT', '590'),
  ('Tùng Phạm', 'BV0458', 'NSK Arthrex', 'Vật tư riêng lẻ - NSK Arthrex', 'Vít treo TightRope', 12700000, 'chinh', 1, 100, 'AR-1588RT', '725'),
  ('Tứ Nguyễn', 'BV0488', 'NSK Arthrex', 'Vật tư riêng lẻ - NSK Arthrex', 'Vít neo Swivelock BC kèm chỉ', 13400000, 'chinh', 1, 269, 'AR-2324BCCT', '917'),
  ('Tấn Phạm', 'BV0336', 'NSK Arthrex', 'Vật tư riêng lẻ - NSK Arthrex', 'Vít neo Swivelock BC kèm chỉ', 13400000, 'chinh', 1, 500, 'AR-2324BCCT', '1018'),
  ('Tùng Phạm', 'BV0458', 'NSK Arthrex', 'Vật tư riêng lẻ - NSK Arthrex', 'Vít neo Swivelock BC kèm chỉ', 13400000, 'chinh', 1, 60, 'AR-2324BCCTT', '716'),
  ('Mậu Cao', 'BV0336', 'Cột sống Ulrich', 'ADD', 'ADD', 31000000, 'chinh', 1, 20, 'UL.ADD1', '966'),
  ('Tứ Nguyễn', 'BV0488', 'Khớp UOC', 'Bipolar thường - UOC', 'Bipolar thường - UOC', 39790000, 'chinh', 1, 110, 'UO.HBPT1', '931'),
  ('Tuyên Phạm', 'BV0655', 'Khớp UOC', 'Bipolar thường - UOC', 'Bipolar thường - UOC', 39790000, 'cu', 1, 2, 'UO.HBPT1', '446'),
  ('Tứ Nguyễn', 'BV0488', 'Khớp UOC', 'MOP - UOC', 'MOP - UOC', 55000000, 'chinh', 1, 20, 'UO.HTPT.MOP1', '928'),
  ('Tuyên Phạm', 'BV0310', 'Khớp UOC', 'MOP - UOC', 'MOP - UOC', 55000000, 'chinh', 1, 50, 'UO.HTPT.MOP1', '893'),
  ('Tuyên Phạm', 'BV0310', 'Khớp UOC', 'Gối thường - UOC', 'Gối thường - UOC', 58000000, 'chinh', 1, 80, 'UO.GTPT1', '895'),
  ('Tấn Phạm', 'BV0304', 'Khớp UOC', 'Bipolar dài - UOC', 'Bipolar dài - UOC', 58290000, 'chinh', 1, 10, 'UO.HBPD1', '1032'),
  ('Tứ Nguyễn', 'BV1432', 'Khớp UOC', 'Bipolar dài - UOC', 'Bipolar dài - UOC', 58290000, 'chinh', 2, 6, 'UO.HBPD1', '772'),
  ('Tứ Nguyễn', 'BV1432', 'Khớp UOC', 'Bipolar dài - UOC', 'Bipolar dài - UOC', 58290000, 'chinh', 1, 15, 'UO.HBPD1', '877'),
  ('Tuyên Phạm', 'BV0310', 'Khớp UOC', 'Bipolar dài - UOC', 'Bipolar dài - UOC', 58290000, 'chinh', 1, 180, 'UO.HBPD1', '891'),
  ('Tấn Phạm', 'BV0304', 'Khớp UOC', 'COP - UOC', 'COP - UOC', 63800000, 'chinh', 1, 20, 'UO.HTPT.COP1', '1031'),
  ('Tứ Nguyễn', 'BV0488', 'Khớp UOC', 'COP - UOC', 'COP - UOC', 63800000, 'chinh', 2, 43, 'UO.HTPT.COP1', '548'),
  ('Tứ Nguyễn', 'BV0488', 'Khớp UOC', 'Bipolar dài - UOC', 'Bipolar dài - UOC', 58290000, 'chinh', 2, 37, 'UO.HBPD1', '551'),
  ('Tứ Nguyễn', 'BV1432', 'Khớp UOC', 'Gối thường - UOC', 'Gối thường - UOC', 58000000, 'chinh', 2, 80, 'UO.GTPT1', '771'),
  ('Tứ Nguyễn', 'BV0488', 'Khớp UOC', 'Gối thường - UOC', 'Gối thường - UOC', 58000000, 'chinh', 2, 24, 'UO.GTPT1', '574'),
  ('Tứ Nguyễn', 'BV1432', 'Khớp UOC', 'Bipolar thường - UOC', 'Bipolar thường - UOC', 39790000, 'chinh', 1, 50, 'UO.HBPT1', '876'),
  ('Tứ Nguyễn', 'BV0488', 'Khớp UOC', 'Gối thay lại - UOC', 'Gối thay lại - UOC', 80080000, 'chinh', 2, 1, 'UO.GTL1', '606'),
  ('Tứ Nguyễn', 'BV0488', 'Khớp UOC', 'MOP dài - UOC', 'MOP dài - UOC', 73500000, 'chinh', 2, 10, 'UO.HTPD.MOP1', '614'),
  ('Tuyên Phạm', 'BV0655', 'Cột sống Ulrich', 'Vật tư riêng lẻ - Cột sống Ulrich', 'Ốc khóa trong 01', 1000000, 'chinh', 2, 120, 'CS 3801-01', '618'),
  ('Mậu Cao', 'BV0342', 'Cột sống Ulrich', 'Vật tư riêng lẻ - Cột sống Ulrich', 'Thanh dọc thường 30-95mm', 1100000, 'chinh', 2, 12000, 'CS 3807-30-95', '903'),
  ('Tùng Phạm', 'BV0333', 'Cột sống Ulrich', 'Vật tư riêng lẻ - Cột sống Ulrich', 'Vít đa trục thường', 5500000, 'chinh', 1, 270, 'CS 3882', '731'),
  ('Tùng Phạm', 'BV0333', 'Cột sống Ulrich', 'Vật tư riêng lẻ - Cột sống Ulrich', 'Kim nối bơm xi măng', 2500000, 'chinh', 1, 60, 'CS 3850-02', '732'),
  ('Tùng Phạm', 'BV0333', 'Cột sống Ulrich', 'Vật tư riêng lẻ - Cột sống Ulrich', 'Vít đa trục qua da', 8200000, 'chinh', 1, 150, 'CS 3802', '733'),
  ('Tùng Phạm', 'BV0333', 'Cột sống Ulrich', 'Vật tư riêng lẻ - Cột sống Ulrich', 'Vít Artus', 1400000, 'chinh', 1, 40, 'CS91', '734'),
  ('Tùng Phạm', 'BV0333', 'Cột sống Ulrich', 'Vật tư riêng lẻ - Cột sống Ulrich', 'Ốc khóa trong 01', 1000000, 'chinh', 1, 420, 'CS 3801-01', '735'),
  ('Tùng Phạm', 'BV0333', 'Cột sống Ulrich', 'Vật tư riêng lẻ - Cột sống Ulrich', 'Thanh dọc thẳng qua da <300mm', 3000000, 'chinh', 1, 30, 'CS 3808-300', '737'),
  ('Tùng Phạm', 'BV0333', 'Cột sống Ulrich', 'ADD', 'ADD', 31000000, 'chinh', 1, 2, 'UL.ADD1', '738'),
  ('Tùng Phạm', 'BV0333', 'Cột sống Ulrich', 'Vật tư riêng lẻ - Cột sống Ulrich', 'Nẹp cổ trước Artus 2 tầng', 9172000, 'chinh', 1, 4, 'CS 9102-02', '740'),
  ('Tùng Phạm', 'BV0333', 'Cột sống Ulrich', 'Vật tư riêng lẻ - Cột sống Ulrich', 'Thanh dọc thường 100-180mm', 2100000, 'chinh', 1, 35, 'CS 3807-100-180', '743'),
  ('Tứ Nguyễn', 'BV1432', 'Khớp UOC', 'COP - UOC', 'COP - UOC', 63800000, 'chinh', 2, 88, 'UO.HTPT.COP1', '769'),
  ('Tứ Nguyễn', 'BV1432', 'Khớp UOC', 'COP - UOC', 'COP - UOC', 63800000, 'chinh', 1, 32, 'UO.HTPT.COP1', '873'),
  ('Tứ Nguyễn', 'BV1432', 'Khớp UOC', 'MOP - UOC', 'MOP - UOC', 55000000, 'chinh', 2, 10, 'UO.HTPT.MOP1', '770'),
  ('Tứ Nguyễn', 'BV1432', 'Khớp UOC', 'MOP dài - UOC', 'MOP dài - UOC', 73500000, 'chinh', 2, 2, 'UO.HTPD.MOP1', '773'),
  ('Tứ Nguyễn', 'BV1432', 'Khớp UOC', 'MOP dài - UOC', 'MOP dài - UOC', 73500000, 'chinh', 1, 10, 'UO.HTPD.MOP1', '878'),
  ('Tứ Nguyễn', 'BV1432', 'Khớp UOC', 'MOP dài - UOC', 'MOP dài - UOC', 73500000, 'cu', 1, 10, 'UO.HTPD.MOP1', '786'),
  ('Tứ Nguyễn', 'BV1432', 'Khớp UOC', 'Gối thay lại - UOC', 'Gối thay lại - UOC', 80080000, 'chinh', 2, 3, 'UO.GTL1', '774'),
  ('Tuyên Phạm', 'BV0310', 'Khớp UOC', 'COP - UOC', 'COP - UOC', 63800000, 'chinh', 1, 150, 'UO.HTPT.COP1', '892'),
  ('Tứ Nguyễn', 'BV1432', 'Khớp UOC', 'COC - UOC', 'COC - UOC', 75800000, 'chinh', 1, 14, 'UO.HTPT.COC1', '871'),
  ('Tuyên Phạm', 'BV0310', 'Khớp UOC', 'Gối thay lại - UOC', 'Gối thay lại - UOC', 80080000, 'chinh', 1, 2, 'UO.GTL1', '896'),
  ('Tứ Nguyễn', 'BV1432', 'Cột sống Ulrich', 'ADD', 'ADD', 31000000, 'chinh', 1, 5, 'UL.ADD1', '837'),
  ('Tứ Nguyễn', 'BV0625', 'Khớp UOC', 'Bipolar thường - UOC', 'Bipolar thường - UOC', 39790000, 'chinh', 1, 5, 'UO.HBPT1', '946'),
  ('Tứ Nguyễn', 'BV0625', 'Khớp UOC', 'Bipolar dài - UOC', 'Bipolar dài - UOC', 58290000, 'chinh', 1, 2, 'UO.HBPD1', '947'),
  ('Tứ Nguyễn', 'BV0625', 'Khớp UOC', 'MOP - UOC', 'MOP - UOC', 55000000, 'chinh', 1, 2, 'UO.HTPT.MOP1', '948'),
  ('Tứ Nguyễn', 'BV0625', 'Khớp UOC', 'COP - UOC', 'COP - UOC', 63800000, 'chinh', 1, 2, 'UO.HTPT.COP1', '949'),
  ('Tứ Nguyễn', 'BV0625', 'Khớp UOC', 'COC - UOC', 'COC - UOC', 75800000, 'chinh', 1, 2, 'UO.HTPT.COC1', '950'),
  ('Tứ Nguyễn', 'BV0625', 'NSK Arthrex', 'Vật tư riêng lẻ - NSK Arthrex', 'Đầu đốt RF', 7333334, 'chinh', 1, 80, 'AR-9811', '958'),
  ('Tứ Nguyễn', 'BV0625', 'NSK Arthrex', 'Vật tư riêng lẻ - NSK Arthrex', 'Dây nước', 1428571, 'chinh', 1, 80, 'AR-6410', '959'),
  ('Tứ Nguyễn', 'BV0625', 'NSK Arthrex', 'Vật tư riêng lẻ - NSK Arthrex', 'Lưỡi bào khớp', 4285714, 'chinh', 1, 80, 'AR-8xx0EX', '960'),
  ('Tứ Nguyễn', 'BV0625', 'NSK Arthrex', 'Vật tư riêng lẻ - NSK Arthrex', 'Lưỡi mài khớp', 5200000, 'chinh', 1, 30, 'AR-8xx0OBx', '961'),
  ('Tứ Nguyễn', 'BV0625', 'NSK Arthrex', 'Vật tư riêng lẻ - NSK Arthrex', 'Troca có ren', 1150000, 'chinh', 1, 6, 'AR-65xx', '962'),
  ('Tứ Nguyễn', 'BV0625', 'NSK Arthrex', 'Vật tư riêng lẻ - NSK Arthrex', 'Vít treo TightRope', 12700000, 'chinh', 1, 40, 'AR-1588RT', '965'),
  ('Mậu Cao', 'BV0336', 'Cột sống Ulrich', 'Vật tư riêng lẻ - Cột sống Ulrich', 'Pezo-P', 12992000, 'chinh', 1, 25, 'CS 330x', '970'),
  ('Mậu Cao', 'BV0336', 'Cột sống Ulrich', 'Vật tư riêng lẻ - Cột sống Ulrich', 'Vít trượt', 7500000, 'chinh', 1, 20, 'CS 3885', '979');
CREATE TEMP TABLE _sp (ps text, kh text, khach_hang text, mien text, bu text, nhom text, bvt text, sp text, ma_sp text, ma_bvt text, gia numeric) ON COMMIT DROP;
INSERT INTO _sp VALUES
  ('Tứ Nguyễn', 'BV0368', 'CÔNG TY CỔ PHẦN BỆNH VIỆN HOÀN MỸ VINH', 'Miền Bắc', 'chcs', 'Cột sống Ulrich', 'Vật tư riêng lẻ - Cột sống Ulrich', 'Ốc khóa Flamenco', 'CS 8010', 'UL.VTRL', 600000),
  ('Tứ Nguyễn', 'BV0488', 'Bệnh viện Bưu Điện', 'Miền Bắc', 'chcs', 'Cột sống Ulrich', 'Vật tư riêng lẻ - Cột sống Ulrich', 'Ốc khóa Cosmic', 'CS 2605', 'UL.VTRL', 840000),
  ('Tứ Nguyễn', 'BV0368', 'CÔNG TY CỔ PHẦN BỆNH VIỆN HOÀN MỸ VINH', 'Miền Bắc', 'chcs', 'Cột sống Ulrich', 'Vật tư riêng lẻ - Cột sống Ulrich', 'Ốc khóa Cosmic', 'CS 2605', 'UL.VTRL', 840000),
  ('Tứ Nguyễn', 'BV0488', 'Bệnh viện Bưu Điện', 'Miền Bắc', 'chcs', 'Cột sống Ulrich', 'Vật tư riêng lẻ - Cột sống Ulrich', 'Ốc khóa trong 01', 'CS 3801-01', 'UL.VTRL', 1000000),
  ('Tùng Phạm', 'DN2753', 'BV Đa Khoa Quốc Tế Huế', 'Miền Bắc', 'chcs', 'NSK Arthrex', 'Vật tư riêng lẻ - NSK Arthrex', 'Troca có ren', 'AR-65xx', 'AR.VTRL', 1150000),
  ('Tùng Phạm', 'DN2753', 'BV Đa Khoa Quốc Tế Huế', 'Miền Bắc', 'chcs', 'NSK Arthrex', 'Vật tư riêng lẻ - NSK Arthrex', 'Chỉ tròn kèm kim', 'AR-7200', 'AR.VTRL', 1200000),
  ('Tứ Nguyễn', 'BV0368', 'CÔNG TY CỔ PHẦN BỆNH VIỆN HOÀN MỸ VINH', 'Miền Bắc', 'chcs', 'Cột sống Ulrich', 'Vật tư riêng lẻ - Cột sống Ulrich', 'Vít Artus', 'CS91', 'UL.VTRL', 1400000),
  ('Tuyên Phạm', 'BV0324', 'Bệnh viện Quân Y 103', 'Miền Bắc', 'chcs', 'BXMCS', 'Vật tư riêng lẻ - CHCS Khác', 'Kim dò cuống sống Bevel', 'KSBEVEL', 'BXM.VTRL', 2000000),
  ('Tứ Nguyễn', 'BV0488', 'Bệnh viện Bưu Điện', 'Miền Bắc', 'chcs', 'Cột sống Ulrich', 'Vật tư riêng lẻ - Cột sống Ulrich', 'Thanh dọc thường 100-180mm', 'CS 3807-100-180', 'UL.VTRL', 2100000),
  ('Tùng Phạm', 'BV0523', 'BV Đa Khoa Trung Ương Huế - Cơ Sở 2', 'Miền Bắc', 'chcs', 'NSK Arthrex', 'Vật tư riêng lẻ - NSK Arthrex', 'Chỉ dẹt xanh', 'AR-7237', 'AR.VTRL', 4200000),
  ('Tuyên Phạm', 'BV0324', 'Bệnh viện Quân Y 103', 'Miền Bắc', 'chcs', 'NSK Arthrex', 'Vật tư riêng lẻ - NSK Arthrex', 'Chỉ dẹt xanh', 'AR-7237', 'AR.VTRL', 4200000),
  ('Tấn Phạm', 'BV0304', 'Bệnh viện đa khoa tỉnh Thanh Hóa', 'Miền Bắc', 'chcs', 'NSK Arthrex', 'Vật tư riêng lẻ - NSK Arthrex', 'Mũi khoan ngược', 'AR-1204AF-xx', 'AR.VTRL', 4500000),
  ('Tùng Phạm', 'BV0338', 'Bệnh viện Đa Khoa Quốc tế Hải Phòng', 'Miền Bắc', 'chcs', 'NSK Arthrex', 'Vật tư riêng lẻ - NSK Arthrex', 'Mũi khoan ngược', 'AR-1204AF-xx', 'AR.VTRL', 4500000),
  ('Tứ Nguyễn', 'BV0368', 'CÔNG TY CỔ PHẦN BỆNH VIỆN HOÀN MỸ VINH', 'Miền Bắc', 'chcs', 'Cột sống Ulrich', 'Vật tư riêng lẻ - Cột sống Ulrich', 'Xương nhân tạo 1cc', 'CS 6604-010', 'UL.VTRL', 4500000),
  ('Tùng Phạm', 'BV0523', 'BV Đa Khoa Trung Ương Huế - Cơ Sở 2', 'Miền Bắc', 'chcs', 'NSK Arthrex', 'Vật tư riêng lẻ - NSK Arthrex', 'Cây đẩy chỉ', 'AR-13995N', 'AR.VTRL', 5000000),
  ('Tùng Phạm', 'DN2753', 'BV Đa Khoa Quốc Tế Huế', 'Miền Bắc', 'chcs', 'NSK Arthrex', 'Vật tư riêng lẻ - NSK Arthrex', 'Cây đẩy chỉ', 'AR-13995N', 'AR.VTRL', 5000000),
  ('Tuyên Phạm', 'BV0324', 'Bệnh viện Quân Y 103', 'Miền Bắc', 'chcs', 'NSK Arthrex', 'Vật tư riêng lẻ - NSK Arthrex', 'Vít chốt khớp cùng đòn', 'AR-2270', 'AR.VTRL', 5200000),
  ('Tùng Phạm', 'DN2753', 'BV Đa Khoa Quốc Tế Huế', 'Miền Bắc', 'chcs', 'NSK Arthrex', 'Vật tư riêng lẻ - NSK Arthrex', 'Lưỡi mài khớp', 'AR-8xx0OBx', 'AR.VTRL', 5200000),
  ('Tứ Nguyễn', 'BV0488', 'Bệnh viện Bưu Điện', 'Miền Bắc', 'chcs', 'Cột sống Ulrich', 'Vật tư riêng lẻ - Cột sống Ulrich', 'Vít đa trục thường', 'CS 3882', 'UL.VTRL', 5500000),
  ('Tứ Nguyễn', 'BV0368', 'CÔNG TY CỔ PHẦN BỆNH VIỆN HOÀN MỸ VINH', 'Miền Bắc', 'chcs', 'Cột sống Ulrich', 'Vật tư riêng lẻ - Cột sống Ulrich', 'Vít Flamenco', 'CS 8009', 'UL.VTRL', 5500000),
  ('Tùng Phạm', 'BV0523', 'BV Đa Khoa Trung Ương Huế - Cơ Sở 2', 'Miền Bắc', 'chcs', 'NSK Arthrex', 'Vật tư riêng lẻ - NSK Arthrex', 'Cây móc chỉ', 'AR-4068-xxx', 'AR.VTRL', 5900000),
  ('Tùng Phạm', 'BV0338', 'Bệnh viện Đa Khoa Quốc tế Hải Phòng', 'Miền Bắc', 'chcs', 'NSK Arthrex', 'Vật tư riêng lẻ - NSK Arthrex', 'Vít Biocomposit ACL', 'AR-5035TC-xx', 'AR.VTRL', 6800000),
  ('Tùng Phạm', 'DN2753', 'BV Đa Khoa Quốc Tế Huế', 'Miền Bắc', 'chcs', 'NSK Arthrex', 'Vật tư riêng lẻ - NSK Arthrex', 'Vít Biocomposit ACL', 'AR-5035TC-xx', 'AR.VTRL', 6800000),
  ('Tứ Nguyễn', 'BV0368', 'CÔNG TY CỔ PHẦN BỆNH VIỆN HOÀN MỸ VINH', 'Miền Bắc', 'chcs', 'Cột sống Ulrich', 'Vật tư riêng lẻ - Cột sống Ulrich', 'Nẹp cổ trước Artus 1 tầng', 'CS 9102-01', 'UL.VTRL', 7300000),
  ('Tứ Nguyễn', 'BV0488', 'Bệnh viện Bưu Điện', 'Miền Bắc', 'chcs', 'Cột sống Ulrich', 'Vật tư riêng lẻ - Cột sống Ulrich', 'Vít Cosmic', 'CS 2600', 'UL.VTRL', 8200000),
  ('Tứ Nguyễn', 'BV0368', 'CÔNG TY CỔ PHẦN BỆNH VIỆN HOÀN MỸ VINH', 'Miền Bắc', 'chcs', 'Cột sống Ulrich', 'Vật tư riêng lẻ - Cột sống Ulrich', 'Vít đa trục qua da', 'CS 3802', 'UL.VTRL', 8200000),
  ('Tứ Nguyễn', 'BV0368', 'CÔNG TY CỔ PHẦN BỆNH VIỆN HOÀN MỸ VINH', 'Miền Bắc', 'chcs', 'Cột sống Ulrich', 'Vật tư riêng lẻ - Cột sống Ulrich', 'Vít Cosmic', 'CS 2600', 'UL.VTRL', 8200000),
  ('Tứ Nguyễn', 'BV0368', 'CÔNG TY CỔ PHẦN BỆNH VIỆN HOÀN MỸ VINH', 'Miền Bắc', 'chcs', 'Cột sống Ulrich', 'Vật tư riêng lẻ - Cột sống Ulrich', 'Thanh ngang uCentum', 'CS 3810', 'UL.VTRL', 8500000),
  ('Tùng Phạm', 'BV0338', 'Bệnh viện Đa Khoa Quốc tế Hải Phòng', 'Miền Bắc', 'chcs', 'NSK Arthrex', 'Vật tư riêng lẻ - NSK Arthrex', 'Vít neo Suturetak', 'AR-1934BCF-2', 'AR.VTRL', 8600000),
  ('Tùng Phạm', 'BV0523', 'BV Đa Khoa Trung Ương Huế - Cơ Sở 2', 'Miền Bắc', 'chcs', 'NSK Arthrex', 'Vật tư riêng lẻ - NSK Arthrex', 'Vít neo Suturetak', 'AR-1934BCF-2', 'AR.VTRL', 8600000),
  ('Tùng Phạm', 'DN2753', 'BV Đa Khoa Quốc Tế Huế', 'Miền Bắc', 'chcs', 'NSK Arthrex', 'Vật tư riêng lẻ - NSK Arthrex', 'Vít neo Suturetak', 'AR-1934BCF-2', 'AR.VTRL', 8600000),
  ('Tùng Phạm', 'BV0458', 'Công Ty Cổ Phần Bệnh Viện Đa Khoa Tâm Anh', 'Miền Bắc', 'chcs', 'NSK Arthrex', 'Vật tư riêng lẻ - NSK Arthrex', 'Vít neo Suturetak', 'AR-1934BCF-2', 'AR.VTRL', 8600000),
  ('Tùng Phạm', 'BV0338', 'Bệnh viện Đa Khoa Quốc tế Hải Phòng', 'Miền Bắc', 'chcs', 'NSK Arthrex', 'Vật tư riêng lẻ - NSK Arthrex', 'Vít neo Pushlock', 'AR-2923BC', 'AR.VTRL', 8900000),
  ('Tùng Phạm', 'BV0523', 'BV Đa Khoa Trung Ương Huế - Cơ Sở 2', 'Miền Bắc', 'chcs', 'NSK Arthrex', 'Vật tư riêng lẻ - NSK Arthrex', 'Vít neo Pushlock', 'AR-2923BC', 'AR.VTRL', 8900000),
  ('Tùng Phạm', 'DN2753', 'BV Đa Khoa Quốc Tế Huế', 'Miền Bắc', 'chcs', 'NSK Arthrex', 'Vật tư riêng lẻ - NSK Arthrex', 'Vít neo Pushlock', 'AR-2923BC', 'AR.VTRL', 8900000),
  ('Tứ Nguyễn', 'BV0368', 'CÔNG TY CỔ PHẦN BỆNH VIỆN HOÀN MỸ VINH', 'Miền Bắc', 'chcs', 'Cột sống Ulrich', 'Vật tư riêng lẻ - Cột sống Ulrich', 'Cerv-X', 'CS 820x', 'UL.VTRL', 9000000),
  ('Tứ Nguyễn', 'BV0368', 'CÔNG TY CỔ PHẦN BỆNH VIỆN HOÀN MỸ VINH', 'Miền Bắc', 'chcs', 'Cột sống Ulrich', 'Vật tư riêng lẻ - Cột sống Ulrich', 'Nẹp cổ trước Artus 2 tầng', 'CS 9102-02', 'UL.VTRL', 9172000),
  ('Tuyên Phạm', 'BV0655', 'Bệnh viện Đa khoa Hà Đông', 'Miền Bắc', 'chcs', 'Cột sống Ulrich', 'Vật tư riêng lẻ - Cột sống Ulrich', 'Vít đa trục qua da', 'CS 3802', 'UL.VTRL', 9200000),
  ('Tứ Nguyễn', 'BV0488', 'Bệnh viện Bưu Điện', 'Miền Bắc', 'chcs', 'Khớp UOC', 'Vật tư riêng lẻ - Khớp UOC', 'Đầu chuyển trục chuôi', '2903', 'UO.VTRL', 9680000),
  ('Tuyên Phạm', 'BV0324', 'Bệnh viện Quân Y 103', 'Miền Bắc', 'chcs', 'Khớp UOC', 'Vật tư riêng lẻ - Khớp UOC', 'Đầu chuyển trục chuôi', '2903', 'UO.VTRL', 9680000),
  ('Tấn Phạm', 'BV0313', 'Bệnh Viện Hữu Nghị', 'Miền Bắc', 'chcs', 'Khớp UOC', 'Vật tư riêng lẻ - Khớp UOC', 'Đầu chuyển trục chuôi', '2903', 'UO.VTRL', 9680000),
  ('Tứ Nguyễn', 'BV0368', 'CÔNG TY CỔ PHẦN BỆNH VIỆN HOÀN MỸ VINH', 'Miền Bắc', 'chcs', 'Cột sống Ulrich', 'Vật tư riêng lẻ - Cột sống Ulrich', 'Nẹp cổ trước Artus 3 tầng', 'CS 9102-03', 'UL.VTRL', 10700000),
  ('Tứ Nguyễn', 'BV0488', 'Bệnh viện Bưu Điện', 'Miền Bắc', 'chcs', 'Khớp UOC', 'Vật tư riêng lẻ - Khớp UOC', 'Miếng ghép mâm chày', '2803-52x', 'UO.VTRL', 11600000),
  ('Tấn Phạm', 'BV0313', 'Bệnh Viện Hữu Nghị', 'Miền Bắc', 'chcs', 'Khớp UOC', 'Vật tư riêng lẻ - Khớp UOC', 'Miếng ghép lồi cầu đùi', '2603-2803', 'UO.VTRL', 11600000),
  ('Tuyên Phạm', 'BV0324', 'Bệnh viện Quân Y 103', 'Miền Bắc', 'chcs', 'Khớp UOC', 'Vật tư riêng lẻ - Khớp UOC', 'Miếng ghép lồi cầu đùi', '2603-2803', 'UO.VTRL', 11600000),
  ('Tấn Phạm', 'BV0313', 'Bệnh Viện Hữu Nghị', 'Miền Bắc', 'chcs', 'Khớp UOC', 'Vật tư riêng lẻ - Khớp UOC', 'Miếng ghép mâm chày', '2803-52x', 'UO.VTRL', 11600000),
  ('Tuyên Phạm', 'BV0324', 'Bệnh viện Quân Y 103', 'Miền Bắc', 'chcs', 'Khớp UOC', 'Vật tư riêng lẻ - Khớp UOC', 'Miếng ghép mâm chày', '2803-52x', 'UO.VTRL', 11600000),
  ('Tùng Phạm', 'BV0458', 'Công Ty Cổ Phần Bệnh Viện Đa Khoa Tâm Anh', 'Miền Bắc', 'chcs', 'Khớp UOC', 'Vật tư riêng lẻ - Khớp UOC', 'Miếng ghép mâm chày', '2803-52x', 'UO.VTRL', 11600000),
  ('Tuyên Phạm', 'BV0324', 'Bệnh viện Quân Y 103', 'Miền Bắc', 'chcs', 'NSK Arthrex', 'Vật tư riêng lẻ - NSK Arthrex', 'Vít neo Suturetak nhỏ', 'AR-1322BCNF', 'AR.VTRL', 12500000),
  ('Tùng Phạm', 'DN2753', 'BV Đa Khoa Quốc Tế Huế', 'Miền Bắc', 'chcs', 'NSK Arthrex', 'Vật tư riêng lẻ - NSK Arthrex', 'Vít treo TightRope', 'AR-1588RT', 'AR.VTRL', 12700000),
  ('Tứ Nguyễn', 'BV0488', 'Bệnh viện Bưu Điện', 'Miền Bắc', 'chcs', 'Khớp UOC', 'Vật tư riêng lẻ - Khớp UOC', 'Chuôi thẳng nối dài PSA', '2703 thang', 'UO.VTRL', 12960000),
  ('Tấn Phạm', 'BV0313', 'Bệnh Viện Hữu Nghị', 'Miền Bắc', 'chcs', 'Khớp UOC', 'Vật tư riêng lẻ - Khớp UOC', 'Chuôi thẳng nối dài PSA', '2703 thang', 'UO.VTRL', 12960000),
  ('Tuyên Phạm', 'BV0324', 'Bệnh viện Quân Y 103', 'Miền Bắc', 'chcs', 'Khớp UOC', 'Vật tư riêng lẻ - Khớp UOC', 'Chuôi thẳng nối dài PSA', '2703 thang', 'UO.VTRL', 12960000),
  ('Tứ Nguyễn', 'BV0308', 'Bệnh viện Đại học Y Hà Nội', 'Miền Bắc', 'chcs', 'Khớp UOC', 'Vật tư riêng lẻ - Khớp UOC', 'Chuôi thẳng nối dài PSA', '2703 thang', 'UO.VTRL', 12960000),
  ('Tứ Nguyễn', 'BV0488', 'Bệnh viện Bưu Điện', 'Miền Bắc', 'chcs', 'Cột sống Ulrich', 'Vật tư riêng lẻ - Cột sống Ulrich', 'Pezo-P', 'CS 330x', 'UL.VTRL', 12992000),
  ('Tùng Phạm', 'DN2753', 'BV Đa Khoa Quốc Tế Huế', 'Miền Bắc', 'chcs', 'NSK Arthrex', 'Vật tư riêng lẻ - NSK Arthrex', 'Vít neo Swivelock BC kèm chỉ', 'AR-2324BCCT', 'AR.VTRL', 13400000),
  ('Tuyên Phạm', 'BV0324', 'Bệnh viện Quân Y 103', 'Miền Bắc', 'chcs', 'NSK Arthrex', 'Vật tư riêng lẻ - NSK Arthrex', 'Vít neo Swivelock cho khớp nhỏ', 'AR-8978P', 'AR.VTRL', 13800000),
  ('Mậu Cao', 'BV0298', 'Bệnh viện Bạch Mai', 'Miền Bắc', 'chcs', 'Cột sống Ulrich', 'ADD', 'ADD', 'UL.ADD1', 'UL.ADD1', 31000000),
  ('Tứ Nguyễn', 'BV0368', 'CÔNG TY CỔ PHẦN BỆNH VIỆN HOÀN MỸ VINH', 'Miền Bắc', 'chcs', 'Cột sống Ulrich', 'ADD', 'ADD', 'UL.ADD1', 'UL.ADD1', 31000000),
  ('Tuyên Phạm', 'BV0324', 'Bệnh viện Quân Y 103', 'Miền Bắc', 'chcs', 'NSK Arthrex', 'Vật tư riêng lẻ - NSK Arthrex', 'Bộ chỉ khâu gân gót chân', 'AR-8860DS', 'AR.VTRL', 35000000),
  ('Tuyên Phạm', 'BV0324', 'Bệnh viện Quân Y 103', 'Miền Bắc', 'chcs', 'NSK Arthrex', 'Vật tư riêng lẻ - NSK Arthrex', 'TightRope khớp chày mác', 'AR-8926T', 'AR.VTRL', 36400000),
  ('Tùng Phạm', 'BV0458', 'Công Ty Cổ Phần Bệnh Viện Đa Khoa Tâm Anh', 'Miền Bắc', 'chcs', 'Khớp UOC', 'Bipolar thường - UOC', 'Bipolar thường - UOC', 'UO.HBPT1', 'UO.HBPT1', 39790000),
  ('Tấn Phạm', 'BV0354', 'BV Đa Khoa Hợp Lực', 'Miền Bắc', 'chcs', 'Khớp UOC', 'Bipolar thường - UOC', 'Bipolar thường - UOC', 'UO.HBPT1', 'UO.HBPT1', 39790000),
  ('Tấn Phạm', 'BV1446', 'Tổng CT Cổ Phần Hợp Lực-CN BV Đa Khoa Quốc Tế Hợp Lực', 'Miền Bắc', 'chcs', 'Khớp UOC', 'Bipolar thường - UOC', 'Bipolar thường - UOC', 'UO.HBPT1', 'UO.HBPT1', 39790000),
  ('Tứ Nguyễn', 'BV0368', 'CÔNG TY CỔ PHẦN BỆNH VIỆN HOÀN MỸ VINH', 'Miền Bắc', 'chcs', 'Cột sống Ulrich', 'ADD Plus', 'ADD Plus', 'UL.ADD2', 'UL.ADD2', 45000000),
  ('Tùng Phạm', 'BV0458', 'Công Ty Cổ Phần Bệnh Viện Đa Khoa Tâm Anh', 'Miền Bắc', 'chcs', 'Khớp UOC', 'MOP - UOC', 'MOP - UOC', 'UO.HTPT.MOP1', 'UO.HTPT.MOP1', 55000000),
  ('Tấn Phạm', 'BV0354', 'BV Đa Khoa Hợp Lực', 'Miền Bắc', 'chcs', 'Khớp UOC', 'MOP - UOC', 'MOP - UOC', 'UO.HTPT.MOP1', 'UO.HTPT.MOP1', 55000000),
  ('Tấn Phạm', 'BV1446', 'Tổng CT Cổ Phần Hợp Lực-CN BV Đa Khoa Quốc Tế Hợp Lực', 'Miền Bắc', 'chcs', 'Khớp UOC', 'MOP - UOC', 'MOP - UOC', 'UO.HTPT.MOP1', 'UO.HTPT.MOP1', 55000000),
  ('Tùng Phạm', 'BV0338', 'Bệnh viện Đa Khoa Quốc tế Hải Phòng', 'Miền Bắc', 'chcs', 'Khớp UOC', 'Gối thường - UOC', 'Gối thường - UOC', 'UO.GTPT1', 'UO.GTPT1', 58000000),
  ('Tùng Phạm', 'BV0458', 'Công Ty Cổ Phần Bệnh Viện Đa Khoa Tâm Anh', 'Miền Bắc', 'chcs', 'Khớp UOC', 'Gối thường - UOC', 'Gối thường - UOC', 'UO.GTPT1', 'UO.GTPT1', 58000000),
  ('Tấn Phạm', 'BV0354', 'BV Đa Khoa Hợp Lực', 'Miền Bắc', 'chcs', 'Khớp UOC', 'Gối thường - UOC', 'Gối thường - UOC', 'UO.GTPT1', 'UO.GTPT1', 58000000),
  ('Tùng Phạm', 'BV0458', 'Công Ty Cổ Phần Bệnh Viện Đa Khoa Tâm Anh', 'Miền Bắc', 'chcs', 'Khớp UOC', 'Bipolar dài - UOC', 'Bipolar dài - UOC', 'UO.HBPD1', 'UO.HBPD1', 58290000),
  ('Tấn Phạm', 'BV1446', 'Tổng CT Cổ Phần Hợp Lực-CN BV Đa Khoa Quốc Tế Hợp Lực', 'Miền Bắc', 'chcs', 'Khớp UOC', 'Bipolar dài - UOC', 'Bipolar dài - UOC', 'UO.HBPD1', 'UO.HBPD1', 58290000),
  ('Tuyên Phạm', 'BV0655', 'Bệnh viện Đa khoa Hà Đông', 'Miền Bắc', 'chcs', 'Cột sống Ulrich', 'Vật tư riêng lẻ - Cột sống Ulrich', 'Ốc khóa trong Neon3', 'CS 3901', 'UL.VTRL', 910000),
  ('Tứ Nguyễn', 'BV1432', 'Bệnh Viện Chấn Thương Chỉnh Hình Nghệ An (1115142)', 'Miền Bắc', 'chcs', 'Khớp UOC', 'Vật tư riêng lẻ - Khớp UOC', 'Miếng ghép mâm chày', '2803-52x', 'UO.VTRL', 11600000),
  ('Tứ Nguyễn', 'BV1432', 'Bệnh Viện Chấn Thương Chỉnh Hình Nghệ An (1115142)', 'Miền Bắc', 'chcs', 'Khớp UOC', 'Vật tư riêng lẻ - Khớp UOC', 'Chuôi thẳng nối dài PSA', '2703 thang', 'UO.VTRL', 12960000),
  ('Tuyên Phạm', 'BV0655', 'Bệnh viện Đa khoa Hà Đông', 'Miền Bắc', 'chcs', 'Khớp UOC', 'COP - UOC', 'COP - UOC', 'UO.HTPT.COP1', 'UO.HTPT.COP1', 63800000),
  ('Tùng Phạm', 'BV0306', 'Bệnh viện Đa khoa Xanh Pôn', 'Miền Bắc', 'chcs', 'NSK Arthrex', 'Vật tư riêng lẻ - NSK Arthrex', 'Lưỡi mài khớp', 'AR-8xx0OBx', 'AR.VTRL', 5200000),
  ('Tứ Nguyễn', 'BV0308', 'Bệnh viện Đại học Y Hà Nội', 'Miền Bắc', 'chcs', 'NSK Arthrex', 'Vật tư riêng lẻ - NSK Arthrex', 'Vít neo Pushlock', 'AR-2923BC', 'AR.VTRL', 8900000),
  ('Mậu Cao', 'BV0342', 'Bệnh Viện Hữu Nghị Việt Đức', 'Miền Bắc', 'chcs', 'Cột sống Ulrich', 'Vật tư riêng lẻ - Cột sống Ulrich', 'Nẹp dọc Neon3 20-100mm', 'CS 3910-20-100', 'UL.VTRL', 1000000),
  ('Tùng Phạm', 'BV0458', 'Công Ty Cổ Phần Bệnh Viện Đa Khoa Tâm Anh', 'Miền Bắc', 'chcs', 'Khớp UOC', 'COP - UOC', 'COP - UOC', 'UO.HTPT.COP1', 'UO.HTPT.COP1', 63800000),
  ('Tứ Nguyễn', 'BV1432', 'Bệnh Viện Chấn Thương Chỉnh Hình Nghệ An (1115142)', 'Miền Bắc', 'chcs', 'Khớp UOC', 'Vật tư riêng lẻ - Khớp UOC', 'Đầu chuyển trục chuôi', '2903', 'UO.VTRL', 9680000),
  ('Tấn Phạm', 'BV0354', 'BV Đa Khoa Hợp Lực', 'Miền Bắc', 'chcs', 'Khớp UOC', 'COP - UOC', 'COP - UOC', 'UO.HTPT.COP1', 'UO.HTPT.COP1', 63800000),
  ('Tấn Phạm', 'BV1446', 'Tổng CT Cổ Phần Hợp Lực-CN BV Đa Khoa Quốc Tế Hợp Lực', 'Miền Bắc', 'chcs', 'Khớp UOC', 'COP - UOC', 'COP - UOC', 'UO.HTPT.COP1', 'UO.HTPT.COP1', 63800000),
  ('Tuyên Phạm', 'BV0310', 'Bệnh Viện Đa Khoa Bắc Ninh Số 1', 'Miền Bắc', 'chcs', 'Khớp UOC', 'MOP dài - UOC', 'MOP dài - UOC', 'UO.HTPD.MOP1', 'UO.HTPD.MOP1', 73500000),
  ('Tùng Phạm', 'BV0458', 'Công Ty Cổ Phần Bệnh Viện Đa Khoa Tâm Anh', 'Miền Bắc', 'chcs', 'Khớp UOC', 'MOP dài - UOC', 'MOP dài - UOC', 'UO.HTPD.MOP1', 'UO.HTPD.MOP1', 73500000),
  ('Tùng Phạm', 'BV0453', 'BỆNH VIỆN HỮU NGHỊ VIỆT TIỆP', 'Miền Bắc', 'chcs', 'Khớp UOC', 'COC - UOC', 'COC - UOC', 'UO.HTPT.COC1', 'UO.HTPT.COC1', 75800000),
  ('Tùng Phạm', 'BV0458', 'Công Ty Cổ Phần Bệnh Viện Đa Khoa Tâm Anh', 'Miền Bắc', 'chcs', 'Khớp UOC', 'COC - UOC', 'COC - UOC', 'UO.HTPT.COC1', 'UO.HTPT.COC1', 75800000),
  ('Mậu Cao', 'BV0298', 'Bệnh viện Bạch Mai', 'Miền Bắc', 'chcs', 'Khớp UOC', 'Gối thay lại - UOC', 'Gối thay lại - UOC', 'UO.GTL1', 'UO.GTL1', 80080000),
  ('Tứ Nguyễn', 'BV1432', 'Bệnh Viện Chấn Thương Chỉnh Hình Nghệ An (1115142)', 'Miền Bắc', 'chcs', 'Cột sống Ulrich', 'ADD Plus', 'ADD Plus', 'UL.ADD2', 'UL.ADD2', 45000000),
  ('Tứ Nguyễn', 'BV1615', 'Bệnh Viện Thể Thao Việt Nam', 'Miền Bắc', 'chcs', 'NSK Arthrex', 'Vật tư riêng lẻ - NSK Arthrex', 'Lưỡi bào khớp', 'AR-8xx0EX', 'AR.VTRL', 4500000),
  ('Tứ Nguyễn', 'BV1615', 'Bệnh Viện Thể Thao Việt Nam', 'Miền Bắc', 'chcs', 'NSK Arthrex', 'Vật tư riêng lẻ - NSK Arthrex', 'Đầu đốt RF', 'AR-9811', 'AR.VTRL', 7700000),
  ('Tứ Nguyễn', 'BV1615', 'Bệnh Viện Thể Thao Việt Nam', 'Miền Bắc', 'chcs', 'NSK Arthrex', 'Vật tư riêng lẻ - NSK Arthrex', 'Dây nước', 'AR-6410', 'AR.VTRL', 1500000),
  ('Tứ Nguyễn', 'BV1615', 'Bệnh Viện Thể Thao Việt Nam', 'Miền Bắc', 'chcs', 'NSK Arthrex', 'Vật tư riêng lẻ - NSK Arthrex', 'Vít treo TightRope luồn chỉ', 'AR-1588RT-J', 'AR.VTRL', 11500000),
  ('Tứ Nguyễn', 'BV1615', 'Bệnh Viện Thể Thao Việt Nam', 'Miền Bắc', 'chcs', 'NSK Arthrex', 'Vật tư riêng lẻ - NSK Arthrex', 'Chỉ tròn kèm kim', 'AR-7200', 'AR.VTRL', 1200000),
  ('Tứ Nguyễn', 'BV1615', 'Bệnh Viện Thể Thao Việt Nam', 'Miền Bắc', 'chcs', 'NSK Arthrex', 'Vật tư riêng lẻ - NSK Arthrex', 'Mũi khoan ngược', 'AR-1204AF-xx', 'AR.VTRL', 4500000),
  ('Tứ Nguyễn', 'BV0625', 'Bệnh Viện Đa Khoa Khu Vực Tây Bắc Tỉnh Nghệ An', 'Miền Bắc', 'chcs', 'Cột sống Ulrich', 'Vật tư riêng lẻ - Cột sống Ulrich', 'Thanh dọc thường 500mm', 'CS 3807-500mm', 'UL.VTRL', 5500000),
  ('Tứ Nguyễn', 'BV0625', 'Bệnh Viện Đa Khoa Khu Vực Tây Bắc Tỉnh Nghệ An', 'Miền Bắc', 'chcs', 'Cột sống Ulrich', 'Vật tư riêng lẻ - Cột sống Ulrich', 'Pezo-P', 'CS 330x', 'UL.VTRL', 12992000),
  ('Mậu Cao', 'BV0336', 'Bệnh viện Trung Ương Quân đội 108', 'Miền Bắc', 'chcs', 'Cột sống Ulrich', 'Vật tư riêng lẻ - Cột sống Ulrich', 'Thanh dọc thường 500mm', 'CS 3807-500mm', 'UL.VTRL', 5500000);
INSERT INTO _ins VALUES
  ('Tứ Nguyễn', 'BV0368', 'Cột sống Ulrich', 'Vật tư riêng lẻ - Cột sống Ulrich', 'Ốc khóa Flamenco', 600000, 'cu', 1, 1, 'CS 8010', '3'),
  ('Tứ Nguyễn', 'BV0488', 'Cột sống Ulrich', 'Vật tư riêng lẻ - Cột sống Ulrich', 'Ốc khóa Cosmic', 840000, 'cu', 1, 37, 'CS 2605', '4'),
  ('Tứ Nguyễn', 'BV0368', 'Cột sống Ulrich', 'Vật tư riêng lẻ - Cột sống Ulrich', 'Ốc khóa Cosmic', 840000, 'cu', 1, 1, 'CS 2605', '9'),
  ('Tứ Nguyễn', 'BV0488', 'Cột sống Ulrich', 'Vật tư riêng lẻ - Cột sống Ulrich', 'Ốc khóa trong 01', 1000000, 'cu', 1, 7, 'CS 3801-01', '17'),
  ('Tùng Phạm', 'DN2753', 'NSK Arthrex', 'Vật tư riêng lẻ - NSK Arthrex', 'Troca có ren', 1150000, 'cu', 1, 0, 'AR-65xx', '32'),
  ('Tùng Phạm', 'DN2753', 'NSK Arthrex', 'Vật tư riêng lẻ - NSK Arthrex', 'Chỉ tròn kèm kim', 1200000, 'cu', 1, 0, 'AR-7200', '42'),
  ('Tứ Nguyễn', 'BV0368', 'Cột sống Ulrich', 'Vật tư riêng lẻ - Cột sống Ulrich', 'Vít Artus', 1400000, 'cu', 1, 0, 'CS91', '54'),
  ('Tuyên Phạm', 'BV0324', 'BXMCS', 'Vật tư riêng lẻ - CHCS Khác', 'Kim dò cuống sống Bevel', 2000000, 'cu', 1, 120, 'KSBEVEL', '83'),
  ('Tứ Nguyễn', 'BV0488', 'Cột sống Ulrich', 'Vật tư riêng lẻ - Cột sống Ulrich', 'Thanh dọc thường 100-180mm', 2100000, 'cu', 1, 20, 'CS 3807-100-180', '87'),
  ('Tùng Phạm', 'BV0523', 'NSK Arthrex', 'Vật tư riêng lẻ - NSK Arthrex', 'Chỉ dẹt xanh', 4200000, 'cu', 1, 20, 'AR-7237', '107'),
  ('Tuyên Phạm', 'BV0324', 'NSK Arthrex', 'Vật tư riêng lẻ - NSK Arthrex', 'Chỉ dẹt xanh', 4200000, 'cu', 1, 20, 'AR-7237', '110'),
  ('Tấn Phạm', 'BV0304', 'NSK Arthrex', 'Vật tư riêng lẻ - NSK Arthrex', 'Mũi khoan ngược', 4500000, 'cu', 1, 60, 'AR-1204AF-xx', '124,127'),
  ('Tùng Phạm', 'BV0338', 'NSK Arthrex', 'Vật tư riêng lẻ - NSK Arthrex', 'Mũi khoan ngược', 4500000, 'cu', 1, 50, 'AR-1204AF-xx', '126'),
  ('Tứ Nguyễn', 'BV0368', 'Cột sống Ulrich', 'Vật tư riêng lẻ - Cột sống Ulrich', 'Xương nhân tạo 1cc', 4500000, 'cu', 1, 0, 'CS 6604-010', '140'),
  ('Tùng Phạm', 'BV0523', 'NSK Arthrex', 'Vật tư riêng lẻ - NSK Arthrex', 'Cây đẩy chỉ', 5000000, 'cu', 1, 20, 'AR-13995N', '145'),
  ('Tùng Phạm', 'DN2753', 'NSK Arthrex', 'Vật tư riêng lẻ - NSK Arthrex', 'Cây đẩy chỉ', 5000000, 'cu', 1, 0, 'AR-13995N', '149'),
  ('Tuyên Phạm', 'BV0324', 'NSK Arthrex', 'Vật tư riêng lẻ - NSK Arthrex', 'Vít chốt khớp cùng đòn', 5200000, 'cu', 1, 20, 'AR-2270', '164'),
  ('Tùng Phạm', 'DN2753', 'NSK Arthrex', 'Vật tư riêng lẻ - NSK Arthrex', 'Lưỡi mài khớp', 5200000, 'cu', 1, 0, 'AR-8xx0OBx', '165'),
  ('Tứ Nguyễn', 'BV0488', 'Cột sống Ulrich', 'Vật tư riêng lẻ - Cột sống Ulrich', 'Vít đa trục thường', 5500000, 'cu', 1, 7, 'CS 3882', '170'),
  ('Tứ Nguyễn', 'BV0368', 'Cột sống Ulrich', 'Vật tư riêng lẻ - Cột sống Ulrich', 'Vít Flamenco', 5500000, 'cu', 1, 1, 'CS 8009', '179'),
  ('Tùng Phạm', 'BV0523', 'NSK Arthrex', 'Vật tư riêng lẻ - NSK Arthrex', 'Cây móc chỉ', 5900000, 'cu', 1, 20, 'AR-4068-xxx', '182'),
  ('Tùng Phạm', 'BV0338', 'NSK Arthrex', 'Vật tư riêng lẻ - NSK Arthrex', 'Vít Biocomposit ACL', 6800000, 'cu', 1, 100, 'AR-5035TC-xx', '193'),
  ('Tùng Phạm', 'DN2753', 'NSK Arthrex', 'Vật tư riêng lẻ - NSK Arthrex', 'Vít Biocomposit ACL', 6800000, 'cu', 1, 0, 'AR-5035TC-xx', '199'),
  ('Tứ Nguyễn', 'BV0368', 'Cột sống Ulrich', 'Vật tư riêng lẻ - Cột sống Ulrich', 'Nẹp cổ trước Artus 1 tầng', 7300000, 'cu', 1, 0, 'CS 9102-01', '216'),
  ('Tứ Nguyễn', 'BV0488', 'Cột sống Ulrich', 'Vật tư riêng lẻ - Cột sống Ulrich', 'Vít Cosmic', 8200000, 'cu', 1, 37, 'CS 2600', '235'),
  ('Tứ Nguyễn', 'BV0368', 'Cột sống Ulrich', 'Vật tư riêng lẻ - Cột sống Ulrich', 'Vít đa trục qua da', 8200000, 'cu', 1, 1, 'CS 3802', '240'),
  ('Tứ Nguyễn', 'BV0368', 'Cột sống Ulrich', 'Vật tư riêng lẻ - Cột sống Ulrich', 'Vít Cosmic', 8200000, 'cu', 1, 1, 'CS 2600', '241'),
  ('Tứ Nguyễn', 'BV0368', 'Cột sống Ulrich', 'Vật tư riêng lẻ - Cột sống Ulrich', 'Thanh ngang uCentum', 8500000, 'cu', 1, 1, 'CS 3810', '245'),
  ('Tùng Phạm', 'BV0338', 'NSK Arthrex', 'Vật tư riêng lẻ - NSK Arthrex', 'Vít neo Suturetak', 8600000, 'cu', 1, 50, 'AR-1934BCF-2', '246'),
  ('Tùng Phạm', 'BV0523', 'NSK Arthrex', 'Vật tư riêng lẻ - NSK Arthrex', 'Vít neo Suturetak', 8600000, 'cu', 1, 100, 'AR-1934BCF-2', '247'),
  ('Tùng Phạm', 'DN2753', 'NSK Arthrex', 'Vật tư riêng lẻ - NSK Arthrex', 'Vít neo Suturetak', 8600000, 'cu', 1, 0, 'AR-1934BCF-2', '250'),
  ('Tùng Phạm', 'BV0458', 'NSK Arthrex', 'Vật tư riêng lẻ - NSK Arthrex', 'Vít neo Suturetak', 8600000, 'cu', 1, 1, 'AR-1934BCF-2', '251'),
  ('Tùng Phạm', 'BV0338', 'NSK Arthrex', 'Vật tư riêng lẻ - NSK Arthrex', 'Vít neo Pushlock', 8900000, 'cu', 1, 20, 'AR-2923BC', '258'),
  ('Tùng Phạm', 'BV0523', 'NSK Arthrex', 'Vật tư riêng lẻ - NSK Arthrex', 'Vít neo Pushlock', 8900000, 'cu', 1, 100, 'AR-2923BC', '259'),
  ('Tùng Phạm', 'DN2753', 'NSK Arthrex', 'Vật tư riêng lẻ - NSK Arthrex', 'Vít neo Pushlock', 8900000, 'cu', 1, 0, 'AR-2923BC', '265'),
  ('Tứ Nguyễn', 'BV0368', 'Cột sống Ulrich', 'Vật tư riêng lẻ - Cột sống Ulrich', 'Cerv-X', 9000000, 'cu', 1, 0, 'CS 820x', '274'),
  ('Tứ Nguyễn', 'BV0368', 'Cột sống Ulrich', 'Vật tư riêng lẻ - Cột sống Ulrich', 'Nẹp cổ trước Artus 2 tầng', 9172000, 'cu', 1, 1, 'CS 9102-02', '288'),
  ('Tuyên Phạm', 'BV0655', 'Cột sống Ulrich', 'Vật tư riêng lẻ - Cột sống Ulrich', 'Vít đa trục qua da', 9200000, 'cu', 1, 30, 'CS 3802', '291'),
  ('Tứ Nguyễn', 'BV0488', 'Khớp UOC', 'Vật tư riêng lẻ - Khớp UOC', 'Đầu chuyển trục chuôi', 9680000, 'cu', 1, 2, '2903', '294'),
  ('Tứ Nguyễn', 'BV0488', 'Khớp UOC', 'Vật tư riêng lẻ - Khớp UOC', 'Đầu chuyển trục chuôi', 9680000, 'chinh', 1, 2, '2903', '935'),
  ('Tuyên Phạm', 'BV0324', 'Khớp UOC', 'Vật tư riêng lẻ - Khớp UOC', 'Đầu chuyển trục chuôi', 9680000, 'cu', 1, 2, '2903', '297'),
  ('Tấn Phạm', 'BV0313', 'Khớp UOC', 'Vật tư riêng lẻ - Khớp UOC', 'Đầu chuyển trục chuôi', 9680000, 'cu', 1, 30, '2903', '298'),
  ('Tứ Nguyễn', 'BV0368', 'Cột sống Ulrich', 'Vật tư riêng lẻ - Cột sống Ulrich', 'Nẹp cổ trước Artus 3 tầng', 10700000, 'cu', 1, 1, 'CS 9102-03', '305'),
  ('Tứ Nguyễn', 'BV0488', 'Khớp UOC', 'Vật tư riêng lẻ - Khớp UOC', 'Miếng ghép mâm chày', 11600000, 'cu', 1, 2, '2803-52x', '330'),
  ('Tứ Nguyễn', 'BV0488', 'Khớp UOC', 'Vật tư riêng lẻ - Khớp UOC', 'Miếng ghép mâm chày', 11600000, 'chinh', 1, 2, '2803-52x', '932'),
  ('Tấn Phạm', 'BV0313', 'Khớp UOC', 'Vật tư riêng lẻ - Khớp UOC', 'Miếng ghép lồi cầu đùi', 11600000, 'cu', 1, 30, '2603-2803', '333'),
  ('Tuyên Phạm', 'BV0324', 'Khớp UOC', 'Vật tư riêng lẻ - Khớp UOC', 'Miếng ghép lồi cầu đùi', 11600000, 'cu', 1, 2, '2603-2803', '334'),
  ('Tấn Phạm', 'BV0313', 'Khớp UOC', 'Vật tư riêng lẻ - Khớp UOC', 'Miếng ghép mâm chày', 11600000, 'cu', 1, 30, '2803-52x', '335'),
  ('Tuyên Phạm', 'BV0324', 'Khớp UOC', 'Vật tư riêng lẻ - Khớp UOC', 'Miếng ghép mâm chày', 11600000, 'cu', 1, 2, '2803-52x', '336'),
  ('Tùng Phạm', 'BV0458', 'Khớp UOC', 'Vật tư riêng lẻ - Khớp UOC', 'Miếng ghép mâm chày', 11600000, 'cu', 1, 1, '2803-52x', '340'),
  ('Tuyên Phạm', 'BV0324', 'NSK Arthrex', 'Vật tư riêng lẻ - NSK Arthrex', 'Vít neo Suturetak nhỏ', 12500000, 'cu', 1, 10, 'AR-1322BCNF', '350'),
  ('Tùng Phạm', 'DN2753', 'NSK Arthrex', 'Vật tư riêng lẻ - NSK Arthrex', 'Vít treo TightRope', 12700000, 'cu', 1, 0, 'AR-1588RT', '360'),
  ('Tứ Nguyễn', 'BV0488', 'Khớp UOC', 'Vật tư riêng lẻ - Khớp UOC', 'Chuôi thẳng nối dài PSA', 12960000, 'cu', 1, 2, '2703 thang', '365'),
  ('Tứ Nguyễn', 'BV0488', 'Khớp UOC', 'Vật tư riêng lẻ - Khớp UOC', 'Chuôi thẳng nối dài PSA', 12960000, 'chinh', 1, 2, '2703 thang', '934'),
  ('Tấn Phạm', 'BV0313', 'Khớp UOC', 'Vật tư riêng lẻ - Khớp UOC', 'Chuôi thẳng nối dài PSA', 12960000, 'cu', 1, 29, '2703 thang', '367'),
  ('Tuyên Phạm', 'BV0324', 'Khớp UOC', 'Vật tư riêng lẻ - Khớp UOC', 'Chuôi thẳng nối dài PSA', 12960000, 'cu', 1, 2, '2703 thang', '368'),
  ('Tứ Nguyễn', 'BV0308', 'Khớp UOC', 'Vật tư riêng lẻ - Khớp UOC', 'Chuôi thẳng nối dài PSA', 12960000, 'cu', 1, 20, '2703 thang', '370'),
  ('Tứ Nguyễn', 'BV0488', 'Cột sống Ulrich', 'Vật tư riêng lẻ - Cột sống Ulrich', 'Pezo-P', 12992000, 'cu', 1, 85, 'CS 330x', '374'),
  ('Tùng Phạm', 'DN2753', 'NSK Arthrex', 'Vật tư riêng lẻ - NSK Arthrex', 'Vít neo Swivelock BC kèm chỉ', 13400000, 'cu', 1, 0, 'AR-2324BCCT', '388'),
  ('Tuyên Phạm', 'BV0324', 'NSK Arthrex', 'Vật tư riêng lẻ - NSK Arthrex', 'Vít neo Swivelock cho khớp nhỏ', 13800000, 'cu', 1, 10, 'AR-8978P', '395'),
  ('Mậu Cao', 'BV0298', 'Cột sống Ulrich', 'ADD', 'ADD', 31000000, 'cu', 1, 0, 'UL.ADD1', '426'),
  ('Mậu Cao', 'BV0298', 'Cột sống Ulrich', 'ADD', 'ADD', 31000000, 'chinh', 1, 7, 'UL.ADD1', '554'),
  ('Tứ Nguyễn', 'BV0368', 'Cột sống Ulrich', 'ADD', 'ADD', 31000000, 'cu', 1, 1, 'UL.ADD1', '432'),
  ('Tuyên Phạm', 'BV0324', 'NSK Arthrex', 'Vật tư riêng lẻ - NSK Arthrex', 'Bộ chỉ khâu gân gót chân', 35000000, 'cu', 1, 5, 'AR-8860DS', '435'),
  ('Tuyên Phạm', 'BV0324', 'NSK Arthrex', 'Vật tư riêng lẻ - NSK Arthrex', 'TightRope khớp chày mác', 36400000, 'cu', 1, 10, 'AR-8926T', '438'),
  ('Tùng Phạm', 'BV0458', 'Khớp UOC', 'Bipolar thường - UOC', 'Bipolar thường - UOC', 39790000, 'cu', 1, 1, 'UO.HBPT1', '451'),
  ('Tấn Phạm', 'BV0354', 'Khớp UOC', 'Bipolar thường - UOC', 'Bipolar thường - UOC', 39790000, 'cu', 1, 1, 'UO.HBPT1', '454'),
  ('Tấn Phạm', 'BV1446', 'Khớp UOC', 'Bipolar thường - UOC', 'Bipolar thường - UOC', 39790000, 'cu', 1, 1, 'UO.HBPT1', '455'),
  ('Tứ Nguyễn', 'BV0368', 'Cột sống Ulrich', 'ADD Plus', 'ADD Plus', 45000000, 'cu', 1, 1, 'UL.ADD2', '465'),
  ('Tùng Phạm', 'BV0458', 'Khớp UOC', 'MOP - UOC', 'MOP - UOC', 55000000, 'cu', 1, 1, 'UO.HTPT.MOP1', '478'),
  ('Tấn Phạm', 'BV0354', 'Khớp UOC', 'MOP - UOC', 'MOP - UOC', 55000000, 'cu', 1, 1, 'UO.HTPT.MOP1', '480'),
  ('Tấn Phạm', 'BV1446', 'Khớp UOC', 'MOP - UOC', 'MOP - UOC', 55000000, 'cu', 1, 1, 'UO.HTPT.MOP1', '481'),
  ('Tùng Phạm', 'BV0338', 'Khớp UOC', 'Gối thường - UOC', 'Gối thường - UOC', 58000000, 'cu', 1, 29, 'UO.GTPT1', '490'),
  ('Tùng Phạm', 'BV0458', 'Khớp UOC', 'Gối thường - UOC', 'Gối thường - UOC', 58000000, 'cu', 1, 0, 'UO.GTPT1', '496'),
  ('Tấn Phạm', 'BV0354', 'Khớp UOC', 'Gối thường - UOC', 'Gối thường - UOC', 58000000, 'cu', 1, 1, 'UO.GTPT1', '501'),
  ('Tùng Phạm', 'BV0458', 'Khớp UOC', 'Bipolar dài - UOC', 'Bipolar dài - UOC', 58290000, 'cu', 1, 0, 'UO.HBPD1', '517'),
  ('Tấn Phạm', 'BV1446', 'Khớp UOC', 'Bipolar dài - UOC', 'Bipolar dài - UOC', 58290000, 'cu', 1, 1, 'UO.HBPD1', '520'),
  ('Tuyên Phạm', 'BV0655', 'Cột sống Ulrich', 'Vật tư riêng lẻ - Cột sống Ulrich', 'Ốc khóa trong Neon3', 910000, 'chinh', 2, 30, 'CS 3901', '557'),
  ('Tứ Nguyễn', 'BV1432', 'Khớp UOC', 'Vật tư riêng lẻ - Khớp UOC', 'Miếng ghép mâm chày', 11600000, 'bo_sung', 1, 5, '2803-52x', '588'),
  ('Tứ Nguyễn', 'BV1432', 'Khớp UOC', 'Vật tư riêng lẻ - Khớp UOC', 'Miếng ghép mâm chày', 11600000, 'chinh', 2, 12, '2803-52x', '775,776'),
  ('Tứ Nguyễn', 'BV1432', 'Khớp UOC', 'Vật tư riêng lẻ - Khớp UOC', 'Miếng ghép mâm chày', 11600000, 'chinh', 1, 25, '2803-52x', '880,881'),
  ('Tứ Nguyễn', 'BV1432', 'Khớp UOC', 'Vật tư riêng lẻ - Khớp UOC', 'Chuôi thẳng nối dài PSA', 12960000, 'bo_sung', 1, 5, '2703 thang', '592'),
  ('Tứ Nguyễn', 'BV1432', 'Khớp UOC', 'Vật tư riêng lẻ - Khớp UOC', 'Chuôi thẳng nối dài PSA', 12960000, 'chinh', 2, 6, '2703 thang', '778'),
  ('Tứ Nguyễn', 'BV1432', 'Khớp UOC', 'Vật tư riêng lẻ - Khớp UOC', 'Chuôi thẳng nối dài PSA', 12960000, 'chinh', 1, 20, '2703 thang', '883'),
  ('Tuyên Phạm', 'BV0655', 'Khớp UOC', 'COP - UOC', 'COP - UOC', 63800000, 'chinh', 1, 10, 'UO.HTPT.COP1', '609'),
  ('Tùng Phạm', 'BV0306', 'NSK Arthrex', 'Vật tư riêng lẻ - NSK Arthrex', 'Lưỡi mài khớp', 5200000, 'chinh', 1, 255, 'AR-8xx0OBx', '648'),
  ('Tứ Nguyễn', 'BV0308', 'NSK Arthrex', 'Vật tư riêng lẻ - NSK Arthrex', 'Vít neo Pushlock', 8900000, 'chinh', 1, 75, 'AR-2923BC', '672'),
  ('Mậu Cao', 'BV0342', 'Cột sống Ulrich', 'Vật tư riêng lẻ - Cột sống Ulrich', 'Nẹp dọc Neon3 20-100mm', 1000000, 'chinh', 1, 900, 'CS 3910-20-100', '679'),
  ('Tùng Phạm', 'BV0458', 'Khớp UOC', 'COP - UOC', 'COP - UOC', 63800000, 'cu', 1, 1, 'UO.HTPT.COP1', '766'),
  ('Tứ Nguyễn', 'BV1432', 'Khớp UOC', 'Vật tư riêng lẻ - Khớp UOC', 'Đầu chuyển trục chuôi', 9680000, 'chinh', 2, 6, '2903', '779'),
  ('Tứ Nguyễn', 'BV1432', 'Khớp UOC', 'Vật tư riêng lẻ - Khớp UOC', 'Đầu chuyển trục chuôi', 9680000, 'chinh', 1, 5, '2903', '884'),
  ('Tấn Phạm', 'BV0354', 'Khớp UOC', 'COP - UOC', 'COP - UOC', 63800000, 'cu', 1, 1, 'UO.HTPT.COP1', '782'),
  ('Tấn Phạm', 'BV1446', 'Khớp UOC', 'COP - UOC', 'COP - UOC', 63800000, 'cu', 1, 1, 'UO.HTPT.COP1', '783'),
  ('Tuyên Phạm', 'BV0310', 'Khớp UOC', 'MOP dài - UOC', 'MOP dài - UOC', 73500000, 'cu', 1, 29, 'UO.HTPD.MOP1', '787'),
  ('Tuyên Phạm', 'BV0310', 'Khớp UOC', 'MOP dài - UOC', 'MOP dài - UOC', 73500000, 'chinh', 1, 10, 'UO.HTPD.MOP1', '894'),
  ('Tùng Phạm', 'BV0458', 'Khớp UOC', 'MOP dài - UOC', 'MOP dài - UOC', 73500000, 'cu', 1, 0, 'UO.HTPD.MOP1', '794'),
  ('Tùng Phạm', 'BV0453', 'Khớp UOC', 'COC - UOC', 'COC - UOC', 75800000, 'cu', 1, 0, 'UO.HTPT.COC1', '802'),
  ('Tùng Phạm', 'BV0458', 'Khớp UOC', 'COC - UOC', 'COC - UOC', 75800000, 'cu', 1, 1, 'UO.HTPT.COC1', '803'),
  ('Mậu Cao', 'BV0298', 'Khớp UOC', 'Gối thay lại - UOC', 'Gối thay lại - UOC', 80080000, 'cu', 1, 2, 'UO.GTL1', '804'),
  ('Tứ Nguyễn', 'BV1432', 'Cột sống Ulrich', 'ADD Plus', 'ADD Plus', 45000000, 'chinh', 1, 5, 'UL.ADD2', '838'),
  ('Tứ Nguyễn', 'BV1615', 'NSK Arthrex', 'Vật tư riêng lẻ - NSK Arthrex', 'Lưỡi bào khớp', 4500000, 'chinh', 1, 900, 'AR-8xx0EX', '885'),
  ('Tứ Nguyễn', 'BV1615', 'NSK Arthrex', 'Vật tư riêng lẻ - NSK Arthrex', 'Đầu đốt RF', 7700000, 'chinh', 1, 70, 'AR-9811', '886'),
  ('Tứ Nguyễn', 'BV1615', 'NSK Arthrex', 'Vật tư riêng lẻ - NSK Arthrex', 'Dây nước', 1500000, 'chinh', 1, 40, 'AR-6410', '887'),
  ('Tứ Nguyễn', 'BV1615', 'NSK Arthrex', 'Vật tư riêng lẻ - NSK Arthrex', 'Vít treo TightRope luồn chỉ', 11500000, 'chinh', 1, 1.5, 'AR-1588RT-J', '888'),
  ('Tứ Nguyễn', 'BV1615', 'NSK Arthrex', 'Vật tư riêng lẻ - NSK Arthrex', 'Chỉ tròn kèm kim', 1200000, 'chinh', 1, 900, 'AR-7200', '889'),
  ('Tứ Nguyễn', 'BV1615', 'NSK Arthrex', 'Vật tư riêng lẻ - NSK Arthrex', 'Mũi khoan ngược', 4500000, 'chinh', 1, 750, 'AR-1204AF-xx', '890'),
  ('Tứ Nguyễn', 'BV0625', 'Cột sống Ulrich', 'Vật tư riêng lẻ - Cột sống Ulrich', 'Thanh dọc thường 500mm', 5500000, 'chinh', 1, 80, 'CS 3807-500mm', '951'),
  ('Tứ Nguyễn', 'BV0625', 'Cột sống Ulrich', 'Vật tư riêng lẻ - Cột sống Ulrich', 'Pezo-P', 12992000, 'chinh', 1, 4, 'CS 330x', '954'),
  ('Mậu Cao', 'BV0336', 'Cột sống Ulrich', 'Vật tư riêng lẻ - Cột sống Ulrich', 'Thanh dọc thường 500mm', 5500000, 'chinh', 1, 150, 'CS 3807-500mm', '977');

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

-- 1. đợt mới
WITH n AS (
  INSERT INTO shared.dot_thau (nam_tai_chinh, bu, mien, ps, ma_khach_hang, nhom_san_pham, loai, dot, thang_thau, thoi_gian,
                               updated_by, trang_thai, nguon)
  SELECT 'FY26', 'chcs', 'Miền Bắc', m.ps, m.kh, m.nhom, m.loai, m.dot, m.thang, m.hl, 'dong_bo_nh_mb_20261109', 'chinh_thuc', 'nh_mb_20261109'
  FROM _dot_moi m RETURNING *)
INSERT INTO shared.quota_chuan_hoa_log (buoc, bang, ban_ghi_id, truoc, sau)
SELECT 'dong_bo_nh_mb_20261109', 'dot_thau', n.id, NULL, to_jsonb(n) FROM n;

-- 2a. sửa SL
WITH o AS (SELECT q.* FROM shared.quota_thau q JOIN _upd u ON u.id = q.id),
u AS (UPDATE shared.quota_thau q SET so_luong = x.sl_moi, updated_at = now(), updated_by = 'dong_bo_nh_mb_20261109'
      FROM _upd x WHERE q.id = x.id RETURNING q.*)
INSERT INTO shared.quota_chuan_hoa_log (buoc, bang, ban_ghi_id, truoc, sau)
SELECT 'dong_bo_nh_mb_20261109', 'quota_thau', u.id, to_jsonb(o), to_jsonb(u) FROM u JOIN o ON o.id = u.id;

-- 2b. xoá
WITH d AS (DELETE FROM shared.quota_thau q USING _del x WHERE q.id = x.id RETURNING q.*)
INSERT INTO shared.quota_chuan_hoa_log (buoc, bang, ban_ghi_id, truoc, sau)
SELECT 'dong_bo_nh_mb_20261109', 'quota_thau', d.id, to_jsonb(d), NULL FROM d;

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
SELECT 'dong_bo_nh_mb_20261109', 'sale_target', s.id, NULL, to_jsonb(s) FROM _st_moi s;

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
SELECT 'dong_bo_nh_mb_20261109_oop', 'sale_target', o.id, to_jsonb(o) - 'dich', jsonb_build_object('hap_thu_vao', o.dich) FROM _oop o;
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
         'dong_bo_nh_mb_20261109', 'chinh_thuc', 'nh_mb_20261109', n.ma
  FROM _ins n CROSS JOIN LATERAL (
    SELECT s.bu, s.mien, s.khach_hang FROM shared.sale_target s
    WHERE s.nam_tai_chinh = 'FY26' AND s.ps = n.ps AND s.ma_khach_hang = n.kh AND s.nhom_san_pham = n.nhom
      AND s.bo_vat_tu = n.bvt AND s.san_pham = n.sp AND s.don_gia = n.gia AND NOT coalesce(s.ngoai_ke_hoach, false)
    ORDER BY s.id LIMIT 1) s
  RETURNING *)
INSERT INTO shared.quota_chuan_hoa_log (buoc, bang, ban_ghi_id, truoc, sau)
SELECT 'dong_bo_nh_mb_20261109', 'quota_thau', i.id, NULL, to_jsonb(i) FROM i;

SET CONSTRAINTS shared.uq_sale_target_khoa IMMEDIATE;
COMMIT;
