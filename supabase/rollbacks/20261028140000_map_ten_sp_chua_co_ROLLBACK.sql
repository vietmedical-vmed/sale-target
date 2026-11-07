-- Hoàn tác 20261028140000_map_ten_sp_chua_co.sql
-- Trả các dòng kế hoạch đã đổi tên và quota liên quan về bản chụp. Dòng giữ của nhóm gộp
-- đã cộng SL từ dòng đổi tên (log quota_chuan_hoa_log buoc 'gop_dong_trung' ngày 28/10):
-- trừ lại theo log trước khi chèn bản chụp nếu dòng giữ không nằm trong bản chụp.

BEGIN;

SET CONSTRAINTS shared.uq_sale_target_khoa DEFERRED;

DELETE FROM shared.sale_target WHERE id IN (SELECT id FROM backup.bak_20261028_map_ten_sp_sale_target);
INSERT INTO shared.sale_target SELECT * FROM backup.bak_20261028_map_ten_sp_sale_target;

SET CONSTRAINTS shared.uq_sale_target_khoa IMMEDIATE;

DELETE FROM shared.quota_thau WHERE id IN (SELECT id FROM backup.bak_20261028_map_ten_sp_quota);
INSERT INTO shared.quota_thau SELECT * FROM backup.bak_20261028_map_ten_sp_quota;

COMMIT;
