-- Cùng lỗi với BV K (20261109120000): "Vít cổ sau Neon3" (5.100.000 đ) mang nhầm mã CS91 (mã Vít Artus)
-- ở 3 KH CH&CS Miền Bắc: VĐ BV0342 (Mậu Cao), CTCH Nghệ An BV1432 (Tứ Nguyễn), Hà Đông BV0655 (Tuyên Phạm).
-- Đổi về CS 390x theo danh mục (MC.UL.CT1.092) trên kế hoạch + quota. Miền Nam (4 KH) chưa đụng.
-- VĐ và CTCH Nghệ An đã có sẵn dòng "Vít cổ sau Neon3" mã CS 390x cùng giá (tạo 28/09, 03/11) → sau khi đổi mã
-- gộp dòng trùng bằng shared.gop_dong_trung_sale_target (cộng SL kế hoạch / thực hiện vào id nhỏ nhất).
-- Rollback: supabase/rollbacks/20261109125000_mb_sua_ma_neon3_ROLLBACK.sql
BEGIN;
SET CONSTRAINTS shared.uq_sale_target_khoa DEFERRED;

DO $$
DECLARE v_st int; v_q int;
BEGIN
  SELECT count(*) INTO v_st FROM shared.sale_target
  WHERE nam_tai_chinh = 'FY26' AND ma_khach_hang IN ('BV0342', 'BV1432', 'BV0655') AND bu = 'chcs' AND mien = 'Miền Bắc'
    AND san_pham = 'Vít cổ sau Neon3' AND ma_san_pham = 'CS91';
  SELECT count(*) INTO v_q FROM shared.quota_thau
  WHERE nam_tai_chinh = 'FY26' AND ma_khach_hang IN ('BV0342', 'BV1432', 'BV0655') AND bu = 'chcs' AND mien = 'Miền Bắc'
    AND san_pham = 'Vít cổ sau Neon3' AND ma_san_pham = 'CS91';
  IF v_st <> 36 OR v_q <> 1 THEN
    RAISE EXCEPTION 'mb_neon3: mong đợi 36 dòng kế hoạch + 1 quota CS91, thấy % + %', v_st, v_q;
  END IF;
END $$;

WITH o AS (SELECT * FROM shared.sale_target
           WHERE nam_tai_chinh = 'FY26' AND ma_khach_hang IN ('BV0342', 'BV1432', 'BV0655') AND bu = 'chcs' AND mien = 'Miền Bắc'
             AND san_pham = 'Vít cổ sau Neon3' AND ma_san_pham = 'CS91'),
u AS (UPDATE shared.sale_target s SET ma_san_pham = 'CS 390x', updated_at = now()
      FROM o WHERE s.id = o.id RETURNING s.*)
INSERT INTO shared.quota_chuan_hoa_log (buoc, bang, ban_ghi_id, truoc, sau)
SELECT 'mb_sua_ma_neon3_20261109', 'sale_target', u.id, jsonb_build_object('ma_san_pham', 'CS91'),
       jsonb_build_object('ma_san_pham', u.ma_san_pham) FROM u;

INSERT INTO shared.quota_chuan_hoa_log (buoc, bang, truoc, sau)
VALUES ('mb_sua_ma_neon3_20261109_moc', 'sale_target', NULL, jsonb_build_object('at', now()));
SELECT shared.gop_dong_trung_sale_target(ARRAY(
  SELECT s.id FROM shared.sale_target s
  WHERE s.nam_tai_chinh = 'FY26' AND s.ma_khach_hang IN ('BV0342', 'BV1432', 'BV0655') AND s.bu = 'chcs'
    AND s.mien = 'Miền Bắc' AND s.san_pham = 'Vít cổ sau Neon3' AND s.ma_san_pham = 'CS 390x'));

WITH u AS (UPDATE shared.quota_thau q SET ma_san_pham = 'CS 390x', updated_at = now(),
                  updated_by = 'mb_sua_ma_neon3_20261109'
           WHERE nam_tai_chinh = 'FY26' AND ma_khach_hang IN ('BV0342', 'BV1432', 'BV0655') AND bu = 'chcs' AND mien = 'Miền Bắc'
             AND san_pham = 'Vít cổ sau Neon3' AND ma_san_pham = 'CS91'
           RETURNING q.*)
INSERT INTO shared.quota_chuan_hoa_log (buoc, bang, ban_ghi_id, truoc, sau)
SELECT 'mb_sua_ma_neon3_20261109', 'quota_thau', u.id, jsonb_build_object('ma_san_pham', 'CS91'),
       jsonb_build_object('ma_san_pham', u.ma_san_pham) FROM u;

SET CONSTRAINTS shared.uq_sale_target_khoa IMMEDIATE;
COMMIT;
