-- Rollback 20261109190000: trả đơn giá NULL cho 12 dòng kế hoạch "Vít Biocomposit ACL" của BV0523
-- (chỉ khi chưa có quota nào ở giá 6.800.000 — quota phải xoá trước bằng rollback đồng bộ).
BEGIN;
UPDATE shared.sale_target s SET don_gia = NULL, updated_at = now()
FROM shared.quota_chuan_hoa_log l
WHERE l.buoc = 'gia_bv0523_vit_biocomposit_20261109' AND s.id = l.ban_ghi_id AND s.don_gia = 6800000
  AND NOT EXISTS (SELECT 1 FROM shared.quota_thau q WHERE q.ma_khach_hang = 'BV0523' AND q.san_pham = 'Vít Biocomposit ACL'
                  AND q.don_gia = 6800000);
COMMIT;
