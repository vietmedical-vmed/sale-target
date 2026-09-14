-- get_quota_thau: loại dữ liệu team demo giống applyScope() bên edge function.
--
-- Quy tắc đang áp cho sale_target: khi không khoá theo 1 team cụ thể (p_bu NULL,
-- tức admin/manager xem "tất cả team", hoặc product_manager nhìn xuyên team) thì
-- KHÔNG trộn dữ liệu của team demo vào. Khoá đúng team demo (p_bu = 'test') thì
-- vẫn xem được bình thường.
--
-- Dòng bu NULL nghĩa là chưa gắn team, không phải dữ liệu demo -> vẫn giữ.

CREATE OR REPLACE FUNCTION public.get_quota_thau(
  p_fy     text,
  p_bu     text,
  p_mien   text,
  p_ps     text,
  p_groups text[]
)
RETURNS TABLE (
  kind      text,
  fy        text,
  ps        text,
  cust_id   text,
  grp       text,
  mset      text,
  prod      text,
  price     numeric,
  loai      text,
  dot       int,
  thang     text,
  thoi_gian numeric,
  qty       numeric
)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public, shared
AS $$
  SELECT 'dot', d.nam_tai_chinh, d.ps, d.ma_khach_hang, d.nhom_san_pham,
         NULL, NULL, NULL, d.loai, d.dot, d.thang_thau, d.thoi_gian, NULL
  FROM   shared.dot_thau d
  WHERE  (p_fy     IS NULL OR d.nam_tai_chinh = p_fy)
    AND  (p_bu     IS NULL OR d.bu            =     p_bu)
    AND  (p_mien   IS NULL OR d.mien          =     p_mien)
    AND  (p_ps     IS NULL OR d.ps            =     p_ps)
    AND  (p_groups IS NULL OR d.nhom_san_pham = ANY(p_groups))
    AND  (p_bu IS NOT NULL OR d.bu IS NULL OR d.bu <> 'test')
  UNION ALL
  SELECT 'quota', q.nam_tai_chinh, q.ps, q.ma_khach_hang, q.nhom_san_pham,
         q.bo_vat_tu, q.san_pham, q.don_gia, q.loai, q.dot, NULL, NULL, q.so_luong
  FROM   shared.quota_thau q
  WHERE  (p_fy     IS NULL OR q.nam_tai_chinh = p_fy)
    AND  (p_bu     IS NULL OR q.bu            =     p_bu)
    AND  (p_mien   IS NULL OR q.mien          =     p_mien)
    AND  (p_ps     IS NULL OR q.ps            =     p_ps)
    AND  (p_groups IS NULL OR q.nhom_san_pham = ANY(p_groups))
    AND  (p_bu IS NOT NULL OR q.bu IS NULL OR q.bu <> 'test');
$$;

REVOKE ALL ON FUNCTION public.get_quota_thau(text, text, text, text, text[]) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.get_quota_thau(text, text, text, text, text[]) TO service_role;
