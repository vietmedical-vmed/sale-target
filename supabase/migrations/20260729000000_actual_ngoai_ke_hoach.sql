-- Thực hiện NGOÀI KẾ HOẠCH
--
-- Các dòng trong sv_bovattu_actual không khớp dòng kế hoạch nào trong sale_target.
-- Dùng cho 2 màn tổng hợp (theo PS / theo sản phẩm) để tổng hiển thị đủ số;
-- màn chi tiết KHÔNG dùng tới.
--
-- Khoá đối chiếu = 5 trường (tháng, PS, mã KH, bộ vật tư, sản phẩm), chuẩn hoá
-- lower(btrim(coalesce(...,''))) để khớp đúng cách pipeline Python làm
-- (strip + casefold, NaN -> '').
--
-- KHÔNG đụng tới v_actual_unmatched: function map_actual_to_sale_target phụ thuộc view đó.

-- bu / nhom_san_pham để 2 màn tổng hợp lọc theo phân quyền (product_manager theo
-- ngành hàng) và gom nhóm được. Pipeline sv_bo_vat_tu_pipeline.py ghi 2 cột này.
ALTER TABLE sv_bovattu_actual
  ADD COLUMN IF NOT EXISTS bu            text,
  ADD COLUMN IF NOT EXISTS nhom_san_pham text;

CREATE OR REPLACE VIEW v_actual_ngoai_ke_hoach AS
SELECT a.thang_ke_hoach,
       a.mien,
       a.ps,
       a.ma_khach_hang,
       a.khach_hang,
       a.bu,
       a.nhom_san_pham,
       a.bo_vat_tu,
       a.san_pham,
       a.sl_thuc_hien
FROM   sv_bovattu_actual a
WHERE  NOT EXISTS (
         SELECT 1
         FROM   sale_target s
         WHERE  s.thang_ke_hoach = a.thang_ke_hoach
           AND  lower(btrim(coalesce(s.ps,            ''))) = lower(btrim(coalesce(a.ps,            '')))
           AND  lower(btrim(coalesce(s.ma_khach_hang, ''))) = lower(btrim(coalesce(a.ma_khach_hang, '')))
           AND  lower(btrim(coalesce(s.bo_vat_tu,     ''))) = lower(btrim(coalesce(a.bo_vat_tu,     '')))
           AND  lower(btrim(coalesce(s.san_pham,      ''))) = lower(btrim(coalesce(a.san_pham,      '')))
       );

-- config.toml để auto_expose_new_tables TẮT -> view mới KHÔNG tự lộ qua Data API,
-- kể cả cho service_role (edge function sale_target-api dùng service_role).
GRANT SELECT ON v_actual_ngoai_ke_hoach TO service_role, anon, authenticated;
