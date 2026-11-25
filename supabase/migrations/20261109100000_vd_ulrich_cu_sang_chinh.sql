-- Bệnh viện Hữu Nghị Việt Đức (BV0342) × Cột sống Ulrich × PS Mậu Cao, FY26:
-- chuyển toàn bộ quota thầu cũ (loai 'cu') sang thầu chính 2026, đợt 1.
-- Lý do: file ngành hàng CH&CS Miền Bắc (bản 09/11/2026) ghi các dòng này là
-- "Quota thầu chính 2026" (hợp đồng HD2600065151 / HD2600091594 / HD2600091771 /
-- HD2600098581, ký 04–05/2026, hết hạn 04–05/2028); user chốt 09/11 chuyển trên hệ thống.
-- Đợt đích đã có sẵn: dot_thau chinh đợt 1, tháng thầu 2026-05, hiệu lực 24 tháng
-- (hết hạn theo app 2028-07) → quota vẫn on hand, tổng không đổi, chỉ đổi loại.
-- Chỉ đổi loai + dot; SL, giá, PS giữ nguyên. Log ở shared.quota_chuan_hoa_log
-- (buoc 'vd_ulrich_cu_sang_chinh_20261109'). Rollback:
-- supabase/rollbacks/20261109100000_vd_ulrich_cu_sang_chinh_ROLLBACK.sql
BEGIN;

CREATE TEMP TABLE _doi ON COMMIT DROP AS
SELECT q.* FROM shared.quota_thau q
WHERE q.nam_tai_chinh = 'FY26' AND q.ma_khach_hang = 'BV0342' AND q.ps = 'Mậu Cao'
  AND q.nhom_san_pham = 'Cột sống Ulrich' AND q.loai = 'cu';

DO $$
DECLARE v_n int;
BEGIN
  SELECT count(*) INTO v_n FROM _doi;
  IF v_n <> 19 THEN RAISE EXCEPTION 'vd_ulrich: mong đợi 19 dòng thầu cũ, thấy %', v_n; END IF;
  IF NOT EXISTS (SELECT 1 FROM shared.dot_thau d
                 WHERE d.nam_tai_chinh = 'FY26' AND d.ps = 'Mậu Cao' AND d.ma_khach_hang = 'BV0342'
                   AND d.nhom_san_pham = 'Cột sống Ulrich' AND d.loai = 'chinh' AND d.dot = 1
                   AND d.thang_thau = '2026-05' AND d.thoi_gian > 0) THEN
    RAISE EXCEPTION 'vd_ulrich: không thấy đợt chính 1 (2026-05) có hiệu lực';
  END IF;
  SELECT count(*) INTO v_n FROM _doi o JOIN shared.quota_thau q
    ON q.nam_tai_chinh = o.nam_tai_chinh AND q.ps = o.ps AND q.ma_khach_hang = o.ma_khach_hang
   AND q.nhom_san_pham = o.nhom_san_pham AND q.bo_vat_tu = o.bo_vat_tu AND q.san_pham = o.san_pham
   AND q.don_gia = o.don_gia AND q.loai = 'chinh' AND q.dot = 1;
  IF v_n > 0 THEN RAISE EXCEPTION 'vd_ulrich: % khoá đã có quota thầu chính đợt 1', v_n; END IF;
END $$;

WITH upd AS (
  UPDATE shared.quota_thau q
  SET loai = 'chinh', dot = 1, updated_at = now(), updated_by = 'vd_ulrich_cu_sang_chinh_20261109'
  FROM _doi o WHERE q.id = o.id
  RETURNING q.*
)
INSERT INTO shared.quota_chuan_hoa_log (buoc, bang, ban_ghi_id, truoc, sau)
SELECT 'vd_ulrich_cu_sang_chinh_20261109', 'quota_thau', u.id, to_jsonb(o), to_jsonb(u)
FROM upd u JOIN _doi o ON o.id = u.id;

COMMIT;
