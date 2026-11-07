-- Index cho nhánh 'sai_bo_vat_tu' của classify_oop_sale_target: mỗi dòng OOP tìm dòng kế
-- hoạch cùng tháng × KH × sản phẩm (bỏ qua PS / bộ vật tư). Không index nào khớp
-- (idx_sale_target_oopkey có PS ở cột 2) nên mỗi dòng OOP quét cả tháng. Đo 07/11 (601 dòng
-- OOP FY26, ép tính ly_do): 108 ms → 19 ms. Index partial đúng điều kiện của truy vấn
-- (ngoai_ke_hoach IS NOT TRUE), ~1,6 MB.
-- CREATE INDEX thường (không CONCURRENTLY, chạy được trong transaction): 35k dòng, khoá ghi
-- sale_target dưới 1 giây.
-- Hoàn tác: supabase/rollbacks/20261107150000_index_classify_sai_bo_vat_tu_ROLLBACK.sql

CREATE INDEX IF NOT EXISTS idx_sale_target_thang_kh_sp_kh
  ON shared.sale_target (
    thang_ke_hoach,
    lower(btrim(coalesce(ma_khach_hang, ''))),
    lower(btrim(coalesce(san_pham, '')))
  )
  WHERE ngoai_ke_hoach IS NOT TRUE;

ANALYZE shared.sale_target;
