-- P0 chuẩn hoá quota: chụp lại toàn bộ dữ liệu quota trước khi gắn lại khoá
-- và chuyển cột cũ sang shared.quota_thau / shared.dot_thau.
-- Bảng backup chỉ để khôi phục: bật RLS, không cấp cho anon/authenticated.

CREATE TABLE shared.bak_20261014_quota_thau AS TABLE shared.quota_thau;
CREATE TABLE shared.bak_20261014_dot_thau   AS TABLE shared.dot_thau;

CREATE TABLE shared.bak_20261014_sale_target_quota AS
SELECT id, nam_tai_chinh, bu, mien, ps, ma_khach_hang, khach_hang, nhom_san_pham,
       bo_vat_tu, san_pham, ma_san_pham, ma_bo_vat_tu, don_gia, thang_ke_hoach,
       ngoai_ke_hoach,
       quota_thau_cu_con_lai, thang_thau_chinh, thoi_gian_thau_chinh, quota_thau_chinh,
       thang_thau_bo_sung, quota_bo_sung
FROM shared.sale_target;

ALTER TABLE shared.bak_20261014_quota_thau        ENABLE ROW LEVEL SECURITY;
ALTER TABLE shared.bak_20261014_dot_thau          ENABLE ROW LEVEL SECURITY;
ALTER TABLE shared.bak_20261014_sale_target_quota ENABLE ROW LEVEL SECURITY;

REVOKE ALL ON shared.bak_20261014_quota_thau,
              shared.bak_20261014_dot_thau,
              shared.bak_20261014_sale_target_quota
  FROM PUBLIC, anon, authenticated;
