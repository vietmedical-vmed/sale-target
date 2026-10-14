-- P2b chuẩn hoá quota: chuyển quota ở cột cũ sale_target sang quota_thau / dot_thau.
--
-- Nguồn tính đúng như app (lib/quota.js): mọi dòng (kể cả OOP) trong 12 tháng FY26,
-- bỏ BU test, cộng theo sản phẩm × giá × loại × tháng thầu. Mỗi khoá xếp vào:
--   * CHINH_THUC: nhóm chưa khai đợt, khoá chưa có quota_thau → app đang hiện số
--     cột cũ. Tạo đợt cho nhóm (mỗi tháng thầu khác nhau một đợt, chưa có tháng xếp
--     trước), quota trạng thái chính thức → app hiện y như cũ.
--   * CHO_DUYET: nhóm đã khai đợt, sản phẩm chưa có quota_thau (hoặc số khác bản sao
--     sync) → app đang ẨN. Vào quota_thau trạng thái chờ duyệt; đợt dùng đợt cùng
--     tháng nếu có, không thì tạo đợt chờ duyệt.
--   * Bỏ qua: khoá đã có quota_thau (cột cũ chỉ là bản sao) và bản sao do sync.
-- Số đợt mới đánh tiếp sau số đợt lớn nhất đang có (kể cả số đợt mà quota_thau
-- đang tham chiếu) để không đổi tháng của quota sẵn có. Không gọi sync.

BEGIN;

CREATE TEMP TABLE _src ON COMMIT DROP AS
with
src as (  -- cột cũ theo khoá × loại × tháng (giống app: cả dòng OOP, chỉ 12 tháng FY26, bỏ test)
  select s.nam_tai_chinh fy, coalesce(s.ps,'') ps, coalesce(s.ma_khach_hang,'') cust, coalesce(s.nhom_san_pham,'') grp,
         coalesce(s.bo_vat_tu,'') mset, coalesce(s.san_pham,'') prod, coalesce(s.don_gia,0) gia,
         min(s.bu) bu, min(s.mien) mien, min(s.khach_hang) khach_hang,
         x.loai, x.thang, sum(x.sl) sl, max(x.tg) tg, bool_or(coalesce(s.ngoai_ke_hoach,false)) co_oop
  from shared.sale_target s
  cross join lateral (values
    ('cu', null::text, coalesce(s.quota_thau_cu_con_lai,0), null::numeric),
    ('chinh', shared.thang_thau_hop_le(s.thang_thau_chinh), coalesce(s.quota_thau_chinh,0), s.thoi_gian_thau_chinh),
    ('bo_sung', shared.thang_thau_hop_le(s.thang_thau_bo_sung), coalesce(s.quota_bo_sung,0), null::numeric)) x(loai, thang, sl, tg)
  where (s.bu is null or s.bu <> 'test') and s.thang_ke_hoach between '2026-04' and '2027-03' and x.sl <> 0
  group by 1,2,3,4,5,6,7,11,12),
khoa as (select fy, ps, cust, grp, mset, prod, gia, sum(sl) sl_khoa from src group by 1,2,3,4,5,6,7),
qk as (select distinct nam_tai_chinh fy, ps, ma_khach_hang cust, nhom_san_pham grp, bo_vat_tu mset, san_pham prod, don_gia gia from shared.quota_thau),
qp as (select nam_tai_chinh fy, ps, ma_khach_hang cust, nhom_san_pham grp, bo_vat_tu mset, san_pham prod, sum(so_luong) tong from shared.quota_thau group by 1,2,3,4,5,6),
dg as (select distinct nam_tai_chinh fy, ps, ma_khach_hang cust, nhom_san_pham grp from shared.dot_thau),
phan_loai as (
  select k.*, case
    when qk.prod is not null then 'BO_DA_CO_QUOTA'
    when dg.grp is null then 'CHINH_THUC'
    when qp.prod is null then 'CHO_DUYET'
    when qp.tong = k.sl_khoa then 'BO_BAN_SAO_SYNC'
    else 'CHO_DUYET' end loai_xu_ly
  from khoa k left join qk using (fy,ps,cust,grp,mset,prod,gia) left join qp using (fy,ps,cust,grp,mset,prod) left join dg using (fy,ps,cust,grp))
select s.*, p.loai_xu_ly from src s join phan_loai p using (fy,ps,cust,grp,mset,prod,gia)
where p.loai_xu_ly in ('CHINH_THUC', 'CHO_DUYET');

-- Số đợt lớn nhất đang dùng theo nhóm × loại (đợt có thật + số đợt quota tham chiếu)
CREATE TEMP TABLE _max_dot ON COMMIT DROP AS
SELECT fy, ps, cust, grp, loai, max(dot) max_dot FROM (
  SELECT nam_tai_chinh fy, ps, ma_khach_hang cust, nhom_san_pham grp, loai, dot FROM shared.dot_thau
  UNION ALL
  SELECT nam_tai_chinh, ps, ma_khach_hang, nhom_san_pham, loai, dot FROM shared.quota_thau WHERE loai <> 'cu'
) u GROUP BY 1,2,3,4,5;

-- Đợt đích cho từng (nhóm, loại, tháng)
CREATE TEMP TABLE _dot ON COMMIT DROP AS
WITH can AS (
  SELECT fy, ps, cust, grp, loai, thang, max(tg) tg, min(bu) bu, min(mien) mien,
         CASE WHEN bool_or(loai_xu_ly = 'CHO_DUYET') THEN 'cho_duyet' ELSE 'chinh_thuc' END trang_thai
  FROM _src WHERE loai <> 'cu' GROUP BY 1,2,3,4,5,6),
co_san AS (
  SELECT c.*, (SELECT min(d.dot) FROM shared.dot_thau d
               WHERE d.nam_tai_chinh = c.fy AND d.ps = c.ps AND d.ma_khach_hang = c.cust
                 AND d.nhom_san_pham = c.grp AND d.loai = c.loai AND d.thang_thau IS NOT DISTINCT FROM c.thang) dot_co
  FROM can c)
SELECT cs.*,
       coalesce(cs.dot_co, coalesce(m.max_dot, 0)
                + row_number() OVER (PARTITION BY cs.fy, cs.ps, cs.cust, cs.grp, cs.loai, (cs.dot_co IS NULL)
                                     ORDER BY cs.thang NULLS FIRST)) dot,
       cs.dot_co IS NULL tao_moi
FROM co_san cs
LEFT JOIN _max_dot m ON m.fy = cs.fy AND m.ps = cs.ps AND m.cust = cs.cust AND m.grp = cs.grp AND m.loai = cs.loai;

WITH moi AS (
  INSERT INTO shared.dot_thau (nam_tai_chinh, bu, mien, ps, ma_khach_hang, nhom_san_pham, loai, dot,
                               thang_thau, thoi_gian, updated_by, trang_thai, nguon)
  SELECT fy, bu, mien, ps, cust, grp, loai, dot, thang, tg, 'chuan_hoa_20261014', trang_thai, 'cot_cu_20261014'
  FROM _dot WHERE tao_moi
  RETURNING *)
INSERT INTO shared.quota_chuan_hoa_log (buoc, bang, ban_ghi_id, sau)
SELECT 'chuyen_cot_cu', 'dot_thau', id, to_jsonb(moi) FROM moi;

WITH moi AS (
  INSERT INTO shared.quota_thau (nam_tai_chinh, bu, mien, ps, ma_khach_hang, khach_hang, nhom_san_pham,
                                 bo_vat_tu, san_pham, don_gia, loai, dot, so_luong, updated_by, trang_thai, nguon)
  SELECT s.fy, min(s.bu), min(s.mien), s.ps, s.cust, min(s.khach_hang), s.grp, s.mset, s.prod, s.gia,
         s.loai, coalesce(d.dot, 1), sum(s.sl), 'chuan_hoa_20261014',
         CASE s.loai_xu_ly WHEN 'CHO_DUYET' THEN 'cho_duyet' ELSE 'chinh_thuc' END, 'cot_cu_20261014'
  FROM _src s
  LEFT JOIN _dot d ON d.fy = s.fy AND d.ps = s.ps AND d.cust = s.cust AND d.grp = s.grp
                  AND d.loai = s.loai AND d.thang IS NOT DISTINCT FROM s.thang AND s.loai <> 'cu'
  GROUP BY s.fy, s.ps, s.cust, s.grp, s.mset, s.prod, s.gia, s.loai, coalesce(d.dot, 1), s.loai_xu_ly
  RETURNING *)
INSERT INTO shared.quota_chuan_hoa_log (buoc, bang, ban_ghi_id, sau)
SELECT 'chuyen_cot_cu', 'quota_thau', id, to_jsonb(moi) FROM moi;

COMMIT;
