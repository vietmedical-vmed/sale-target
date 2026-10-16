-- Rollback 20261017110000_tang_toc_get_data.sql
-- Edge function tự rơi về classify_oop_sale_target phân trang khi thiếu hàm _json.
DROP FUNCTION IF EXISTS public.classify_oop_sale_target_json(text, text, text, text[]);
DROP INDEX IF EXISTS app_sale.idx_hoa_don_bovattu_ngay_tai_lieu;
