-- get_quota_thau: sắp xếp cố định để phân trang được.
--
-- Bảng đợt + quota đã vượt 1.000 dòng, trong khi PostgREST cắt ở max_rows = 1000.
-- Edge function gọi RPC không phân trang nên chỉ nhận 1.000 dòng đầu: quota vừa
-- ghi nằm cuối bảng, không bao giờ về tới app -> lưu xong mà ô vẫn trống.
--
-- Phân trang bằng .range() chỉ đúng khi thứ tự ổn định giữa các lần gọi, mà
-- UNION ALL không bảo đảm điều đó. Ở đây bọc lại và ORDER BY đủ khoá.

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
  SELECT * FROM (
    SELECT 'dot'::text AS kind, d.nam_tai_chinh, d.ps, d.ma_khach_hang, d.nhom_san_pham,
           NULL::text, NULL::text, NULL::numeric, d.loai, d.dot, d.thang_thau, d.thoi_gian, NULL::numeric
    FROM   shared.dot_thau d
    WHERE  (p_fy     IS NULL OR d.nam_tai_chinh = p_fy)
      AND  (p_bu     IS NULL OR d.bu            =     p_bu)
      AND  (p_mien   IS NULL OR d.mien          =     p_mien)
      AND  (p_ps     IS NULL OR d.ps            =     p_ps)
      AND  (p_groups IS NULL OR d.nhom_san_pham = ANY(p_groups))
      AND  (p_bu IS NOT NULL OR d.bu IS NULL OR d.bu <> 'test')
    UNION ALL
    SELECT 'quota'::text, q.nam_tai_chinh, q.ps, q.ma_khach_hang, q.nhom_san_pham,
           q.bo_vat_tu, q.san_pham, q.don_gia, q.loai, q.dot, NULL::text, NULL::numeric, q.so_luong
    FROM   shared.quota_thau q
    WHERE  (p_fy     IS NULL OR q.nam_tai_chinh = p_fy)
      AND  (p_bu     IS NULL OR q.bu            =     p_bu)
      AND  (p_mien   IS NULL OR q.mien          =     p_mien)
      AND  (p_ps     IS NULL OR q.ps            =     p_ps)
      AND  (p_groups IS NULL OR q.nhom_san_pham = ANY(p_groups))
      AND  (p_bu IS NOT NULL OR q.bu IS NULL OR q.bu <> 'test')
  ) t
  ORDER BY 1, 2, 3, 4, 5, 6, 7, 8, 9, 10;
$$;

REVOKE ALL ON FUNCTION public.get_quota_thau(text, text, text, text, text[]) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.get_quota_thau(text, text, text, text, text[]) TO service_role;
