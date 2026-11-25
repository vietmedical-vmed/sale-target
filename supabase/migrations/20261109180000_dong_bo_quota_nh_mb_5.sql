-- Đồng bộ quota thầu CH&CS Miền Bắc theo file ngành hàng bản 09/11/2026 (user chốt 09/11), buoc 'dong_bo_nh_mb_20261109e':
--   0. Sửa tháng thầu 1 đợt + chuyển 0 quota sang đợt đúng on hand/upcoming theo file.
--   1. Thêm 4 đợt thầu thiếu, tháng thầu = tháng "Ngày ký" trong file, hiệu lực = số tháng từ ngày ký
--      tới ngày hết hạn (chỉ đợt đã trúng; riêng VĐ Ulrich thêm đợt dự kiến 2027-03 theo file).
--   2. Sửa quota trên khoá kế hoạch đã có: 0 dòng đổi SL, 0 dòng xoá (SL file = 0 ở loại/đợt đó),
--      0 dòng thêm (loại/đợt file có mà HT chưa có). VĐ Ulrich giữ PS Mậu Cao; ĐHY HN gối U2 theo file.
--   3. Thêm 99 sản phẩm vào kế hoạch FY26 của PS (12 tháng, SL 0, hấp thụ dòng OOP cùng khoá như "Thêm sản phẩm"),
--      rồi nạp quota cho các sản phẩm đó.
-- File NH bỏ 4 dòng trùng BV K (dòng 52, 151, 287, 303). Log: shared.quota_chuan_hoa_log buoc 'dong_bo_nh_mb_20261109e'.
-- Rollback: supabase/rollbacks/20261109180000_dong_bo_quota_nh_mb_5_ROLLBACK.sql
BEGIN;
SET CONSTRAINTS shared.uq_sale_target_khoa DEFERRED;

CREATE TEMP TABLE _dot_moi (ps text, kh text, nhom text, loai text, dot int, thang text, hl numeric) ON COMMIT DROP;
INSERT INTO _dot_moi VALUES
  ('Mậu Cao', 'BV0320', 'Cột sống Ulrich', 'chinh', 1, '2026-06', 18),
  ('Tuyên Phạm', 'DN2665', 'NSK Arthrex', 'bo_sung', 1, '2026-09', 1),
  ('Tuyên Phạm', 'DN0605', 'Khớp UOC', 'bo_sung', 1, '2026-07', 8),
  ('Tuyên Phạm', 'BV0324', 'Khớp UOC', 'bo_sung', 2, '2027-03', 5);
CREATE TEMP TABLE _upd (id bigint, sl_cu numeric, sl_moi numeric) ON COMMIT DROP;

CREATE TEMP TABLE _del (id bigint, sl_cu numeric) ON COMMIT DROP;

CREATE TEMP TABLE _ins (ps text, kh text, nhom text, bvt text, sp text, gia numeric, loai text, dot int, sl numeric, ma text, dong text) ON COMMIT DROP;

CREATE TEMP TABLE _sp (ps text, kh text, khach_hang text, mien text, bu text, nhom text, bvt text, sp text, ma_sp text, ma_bvt text, gia numeric) ON COMMIT DROP;
INSERT INTO _sp VALUES
  ('Tứ Nguyễn', 'BV0414', 'BỆNH VIỆN ĐA KHOA CỬA ĐÔNG THUỘC CÔNG TY TNHH LƯƠNG THỰC MIỀN TRUNG', 'Miền Bắc', 'chcs', 'NSK Arthrex', 'Vật tư riêng lẻ - NSK Arthrex', 'Troca có ren', 'AR-65xx', 'AR.VTRL', 1150000),
  ('Tứ Nguyễn', 'BV0521', 'Công Ty Cổ Phần Bệnh Viện Đa Khoa Quốc Tế Vinmec', 'Miền Bắc', 'chcs', 'NSK Arthrex', 'Vật tư riêng lẻ - NSK Arthrex', 'Troca có ren', 'AR-65xx', 'AR.VTRL', 1150000),
  ('Tứ Nguyễn', 'BV0414', 'BỆNH VIỆN ĐA KHOA CỬA ĐÔNG THUỘC CÔNG TY TNHH LƯƠNG THỰC MIỀN TRUNG', 'Miền Bắc', 'chcs', 'NSK Arthrex', 'Vật tư riêng lẻ - NSK Arthrex', 'Chỉ tròn kèm kim', 'AR-7200', 'AR.VTRL', 1200000),
  ('Tứ Nguyễn', 'BV0521', 'Công Ty Cổ Phần Bệnh Viện Đa Khoa Quốc Tế Vinmec', 'Miền Bắc', 'chcs', 'NSK Arthrex', 'Vật tư riêng lẻ - NSK Arthrex', 'Chỉ tròn kèm kim', 'AR-7200', 'AR.VTRL', 1200000),
  ('Tứ Nguyễn', 'BV0414', 'BỆNH VIỆN ĐA KHOA CỬA ĐÔNG THUỘC CÔNG TY TNHH LƯƠNG THỰC MIỀN TRUNG', 'Miền Bắc', 'chcs', 'NSK Arthrex', 'Vật tư riêng lẻ - NSK Arthrex', 'Dây nước', 'AR-6410', 'AR.VTRL', 1500000),
  ('Tứ Nguyễn', 'BV0521', 'Công Ty Cổ Phần Bệnh Viện Đa Khoa Quốc Tế Vinmec', 'Miền Bắc', 'chcs', 'NSK Arthrex', 'Vật tư riêng lẻ - NSK Arthrex', 'Dây nước', 'AR-6410', 'AR.VTRL', 1500000),
  ('Tùng Phạm', 'BV0519', 'CÔNG TY CỔ PHẦN Y KHOA BÁC SỸ GIA ĐÌNH', 'Miền Bắc', 'chcs', 'NSK Arthrex', 'Vật tư riêng lẻ - NSK Arthrex', 'Dây nước', 'AR-6410', 'AR.VTRL', 1500000),
  ('Tứ Nguyễn', 'BV0414', 'BỆNH VIỆN ĐA KHOA CỬA ĐÔNG THUỘC CÔNG TY TNHH LƯƠNG THỰC MIỀN TRUNG', 'Miền Bắc', 'chcs', 'Cột sống Ulrich', 'Vật tư riêng lẻ - Cột sống Ulrich', 'Thanh dọc Flamenco', 'CS 8012-480', 'UL.VTRL', 2000000),
  ('Tứ Nguyễn', 'BV0414', 'BỆNH VIỆN ĐA KHOA CỬA ĐÔNG THUỘC CÔNG TY TNHH LƯƠNG THỰC MIỀN TRUNG', 'Miền Bắc', 'chcs', 'Cột sống Ulrich', 'Vật tư riêng lẻ - Cột sống Ulrich', 'Thanh dọc thường 100-180mm', 'CS 3807-100-180', 'UL.VTRL', 2100000),
  ('Tứ Nguyễn', 'BV0414', 'BỆNH VIỆN ĐA KHOA CỬA ĐÔNG THUỘC CÔNG TY TNHH LƯƠNG THỰC MIỀN TRUNG', 'Miền Bắc', 'chcs', 'Cột sống Ulrich', 'Vật tư riêng lẻ - Cột sống Ulrich', 'Thanh dọc thẳng qua da <300mm', 'CS 3808-300', 'UL.VTRL', 3000000),
  ('Tùng Phạm', 'BV0338', 'Bệnh viện Đa Khoa Quốc tế Hải Phòng', 'Miền Bắc', 'chcs', 'Khớp UOC', 'Vật tư riêng lẻ - Khớp UOC', 'Xi măng khớp', '880013', 'UO.VTRL', 4000000),
  ('Tấn Phạm', 'BV1689', 'BỆNH VIỆN ĐA KHOA LÂM HOA THÁI BÌNH', 'Miền Bắc', 'chcs', 'Khớp UOC', 'Vật tư riêng lẻ - Khớp UOC', 'Xi măng khớp', '880013', 'UO.VTRL', 4000000),
  ('Tấn Phạm', 'BV0313', 'Bệnh Viện Hữu Nghị', 'Miền Bắc', 'chcs', 'Khớp UOC', 'Vật tư riêng lẻ - Khớp UOC', 'Xi măng khớp', '880013', 'UO.VTRL', 4000000),
  ('Tứ Nguyễn', 'BV0414', 'BỆNH VIỆN ĐA KHOA CỬA ĐÔNG THUỘC CÔNG TY TNHH LƯƠNG THỰC MIỀN TRUNG', 'Miền Bắc', 'chcs', 'Cột sống Ulrich', 'Vật tư riêng lẻ - Cột sống Ulrich', 'Xương nhân tạo 1cc', 'CS 6604-010', 'UL.VTRL', 4500000),
  ('Tứ Nguyễn', 'BV0414', 'BỆNH VIỆN ĐA KHOA CỬA ĐÔNG THUỘC CÔNG TY TNHH LƯƠNG THỰC MIỀN TRUNG', 'Miền Bắc', 'chcs', 'NSK Arthrex', 'Vật tư riêng lẻ - NSK Arthrex', 'Lưỡi bào khớp', 'AR-8xx0EX', 'AR.VTRL', 4500000),
  ('Tứ Nguyễn', 'BV0521', 'Công Ty Cổ Phần Bệnh Viện Đa Khoa Quốc Tế Vinmec', 'Miền Bắc', 'chcs', 'NSK Arthrex', 'Vật tư riêng lẻ - NSK Arthrex', 'Lưỡi bào khớp', 'AR-8xx0EX', 'AR.VTRL', 4500000),
  ('Tứ Nguyễn', 'BV0521', 'Công Ty Cổ Phần Bệnh Viện Đa Khoa Quốc Tế Vinmec', 'Miền Bắc', 'chcs', 'NSK Arthrex', 'Vật tư riêng lẻ - NSK Arthrex', 'Mũi khoan ngược', 'AR-1204AF-xx', 'AR.VTRL', 4500000),
  ('Tùng Phạm', 'BV0519', 'CÔNG TY CỔ PHẦN Y KHOA BÁC SỸ GIA ĐÌNH', 'Miền Bắc', 'chcs', 'NSK Arthrex', 'Vật tư riêng lẻ - NSK Arthrex', 'Lưỡi bào khớp', 'AR-8xx0EX', 'AR.VTRL', 4500000),
  ('Tứ Nguyễn', 'BV0414', 'BỆNH VIỆN ĐA KHOA CỬA ĐÔNG THUỘC CÔNG TY TNHH LƯƠNG THỰC MIỀN TRUNG', 'Miền Bắc', 'chcs', 'NSK Arthrex', 'Vật tư riêng lẻ - NSK Arthrex', 'Lưỡi mài khớp', 'AR-8xx0OBx', 'AR.VTRL', 5200000),
  ('Tứ Nguyễn', 'BV0521', 'Công Ty Cổ Phần Bệnh Viện Đa Khoa Quốc Tế Vinmec', 'Miền Bắc', 'chcs', 'NSK Arthrex', 'Vật tư riêng lẻ - NSK Arthrex', 'Lưỡi mài khớp', 'AR-8xx0OBx', 'AR.VTRL', 5200000),
  ('Tứ Nguyễn', 'BV0521', 'Công Ty Cổ Phần Bệnh Viện Đa Khoa Quốc Tế Vinmec', 'Miền Bắc', 'chcs', 'NSK Arthrex', 'Vật tư riêng lẻ - NSK Arthrex', 'Cây móc chỉ', 'AR-4068-xxx', 'AR.VTRL', 5900000),
  ('Tứ Nguyễn', 'BV0521', 'Công Ty Cổ Phần Bệnh Viện Đa Khoa Quốc Tế Vinmec', 'Miền Bắc', 'chcs', 'NSK Arthrex', 'Vật tư riêng lẻ - NSK Arthrex', 'Cây đẩy chỉ', 'AR-13999HDN', 'AR.VTRL', 6000000),
  ('Tuyên Phạm', 'BV0324', 'Bệnh viện Quân Y 103', 'Miền Bắc', 'chcs', 'Cột sống Ulrich', 'Bộ vít đa trục thường', 'Bộ vít đa trục thường', 'UL.UCT1', 'UL.UCT1', 6500000),
  ('Tứ Nguyễn', 'BV0521', 'Công Ty Cổ Phần Bệnh Viện Đa Khoa Quốc Tế Vinmec', 'Miền Bắc', 'chcs', 'NSK Arthrex', 'Vật tư riêng lẻ - NSK Arthrex', 'Vít Biocomposit ACL', 'AR-5035TC-xx', 'AR.VTRL', 6800000),
  ('Tứ Nguyễn', 'BV0414', 'BỆNH VIỆN ĐA KHOA CỬA ĐÔNG THUỘC CÔNG TY TNHH LƯƠNG THỰC MIỀN TRUNG', 'Miền Bắc', 'chcs', 'NSK Arthrex', 'Vật tư riêng lẻ - NSK Arthrex', 'Đầu đốt RF', 'AR-9811', 'AR.VTRL', 7700000),
  ('Tứ Nguyễn', 'BV0521', 'Công Ty Cổ Phần Bệnh Viện Đa Khoa Quốc Tế Vinmec', 'Miền Bắc', 'chcs', 'NSK Arthrex', 'Vật tư riêng lẻ - NSK Arthrex', 'Đầu đốt RF', 'AR-9811', 'AR.VTRL', 7700000),
  ('Tùng Phạm', 'BV0519', 'CÔNG TY CỔ PHẦN Y KHOA BÁC SỸ GIA ĐÌNH', 'Miền Bắc', 'chcs', 'NSK Arthrex', 'Vật tư riêng lẻ - NSK Arthrex', 'Đầu đốt RF', 'AR-9811', 'AR.VTRL', 7700000),
  ('Tứ Nguyễn', 'BV0414', 'BỆNH VIỆN ĐA KHOA CỬA ĐÔNG THUỘC CÔNG TY TNHH LƯƠNG THỰC MIỀN TRUNG', 'Miền Bắc', 'chcs', 'Cột sống Ulrich', 'Vật tư riêng lẻ - Cột sống Ulrich', 'Thanh ngang uCentum', 'CS 3810', 'UL.VTRL', 8500000),
  ('Tùng Phạm', 'BV0519', 'CÔNG TY CỔ PHẦN Y KHOA BÁC SỸ GIA ĐÌNH', 'Miền Bắc', 'chcs', 'NSK Arthrex', 'Vật tư riêng lẻ - NSK Arthrex', 'Vít neo Suturetak', 'AR-1934BCF-2', 'AR.VTRL', 8600000),
  ('Tứ Nguyễn', 'BV0521', 'Công Ty Cổ Phần Bệnh Viện Đa Khoa Quốc Tế Vinmec', 'Miền Bắc', 'chcs', 'NSK Arthrex', 'Vật tư riêng lẻ - NSK Arthrex', 'Vít neo Pushlock', 'AR-2923BC', 'AR.VTRL', 8900000),
  ('Tùng Phạm', 'BV0519', 'CÔNG TY CỔ PHẦN Y KHOA BÁC SỸ GIA ĐÌNH', 'Miền Bắc', 'chcs', 'NSK Arthrex', 'Vật tư riêng lẻ - NSK Arthrex', 'Vít neo Pushlock', 'AR-2923BC', 'AR.VTRL', 8900000),
  ('Tứ Nguyễn', 'BV0414', 'BỆNH VIỆN ĐA KHOA CỬA ĐÔNG THUỘC CÔNG TY TNHH LƯƠNG THỰC MIỀN TRUNG', 'Miền Bắc', 'chcs', 'Cột sống Ulrich', 'Vật tư riêng lẻ - Cột sống Ulrich', 'Cerv-X', 'CS 820x', 'UL.VTRL', 9000000),
  ('Tùng Phạm', 'BV0330', 'Bệnh viện Trung ương Huế', 'Miền Bắc', 'chcs', 'Cột sống Ulrich', 'Bộ vít bán động CosmicMIA', 'Bộ vít bán động CosmicMIA', 'UL.MIA', 'UL.MIA', 9040000),
  ('Tuyên Phạm', 'BV0324', 'Bệnh viện Quân Y 103', 'Miền Bắc', 'chcs', 'Cột sống Ulrich', 'Bộ vít bán động CosmicMIA', 'Bộ vít bán động CosmicMIA', 'UL.MIA', 'UL.MIA', 9040000),
  ('Tuyên Phạm', 'BV0324', 'Bệnh viện Quân Y 103', 'Miền Bắc', 'chcs', 'Cột sống Ulrich', 'Bộ vít đa trục qua da', 'Bộ vít đa trục qua da', 'UL.UCT5', 'UL.UCT5', 9200000),
  ('Tứ Nguyễn', 'BV0414', 'BỆNH VIỆN ĐA KHOA CỬA ĐÔNG THUỘC CÔNG TY TNHH LƯƠNG THỰC MIỀN TRUNG', 'Miền Bắc', 'chcs', 'NSK Arthrex', 'Vật tư riêng lẻ - NSK Arthrex', 'Vít neo Swivelock BC', 'AR-2324BCC', 'AR.VTRL', 11100000),
  ('Tứ Nguyễn', 'BV0521', 'Công Ty Cổ Phần Bệnh Viện Đa Khoa Quốc Tế Vinmec', 'Miền Bắc', 'chcs', 'NSK Arthrex', 'Vật tư riêng lẻ - NSK Arthrex', 'Vít neo Swivelock BC', 'AR-2324BCC', 'AR.VTRL', 11100000),
  ('Tùng Phạm', 'BV0519', 'CÔNG TY CỔ PHẦN Y KHOA BÁC SỸ GIA ĐÌNH', 'Miền Bắc', 'chcs', 'NSK Arthrex', 'Vật tư riêng lẻ - NSK Arthrex', 'Vít neo Swivelock BC', 'AR-2324BCC', 'AR.VTRL', 11100000),
  ('Tứ Nguyễn', 'BV0414', 'BỆNH VIỆN ĐA KHOA CỬA ĐÔNG THUỘC CÔNG TY TNHH LƯƠNG THỰC MIỀN TRUNG', 'Miền Bắc', 'chcs', 'NSK Arthrex', 'Vật tư riêng lẻ - NSK Arthrex', 'Vít treo TightRope', 'AR-1588RT', 'AR.VTRL', 12700000),
  ('Tứ Nguyễn', 'BV0521', 'Công Ty Cổ Phần Bệnh Viện Đa Khoa Quốc Tế Vinmec', 'Miền Bắc', 'chcs', 'NSK Arthrex', 'Vật tư riêng lẻ - NSK Arthrex', 'Vít treo TightRope', 'AR-1588RT', 'AR.VTRL', 12700000),
  ('Tứ Nguyễn', 'BV0414', 'BỆNH VIỆN ĐA KHOA CỬA ĐÔNG THUỘC CÔNG TY TNHH LƯƠNG THỰC MIỀN TRUNG', 'Miền Bắc', 'chcs', 'Cột sống Ulrich', 'Vật tư riêng lẻ - Cột sống Ulrich', 'Pezo-P', 'CS 330x', 'UL.VTRL', 12992000),
  ('Tứ Nguyễn', 'BV0414', 'BỆNH VIỆN ĐA KHOA CỬA ĐÔNG THUỘC CÔNG TY TNHH LƯƠNG THỰC MIỀN TRUNG', 'Miền Bắc', 'chcs', 'NSK Arthrex', 'Vật tư riêng lẻ - NSK Arthrex', 'Vít neo Swivelock BC kèm chỉ', 'AR-2324BCCT', 'AR.VTRL', 13400000),
  ('Tứ Nguyễn', 'BV0521', 'Công Ty Cổ Phần Bệnh Viện Đa Khoa Quốc Tế Vinmec', 'Miền Bắc', 'chcs', 'NSK Arthrex', 'Vật tư riêng lẻ - NSK Arthrex', 'Vít neo Swivelock BC kèm chỉ', 'AR-2324BCCT', 'AR.VTRL', 13400000),
  ('Tùng Phạm', 'BV0519', 'CÔNG TY CỔ PHẦN Y KHOA BÁC SỸ GIA ĐÌNH', 'Miền Bắc', 'chcs', 'NSK Arthrex', 'Vật tư riêng lẻ - NSK Arthrex', 'Vít neo Swivelock BC kèm chỉ', 'AR-2324BCCT', 'AR.VTRL', 13400000),
  ('Tứ Nguyễn', 'BV0414', 'BỆNH VIỆN ĐA KHOA CỬA ĐÔNG THUỘC CÔNG TY TNHH LƯƠNG THỰC MIỀN TRUNG', 'Miền Bắc', 'chcs', 'Khớp UOC', 'Vật tư riêng lẻ - Khớp UOC', 'Chuôi nối dài xương đùi (đã bao gồm vít chốt)', '2703vis', 'UO.VTRL', 16160000),
  ('Tấn Phạm', 'BV1689', 'BỆNH VIỆN ĐA KHOA LÂM HOA THÁI BÌNH', 'Miền Bắc', 'chcs', 'Khớp UOC', 'Vật tư riêng lẻ - Khớp UOC', 'Chuôi nối dài xương đùi (đã bao gồm vít chốt)', '2703vis', 'UO.VTRL', 16160000),
  ('Tuyên Phạm', 'BV0342', 'Bệnh Viện Hữu Nghị Việt Đức', 'Miền Bắc', 'chcs', 'Khớp UOC', 'Vật tư riêng lẻ - Khớp UOC', 'Chuôi nối dài xương đùi (đã bao gồm vít chốt)', '2703vis', 'UO.VTRL', 16160000),
  ('Tuyên Phạm', 'BV0324', 'Bệnh viện Quân Y 103', 'Miền Bắc', 'chcs', 'Khớp UOC', 'Vật tư riêng lẻ - Khớp UOC', 'Chuôi nối dài xương đùi (đã bao gồm vít chốt)', '2703vis', 'UO.VTRL', 16160000),
  ('Tấn Phạm', 'BV0313', 'Bệnh Viện Hữu Nghị', 'Miền Bắc', 'chcs', 'Khớp UOC', 'Vật tư riêng lẻ - Khớp UOC', 'Chuôi nối dài xương đùi (đã bao gồm vít chốt)', '2703vis', 'UO.VTRL', 16160000),
  ('Tứ Nguyễn', 'BV0308', 'Bệnh viện Đại học Y Hà Nội', 'Miền Bắc', 'chcs', 'Khớp UOC', 'Vật tư riêng lẻ - Khớp UOC', 'Chuôi nối dài xương đùi (đã bao gồm vít chốt)', '2703vis', 'UO.VTRL', 16160000),
  ('Tứ Nguyễn', 'BV0414', 'BỆNH VIỆN ĐA KHOA CỬA ĐÔNG THUỘC CÔNG TY TNHH LƯƠNG THỰC MIỀN TRUNG', 'Miền Bắc', 'chcs', 'BXMCS', 'BXM không bóng', 'BXM không bóng', 'BI.VER1', 'BI.VER1', 16590000),
  ('Tứ Nguyễn', 'BV0414', 'BỆNH VIỆN ĐA KHOA CỬA ĐÔNG THUỘC CÔNG TY TNHH LƯƠNG THỰC MIỀN TRUNG', 'Miền Bắc', 'chcs', 'Cột sống Ulrich', 'ADD', 'ADD', 'UL.ADD1', 'UL.ADD1', 31000000),
  ('Mậu Cao', 'BV1829', 'BỆNH VIỆN ĐẠI HỌC Y DƯỢC – CƠ SỞ LINH ĐÀM', 'Miền Bắc', 'chcs', 'Cột sống Ulrich', 'ADD', 'ADD', 'UL.ADD1', 'UL.ADD1', 31000000),
  ('Tứ Nguyễn', 'BV0521', 'Công Ty Cổ Phần Bệnh Viện Đa Khoa Quốc Tế Vinmec', 'Miền Bắc', 'chcs', 'Cột sống Ulrich', 'ADD', 'ADD', 'UL.ADD1', 'UL.ADD1', 31000000),
  ('Tứ Nguyễn', 'BV0521', 'Công Ty Cổ Phần Bệnh Viện Đa Khoa Quốc Tế Vinmec', 'Miền Bắc', 'chcs', 'NSK Arthrex', 'Vật tư riêng lẻ - NSK Arthrex', 'Bộ chỉ khâu gân gót chân', 'AR-8860DS', 'AR.VTRL', 35000000),
  ('Tứ Nguyễn', 'BV0414', 'BỆNH VIỆN ĐA KHOA CỬA ĐÔNG THUỘC CÔNG TY TNHH LƯƠNG THỰC MIỀN TRUNG', 'Miền Bắc', 'chcs', 'Khớp UOC', 'Bipolar thường - UOC', 'Bipolar thường - UOC', 'UO.HBPT1', 'UO.HBPT1', 39790000),
  ('Tuyên Phạm', 'DN2642', 'CÔNG TY TNHH BỆNH VIỆN ĐA KHOA ANH QUẤT', 'Miền Bắc', 'chcs', 'Khớp UOC', 'Bipolar thường - UOC', 'Bipolar thường - UOC', 'UO.HBPT1', 'UO.HBPT1', 39790000),
  ('Tứ Nguyễn', 'BV0521', 'Công Ty Cổ Phần Bệnh Viện Đa Khoa Quốc Tế Vinmec', 'Miền Bắc', 'chcs', 'Khớp UOC', 'Bipolar thường - UOC', 'Bipolar thường - UOC', 'UO.HBPT1', 'UO.HBPT1', 39790000),
  ('Tứ Nguyễn', 'BV0414', 'BỆNH VIỆN ĐA KHOA CỬA ĐÔNG THUỘC CÔNG TY TNHH LƯƠNG THỰC MIỀN TRUNG', 'Miền Bắc', 'chcs', 'Cột sống Ulrich', 'ADD Plus', 'ADD Plus', 'UL.ADD2', 'UL.ADD2', 45000000),
  ('Tứ Nguyễn', 'BV0521', 'Công Ty Cổ Phần Bệnh Viện Đa Khoa Quốc Tế Vinmec', 'Miền Bắc', 'chcs', 'Cột sống Ulrich', 'ADD Plus', 'ADD Plus', 'UL.ADD2', 'UL.ADD2', 45000000),
  ('Tứ Nguyễn', 'BV0414', 'BỆNH VIỆN ĐA KHOA CỬA ĐÔNG THUỘC CÔNG TY TNHH LƯƠNG THỰC MIỀN TRUNG', 'Miền Bắc', 'chcs', 'BXMCS', 'BXM có bóng', 'BXM có bóng', 'BI.KYP1', 'BI.KYP1', 52500000),
  ('Tứ Nguyễn', 'BV0414', 'BỆNH VIỆN ĐA KHOA CỬA ĐÔNG THUỘC CÔNG TY TNHH LƯƠNG THỰC MIỀN TRUNG', 'Miền Bắc', 'chcs', 'Khớp UOC', 'MOP - UOC', 'MOP - UOC', 'UO.HTPT.MOP1', 'UO.HTPT.MOP1', 55000000),
  ('Tuyên Phạm', 'BV1405', 'Bệnh Viện Đa Khoa Quốc Tế Bắc Hà - Chi Nhánh Công Ty TNHH Minh Hưng', 'Miền Bắc', 'chcs', 'Khớp UOC', 'MOP - UOC', 'MOP - UOC', 'UO.HTPT.MOP1', 'UO.HTPT.MOP1', 55000000),
  ('Tuyên Phạm', 'DN2642', 'CÔNG TY TNHH BỆNH VIỆN ĐA KHOA ANH QUẤT', 'Miền Bắc', 'chcs', 'Khớp UOC', 'MOP - UOC', 'MOP - UOC', 'UO.HTPT.MOP1', 'UO.HTPT.MOP1', 55000000),
  ('Tứ Nguyễn', 'BV0414', 'BỆNH VIỆN ĐA KHOA CỬA ĐÔNG THUỘC CÔNG TY TNHH LƯƠNG THỰC MIỀN TRUNG', 'Miền Bắc', 'chcs', 'Khớp UOC', 'Gối thường - UOC', 'Gối thường - UOC', 'UO.GTPT1', 'UO.GTPT1', 58000000),
  ('Tùng Phạm', 'BV0519', 'CÔNG TY CỔ PHẦN Y KHOA BÁC SỸ GIA ĐÌNH', 'Miền Bắc', 'chcs', 'Khớp UOC', 'Gối thường - UOC', 'Gối thường - UOC', 'UO.GTPT1', 'UO.GTPT1', 58000000),
  ('Tuyên Phạm', 'DN2642', 'CÔNG TY TNHH BỆNH VIỆN ĐA KHOA ANH QUẤT', 'Miền Bắc', 'chcs', 'Khớp UOC', 'Gối thường - UOC', 'Gối thường - UOC', 'UO.GTPT1', 'UO.GTPT1', 58000000),
  ('Tứ Nguyễn', 'BV0521', 'Công Ty Cổ Phần Bệnh Viện Đa Khoa Quốc Tế Vinmec', 'Miền Bắc', 'chcs', 'Khớp UOC', 'Gối thường - UOC', 'Gối thường - UOC', 'UO.GTPT1', 'UO.GTPT1', 58000000),
  ('Tứ Nguyễn', 'BV0414', 'BỆNH VIỆN ĐA KHOA CỬA ĐÔNG THUỘC CÔNG TY TNHH LƯƠNG THỰC MIỀN TRUNG', 'Miền Bắc', 'chcs', 'Khớp UOC', 'Bipolar dài - UOC', 'Bipolar dài - UOC', 'UO.HBPD1', 'UO.HBPD1', 58290000),
  ('Tuyên Phạm', 'DN2642', 'CÔNG TY TNHH BỆNH VIỆN ĐA KHOA ANH QUẤT', 'Miền Bắc', 'chcs', 'Khớp UOC', 'Bipolar dài - UOC', 'Bipolar dài - UOC', 'UO.HBPD1', 'UO.HBPD1', 58290000),
  ('Tứ Nguyễn', 'BV0488', 'Bệnh viện Bưu Điện', 'Miền Bắc', 'chcs', 'Khớp UOC', 'Vật tư riêng lẻ - Khớp UOC', 'Chuôi nối dài xương đùi (đã bao gồm vít chốt)', '2703vis', 'UO.VTRL', 16160000),
  ('Tứ Nguyễn', 'BV1432', 'Bệnh Viện Chấn Thương Chỉnh Hình Nghệ An (1115142)', 'Miền Bắc', 'chcs', 'Khớp UOC', 'Vật tư riêng lẻ - Khớp UOC', 'Xi măng khớp', '880013', 'UO.VTRL', 4000000),
  ('Mậu Cao', 'BV0320', 'Bệnh Viện Phổi Trung Ương', 'Miền Bắc', 'chcs', 'Cột sống Ulrich', 'ADD', 'ADD', 'UL.ADD1', 'UL.ADD1', 31000000),
  ('Tuyên Phạm', 'DN2665', 'CÔNG TY CỔ PHẦN KINH DOANH VÀ THƯƠNG MẠI TRẦN GIA', 'Miền Bắc', 'chcs', 'NSK Arthrex', 'Vật tư riêng lẻ - NSK Arthrex', 'Vít treo TightRope', 'AR-1588RT', 'AR.VTRL', 12319000),
  ('Tuyên Phạm', 'DN2665', 'CÔNG TY CỔ PHẦN KINH DOANH VÀ THƯƠNG MẠI TRẦN GIA', 'Miền Bắc', 'chcs', 'NSK Arthrex', 'Vật tư riêng lẻ - NSK Arthrex', 'Chỉ tròn kèm kim', 'AR-7200', 'AR.VTRL', 1164000),
  ('Tuyên Phạm', 'DN2665', 'CÔNG TY CỔ PHẦN KINH DOANH VÀ THƯƠNG MẠI TRẦN GIA', 'Miền Bắc', 'chcs', 'NSK Arthrex', 'Vật tư riêng lẻ - NSK Arthrex', 'Lưỡi bào khớp', 'AR-8xx0EX', 'AR.VTRL', 4365000),
  ('Tuyên Phạm', 'DN2665', 'CÔNG TY CỔ PHẦN KINH DOANH VÀ THƯƠNG MẠI TRẦN GIA', 'Miền Bắc', 'chcs', 'NSK Arthrex', 'Vật tư riêng lẻ - NSK Arthrex', 'Đầu đốt RF', 'AR-9811', 'AR.VTRL', 7469000),
  ('Tuyên Phạm', 'DN2665', 'CÔNG TY CỔ PHẦN KINH DOANH VÀ THƯƠNG MẠI TRẦN GIA', 'Miền Bắc', 'chcs', 'NSK Arthrex', 'Vật tư riêng lẻ - NSK Arthrex', 'Mũi khoan ngược', 'AR-1204AF-xx', 'AR.VTRL', 4365000),
  ('Tuyên Phạm', 'DN2665', 'CÔNG TY CỔ PHẦN KINH DOANH VÀ THƯƠNG MẠI TRẦN GIA', 'Miền Bắc', 'chcs', 'NSK Arthrex', 'Vật tư riêng lẻ - NSK Arthrex', 'Dây nước', 'AR-6410', 'AR.VTRL', 1455000),
  ('Tuyên Phạm', 'DN0605', 'Công ty Cổ phần MD 268', 'Miền Bắc', 'chcs', 'Khớp UOC', 'MOP dài - UOC', 'MOP dài - UOC', 'UO.HTPD.MOP1', 'UO.HTPD.MOP1', 73500000),
  ('Tuyên Phạm', 'BV1405', 'Bệnh Viện Đa Khoa Quốc Tế Bắc Hà - Chi Nhánh Công Ty TNHH Minh Hưng', 'Miền Bắc', 'chcs', 'Khớp UOC', 'COP - UOC', 'COP - UOC', 'UO.HTPT.COP1', 'UO.HTPT.COP1', 63800000),
  ('Tứ Nguyễn', 'BV0414', 'BỆNH VIỆN ĐA KHOA CỬA ĐÔNG THUỘC CÔNG TY TNHH LƯƠNG THỰC MIỀN TRUNG', 'Miền Bắc', 'chcs', 'Khớp UOC', 'COP - UOC', 'COP - UOC', 'UO.HTPT.COP1', 'UO.HTPT.COP1', 63800000),
  ('Tứ Nguyễn', 'BV1432', 'Bệnh Viện Chấn Thương Chỉnh Hình Nghệ An (1115142)', 'Miền Bắc', 'chcs', 'Khớp UOC', 'Vật tư riêng lẻ - Khớp UOC', 'Chuôi nối dài xương đùi (đã bao gồm vít chốt)', '2703vis', 'UO.VTRL', 16160000),
  ('Tuyên Phạm', 'DN2642', 'CÔNG TY TNHH BỆNH VIỆN ĐA KHOA ANH QUẤT', 'Miền Bắc', 'chcs', 'Khớp UOC', 'COP - UOC', 'COP - UOC', 'UO.HTPT.COP1', 'UO.HTPT.COP1', 63800000),
  ('Tứ Nguyễn', 'BV0521', 'Công Ty Cổ Phần Bệnh Viện Đa Khoa Quốc Tế Vinmec', 'Miền Bắc', 'chcs', 'Khớp UOC', 'COP - UOC', 'COP - UOC', 'UO.HTPT.COP1', 'UO.HTPT.COP1', 63800000),
  ('Tứ Nguyễn', 'BV0414', 'BỆNH VIỆN ĐA KHOA CỬA ĐÔNG THUỘC CÔNG TY TNHH LƯƠNG THỰC MIỀN TRUNG', 'Miền Bắc', 'chcs', 'Khớp UOC', 'MOP dài - UOC', 'MOP dài - UOC', 'UO.HTPD.MOP1', 'UO.HTPD.MOP1', 73500000),
  ('Tuyên Phạm', 'BV1405', 'Bệnh Viện Đa Khoa Quốc Tế Bắc Hà - Chi Nhánh Công Ty TNHH Minh Hưng', 'Miền Bắc', 'chcs', 'Khớp UOC', 'MOP dài - UOC', 'MOP dài - UOC', 'UO.HTPD.MOP1', 'UO.HTPD.MOP1', 73500000),
  ('Tuyên Phạm', 'DN2642', 'CÔNG TY TNHH BỆNH VIỆN ĐA KHOA ANH QUẤT', 'Miền Bắc', 'chcs', 'Khớp UOC', 'MOP dài - UOC', 'MOP dài - UOC', 'UO.HTPD.MOP1', 'UO.HTPD.MOP1', 73500000),
  ('Tứ Nguyễn', 'BV0414', 'BỆNH VIỆN ĐA KHOA CỬA ĐÔNG THUỘC CÔNG TY TNHH LƯƠNG THỰC MIỀN TRUNG', 'Miền Bắc', 'chcs', 'Khớp UOC', 'COC - UOC', 'COC - UOC', 'UO.HTPT.COC1', 'UO.HTPT.COC1', 75800000),
  ('Tứ Nguyễn', 'BV0414', 'BỆNH VIỆN ĐA KHOA CỬA ĐÔNG THUỘC CÔNG TY TNHH LƯƠNG THỰC MIỀN TRUNG', 'Miền Bắc', 'chcs', 'Khớp UOC', 'Gối thay lại - UOC', 'Gối thay lại - UOC', 'UO.GTL1', 'UO.GTL1', 80080000),
  ('Tuyên Phạm', 'DN2642', 'CÔNG TY TNHH BỆNH VIỆN ĐA KHOA ANH QUẤT', 'Miền Bắc', 'chcs', 'Khớp UOC', 'Gối thay lại - UOC', 'Gối thay lại - UOC', 'UO.GTL1', 'UO.GTL1', 80080000),
  ('Tứ Nguyễn', 'BV1432', 'Bệnh Viện Chấn Thương Chỉnh Hình Nghệ An (1115142)', 'Miền Bắc', 'chcs', 'BXMCS', 'Vật tư riêng lẻ - CHCS Khác', 'Hệ thống trộn, bơm áp lực đẩy xi măng', 'VCEM_110190', 'BXM.VTRL', 6500000),
  ('Tứ Nguyễn', 'BV1432', 'Bệnh Viện Chấn Thương Chỉnh Hình Nghệ An (1115142)', 'Miền Bắc', 'chcs', 'NSK Arthrex', 'Vật tư riêng lẻ - NSK Arthrex', 'Cây đẩy chỉ', 'AR-13999HDN', 'AR.VTRL', 6000000);
INSERT INTO _ins VALUES
  ('Tứ Nguyễn', 'BV0414', 'NSK Arthrex', 'Vật tư riêng lẻ - NSK Arthrex', 'Troca có ren', 1150000, 'cu', 1, 1, 'AR-65xx', '29'),
  ('Tứ Nguyễn', 'BV0521', 'NSK Arthrex', 'Vật tư riêng lẻ - NSK Arthrex', 'Troca có ren', 1150000, 'cu', 1, 0, 'AR-65xx', '33'),
  ('Tứ Nguyễn', 'BV0414', 'NSK Arthrex', 'Vật tư riêng lẻ - NSK Arthrex', 'Chỉ tròn kèm kim', 1200000, 'cu', 1, 1, 'AR-7200', '37'),
  ('Tứ Nguyễn', 'BV0521', 'NSK Arthrex', 'Vật tư riêng lẻ - NSK Arthrex', 'Chỉ tròn kèm kim', 1200000, 'cu', 1, 0, 'AR-7200', '44'),
  ('Tùng Phạm', 'BV0338', 'NSK Arthrex', 'Vật tư riêng lẻ - NSK Arthrex', 'Dây nước', 1454081, 'cu', 1, 198, 'AR-6410', '62'),
  ('Tứ Nguyễn', 'BV0414', 'NSK Arthrex', 'Vật tư riêng lẻ - NSK Arthrex', 'Dây nước', 1500000, 'cu', 1, 1, 'AR-6410', '65'),
  ('Tứ Nguyễn', 'BV0521', 'NSK Arthrex', 'Vật tư riêng lẻ - NSK Arthrex', 'Dây nước', 1500000, 'cu', 1, 0, 'AR-6410', '71'),
  ('Tùng Phạm', 'BV0519', 'NSK Arthrex', 'Vật tư riêng lẻ - NSK Arthrex', 'Dây nước', 1500000, 'cu', 1, 10, 'AR-6410', '72'),
  ('Tứ Nguyễn', 'BV0414', 'Cột sống Ulrich', 'Vật tư riêng lẻ - Cột sống Ulrich', 'Thanh dọc Flamenco', 2000000, 'cu', 1, 1, 'CS 8012-480', '80'),
  ('Tứ Nguyễn', 'BV0414', 'Cột sống Ulrich', 'Vật tư riêng lẻ - Cột sống Ulrich', 'Thanh dọc thường 100-180mm', 2100000, 'cu', 1, 1, 'CS 3807-100-180', '88'),
  ('Tứ Nguyễn', 'BV0414', 'Cột sống Ulrich', 'Vật tư riêng lẻ - Cột sống Ulrich', 'Thanh dọc thẳng qua da <300mm', 3000000, 'cu', 1, 1, 'CS 3808-300', '100'),
  ('Tùng Phạm', 'BV0338', 'Khớp UOC', 'Vật tư riêng lẻ - Khớp UOC', 'Xi măng khớp', 4000000, 'cu', 1, 30, '880013', '103'),
  ('Tấn Phạm', 'BV1689', 'Khớp UOC', 'Vật tư riêng lẻ - Khớp UOC', 'Xi măng khớp', 4000000, 'cu', 1, 1, '880013', '104'),
  ('Tấn Phạm', 'BV0313', 'Khớp UOC', 'Vật tư riêng lẻ - Khớp UOC', 'Xi măng khớp', 4000000, 'cu', 1, 30, '880013', '105'),
  ('Tứ Nguyễn', 'BV0414', 'Cột sống Ulrich', 'Vật tư riêng lẻ - Cột sống Ulrich', 'Xương nhân tạo 1cc', 4500000, 'cu', 1, 1, 'CS 6604-010', '121'),
  ('Tứ Nguyễn', 'BV0414', 'NSK Arthrex', 'Vật tư riêng lẻ - NSK Arthrex', 'Lưỡi bào khớp', 4500000, 'cu', 1, 1, 'AR-8xx0EX', '123'),
  ('Tứ Nguyễn', 'BV0521', 'NSK Arthrex', 'Vật tư riêng lẻ - NSK Arthrex', 'Lưỡi bào khớp', 4500000, 'cu', 1, 0, 'AR-8xx0EX', '137'),
  ('Tứ Nguyễn', 'BV0521', 'NSK Arthrex', 'Vật tư riêng lẻ - NSK Arthrex', 'Mũi khoan ngược', 4500000, 'cu', 1, 0, 'AR-1204AF-xx', '138'),
  ('Tùng Phạm', 'BV0519', 'NSK Arthrex', 'Vật tư riêng lẻ - NSK Arthrex', 'Lưỡi bào khớp', 4500000, 'cu', 1, 10, 'AR-8xx0EX', '139'),
  ('Tứ Nguyễn', 'BV0414', 'NSK Arthrex', 'Vật tư riêng lẻ - NSK Arthrex', 'Lưỡi mài khớp', 5200000, 'cu', 1, 1, 'AR-8xx0OBx', '161'),
  ('Tứ Nguyễn', 'BV0521', 'NSK Arthrex', 'Vật tư riêng lẻ - NSK Arthrex', 'Lưỡi mài khớp', 5200000, 'cu', 1, 0, 'AR-8xx0OBx', '167'),
  ('Tứ Nguyễn', 'BV0521', 'NSK Arthrex', 'Vật tư riêng lẻ - NSK Arthrex', 'Cây móc chỉ', 5900000, 'cu', 1, 1, 'AR-4068-xxx', '186'),
  ('Tứ Nguyễn', 'BV0521', 'NSK Arthrex', 'Vật tư riêng lẻ - NSK Arthrex', 'Cây đẩy chỉ', 6000000, 'cu', 1, 1, 'AR-13999HDN', '190'),
  ('Tuyên Phạm', 'BV0324', 'Cột sống Ulrich', 'Bộ vít đa trục thường', 'Bộ vít đa trục thường', 6500000, 'cu', 1, 200, 'UL.UCT1', '191'),
  ('Tứ Nguyễn', 'BV0521', 'NSK Arthrex', 'Vật tư riêng lẻ - NSK Arthrex', 'Vít Biocomposit ACL', 6800000, 'cu', 1, 1, 'AR-5035TC-xx', '201'),
  ('Tứ Nguyễn', 'BV0414', 'NSK Arthrex', 'Vật tư riêng lẻ - NSK Arthrex', 'Đầu đốt RF', 7700000, 'cu', 1, 1, 'AR-9811', '223'),
  ('Tứ Nguyễn', 'BV0521', 'NSK Arthrex', 'Vật tư riêng lẻ - NSK Arthrex', 'Đầu đốt RF', 7700000, 'cu', 1, 0, 'AR-9811', '229'),
  ('Tùng Phạm', 'BV0519', 'NSK Arthrex', 'Vật tư riêng lẻ - NSK Arthrex', 'Đầu đốt RF', 7700000, 'cu', 1, 10, 'AR-9811', '230'),
  ('Tứ Nguyễn', 'BV0414', 'Cột sống Ulrich', 'Vật tư riêng lẻ - Cột sống Ulrich', 'Thanh ngang uCentum', 8500000, 'cu', 1, 1, 'CS 3810', '243'),
  ('Tùng Phạm', 'BV0519', 'NSK Arthrex', 'Vật tư riêng lẻ - NSK Arthrex', 'Vít neo Suturetak', 8600000, 'cu', 1, 11, 'AR-1934BCF-2', '252'),
  ('Tứ Nguyễn', 'BV0521', 'NSK Arthrex', 'Vật tư riêng lẻ - NSK Arthrex', 'Vít neo Pushlock', 8900000, 'cu', 1, 0, 'AR-2923BC', '267'),
  ('Tùng Phạm', 'BV0519', 'NSK Arthrex', 'Vật tư riêng lẻ - NSK Arthrex', 'Vít neo Pushlock', 8900000, 'cu', 1, 15, 'AR-2923BC', '268'),
  ('Tứ Nguyễn', 'BV0414', 'Cột sống Ulrich', 'Vật tư riêng lẻ - Cột sống Ulrich', 'Cerv-X', 9000000, 'cu', 1, 1, 'CS 820x', '271'),
  ('Tùng Phạm', 'BV0330', 'Cột sống Ulrich', 'Bộ vít bán động CosmicMIA', 'Bộ vít bán động CosmicMIA', 9040000, 'cu', 1, 400, 'UL.MIA', '277'),
  ('Tuyên Phạm', 'BV0324', 'Cột sống Ulrich', 'Bộ vít bán động CosmicMIA', 'Bộ vít bán động CosmicMIA', 9040000, 'cu', 1, 60, 'UL.MIA', '278'),
  ('Tuyên Phạm', 'BV0324', 'Cột sống Ulrich', 'Bộ vít đa trục qua da', 'Bộ vít đa trục qua da', 9200000, 'cu', 1, 112, 'UL.UCT5', '292'),
  ('Tứ Nguyễn', 'BV0414', 'NSK Arthrex', 'Vật tư riêng lẻ - NSK Arthrex', 'Vít neo Swivelock BC', 11100000, 'cu', 1, 1, 'AR-2324BCC', '312'),
  ('Tứ Nguyễn', 'BV0521', 'NSK Arthrex', 'Vật tư riêng lẻ - NSK Arthrex', 'Vít neo Swivelock BC', 11100000, 'cu', 1, 1, 'AR-2324BCC', '317'),
  ('Tùng Phạm', 'BV0519', 'NSK Arthrex', 'Vật tư riêng lẻ - NSK Arthrex', 'Vít neo Swivelock BC', 11100000, 'cu', 1, 0, 'AR-2324BCC', '318'),
  ('Mậu Cao', 'BV0336', 'Cột sống Ulrich', 'Vật tư riêng lẻ - Cột sống Ulrich', 'Pezo-P', 12992000, 'cu', 1, 25, 'CS 330x', '349'),
  ('Tứ Nguyễn', 'BV0414', 'NSK Arthrex', 'Vật tư riêng lẻ - NSK Arthrex', 'Vít treo TightRope', 12700000, 'cu', 1, 1, 'AR-1588RT', '355'),
  ('Tứ Nguyễn', 'BV0521', 'NSK Arthrex', 'Vật tư riêng lẻ - NSK Arthrex', 'Vít treo TightRope', 12700000, 'cu', 1, 0, 'AR-1588RT', '362'),
  ('Tứ Nguyễn', 'BV0414', 'Cột sống Ulrich', 'Vật tư riêng lẻ - Cột sống Ulrich', 'Pezo-P', 12992000, 'cu', 1, 1, 'CS 330x', '373'),
  ('Tứ Nguyễn', 'BV0414', 'NSK Arthrex', 'Vật tư riêng lẻ - NSK Arthrex', 'Vít neo Swivelock BC kèm chỉ', 13400000, 'cu', 1, 1, 'AR-2324BCCT', '382'),
  ('Tứ Nguyễn', 'BV0521', 'NSK Arthrex', 'Vật tư riêng lẻ - NSK Arthrex', 'Vít neo Swivelock BC kèm chỉ', 13400000, 'cu', 1, 0, 'AR-2324BCCT', '390'),
  ('Tùng Phạm', 'BV0519', 'NSK Arthrex', 'Vật tư riêng lẻ - NSK Arthrex', 'Vít neo Swivelock BC kèm chỉ', 13400000, 'cu', 1, 0, 'AR-2324BCCT', '391,392,393'),
  ('Tứ Nguyễn', 'BV0414', 'Khớp UOC', 'Vật tư riêng lẻ - Khớp UOC', 'Chuôi nối dài xương đùi (đã bao gồm vít chốt)', 16160000, 'cu', 1, 1, '2703vis', '401'),
  ('Tấn Phạm', 'BV1689', 'Khớp UOC', 'Vật tư riêng lẻ - Khớp UOC', 'Chuôi nối dài xương đùi (đã bao gồm vít chốt)', 16160000, 'cu', 1, 1, '2703vis', '402'),
  ('Tuyên Phạm', 'BV0342', 'Khớp UOC', 'Vật tư riêng lẻ - Khớp UOC', 'Chuôi nối dài xương đùi (đã bao gồm vít chốt)', 16160000, 'cu', 1, 50, '2703vis', '403'),
  ('Tuyên Phạm', 'BV0324', 'Khớp UOC', 'Vật tư riêng lẻ - Khớp UOC', 'Chuôi nối dài xương đùi (đã bao gồm vít chốt)', 16160000, 'cu', 1, 2, '2703vis', '404'),
  ('Tấn Phạm', 'BV0313', 'Khớp UOC', 'Vật tư riêng lẻ - Khớp UOC', 'Chuôi nối dài xương đùi (đã bao gồm vít chốt)', 16160000, 'cu', 1, 30, '2703vis', '405'),
  ('Tứ Nguyễn', 'BV0308', 'Khớp UOC', 'Vật tư riêng lẻ - Khớp UOC', 'Chuôi nối dài xương đùi (đã bao gồm vít chốt)', 16160000, 'cu', 1, 20, '2703vis', '406'),
  ('Tứ Nguyễn', 'BV0414', 'BXMCS', 'BXM không bóng', 'BXM không bóng', 16590000, 'cu', 1, 1, 'BI.VER1', '407'),
  ('Tứ Nguyễn', 'BV0414', 'Cột sống Ulrich', 'ADD', 'ADD', 31000000, 'cu', 1, 1, 'UL.ADD1', '427'),
  ('Mậu Cao', 'BV1829', 'Cột sống Ulrich', 'ADD', 'ADD', 31000000, 'cu', 1, 12, 'UL.ADD1', '429'),
  ('Tứ Nguyễn', 'BV0521', 'Cột sống Ulrich', 'ADD', 'ADD', 31000000, 'cu', 1, 1, 'UL.ADD1', '433'),
  ('Tứ Nguyễn', 'BV0521', 'NSK Arthrex', 'Vật tư riêng lẻ - NSK Arthrex', 'Bộ chỉ khâu gân gót chân', 35000000, 'cu', 1, 1, 'AR-8860DS', '436'),
  ('Tứ Nguyễn', 'BV0414', 'Khớp UOC', 'Bipolar thường - UOC', 'Bipolar thường - UOC', 39790000, 'cu', 1, 1, 'UO.HBPT1', '448'),
  ('Tuyên Phạm', 'DN2642', 'Khớp UOC', 'Bipolar thường - UOC', 'Bipolar thường - UOC', 39790000, 'cu', 1, 70, 'UO.HBPT1', '452'),
  ('Tứ Nguyễn', 'BV0521', 'Khớp UOC', 'Bipolar thường - UOC', 'Bipolar thường - UOC', 39790000, 'cu', 1, 1, 'UO.HBPT1', '453'),
  ('Tứ Nguyễn', 'BV0414', 'Cột sống Ulrich', 'ADD Plus', 'ADD Plus', 45000000, 'cu', 1, 1, 'UL.ADD2', '462'),
  ('Tứ Nguyễn', 'BV0521', 'Cột sống Ulrich', 'ADD Plus', 'ADD Plus', 45000000, 'cu', 1, 1, 'UL.ADD2', '466'),
  ('Tứ Nguyễn', 'BV0414', 'BXMCS', 'BXM có bóng', 'BXM có bóng', 52500000, 'cu', 1, 1, 'BI.KYP1', '467'),
  ('Tứ Nguyễn', 'BV0414', 'Khớp UOC', 'MOP - UOC', 'MOP - UOC', 55000000, 'cu', 1, 1, 'UO.HTPT.MOP1', '475'),
  ('Tuyên Phạm', 'BV1405', 'Khớp UOC', 'MOP - UOC', 'MOP - UOC', 55000000, 'cu', 1, 1, 'UO.HTPT.MOP1', '476'),
  ('Tuyên Phạm', 'DN2642', 'Khớp UOC', 'MOP - UOC', 'MOP - UOC', 55000000, 'cu', 1, 120, 'UO.HTPT.MOP1', '479'),
  ('Tứ Nguyễn', 'BV0414', 'Khớp UOC', 'Gối thường - UOC', 'Gối thường - UOC', 58000000, 'cu', 1, 1, 'UO.GTPT1', '492'),
  ('Tùng Phạm', 'BV0519', 'Khớp UOC', 'Gối thường - UOC', 'Gối thường - UOC', 58000000, 'cu', 1, 13, 'UO.GTPT1', '497,498'),
  ('Tuyên Phạm', 'DN2642', 'Khớp UOC', 'Gối thường - UOC', 'Gối thường - UOC', 58000000, 'cu', 1, 60, 'UO.GTPT1', '499'),
  ('Tứ Nguyễn', 'BV0521', 'Khớp UOC', 'Gối thường - UOC', 'Gối thường - UOC', 58000000, 'cu', 1, 1, 'UO.GTPT1', '500'),
  ('Tứ Nguyễn', 'BV0414', 'Khớp UOC', 'Bipolar dài - UOC', 'Bipolar dài - UOC', 58290000, 'cu', 1, 1, 'UO.HBPD1', '510'),
  ('Tuyên Phạm', 'DN2642', 'Khớp UOC', 'Bipolar dài - UOC', 'Bipolar dài - UOC', 58290000, 'cu', 1, 140, 'UO.HBPD1', '518'),
  ('Tứ Nguyễn', 'BV0488', 'Khớp UOC', 'Vật tư riêng lẻ - Khớp UOC', 'Chuôi nối dài xương đùi (đã bao gồm vít chốt)', 16160000, 'chinh', 2, 2, '2703vis', '600'),
  ('Tứ Nguyễn', 'BV0488', 'Khớp UOC', 'Vật tư riêng lẻ - Khớp UOC', 'Chuôi nối dài xương đùi (đã bao gồm vít chốt)', 16160000, 'chinh', 1, 2, '2703vis', '933'),
  ('Tứ Nguyễn', 'BV1432', 'Khớp UOC', 'Vật tư riêng lẻ - Khớp UOC', 'Xi măng khớp', 4000000, 'bo_sung', 1, 25, '880013', '610'),
  ('Mậu Cao', 'BV0320', 'Cột sống Ulrich', 'ADD', 'ADD', 31000000, 'chinh', 1, 10, 'UL.ADD1', '681'),
  ('Tuyên Phạm', 'DN2665', 'NSK Arthrex', 'Vật tư riêng lẻ - NSK Arthrex', 'Vít treo TightRope', 12319000, 'bo_sung', 1, 2, 'AR-1588RT', '744'),
  ('Tuyên Phạm', 'DN2665', 'NSK Arthrex', 'Vật tư riêng lẻ - NSK Arthrex', 'Chỉ tròn kèm kim', 1164000, 'bo_sung', 1, 2, 'AR-7200', '745'),
  ('Tuyên Phạm', 'DN2665', 'NSK Arthrex', 'Vật tư riêng lẻ - NSK Arthrex', 'Lưỡi bào khớp', 4365000, 'bo_sung', 1, 7, 'AR-8xx0EX', '746'),
  ('Tuyên Phạm', 'DN2665', 'NSK Arthrex', 'Vật tư riêng lẻ - NSK Arthrex', 'Đầu đốt RF', 7469000, 'bo_sung', 1, 7, 'AR-9811', '747'),
  ('Tuyên Phạm', 'DN2665', 'NSK Arthrex', 'Vật tư riêng lẻ - NSK Arthrex', 'Mũi khoan ngược', 4365000, 'bo_sung', 1, 2, 'AR-1204AF-xx', '748'),
  ('Tuyên Phạm', 'DN2665', 'NSK Arthrex', 'Vật tư riêng lẻ - NSK Arthrex', 'Dây nước', 1455000, 'bo_sung', 1, 9, 'AR-6410', '749'),
  ('Tuyên Phạm', 'DN0605', 'Khớp UOC', 'MOP dài - UOC', 'MOP dài - UOC', 73500000, 'bo_sung', 1, 4, 'UO.HTPD.MOP1', '759'),
  ('Tuyên Phạm', 'BV1405', 'Khớp UOC', 'COP - UOC', 'COP - UOC', 63800000, 'cu', 1, 1, 'UO.HTPT.COP1', '762'),
  ('Tứ Nguyễn', 'BV0414', 'Khớp UOC', 'COP - UOC', 'COP - UOC', 63800000, 'cu', 1, 1, 'UO.HTPT.COP1', '764'),
  ('Tứ Nguyễn', 'BV1432', 'Khớp UOC', 'Vật tư riêng lẻ - Khớp UOC', 'Chuôi nối dài xương đùi (đã bao gồm vít chốt)', 16160000, 'chinh', 2, 6, '2703vis', '777'),
  ('Tứ Nguyễn', 'BV1432', 'Khớp UOC', 'Vật tư riêng lẻ - Khớp UOC', 'Chuôi nối dài xương đùi (đã bao gồm vít chốt)', 16160000, 'chinh', 1, 5, '2703vis', '882'),
  ('Tuyên Phạm', 'DN2642', 'Khớp UOC', 'COP - UOC', 'COP - UOC', 63800000, 'cu', 1, 140, 'UO.HTPT.COP1', '780'),
  ('Tứ Nguyễn', 'BV0521', 'Khớp UOC', 'COP - UOC', 'COP - UOC', 63800000, 'cu', 1, 1, 'UO.HTPT.COP1', '781'),
  ('Tứ Nguyễn', 'BV0414', 'Khớp UOC', 'MOP dài - UOC', 'MOP dài - UOC', 73500000, 'cu', 1, 1, 'UO.HTPD.MOP1', '789'),
  ('Tuyên Phạm', 'BV1405', 'Khớp UOC', 'MOP dài - UOC', 'MOP dài - UOC', 73500000, 'cu', 1, 1, 'UO.HTPD.MOP1', '791'),
  ('Tuyên Phạm', 'DN2642', 'Khớp UOC', 'MOP dài - UOC', 'MOP dài - UOC', 73500000, 'cu', 1, 4, 'UO.HTPD.MOP1', '795'),
  ('Tứ Nguyễn', 'BV0414', 'Khớp UOC', 'COC - UOC', 'COC - UOC', 75800000, 'cu', 1, 1, 'UO.HTPT.COC1', '801'),
  ('Tứ Nguyễn', 'BV0414', 'Khớp UOC', 'Gối thay lại - UOC', 'Gối thay lại - UOC', 80080000, 'cu', 1, 1, 'UO.GTL1', '805'),
  ('Tuyên Phạm', 'DN2642', 'Khớp UOC', 'Gối thay lại - UOC', 'Gối thay lại - UOC', 80080000, 'cu', 1, 2, 'UO.GTL1', '808'),
  ('Tứ Nguyễn', 'BV1432', 'BXMCS', 'Vật tư riêng lẻ - CHCS Khác', 'Xi măng cột sống', 6825000, 'chinh', 1, 20, '01-0350', '854'),
  ('Tứ Nguyễn', 'BV1432', 'BXMCS', 'Vật tư riêng lẻ - CHCS Khác', 'Hệ thống trộn, bơm áp lực đẩy xi măng', 6500000, 'chinh', 1, 20, 'VCEM_110190', '855'),
  ('Tứ Nguyễn', 'BV1432', 'NSK Arthrex', 'Vật tư riêng lẻ - NSK Arthrex', 'Cây đẩy chỉ', 6000000, 'chinh', 2, 5, 'AR-13999HDN', '868'),
  ('Tuyên Phạm', 'BV0324', 'Khớp UOC', 'Bipolar dài - UOC', 'Bipolar dài - UOC', 58290000, 'bo_sung', 2, 20, 'UO.HBPD1', '904'),
  ('Tứ Nguyễn', 'BV0488', 'NSK Arthrex', 'Vật tư riêng lẻ - NSK Arthrex', 'Cây đẩy chỉ', 6000000, 'chinh', 1, 27, 'AR-13999HDN', '918'),
  ('Tứ Nguyễn', 'BV0625', 'BXMCS', 'BXM không bóng', 'BXM không bóng', 16590000, 'chinh', 1, 14, 'BI.VER1', '955');
CREATE TEMP TABLE _mv (id bigint, dot_cu int, dot_moi int) ON COMMIT DROP;

CREATE TEMP TABLE _dot_sua (ps text, kh text, nhom text, loai text, dot int, thang_cu text, thang_moi text) ON COMMIT DROP;
INSERT INTO _dot_sua VALUES
  ('Tùng Phạm', 'BV1742', 'Khớp UOC', 'chinh', 1, '2026-10', '2026-11');

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
u AS (UPDATE shared.dot_thau d SET thang_thau = x.thang_moi, updated_at = now(), updated_by = 'dong_bo_nh_mb_20261109e'
      FROM _dot_sua x WHERE d.nam_tai_chinh = 'FY26' AND d.ps = x.ps AND d.ma_khach_hang = x.kh AND d.nhom_san_pham = x.nhom
        AND d.loai = x.loai AND d.dot = x.dot RETURNING d.*)
INSERT INTO shared.quota_chuan_hoa_log (buoc, bang, ban_ghi_id, truoc, sau)
SELECT 'dong_bo_nh_mb_20261109e', 'dot_thau', u.id, to_jsonb(o), to_jsonb(u) FROM u JOIN o ON o.id = u.id;

-- 1. đợt mới
WITH n AS (
  INSERT INTO shared.dot_thau (nam_tai_chinh, bu, mien, ps, ma_khach_hang, nhom_san_pham, loai, dot, thang_thau, thoi_gian,
                               updated_by, trang_thai, nguon)
  SELECT 'FY26', 'chcs', 'Miền Bắc', m.ps, m.kh, m.nhom, m.loai, m.dot, m.thang, m.hl, 'dong_bo_nh_mb_20261109e', 'chinh_thuc', 'dong_bo_nh_mb_20261109e'
  FROM _dot_moi m RETURNING *)
INSERT INTO shared.quota_chuan_hoa_log (buoc, bang, ban_ghi_id, truoc, sau)
SELECT 'dong_bo_nh_mb_20261109e', 'dot_thau', n.id, NULL, to_jsonb(n) FROM n;

-- 2a. sửa SL
WITH o AS (SELECT q.* FROM shared.quota_thau q JOIN _upd u ON u.id = q.id),
u AS (UPDATE shared.quota_thau q SET so_luong = x.sl_moi, updated_at = now(), updated_by = 'dong_bo_nh_mb_20261109e'
      FROM _upd x WHERE q.id = x.id RETURNING q.*)
INSERT INTO shared.quota_chuan_hoa_log (buoc, bang, ban_ghi_id, truoc, sau)
SELECT 'dong_bo_nh_mb_20261109e', 'quota_thau', u.id, to_jsonb(o), to_jsonb(u) FROM u JOIN o ON o.id = u.id;

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
u AS (UPDATE shared.quota_thau q SET dot = m.dot_moi, updated_at = now(), updated_by = 'dong_bo_nh_mb_20261109e'
      FROM _mv m WHERE q.id = m.id RETURNING q.*)
INSERT INTO shared.quota_chuan_hoa_log (buoc, bang, ban_ghi_id, truoc, sau)
SELECT 'dong_bo_nh_mb_20261109e', 'quota_thau', u.id, to_jsonb(o), to_jsonb(u) FROM u JOIN o ON o.id = u.id;

-- 2b. xoá
WITH d AS (DELETE FROM shared.quota_thau q USING _del x WHERE q.id = x.id RETURNING q.*)
INSERT INTO shared.quota_chuan_hoa_log (buoc, bang, ban_ghi_id, truoc, sau)
SELECT 'dong_bo_nh_mb_20261109e', 'quota_thau', d.id, to_jsonb(d), NULL FROM d;

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
SELECT 'dong_bo_nh_mb_20261109e', 'sale_target', s.id, NULL, to_jsonb(s) FROM _st_moi s;

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
SELECT 'dong_bo_nh_mb_20261109e_oop', 'sale_target', o.id, to_jsonb(o) - 'dich', jsonb_build_object('hap_thu_vao', o.dich) FROM _oop o;
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
         'dong_bo_nh_mb_20261109e', 'chinh_thuc', 'dong_bo_nh_mb_20261109e', n.ma
  FROM _ins n CROSS JOIN LATERAL (
    SELECT s.bu, s.mien, s.khach_hang FROM shared.sale_target s
    WHERE s.nam_tai_chinh = 'FY26' AND s.ps = n.ps AND s.ma_khach_hang = n.kh AND s.nhom_san_pham = n.nhom
      AND s.bo_vat_tu = n.bvt AND s.san_pham = n.sp AND s.don_gia = n.gia AND NOT coalesce(s.ngoai_ke_hoach, false)
    ORDER BY s.id LIMIT 1) s
  RETURNING *)
INSERT INTO shared.quota_chuan_hoa_log (buoc, bang, ban_ghi_id, truoc, sau)
SELECT 'dong_bo_nh_mb_20261109e', 'quota_thau', i.id, NULL, to_jsonb(i) FROM i;

SET CONSTRAINTS shared.uq_sale_target_khoa IMMEDIATE;
COMMIT;
