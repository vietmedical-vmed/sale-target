-- Xóa cột giai_trinh cũ khỏi sale_target.
-- Dữ liệu đã migrate sang bảng shared.giai_trinh (append-only log).

ALTER TABLE shared.sale_target DROP COLUMN IF EXISTS giai_trinh;
