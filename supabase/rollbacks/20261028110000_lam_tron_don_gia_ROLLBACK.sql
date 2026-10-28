-- Hoàn tác 20261028110000_lam_tron_don_gia.sql
-- Bỏ trigger làm tròn, trả đơn giá lẻ về từ bản chụp (theo id; dòng ngoài kế hoạch đã
-- tạo lại khi đồng bộ có id mới, không trả về được).

BEGIN;

DROP TRIGGER IF EXISTS trg_sale_target_lam_tron_gia ON shared.sale_target;
DROP TRIGGER IF EXISTS trg_quota_thau_lam_tron_gia ON shared.quota_thau;
DROP FUNCTION IF EXISTS shared.lam_tron_don_gia();

UPDATE shared.sale_target s SET don_gia = b.don_gia, updated_at = now()
FROM backup.bak_20261028_don_gia_le b
WHERE b.id = s.id AND s.don_gia IS DISTINCT FROM b.don_gia;

UPDATE shared.quota_thau q SET don_gia = b.don_gia, updated_at = now()
FROM backup.bak_20261028_quota_don_gia_le b
WHERE b.id = q.id AND q.don_gia IS DISTINCT FROM b.don_gia;

COMMIT;
