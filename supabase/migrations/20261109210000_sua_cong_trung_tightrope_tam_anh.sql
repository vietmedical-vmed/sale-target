-- Sửa lỗi vòng 6 (20261109200000): quota "Vít treo TightRope (bộ cố định vỏ xương chày)" của Tâm Anh (BV0458,
-- Tùng Phạm, thầu chính đợt 1) bị cộng dồn lần 2 từ CÙNG dòng file NH (dòng 608, đã nạp 40 ở vòng 3) → 80.
-- Trả về 40. Rollback: supabase/rollbacks/20261109210000_sua_cong_trung_tightrope_tam_anh_ROLLBACK.sql
BEGIN;
DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM shared.quota_thau WHERE id = 7180 AND ma_khach_hang = 'BV0458' AND so_luong = 80) THEN
    RAISE EXCEPTION 'tightrope: quota 7180 không còn ở SL 80';
  END IF;
END $$;
WITH o AS (SELECT * FROM shared.quota_thau WHERE id = 7180),
u AS (UPDATE shared.quota_thau SET so_luong = 40, updated_at = now(), updated_by = 'sua_cong_trung_tightrope_20261109'
      WHERE id = 7180 RETURNING *)
INSERT INTO shared.quota_chuan_hoa_log (buoc, bang, ban_ghi_id, truoc, sau)
SELECT 'sua_cong_trung_tightrope_20261109', 'quota_thau', u.id, to_jsonb(o), to_jsonb(u) FROM u, o;
COMMIT;
