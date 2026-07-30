-- Đổi tên bảng catalog -> dm_bo_vat_tu
--
-- LÝ DO
-- Đặt tên theo đúng quy ước danh mục đang dùng (dm_khach_hang) và nói rõ nội dung
-- bảng: danh mục bộ vật tư / sản phẩm chuẩn (nhom_san_pham, bo_vat_tu, san_pham,
-- don_gia). "catalog" quá chung, dễ lẫn với pg_catalog trong các câu SQL.
--
-- ĐI THEO TỰ ĐỘNG khi RENAME (không cần khai lại):
--   - RLS đã bật + mọi policy gắn với bảng
--   - GRANT cho anon / authenticated / service_role
--   - quyền sở hữu sequence identity của cột id
--
-- KHÔNG tự đổi tên (Postgres giữ tên cũ) → đổi tay ở dưới cho sạch:
--   catalog_pkey, catalog_bo_vat_tu_san_pham_key, catalog_id_seq
--
-- PHỐI HỢP DEPLOY — QUAN TRỌNG
-- Edge function sale_target-api (action getCatalog) đọc thẳng tên bảng này và
-- phải deploy TAY, không đi theo Pages. Nếu chạy migration mà chưa deploy bản
-- mới: getCatalog lỗi → app nuốt lỗi, catalog = [] → nút "Thêm SP" và panel
-- "Thêm khách hàng" IM LẶNG biến mất, không có thông báo lỗi nào.
-- => Chạy migration và deploy edge function liền nhau.
--
-- Ngoài repo: bất kỳ script/quy trình import Excel nào đang ghi vào bảng
-- catalog cũng phải đổi theo (danh mục được quản trị ngoài UI).

-- Bọc trong DO để chạy lại lần 2 không lỗi (bảng đã đổi tên rồi thì bỏ qua).
DO $$
BEGIN
  IF EXISTS (
    SELECT 1 FROM pg_class c
    JOIN pg_namespace n ON n.oid = c.relnamespace
    WHERE n.nspname = 'public' AND c.relname = 'catalog' AND c.relkind = 'r'
  ) AND NOT EXISTS (
    SELECT 1 FROM pg_class c
    JOIN pg_namespace n ON n.oid = c.relnamespace
    WHERE n.nspname = 'public' AND c.relname = 'dm_bo_vat_tu'
  ) THEN
    ALTER TABLE public.catalog RENAME TO dm_bo_vat_tu;
  END IF;
END $$;

-- Đổi tên constraint / index / sequence còn mang tiền tố cũ.
-- Đổi tên constraint kéo theo index cùng tên, không cần ALTER INDEX riêng.
DO $$
BEGIN
  IF EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'catalog_pkey'
             AND conrelid = 'public.dm_bo_vat_tu'::regclass) THEN
    ALTER TABLE public.dm_bo_vat_tu RENAME CONSTRAINT catalog_pkey TO dm_bo_vat_tu_pkey;
  END IF;

  IF EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'catalog_bo_vat_tu_san_pham_key'
             AND conrelid = 'public.dm_bo_vat_tu'::regclass) THEN
    ALTER TABLE public.dm_bo_vat_tu
      RENAME CONSTRAINT catalog_bo_vat_tu_san_pham_key TO dm_bo_vat_tu_bo_vat_tu_san_pham_key;
  END IF;

  IF EXISTS (
    SELECT 1 FROM pg_class c
    JOIN pg_namespace n ON n.oid = c.relnamespace
    WHERE n.nspname = 'public' AND c.relname = 'catalog_id_seq' AND c.relkind = 'S'
  ) THEN
    ALTER SEQUENCE public.catalog_id_seq RENAME TO dm_bo_vat_tu_id_seq;
  END IF;
END $$;

COMMENT ON TABLE public.dm_bo_vat_tu IS
  'Danh mục bộ vật tư / sản phẩm chuẩn (trước 30/07/2026 tên là "catalog"). Nguồn cho dropdown Nhóm SP -> Bộ vật tư -> Sản phẩm ở form thêm sản phẩm, unique theo (bo_vat_tu, san_pham).';
