-- Đổi đơn giá kế hoạch FY26 theo giá user chốt 09/11/2026 (lệch giá file NH CH&CS Miền Bắc không phải VAT):
--   * BV đa khoa tỉnh Thanh Hóa (BV0304), Tấn Phạm, NSK Arthrex, "Troca có ren" (MC.AR.CT2.021): 1.500.000 → 1.150.000
--   * BV Việt Nam - Thụy Điển Uông Bí (BV0333), Tùng Phạm, BXMCS, "Xi măng cột sống" (MC.BI.CT1.156): 6.820.000 → 6.500.000
-- Giống sửa giá trên app: chỉ đổi don_gia (doanh thu kế hoạch đã lưu không tính lại). Quota/đợt đi theo khoá mới
-- qua trigger trg_sale_target_giu_khoa_quota. Dòng trùng khoá sau khi đổi được gộp (gop_dong_trung_sale_target).
-- Rollback: supabase/rollbacks/20261109150000_doi_gia_ke_hoach_nh_mb_ROLLBACK.sql
BEGIN;
SET CONSTRAINTS shared.uq_sale_target_khoa DEFERRED;

CREATE TEMP TABLE _gia (kh text, ps text, nhom text, bvt text, sp text, gia_cu numeric, gia_moi numeric) ON COMMIT DROP;
INSERT INTO _gia VALUES
  ('BV0304', 'Tấn Phạm', 'NSK Arthrex', 'Vật tư riêng lẻ - NSK Arthrex', 'Troca có ren', 1500000, 1150000),
  ('BV0333', 'Tùng Phạm', 'BXMCS', 'Vật tư riêng lẻ - CHCS Khác', 'Xi măng cột sống', 6820000, 6500000);

DO $$
DECLARE v_n int;
BEGIN
  SELECT count(*) INTO v_n FROM shared.sale_target s JOIN _gia g
    ON s.nam_tai_chinh = 'FY26' AND s.ma_khach_hang = g.kh AND s.ps = g.ps AND s.nhom_san_pham = g.nhom
   AND s.bo_vat_tu = g.bvt AND s.san_pham = g.sp AND s.don_gia = g.gia_cu AND NOT coalesce(s.ngoai_ke_hoach, false);
  IF v_n <> 24 THEN RAISE EXCEPTION 'doi_gia: mong đợi 24 dòng kế hoạch, thấy %', v_n; END IF;
END $$;

WITH u AS (
  UPDATE shared.sale_target s SET don_gia = g.gia_moi, updated_at = now()
  FROM _gia g
  WHERE s.nam_tai_chinh = 'FY26' AND s.ma_khach_hang = g.kh AND s.ps = g.ps AND s.nhom_san_pham = g.nhom
    AND s.bo_vat_tu = g.bvt AND s.san_pham = g.sp AND s.don_gia = g.gia_cu AND NOT coalesce(s.ngoai_ke_hoach, false)
  RETURNING s.id, g.gia_cu, s.don_gia)
INSERT INTO shared.quota_chuan_hoa_log (buoc, bang, ban_ghi_id, truoc, sau)
SELECT 'doi_gia_ke_hoach_nh_mb_20261109', 'sale_target', u.id, jsonb_build_object('don_gia', u.gia_cu),
       jsonb_build_object('don_gia', u.don_gia) FROM u;

SELECT shared.gop_dong_trung_sale_target(ARRAY(
  SELECT ban_ghi_id FROM shared.quota_chuan_hoa_log WHERE buoc = 'doi_gia_ke_hoach_nh_mb_20261109'));

DO $$
DECLARE v_n int;
BEGIN
  -- quota không được kẹt lại ở giá cũ
  SELECT count(*) INTO v_n FROM shared.quota_thau q JOIN _gia g
    ON q.nam_tai_chinh = 'FY26' AND q.ma_khach_hang = g.kh AND q.ps = g.ps AND q.nhom_san_pham = g.nhom
   AND q.bo_vat_tu = g.bvt AND q.san_pham = g.sp AND q.don_gia = g.gia_cu;
  IF v_n > 0 THEN RAISE EXCEPTION 'doi_gia: % quota còn ở giá cũ', v_n; END IF;
END $$;
SET CONSTRAINTS shared.uq_sale_target_khoa IMMEDIATE;
COMMIT;
