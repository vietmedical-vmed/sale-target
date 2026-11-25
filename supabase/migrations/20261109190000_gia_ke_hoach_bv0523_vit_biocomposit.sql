-- BV ĐK Trung ương Huế - cơ sở 2 (BV0523), Tùng Phạm, NSK Arthrex, "Vít Biocomposit ACL" (AR-5035TC-xx,
-- MC.AR.CT2.018): 12 dòng kế hoạch FY26 chưa có đơn giá → 6.800.000 (user chốt 09/11/2026), để nạp quota theo file NH.
-- Rollback: supabase/rollbacks/20261109190000_gia_ke_hoach_bv0523_vit_biocomposit_ROLLBACK.sql
BEGIN;
DO $$
DECLARE v_n int;
BEGIN
  SELECT count(*) INTO v_n FROM shared.sale_target
  WHERE nam_tai_chinh = 'FY26' AND ma_khach_hang = 'BV0523' AND ps = 'Tùng Phạm' AND san_pham = 'Vít Biocomposit ACL'
    AND don_gia IS NULL AND NOT coalesce(ngoai_ke_hoach, false);
  IF v_n <> 12 THEN RAISE EXCEPTION 'gia_bv0523: mong đợi 12 dòng chưa có giá, thấy %', v_n; END IF;
END $$;
WITH u AS (
  UPDATE shared.sale_target SET don_gia = 6800000, updated_at = now()
  WHERE nam_tai_chinh = 'FY26' AND ma_khach_hang = 'BV0523' AND ps = 'Tùng Phạm' AND san_pham = 'Vít Biocomposit ACL'
    AND don_gia IS NULL AND NOT coalesce(ngoai_ke_hoach, false)
  RETURNING id)
INSERT INTO shared.quota_chuan_hoa_log (buoc, bang, ban_ghi_id, truoc, sau)
SELECT 'gia_bv0523_vit_biocomposit_20261109', 'sale_target', id, jsonb_build_object('don_gia', NULL),
       jsonb_build_object('don_gia', 6800000) FROM u;
COMMIT;
