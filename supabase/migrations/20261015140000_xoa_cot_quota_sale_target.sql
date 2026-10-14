-- Chuẩn hoá quota (C): dọn sạch 6 cột quota / tháng / thời gian thầu trên sale_target.
-- Áp SAU 20261015110000 (trigger chặn ghi) và sau khi edge + frontend bản mới đã
-- deploy. Toàn bộ thông tin đã chuyển sang quota_thau / dot_thau (20261014170000,
-- 20261015120000); phần lệch còn lại đã xuất danh sách cho user duyệt tay.
-- Chụp lại giá trị hiện tại trước khi đặt NULL (backup 14/10 chưa có các số mà
-- sync ghi trong lúc duyệt quota chờ duyệt). Cột chỉ drop ở bước sau (P6).

BEGIN;

CREATE TABLE shared.bak_20261015_sale_target_quota AS
SELECT id, nam_tai_chinh, bu, ps, ma_khach_hang, nhom_san_pham, bo_vat_tu, san_pham, don_gia, thang_ke_hoach,
       quota_thau_cu_con_lai, thang_thau_chinh, thoi_gian_thau_chinh, quota_thau_chinh,
       thang_thau_bo_sung, quota_bo_sung
FROM shared.sale_target
WHERE quota_thau_cu_con_lai IS NOT NULL OR quota_thau_chinh IS NOT NULL OR quota_bo_sung IS NOT NULL
   OR thang_thau_chinh IS NOT NULL OR thang_thau_bo_sung IS NOT NULL OR thoi_gian_thau_chinh IS NOT NULL;
ALTER TABLE shared.bak_20261015_sale_target_quota ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON shared.bak_20261015_sale_target_quota FROM PUBLIC, anon, authenticated;

UPDATE shared.sale_target SET
  quota_thau_cu_con_lai = NULL, quota_thau_chinh = NULL, quota_bo_sung = NULL,
  thang_thau_chinh = NULL, thang_thau_bo_sung = NULL, thoi_gian_thau_chinh = NULL
WHERE quota_thau_cu_con_lai IS NOT NULL OR quota_thau_chinh IS NOT NULL OR quota_bo_sung IS NOT NULL
   OR thang_thau_chinh IS NOT NULL OR thang_thau_bo_sung IS NOT NULL OR thoi_gian_thau_chinh IS NOT NULL;

COMMIT;
