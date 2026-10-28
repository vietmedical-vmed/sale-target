-- Làm tròn đơn giá kế hoạch / quota về số nguyên đồng.
--
-- Giá lẻ (thêm SP theo giá hoá đơn = tổng tiền / SL, giá chia 1.05...) làm 1 SP hiện
-- nhiều mức giá chỉ khác phần thập phân. Ca gốc 28/10: "Đầu đốt RF" (NSK Arthrex) có
-- 7333333.2 / 7333333.3 / 7333333.357142857 / 7333333.36. Ngày 28/10 kế hoạch FY26 còn
-- 216 dòng giá lẻ (đều CH&CS, không dòng nào trùng khoá sau khi tròn); dòng ngoài kế
-- hoạch lẻ do lấy giá trung bình hoá đơn.
--
--   1. sale_target.don_gia := round(don_gia), mọi BU, cả dòng ngoài kế hoạch. Hoãn
--      uq_sale_target_khoa rồi gộp phòng khi có dòng về cùng khoá. Quota đi theo khoá
--      mới nhờ trg_sale_target_giu_khoa_quota; quota_thau còn giá lẻ thì tròn nốt.
--   2. Trigger BEFORE INSERT / UPDATE OF don_gia trên sale_target và quota_thau tự làm
--      tròn, để thêm SP, nạp kế hoạch, đồng bộ thực hiện (dòng OOP) không sinh giá lẻ.
-- Doanh thu KH đã lưu (doanh_thu_kh_*) giữ nguyên: lệch < 1đ × SL.
-- Hoàn tác: supabase/rollbacks/20261028110000_lam_tron_don_gia_ROLLBACK.sql

BEGIN;

CREATE TABLE backup.bak_20261028_don_gia_le AS
SELECT id, nam_tai_chinh, bu, ps, ma_khach_hang, nhom_san_pham, bo_vat_tu, san_pham,
       ma_san_pham, thang_ke_hoach, ngoai_ke_hoach, don_gia
FROM shared.sale_target
WHERE don_gia <> round(don_gia);
ALTER TABLE backup.bak_20261028_don_gia_le ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON backup.bak_20261028_don_gia_le FROM PUBLIC, anon, authenticated;

CREATE TABLE backup.bak_20261028_quota_don_gia_le AS
SELECT * FROM shared.quota_thau WHERE don_gia <> round(don_gia);
ALTER TABLE backup.bak_20261028_quota_don_gia_le ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON backup.bak_20261028_quota_don_gia_le FROM PUBLIC, anon, authenticated;

SET CONSTRAINTS shared.uq_sale_target_khoa DEFERRED;

CREATE TEMP TABLE _tron ON COMMIT DROP AS
WITH u AS (
  UPDATE shared.sale_target SET don_gia = round(don_gia), updated_at = now()
  WHERE don_gia <> round(don_gia)
  RETURNING id
)
SELECT id FROM u;

SELECT shared.gop_dong_trung_sale_target((SELECT array_agg(id) FROM _tron));

SET CONSTRAINTS shared.uq_sale_target_khoa IMMEDIATE;

-- Quota giá lẻ trigger chưa chuyển (khoá cũ không có dòng kế hoạch): tròn nếu khoá
-- tròn chưa có quota cùng loại × đợt; còn trùng thì để lại, log để xem tay.
INSERT INTO shared.quota_chuan_hoa_log (buoc, bang, ban_ghi_id, truoc, sau)
SELECT 'lam_tron_gia_xung_dot', 'quota_thau', q.id, to_jsonb(q), NULL
FROM shared.quota_thau q
WHERE q.don_gia <> round(q.don_gia)
  AND EXISTS (SELECT 1 FROM shared.quota_thau d
              WHERE d.nam_tai_chinh = q.nam_tai_chinh AND d.ps = q.ps
                AND d.ma_khach_hang = q.ma_khach_hang AND d.nhom_san_pham = q.nhom_san_pham
                AND d.bo_vat_tu = q.bo_vat_tu AND d.san_pham = q.san_pham
                AND d.don_gia = round(q.don_gia) AND d.loai = q.loai
                AND d.dot IS NOT DISTINCT FROM q.dot);

UPDATE shared.quota_thau q SET don_gia = round(q.don_gia), updated_at = now()
WHERE q.don_gia <> round(q.don_gia)
  AND NOT EXISTS (SELECT 1 FROM shared.quota_thau d
                  WHERE d.nam_tai_chinh = q.nam_tai_chinh AND d.ps = q.ps
                    AND d.ma_khach_hang = q.ma_khach_hang AND d.nhom_san_pham = q.nhom_san_pham
                    AND d.bo_vat_tu = q.bo_vat_tu AND d.san_pham = q.san_pham
                    AND d.don_gia = round(q.don_gia) AND d.loai = q.loai
                    AND d.dot IS NOT DISTINCT FROM q.dot);

CREATE OR REPLACE FUNCTION shared.lam_tron_don_gia()
RETURNS trigger
LANGUAGE plpgsql
SET search_path = shared, public
AS $$
BEGIN
  NEW.don_gia := round(NEW.don_gia);
  RETURN NEW;
END;
$$;
REVOKE ALL ON FUNCTION shared.lam_tron_don_gia() FROM PUBLIC, anon, authenticated;

DROP TRIGGER IF EXISTS trg_sale_target_lam_tron_gia ON shared.sale_target;
CREATE TRIGGER trg_sale_target_lam_tron_gia
BEFORE INSERT OR UPDATE OF don_gia ON shared.sale_target
FOR EACH ROW WHEN (NEW.don_gia <> round(NEW.don_gia))
EXECUTE FUNCTION shared.lam_tron_don_gia();

DROP TRIGGER IF EXISTS trg_quota_thau_lam_tron_gia ON shared.quota_thau;
CREATE TRIGGER trg_quota_thau_lam_tron_gia
BEFORE INSERT OR UPDATE OF don_gia ON shared.quota_thau
FOR EACH ROW WHEN (NEW.don_gia <> round(NEW.don_gia))
EXECUTE FUNCTION shared.lam_tron_don_gia();

COMMIT;
