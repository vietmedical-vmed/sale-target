-- Rollback 20261118120000_v4_upcoming_da_ky_hd: trả 5 dòng quota về loại / đợt / SL cũ theo log,
-- xoá 4 đợt mới. Sau đó chạy lại app_sale.chay_gan_quota_hop_dong('rollback_v4').
BEGIN;

UPDATE shared.quota_thau q
SET loai = l.truoc->>'loai',
    dot = (l.truoc->>'dot')::int,
    so_luong = (l.truoc->>'so_luong')::numeric,
    updated_at = (l.truoc->>'updated_at')::timestamptz,
    updated_by = l.truoc->>'updated_by'
FROM app_sale.quota_chuan_hoa_log l
WHERE l.buoc = 'v4_upcoming_da_ky_hd_20261118' AND l.bang = 'quota_thau' AND l.ban_ghi_id = q.id;

DELETE FROM shared.dot_thau d
WHERE d.nguon = 'v4_upcoming_da_ky_hd_20261118'
  AND NOT EXISTS (SELECT 1 FROM shared.quota_thau q
                  WHERE q.nam_tai_chinh = d.nam_tai_chinh AND q.ps = d.ps AND q.ma_khach_hang = d.ma_khach_hang
                    AND q.nhom_san_pham = d.nhom_san_pham AND q.loai = d.loai AND q.dot = d.dot);

DELETE FROM app_sale.quota_chuan_hoa_log WHERE buoc = 'v4_upcoming_da_ky_hd_20261118';

COMMIT;
