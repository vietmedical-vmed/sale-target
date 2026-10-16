-- Tăng tốc getData (load ban đầu bị treo khi DB quá tải sau deploy).
--
-- 1) maxDocDate: getData lấy ngay_tai_lieu lớn nhất của hoa_don_bovattu bằng
--    ORDER BY ... DESC LIMIT 1. Không có index nên mỗi lần phải seq scan + sort
--    cả bảng (~0,25s bình thường, tới 2,7s khi DB quá tải). Index btree cho
--    phép đọc thẳng phần tử cuối.
CREATE INDEX IF NOT EXISTS idx_hoa_don_bovattu_ngay_tai_lieu
  ON app_sale.hoa_don_bovattu (ngay_tai_lieu);

-- 2) classify_oop_sale_target trả SETOF; edge function phải phân trang
--    .range() 1000 dòng/lần (giới hạn max-rows của PostgREST), mà mỗi trang
--    lại chạy lại TOÀN BỘ hàm (~6,5k dòng OOP -> 7 lần). Bản _json gói kết quả
--    thành 1 giá trị jsonb nên chỉ cần gọi 1 lần. Giữ nguyên hàm gốc để logic
--    phân loại ở một chỗ và edge cũ vẫn chạy.
CREATE OR REPLACE FUNCTION public.classify_oop_sale_target_json(
  p_bu text DEFAULT NULL,
  p_mien text DEFAULT NULL,
  p_ps text DEFAULT NULL,
  p_groups text[] DEFAULT NULL
)
RETURNS jsonb
LANGUAGE sql
STABLE
SET search_path TO 'public', 'shared', 'app_sale'
AS $$
  SELECT coalesce(
    jsonb_agg(jsonb_build_object(
      'target_id', c.target_id,
      'ly_do', c.ly_do,
      'ps_dia_ban', c.ps_dia_ban
    )),
    '[]'::jsonb
  )
  FROM public.classify_oop_sale_target(p_bu, p_mien, p_ps, p_groups) c;
$$;

REVOKE ALL ON FUNCTION public.classify_oop_sale_target_json(text, text, text, text[])
  FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.classify_oop_sale_target_json(text, text, text, text[])
  TO service_role;

COMMENT ON FUNCTION public.classify_oop_sale_target_json(text, text, text, text[]) IS
  'Như classify_oop_sale_target nhưng trả 1 mảng jsonb, để edge gọi 1 lần thay vì phân trang.';
