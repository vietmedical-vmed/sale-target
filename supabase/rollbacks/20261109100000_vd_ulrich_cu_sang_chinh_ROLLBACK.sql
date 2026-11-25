-- Rollback 20261109100000_vd_ulrich_cu_sang_chinh.sql: trả loai/dot về giá trị trước khi chuyển,
-- chỉ cho dòng vẫn đang mang đúng giá trị sau khi chuyển (không đè sửa tay sau đó).
BEGIN;
WITH l AS (
  SELECT DISTINCT ON (ban_ghi_id) ban_ghi_id, truoc
  FROM shared.quota_chuan_hoa_log
  WHERE buoc = 'vd_ulrich_cu_sang_chinh_20261109' AND bang = 'quota_thau'
  ORDER BY ban_ghi_id, id
), upd AS (
  UPDATE shared.quota_thau q
  SET loai = l.truoc->>'loai', dot = (l.truoc->>'dot')::int, updated_at = now(),
      updated_by = 'vd_ulrich_cu_sang_chinh_20261109_rollback'
  FROM l WHERE q.id = l.ban_ghi_id AND q.loai = 'chinh' AND q.dot = 1
  RETURNING q.*
)
INSERT INTO shared.quota_chuan_hoa_log (buoc, bang, ban_ghi_id, truoc, sau)
SELECT 'vd_ulrich_cu_sang_chinh_20261109_rollback', 'quota_thau', u.id, NULL, to_jsonb(u) FROM upd u;
COMMIT;
