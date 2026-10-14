-- User chốt (14/10) cho 98 dòng quota xung đột: giữ số app đang hiện, xoá quota
-- cũ. Xoá các dòng quota_thau đã hoàn tác ở 20261014130000 / 20261014140000, TRỪ
-- dòng mà chính khoá hiện tại của nó đang được app hiển thị (khi đó nó là số đang
-- hiện, không phải quota cũ). Dòng xoá ghi vào quota_chuan_hoa_log.

BEGIN;

CREATE TEMP TABLE _khoa_hien ON COMMIT DROP AS
with
r as (
  select coalesce(nam_tai_chinh,'') fy, coalesce(ps,'') ps, coalesce(ma_khach_hang,'') cust, coalesce(nhom_san_pham,'') grp,
         coalesce(bo_vat_tu,'') mset, coalesce(san_pham,'') prod, coalesce(don_gia,0) gia, coalesce(ngoai_ke_hoach,false) oop, bu,
         coalesce(quota_thau_cu_con_lai,0)+coalesce(quota_thau_chinh,0)+coalesce(quota_bo_sung,0) q_cu
  from shared.sale_target
  where (bu is null or bu <> 'test') and thang_ke_hoach between '2026-04' and '2027-03' and thang_ke_hoach ~ '^\d{4}-\d{2}$'),
qt as (select nam_tai_chinh fy, ps, ma_khach_hang cust, nhom_san_pham grp, bo_vat_tu mset, san_pham prod, don_gia gia, sum(so_luong) qty
       from shared.quota_thau where bu is null or bu <> 'test' group by 1,2,3,4,5,6,7),
dg as (select distinct nam_tai_chinh fy, ps, ma_khach_hang cust, nhom_san_pham grp from shared.dot_thau where bu is null or bu <> 'test'),
k as (select fy,ps,cust,grp,mset,prod,gia, min(bu) bu, bool_or(not oop) co_ke_hoach, sum(q_cu) q_cu from r group by 1,2,3,4,5,6,7),
app as (
  select k.*, (dg.grp is not null or qt.qty is not null) nguon_moi,
         case when dg.grp is not null or qt.qty is not null
              then case when k.co_ke_hoach then coalesce(qt.qty,0) else 0 end
              else k.q_cu end qty
  from k left join qt using (fy,ps,cust,grp,mset,prod,gia) left join dg using (fy,ps,cust,grp))
select fy, ps, cust, grp, mset, prod, gia from app where qty <> 0 and nguon_moi;

WITH xoa AS (
  DELETE FROM shared.quota_thau q
  WHERE q.id IN (SELECT ban_ghi_id FROM shared.quota_chuan_hoa_log
                 WHERE bang = 'quota_thau' AND buoc IN ('hoan_xung_dot_cot_cu', 'hoan_khoa_dang_hien'))
    AND NOT EXISTS (SELECT 1 FROM _khoa_hien k
                    WHERE k.fy = q.nam_tai_chinh AND k.ps = q.ps AND k.cust = q.ma_khach_hang
                      AND k.grp = q.nhom_san_pham AND k.mset = q.bo_vat_tu AND k.prod = q.san_pham
                      AND k.gia = q.don_gia)
  RETURNING q.*)
INSERT INTO shared.quota_chuan_hoa_log (buoc, bang, ban_ghi_id, truoc)
SELECT 'xoa_quota_cu_xung_dot', 'quota_thau', id, to_jsonb(xoa) FROM xoa;

COMMIT;
