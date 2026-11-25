-- Rollback 20261109150000_doi_gia_ke_hoach_nh_mb.sql: trả đơn giá cũ cho dòng kế hoạch (quota đi theo qua trigger giữ khoá).
-- Nếu lúc đổi có gộp dòng trùng (log 'gop_dong_trung'), dòng đã xoá không tự tạo lại.
BEGIN;
SET CONSTRAINTS shared.uq_sale_target_khoa DEFERRED;
UPDATE shared.sale_target s SET don_gia = (l.truoc->>'don_gia')::numeric, updated_at = now()
FROM shared.quota_chuan_hoa_log l
WHERE l.buoc = 'doi_gia_ke_hoach_nh_mb_20261109' AND l.bang = 'sale_target' AND s.id = l.ban_ghi_id
  AND s.don_gia = (l.sau->>'don_gia')::numeric;
SET CONSTRAINTS shared.uq_sale_target_khoa IMMEDIATE;
COMMIT;
