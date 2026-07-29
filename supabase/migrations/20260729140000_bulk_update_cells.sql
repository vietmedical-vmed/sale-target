-- Lưu điều chỉnh hàng loạt trong MỘT câu lệnh
--
-- VẤN ĐỀ
-- action "updateCells" của sale_target-api chạy vòng lặp tuần tự:
--     for (const u of updates) await db.from("sale_target").update(...).eq("id", ...)
-- 600 ô sửa = 600 lượt gọi PostgREST nối tiếp, mỗi lượt ~50ms → 30-40s.
--
-- CÁCH SỬA
-- Gom các ô theo id ở edge function rồi gọi RPC này đúng 1 lần. Toàn bộ update
-- chạy trong 1 câu UPDATE ... FROM jsonb_array_elements → 1 lượt mạng, 1 giao
-- dịch (hoặc lưu hết, hoặc không lưu gì — không còn cảnh lưu dở nửa chừng).
--
-- Tham số p_updates: [{ "id": 123, "patch": { "<cột db>": <giá trị|null> } }, ...]
-- Chỉ cột nào CÓ MẶT trong patch mới bị ghi đè; patch có key với giá trị null
-- nghĩa là xoá trắng ô đó (giữ đúng hành vi cũ: value === "" -> null).
--
-- Danh sách cột = EDITABLE + ADMIN_EDITABLE trong sale_target-api/index.ts.
-- Việc kiểm tra quyền (role nào được sửa cột nào) vẫn nằm ở edge function;
-- function này chỉ được gọi bằng service_role.

CREATE OR REPLACE FUNCTION public.update_sale_target_cells(p_updates jsonb)
RETURNS integer
LANGUAGE sql
SECURITY DEFINER
SET search_path = public
AS $$
  WITH u AS (
    SELECT (e->>'id')::bigint AS id,
           e->'patch'         AS patch
    FROM   jsonb_array_elements(coalesce(p_updates, '[]'::jsonb)) e
    WHERE  jsonb_typeof(e->'patch') = 'object'
  ), upd AS (
    UPDATE sale_target s SET
      quota_thau_cu_con_lai = CASE WHEN u.patch ? 'quota_thau_cu_con_lai'
             THEN nullif(u.patch->>'quota_thau_cu_con_lai', '')::numeric
             ELSE s.quota_thau_cu_con_lai END,
      thang_thau_chinh      = CASE WHEN u.patch ? 'thang_thau_chinh'
             THEN u.patch->>'thang_thau_chinh'
             ELSE s.thang_thau_chinh END,
      thoi_gian_thau_chinh  = CASE WHEN u.patch ? 'thoi_gian_thau_chinh'
             THEN nullif(u.patch->>'thoi_gian_thau_chinh', '')::numeric
             ELSE s.thoi_gian_thau_chinh END,
      quota_thau_chinh      = CASE WHEN u.patch ? 'quota_thau_chinh'
             THEN nullif(u.patch->>'quota_thau_chinh', '')::numeric
             ELSE s.quota_thau_chinh END,
      thang_thau_bo_sung    = CASE WHEN u.patch ? 'thang_thau_bo_sung'
             THEN u.patch->>'thang_thau_bo_sung'
             ELSE s.thang_thau_bo_sung END,
      quota_bo_sung         = CASE WHEN u.patch ? 'quota_bo_sung'
             THEN nullif(u.patch->>'quota_bo_sung', '')::numeric
             ELSE s.quota_bo_sung END,
      sl_ke_hoach_update    = CASE WHEN u.patch ? 'sl_ke_hoach_update'
             THEN nullif(u.patch->>'sl_ke_hoach_update', '')::numeric
             ELSE s.sl_ke_hoach_update END,
      don_gia               = CASE WHEN u.patch ? 'don_gia'
             THEN nullif(u.patch->>'don_gia', '')::numeric
             ELSE s.don_gia END,
      giai_trinh            = CASE WHEN u.patch ? 'giai_trinh'
             THEN u.patch->>'giai_trinh'
             ELSE s.giai_trinh END,
      bo_vat_tu             = CASE WHEN u.patch ? 'bo_vat_tu'
             THEN u.patch->>'bo_vat_tu'
             ELSE s.bo_vat_tu END,
      san_pham              = CASE WHEN u.patch ? 'san_pham'
             THEN u.patch->>'san_pham'
             ELSE s.san_pham END
    FROM   u
    WHERE  s.id = u.id
    RETURNING s.id
  )
  SELECT count(*)::integer FROM upd;
$$;

-- Postgres mặc định cấp EXECUTE cho PUBLIC → phải thu hồi, chỉ service_role
-- (edge function) được gọi. anon/authenticated tuyệt đối không.
REVOKE ALL ON FUNCTION public.update_sale_target_cells(jsonb) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.update_sale_target_cells(jsonb) FROM anon, authenticated;
GRANT EXECUTE ON FUNCTION public.update_sale_target_cells(jsonb) TO service_role;

COMMENT ON FUNCTION public.update_sale_target_cells(jsonb) IS
  'Ghi hàng loạt ô đã sửa trong 1 câu UPDATE. Chỉ ghi cột có mặt trong patch. Quyền theo cột do sale_target-api kiểm tra trước khi gọi.';
