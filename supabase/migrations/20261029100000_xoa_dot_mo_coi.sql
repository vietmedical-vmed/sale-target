-- Xoá đợt thầu mồ côi: không có quota_thau nào cùng khoá đợt và không còn dòng
-- sale_target nào cùng năm × PS × KH × nhóm SP.
--
-- Các đợt này nạp từ cột cũ sale_target ngày 14/09 (20260914100000). Bước dọn quota
-- mồ côi 15/10 (20261016160000) đã xoá quota của chúng nhưng để lại đợt, nên đợt
-- vẫn hiện ở tab "Đợt thiếu tháng thầu" dù không còn kế hoạch (vd Đinh Kiên ·
-- BV0350). Đo ngày 29/10: 134 đợt.
--
-- Theo yêu cầu user: xoá hẳn, không backup bảng riêng. Dòng xoá vẫn ghi vào
-- shared.quota_chuan_hoa_log (cột truoc) như mọi thay đổi quota khác.

BEGIN;

WITH xoa AS (
  DELETE FROM shared.dot_thau d
  WHERE NOT EXISTS (
          SELECT 1 FROM shared.quota_thau q
          WHERE q.nam_tai_chinh = d.nam_tai_chinh AND q.ps = d.ps
            AND q.ma_khach_hang = d.ma_khach_hang AND q.nhom_san_pham = d.nhom_san_pham
            AND q.loai = d.loai AND q.dot = d.dot)
    AND NOT EXISTS (
          SELECT 1 FROM shared.sale_target s
          WHERE s.nam_tai_chinh = d.nam_tai_chinh AND s.ps = d.ps
            AND s.ma_khach_hang = d.ma_khach_hang AND s.nhom_san_pham = d.nhom_san_pham)
  RETURNING d.*
)
INSERT INTO shared.quota_chuan_hoa_log (buoc, bang, ban_ghi_id, truoc)
SELECT 'xoa_dot_mo_coi', 'dot_thau', id, to_jsonb(xoa) FROM xoa;

COMMIT;
