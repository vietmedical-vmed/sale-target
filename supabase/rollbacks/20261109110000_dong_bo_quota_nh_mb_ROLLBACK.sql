-- Rollback 20261109110000_dong_bo_quota_nh_mb.sql (buoc 'dong_bo_nh_mb_20261109').
-- Thứ tự: xoá quota đã thêm → trả SL đã sửa (chỉ dòng chưa bị sửa tiếp) → chèn lại quota đã xoá
-- → xoá dòng kế hoạch đã thêm → chèn lại dòng OOP đã hấp thụ → xoá đợt đã thêm.
-- Lưu ý: nếu trigger gan_quota_theo_ma đã gắn quota mồ côi vào dòng kế hoạch mới (log buoc 'gan_theo_ma'),
-- các quota đó không tự trả về khoá cũ.
BEGIN;
SET CONSTRAINTS shared.uq_sale_target_khoa DEFERRED;

DELETE FROM shared.quota_thau q USING shared.quota_chuan_hoa_log l
WHERE l.buoc = 'dong_bo_nh_mb_20261109' AND l.bang = 'quota_thau' AND l.truoc IS NULL AND q.id = l.ban_ghi_id;

UPDATE shared.quota_thau q SET so_luong = (l.truoc->>'so_luong')::numeric, updated_at = now(),
       updated_by = 'dong_bo_nh_mb_20261109_rollback'
FROM shared.quota_chuan_hoa_log l
WHERE l.buoc = 'dong_bo_nh_mb_20261109' AND l.bang = 'quota_thau' AND l.truoc IS NOT NULL AND l.sau IS NOT NULL
  AND q.id = l.ban_ghi_id AND q.so_luong = (l.sau->>'so_luong')::numeric;

INSERT INTO shared.quota_thau
SELECT (jsonb_populate_record(NULL::shared.quota_thau, l.truoc)).*
FROM shared.quota_chuan_hoa_log l
WHERE l.buoc = 'dong_bo_nh_mb_20261109' AND l.bang = 'quota_thau' AND l.truoc IS NOT NULL AND l.sau IS NULL
  AND NOT EXISTS (SELECT 1 FROM shared.quota_thau q WHERE q.id = l.ban_ghi_id);

DELETE FROM shared.sale_target s USING shared.quota_chuan_hoa_log l
WHERE l.buoc = 'dong_bo_nh_mb_20261109' AND l.bang = 'sale_target' AND s.id = l.ban_ghi_id;

-- sale_target có cột sinh (nhom_ref) → liệt kê cột thường
DO $$
DECLARE cols text;
BEGIN
  SELECT string_agg(quote_ident(column_name), ',' ORDER BY ordinal_position) INTO cols
  FROM information_schema.columns
  WHERE table_schema = 'shared' AND table_name = 'sale_target' AND is_generated = 'NEVER';
  EXECUTE format(
    'INSERT INTO shared.sale_target (%1$s) OVERRIDING SYSTEM VALUE
     SELECT %1$s FROM (
       SELECT (jsonb_populate_record(NULL::shared.sale_target, l.truoc)).*
       FROM shared.quota_chuan_hoa_log l
       WHERE l.buoc = %2$L AND l.bang = %3$L
         AND NOT EXISTS (SELECT 1 FROM shared.sale_target s WHERE s.id = l.ban_ghi_id)) r',
    cols, 'dong_bo_nh_mb_20261109_oop', 'sale_target');
END $$;

DELETE FROM shared.dot_thau d USING shared.quota_chuan_hoa_log l
WHERE l.buoc = 'dong_bo_nh_mb_20261109' AND l.bang = 'dot_thau' AND d.id = l.ban_ghi_id;

INSERT INTO shared.quota_chuan_hoa_log (buoc, bang, truoc, sau)
VALUES ('dong_bo_nh_mb_20261109_rollback', 'all', NULL, jsonb_build_object('at', now()));
SET CONSTRAINTS shared.uq_sale_target_khoa IMMEDIATE;
COMMIT;
