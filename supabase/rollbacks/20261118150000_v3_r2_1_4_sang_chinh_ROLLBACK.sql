-- Rollback 20261118150000_v3_r2_1_4_sang_chinh: dựng lại mọi dòng quota_thau bị chạm về trạng
-- thái TRƯỚC lần chạm đầu tiên (log theo thứ tự id), xoá dòng tạo mới, xoá đợt mới.
-- Sau đó chạy lại app_sale.chay_gan_quota_hop_dong('rollback_v3_r2').
BEGIN;

CREATE TEMP TABLE _goc ON COMMIT DROP AS
SELECT DISTINCT ON (ban_ghi_id) ban_ghi_id, truoc
FROM app_sale.quota_chuan_hoa_log
WHERE buoc = 'v3_r2_1_4_sang_chinh_20261118' AND bang = 'quota_thau'
ORDER BY ban_ghi_id, id;

-- dòng tạo mới trong migration (lần chạm đầu không có truoc)
DELETE FROM shared.quota_thau q USING _goc g WHERE g.ban_ghi_id = q.id AND g.truoc IS NULL;

-- dòng có sẵn: xoá bản hiện tại (nếu còn) rồi chèn lại nguyên trạng cũ (giữ id)
DELETE FROM shared.quota_thau q USING _goc g WHERE g.ban_ghi_id = q.id AND g.truoc IS NOT NULL;
INSERT INTO shared.quota_thau
SELECT (jsonb_populate_record(NULL::shared.quota_thau, g.truoc)).*
FROM _goc g WHERE g.truoc IS NOT NULL;
-- trg_quota_thau_ma_sp tự điền ma_san_pham khi INSERT; trả lại giá trị cũ (UPDATE chỉ cột này
-- không kích trigger).
UPDATE shared.quota_thau q SET ma_san_pham = g.truoc->>'ma_san_pham'
FROM _goc g WHERE g.ban_ghi_id = q.id AND g.truoc IS NOT NULL
  AND q.ma_san_pham IS DISTINCT FROM g.truoc->>'ma_san_pham';

DELETE FROM shared.dot_thau d
WHERE d.nguon = 'v3_r2_1_4_sang_chinh_20261118'
  AND NOT EXISTS (SELECT 1 FROM shared.quota_thau q
                  WHERE q.nam_tai_chinh = d.nam_tai_chinh AND q.ps = d.ps AND q.ma_khach_hang = d.ma_khach_hang
                    AND q.nhom_san_pham = d.nhom_san_pham AND q.loai = d.loai AND q.dot = d.dot);

DELETE FROM app_sale.quota_chuan_hoa_log WHERE buoc = 'v3_r2_1_4_sang_chinh_20261118';

COMMIT;
