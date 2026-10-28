-- Hoàn tác 20261028100000_thnk_san_pham_theo_danh_muc_moi.sql
-- Trả kế hoạch FY26 THNK, quota / đợt THNK và tên SP hoá đơn về bản chụp ngày 28/10.
-- Sửa tay trên kế hoạch / quota THNK sau migration sẽ mất.
-- Hoá đơn nạp lại sau migration có id mới, không nằm trong bản chụp: giữ tên danh mục.
-- Sau khi chạy phải "Cập nhật thực hiện" (start_sync_job).

BEGIN;

DROP TRIGGER IF EXISTS trg_hoa_don_san_pham_theo_danh_muc ON app_sale.hoa_don_bovattu;
DROP FUNCTION IF EXISTS app_sale.san_pham_theo_danh_muc();
DROP INDEX IF EXISTS shared.idx_dm_vat_tu_ma_bravo;

UPDATE app_sale.hoa_don_bovattu h SET san_pham = b.san_pham
FROM backup.bak_20261028_hoa_don_san_pham b
WHERE b.id = h.id AND h.san_pham IS DISTINCT FROM b.san_pham;

DELETE FROM shared.sale_target WHERE nam_tai_chinh = 'FY26' AND bu = 'thnk';
INSERT INTO shared.sale_target SELECT * FROM backup.bak_20261028_thnk_sale_target;

DELETE FROM shared.quota_thau
WHERE nhom_san_pham IN (SELECT nhom_san_pham FROM shared.dm_nhom_san_pham WHERE bu_code = 'thnk');
INSERT INTO shared.quota_thau SELECT * FROM backup.bak_20261028_thnk_quota_thau;

DELETE FROM shared.dot_thau
WHERE nhom_san_pham IN (SELECT nhom_san_pham FROM shared.dm_nhom_san_pham WHERE bu_code = 'thnk');
INSERT INTO shared.dot_thau SELECT * FROM backup.bak_20261028_thnk_dot_thau;

COMMIT;
