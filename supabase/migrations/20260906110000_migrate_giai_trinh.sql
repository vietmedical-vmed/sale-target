-- Chuyển giải trình cũ từ sale_target.giai_trinh sang bảng shared.giai_trinh (append-only log).
-- Gom theo (ps, ma_khach_hang, nhom_san_pham), lấy giá trị giai_trinh không rỗng.
-- Mỗi nhóm SP chỉ tạo 1 entry (lấy nội dung dài nhất nếu trùng).

INSERT INTO shared.giai_trinh (ps, customer_id, grp, content, created_by, created_at)
SELECT
  st.ps,
  st.ma_khach_hang,
  st.nhom_san_pham,
  -- Nếu nhiều dòng cùng nhóm có giai_trinh khác nhau, lấy dòng dài nhất
  (ARRAY_AGG(st.giai_trinh ORDER BY LENGTH(st.giai_trinh) DESC))[1],
  st.ps,  -- created_by = PS name (không biết ai nhập ban đầu)
  COALESCE(MAX(st.updated_at), NOW())
FROM shared.sale_target st
WHERE st.giai_trinh IS NOT NULL
  AND TRIM(st.giai_trinh) <> ''
GROUP BY st.ps, st.ma_khach_hang, st.nhom_san_pham;
