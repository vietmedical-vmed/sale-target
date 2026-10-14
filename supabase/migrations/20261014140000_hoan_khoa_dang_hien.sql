-- Hoàn tác tiếp 20261014120000_gan_lai_khoa_quota.sql: trả về khoá cũ mọi dòng gắn
-- lại mà khoá gốc HOẶC khoá đích đang hiển thị quota trên app trước khi gắn lại
-- (tính đúng như lib/quota.js trên bản backup 14/10). Hai trường hợp gặp phải:
--   * kế hoạch có 2 cách viết cùng một tên SP / BVT ("Gối thay lại - UOC" và
--     "Gối thay lại  - UOC") → quota bị kéo khỏi khoá đang hiện;
--   * quota nạp 14/09 dưới tên nhóm cũ dồn vào khoá đã có quota mới nhập ở tên
--     nhóm mới → có thể đếm đôi.
-- Các dòng này về lại danh sách cảnh báo để duyệt tay.

BEGIN;

CREATE TEMP TABLE _khoa_hien ON COMMIT DROP AS
with
r as (
  select coalesce(nam_tai_chinh,'') fy, coalesce(ps,'') ps, coalesce(ma_khach_hang,'') cust, coalesce(nhom_san_pham,'') grp,
         coalesce(bo_vat_tu,'') mset, coalesce(san_pham,'') prod, coalesce(don_gia,0) gia, coalesce(ngoai_ke_hoach,false) oop, bu,
         coalesce(quota_thau_cu_con_lai,0)+coalesce(quota_thau_chinh,0)+coalesce(quota_bo_sung,0) q_cu
  from shared.bak_20261014_sale_target_quota
  where (bu is null or bu <> 'test') and thang_ke_hoach between '2026-04' and '2027-03' and thang_ke_hoach ~ '^\d{4}-\d{2}$'),
qt as (select nam_tai_chinh fy, ps, ma_khach_hang cust, nhom_san_pham grp, bo_vat_tu mset, san_pham prod, don_gia gia, sum(so_luong) qty
       from shared.bak_20261014_quota_thau where bu is null or bu <> 'test' group by 1,2,3,4,5,6,7),
dg as (select distinct nam_tai_chinh fy, ps, ma_khach_hang cust, nhom_san_pham grp from shared.bak_20261014_dot_thau where bu is null or bu <> 'test'),
k as (select fy,ps,cust,grp,mset,prod,gia, min(bu) bu, bool_or(not oop) co_ke_hoach, sum(q_cu) q_cu from r group by 1,2,3,4,5,6,7),
app as (
  select k.*, (dg.grp is not null or qt.qty is not null) nguon_moi,
         case when dg.grp is not null or qt.qty is not null
              then case when k.co_ke_hoach then coalesce(qt.qty,0) else 0 end
              else k.q_cu end qty
  from k left join qt using (fy,ps,cust,grp,mset,prod,gia) left join dg using (fy,ps,cust,grp))
select fy, ps, cust, grp, mset, prod, gia from app where qty <> 0;

CREATE TEMP TABLE _hoan ON COMMIT DROP AS
SELECT l.ban_ghi_id id, l.truoc, l.sau
FROM shared.quota_chuan_hoa_log l
WHERE l.buoc = 'gan_lai_khoa' AND l.bang = 'quota_thau'
  AND NOT EXISTS (SELECT 1 FROM shared.quota_chuan_hoa_log h
                  WHERE h.buoc LIKE 'hoan%' AND h.bang = 'quota_thau' AND h.ban_ghi_id = l.ban_ghi_id)
  AND EXISTS (SELECT 1 FROM _khoa_hien k, LATERAL (VALUES (l.truoc), (l.sau)) v(x)
              WHERE k.fy = x->>'nam_tai_chinh' AND k.ps = x->>'ps' AND k.cust = x->>'ma_khach_hang'
                AND k.grp = x->>'nhom_san_pham' AND k.mset = x->>'bo_vat_tu' AND k.prod = x->>'san_pham'
                AND k.gia = (x->>'don_gia')::numeric);

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
SELECT 'hoan_khoa_dang_hien', 'quota_thau', d.id, to_jsonb(t), to_jsonb(d)
FROM doi d JOIN truoc t ON t.id = d.id;

WITH xoa AS (
  DELETE FROM shared.dot_thau d
  USING shared.quota_chuan_hoa_log l
  WHERE l.buoc = 'gan_lai_khoa' AND l.bang = 'dot_thau' AND d.id = l.ban_ghi_id
    AND NOT EXISTS (SELECT 1 FROM shared.quota_thau q
                    WHERE q.nam_tai_chinh = d.nam_tai_chinh AND q.ps = d.ps AND q.ma_khach_hang = d.ma_khach_hang
                      AND q.nhom_san_pham = d.nhom_san_pham AND q.loai = d.loai AND q.dot = d.dot)
  RETURNING d.*)
INSERT INTO shared.quota_chuan_hoa_log (buoc, bang, ban_ghi_id, truoc)
SELECT 'hoan_khoa_dang_hien', 'dot_thau', id, to_jsonb(xoa) FROM xoa;

COMMIT;
