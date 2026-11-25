-- Bệnh viện K (BV0295), PS Mậu Cao, Cột sống Ulrich: dòng kế hoạch + quota "Vít cổ sau Neon3"
-- (5.100.000 đ, quota thầu cũ 110) đang mang nhầm mã CS91 (mã của Vít Artus). Đổi về mã đúng CS 390x
-- theo danh mục (dm_vat_tu MC.UL.CT1.092). Tên, giá, SL giữ nguyên. User chốt 09/11/2026.
-- Rollback: supabase/rollbacks/20261109120000_bvk_sua_ma_neon3_ROLLBACK.sql
BEGIN;
SET CONSTRAINTS shared.uq_sale_target_khoa DEFERRED;

DO $$
DECLARE v_st int; v_q int;
BEGIN
  SELECT count(*) INTO v_st FROM shared.sale_target
  WHERE nam_tai_chinh = 'FY26' AND ma_khach_hang = 'BV0295' AND ps = 'Mậu Cao'
    AND san_pham = 'Vít cổ sau Neon3' AND ma_san_pham = 'CS91';
  SELECT count(*) INTO v_q FROM shared.quota_thau
  WHERE nam_tai_chinh = 'FY26' AND ma_khach_hang = 'BV0295' AND ps = 'Mậu Cao'
    AND san_pham = 'Vít cổ sau Neon3' AND ma_san_pham = 'CS91';
  IF v_st <> 12 OR v_q <> 1 THEN
    RAISE EXCEPTION 'bvk_neon3: mong đợi 12 dòng kế hoạch + 1 quota, thấy % + %', v_st, v_q;
  END IF;
END $$;

WITH o AS (SELECT * FROM shared.sale_target
           WHERE nam_tai_chinh = 'FY26' AND ma_khach_hang = 'BV0295' AND ps = 'Mậu Cao'
             AND san_pham = 'Vít cổ sau Neon3' AND ma_san_pham = 'CS91'),
u AS (UPDATE shared.sale_target s SET ma_san_pham = 'CS 390x', updated_at = now()
      FROM o WHERE s.id = o.id RETURNING s.*)
INSERT INTO shared.quota_chuan_hoa_log (buoc, bang, ban_ghi_id, truoc, sau)
SELECT 'bvk_sua_ma_neon3_20261109', 'sale_target', u.id, jsonb_build_object('ma_san_pham', 'CS91'),
       jsonb_build_object('ma_san_pham', u.ma_san_pham) FROM u;

WITH u AS (UPDATE shared.quota_thau q SET ma_san_pham = 'CS 390x', updated_at = now(),
                  updated_by = 'bvk_sua_ma_neon3_20261109'
           WHERE nam_tai_chinh = 'FY26' AND ma_khach_hang = 'BV0295' AND ps = 'Mậu Cao'
             AND san_pham = 'Vít cổ sau Neon3' AND ma_san_pham IN ('CS91', 'CS 390x')
           RETURNING q.*)
INSERT INTO shared.quota_chuan_hoa_log (buoc, bang, ban_ghi_id, truoc, sau)
SELECT 'bvk_sua_ma_neon3_20261109', 'quota_thau', u.id, jsonb_build_object('ma_san_pham', 'CS91'),
       jsonb_build_object('ma_san_pham', u.ma_san_pham) FROM u;

SET CONSTRAINTS shared.uq_sale_target_khoa IMMEDIATE;
COMMIT;
