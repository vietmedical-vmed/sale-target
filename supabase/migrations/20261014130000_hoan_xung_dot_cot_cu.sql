-- Hoàn tác một phần 20261014120000_gan_lai_khoa_quota.sql.
--
-- Gắn lại khoá đã đưa quota_thau (thường là số nạp 14/09 dưới tên nhóm cũ) vào
-- khoá mà app đang hiển thị quota theo CỘT CŨ trên sale_target — số user đã sửa
-- sau khi đổi tên nhóm. App ưu tiên quota_thau nên số cột cũ bị đè. Nguyên tắc:
-- số app đang hiện là chuẩn → trả các dòng đó về khoá cũ (lại thành mồ côi, vào
-- danh sách cảnh báo), rồi xoá các đợt vừa tạo mà không còn quota nào dùng để
-- nhóm quay lại tính theo cột cũ như trước.

BEGIN;

-- Khoá đang hiển thị quota theo cột cũ TRƯỚC khi gắn lại (tính trên bản backup)
CREATE TEMP TABLE _khoa_cot_cu ON COMMIT DROP AS
SELECT k.* FROM (
  SELECT s.nam_tai_chinh fy, coalesce(s.ps,'') ps, coalesce(s.ma_khach_hang,'') cust,
         coalesce(s.nhom_san_pham,'') grp, coalesce(s.bo_vat_tu,'') mset,
         coalesce(s.san_pham,'') prod, coalesce(s.don_gia,0) gia
  FROM shared.bak_20261014_sale_target_quota s
  WHERE coalesce(s.bu,'') <> 'test'
  GROUP BY 1,2,3,4,5,6,7
  HAVING sum(coalesce(s.quota_thau_cu_con_lai,0) + coalesce(s.quota_thau_chinh,0) + coalesce(s.quota_bo_sung,0)) <> 0
) k
WHERE NOT EXISTS (SELECT 1 FROM shared.bak_20261014_dot_thau d
                  WHERE d.nam_tai_chinh = k.fy AND d.ps = k.ps AND d.ma_khach_hang = k.cust AND d.nhom_san_pham = k.grp)
  AND NOT EXISTS (SELECT 1 FROM shared.bak_20261014_quota_thau q
                  WHERE q.nam_tai_chinh = k.fy AND q.ps = k.ps AND q.ma_khach_hang = k.cust AND q.nhom_san_pham = k.grp
                    AND q.bo_vat_tu = k.mset AND q.san_pham = k.prod AND q.don_gia = k.gia);

CREATE TEMP TABLE _hoan ON COMMIT DROP AS
SELECT l.ban_ghi_id id, l.truoc, l.sau
FROM shared.quota_chuan_hoa_log l
JOIN _khoa_cot_cu k
  ON k.fy = l.sau->>'nam_tai_chinh' AND k.ps = l.sau->>'ps' AND k.cust = l.sau->>'ma_khach_hang'
 AND k.grp = l.sau->>'nhom_san_pham' AND k.mset = l.sau->>'bo_vat_tu' AND k.prod = l.sau->>'san_pham'
 AND k.gia = (l.sau->>'don_gia')::numeric
WHERE l.buoc = 'gan_lai_khoa' AND l.bang = 'quota_thau';

WITH truoc AS (SELECT q.* FROM shared.quota_thau q JOIN _hoan h ON h.id = q.id),
doi AS (
  UPDATE shared.quota_thau q SET
    ps = h.truoc->>'ps', bu = h.truoc->>'bu', mien = h.truoc->>'mien',
    nhom_san_pham = h.truoc->>'nhom_san_pham', bo_vat_tu = h.truoc->>'bo_vat_tu',
    san_pham = h.truoc->>'san_pham', don_gia = (h.truoc->>'don_gia')::numeric,
    updated_at = now(), updated_by = 'chuan_hoa_20261014_hoan'
  FROM _hoan h WHERE q.id = h.id
  RETURNING q.*)
INSERT INTO shared.quota_chuan_hoa_log (buoc, bang, ban_ghi_id, truoc, sau)
SELECT 'hoan_xung_dot_cot_cu', 'quota_thau', d.id, to_jsonb(t), to_jsonb(d)
FROM doi d JOIN truoc t ON t.id = d.id;

-- Đợt vừa tạo mà không còn quota nào dùng → xoá
WITH xoa AS (
  DELETE FROM shared.dot_thau d
  USING shared.quota_chuan_hoa_log l
  WHERE l.buoc = 'gan_lai_khoa' AND l.bang = 'dot_thau' AND d.id = l.ban_ghi_id
    AND NOT EXISTS (SELECT 1 FROM shared.quota_thau q
                    WHERE q.nam_tai_chinh = d.nam_tai_chinh AND q.ps = d.ps AND q.ma_khach_hang = d.ma_khach_hang
                      AND q.nhom_san_pham = d.nhom_san_pham AND q.loai = d.loai AND q.dot = d.dot)
  RETURNING d.*)
INSERT INTO shared.quota_chuan_hoa_log (buoc, bang, ban_ghi_id, truoc)
SELECT 'hoan_xung_dot_cot_cu', 'dot_thau', id, to_jsonb(xoa) FROM xoa;

-- Bước gắn lại đã gọi sync_quota_to_sale_target cho khoá mới / cũ: hàm này ghi
-- tổng quota_thau đè lên cột cũ của sale_target, xoá mất số user đang dùng ở các
-- khoá theo cột cũ. Trả cột cũ về đúng bản backup (chỉ các dòng bị ghi đè; dừng
-- nếu có dòng user sửa sau thời điểm gắn lại).
DO $$
BEGIN
  IF EXISTS (
    SELECT 1 FROM shared.sale_target s JOIN shared.bak_20261014_sale_target_quota b ON b.id = s.id
    WHERE (s.quota_thau_cu_con_lai, s.quota_thau_chinh, s.quota_bo_sung, s.thang_thau_chinh, s.thang_thau_bo_sung, s.thoi_gian_thau_chinh)
          IS DISTINCT FROM (b.quota_thau_cu_con_lai, b.quota_thau_chinh, b.quota_bo_sung, b.thang_thau_chinh, b.thang_thau_bo_sung, b.thoi_gian_thau_chinh)
      AND s.updated_at > (SELECT min(created_at) FROM shared.quota_chuan_hoa_log)
  ) THEN
    RAISE EXCEPTION 'co_dong_user_sua: có dòng sale_target bị sửa sau khi gắn lại khoá — kiểm tra tay trước khi khôi phục';
  END IF;
END $$;

WITH doi AS (
  UPDATE shared.sale_target s SET
    quota_thau_cu_con_lai = b.quota_thau_cu_con_lai, quota_thau_chinh = b.quota_thau_chinh,
    quota_bo_sung = b.quota_bo_sung, thang_thau_chinh = b.thang_thau_chinh,
    thang_thau_bo_sung = b.thang_thau_bo_sung, thoi_gian_thau_chinh = b.thoi_gian_thau_chinh
  FROM shared.bak_20261014_sale_target_quota b
  WHERE b.id = s.id
    AND (s.quota_thau_cu_con_lai, s.quota_thau_chinh, s.quota_bo_sung, s.thang_thau_chinh, s.thang_thau_bo_sung, s.thoi_gian_thau_chinh)
        IS DISTINCT FROM (b.quota_thau_cu_con_lai, b.quota_thau_chinh, b.quota_bo_sung, b.thang_thau_chinh, b.thang_thau_bo_sung, b.thoi_gian_thau_chinh)
  RETURNING s.id, s.quota_thau_cu_con_lai, s.quota_thau_chinh, s.quota_bo_sung)
INSERT INTO shared.quota_chuan_hoa_log (buoc, bang, ban_ghi_id, sau)
SELECT 'khoi_phuc_cot_cu', 'sale_target', id, to_jsonb(doi) FROM doi;

COMMIT;
