-- P1 chuẩn hoá quota: gắn lại khoá shared.quota_thau theo dòng kế hoạch hiện tại.
--
-- Khoá quota = bệnh viện × sản phẩm × PS (× giá × loại × đợt). Nhóm SP / BVT / tên
-- chính xác lấy theo dòng kế hoạch. Chỉ áp các dòng chắc chắn (user duyệt 14/10):
--   * SP còn trên kế hoạch cùng PS: chép nhóm / BVT / tên SP của kế hoạch; đổi giá
--     khi kế hoạch chỉ còn 1 mức giá và chênh ≤ 25% (hoặc giá cũ = 0 / lỗi nhập ≥ 1e12).
--   * SP không còn ở PS cũ nhưng còn ở KH do đúng 1 PS khác phụ trách → chuyển sang
--     PS đó (bu / miền theo dòng kế hoạch), cùng quy tắc giá.
--   * SP sang nhóm chưa có loại đợt đó → tạo đợt cùng số, chép tháng / thời gian.
-- Không áp (để cảnh báo): khoá đích đã có quota khác, nhiều nguồn tạo cùng một đợt
-- với tháng khác nhau, giá đổi > 25%, không tìm được dòng kế hoạch.
-- Mọi thay đổi ghi vào shared.quota_chuan_hoa_log để đối chiếu / khôi phục.

BEGIN;

CREATE TABLE IF NOT EXISTS shared.quota_chuan_hoa_log (
  id         bigserial PRIMARY KEY,
  buoc       text        NOT NULL,
  bang       text        NOT NULL,
  ban_ghi_id bigint,
  truoc      jsonb,
  sau        jsonb,
  created_at timestamptz NOT NULL DEFAULT now()
);
ALTER TABLE shared.quota_chuan_hoa_log ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON shared.quota_chuan_hoa_log FROM PUBLIC, anon, authenticated;
REVOKE ALL ON SEQUENCE shared.quota_chuan_hoa_log_id_seq FROM PUBLIC, anon, authenticated;

CREATE TEMP TABLE _ke_hoach_doi ON COMMIT DROP AS
with
kh as (
  select nam_tai_chinh fy, ps, coalesce(ma_khach_hang,'') cust, coalesce(don_gia,0) gia, san_pham, bu, mien,
         lower(regexp_replace(btrim(coalesce(san_pham,'')), '\s+', ' ', 'g')) ten,
         coalesce(nhom_san_pham,'') grp, coalesce(bo_vat_tu,'') mset
  from shared.sale_target where not coalesce(ngoai_ke_hoach,false) and coalesce(bu,'')<>'test' and nam_tai_chinh is not null),
khsp as (
  select fy, ps, cust, ten, min(san_pham) sp, array_agg(distinct gia order by gia) gias, min(grp) grp, min(mset) mset, min(bu) bu, min(mien) mien
  from kh group by 1,2,3,4),
q as (select q.*, lower(regexp_replace(btrim(q.san_pham), '\s+', ' ', 'g')) ten from shared.quota_thau q where coalesce(q.bu,'')<>'test'),
t as (  -- PS đích: PS hiện tại nếu còn SP, không thì PS khác duy nhất có SP ở KH đó
  select q.*,
    case when exists (select 1 from khsp k where k.fy=q.nam_tai_chinh and k.ps=q.ps and k.cust=q.ma_khach_hang and k.ten=q.ten) then q.ps
         when (select count(distinct k.ps) from khsp k where k.fy=q.nam_tai_chinh and k.cust=q.ma_khach_hang and k.ten=q.ten) = 1
           then (select min(k.ps) from khsp k where k.fy=q.nam_tai_chinh and k.cust=q.ma_khach_hang and k.ten=q.ten) end tps
  from q),
p as (
  select t.id, t.nam_tai_chinh fy, t.ps, t.ma_khach_hang cust, t.nhom_san_pham grp, t.bo_vat_tu mset, t.san_pham sp, t.don_gia gia, t.loai, t.dot, t.so_luong, t.bu, t.mien,
         t.tps, k.sp k_sp, k.grp k_grp, k.mset k_mset, k.gias, k.bu k_bu, k.mien k_mien,
         case when k.sp is null then null
              when t.don_gia = any(k.gias) then t.don_gia
              when cardinality(k.gias) = 1 and (t.don_gia = 0 or t.don_gia >= 1e12 or abs(k.gias[1]-t.don_gia)/t.don_gia <= 0.25) then k.gias[1] end new_gia,
         (select d.thang_thau from shared.dot_thau d where d.nam_tai_chinh=t.nam_tai_chinh and d.ps=t.ps and d.ma_khach_hang=t.ma_khach_hang and d.nhom_san_pham=t.nhom_san_pham and d.loai=t.loai and d.dot=t.dot) src_thang,
         (select d.thoi_gian from shared.dot_thau d where d.nam_tai_chinh=t.nam_tai_chinh and d.ps=t.ps and d.ma_khach_hang=t.ma_khach_hang and d.nhom_san_pham=t.nhom_san_pham and d.loai=t.loai and d.dot=t.dot) src_tg,
         exists (select 1 from shared.dot_thau d where d.nam_tai_chinh=t.nam_tai_chinh and d.ps=t.tps and d.ma_khach_hang=t.ma_khach_hang and d.nhom_san_pham=k.grp and d.loai=t.loai and d.dot=t.dot) dot_co,
         exists (select 1 from shared.dot_thau d where d.nam_tai_chinh=t.nam_tai_chinh and d.ps=t.tps and d.ma_khach_hang=t.ma_khach_hang and d.nhom_san_pham=k.grp and d.loai=t.loai) loai_co
  from t left join khsp k on k.fy=t.nam_tai_chinh and k.ps=t.tps and k.cust=t.ma_khach_hang and k.ten=t.ten),
d as (
  select p.*,
    case
      when k_sp is null then 'CANH_BAO'
      when new_gia is null then 'CANH_BAO'
      when loai <> 'cu' and not dot_co and loai_co then 'CANH_BAO'
      when tps = ps and k_sp = sp and k_grp = grp and k_mset = mset and new_gia = gia then 'GIU'
      else 'TU_DONG' end hanh_dong,
    (loai <> 'cu' and not dot_co) tao_dot
  from p),
-- va chạm khoá sau khi đổi
x as (
  select d.*, count(*) over (partition by fy, coalesce(tps,ps), cust, coalesce(k_grp,grp), coalesce(k_mset,mset), coalesce(k_sp,sp), coalesce(new_gia,gia), loai, dot) n_trung
  from d where hanh_dong in ('GIU','TU_DONG')),
-- đợt cần tạo: nhiều nguồn khác tháng → xung đột
dt as (
  select fy, tps, cust, k_grp, loai, dot, count(distinct coalesce(src_thang,'∅')) n_thang, min(src_thang) thang, max(src_tg) tg
  from d where hanh_dong='TU_DONG' and tao_dot group by 1,2,3,4,5,6)
select x.*, dt.n_thang, dt.thang dot_thang, dt.tg dot_tg
from x left join dt on dt.fy=x.fy and dt.tps=x.tps and dt.cust=x.cust and dt.k_grp=x.k_grp and dt.loai=x.loai and dt.dot=x.dot and x.tao_dot
where x.hanh_dong = 'TU_DONG' and x.n_trung = 1 and coalesce(dt.n_thang, 1) = 1;

-- 1) Tạo đợt còn thiếu ở nhóm / PS đích
WITH moi AS (
  INSERT INTO shared.dot_thau (nam_tai_chinh, bu, mien, ps, ma_khach_hang, nhom_san_pham, loai, dot, thang_thau, thoi_gian, updated_by)
  SELECT DISTINCT ON (fy, tps, cust, k_grp, loai, dot)
         fy, k_bu, k_mien, tps, cust, k_grp, loai, dot, dot_thang, dot_tg, 'chuan_hoa_20261014'
  FROM _ke_hoach_doi WHERE tao_dot
  ORDER BY fy, tps, cust, k_grp, loai, dot
  ON CONFLICT (nam_tai_chinh, ps, ma_khach_hang, nhom_san_pham, loai, dot) DO NOTHING
  RETURNING *)
INSERT INTO shared.quota_chuan_hoa_log (buoc, bang, ban_ghi_id, sau)
SELECT 'gan_lai_khoa', 'dot_thau', id, to_jsonb(moi) FROM moi;

-- 2) Gắn lại khoá quota
WITH truoc AS (
  SELECT q.* FROM shared.quota_thau q JOIN _ke_hoach_doi k ON k.id = q.id
), doi AS (
  UPDATE shared.quota_thau q SET
    ps = k.tps, bu = k.k_bu, mien = k.k_mien,
    nhom_san_pham = k.k_grp, bo_vat_tu = k.k_mset, san_pham = k.k_sp, don_gia = k.new_gia,
    updated_at = now(), updated_by = 'chuan_hoa_20261014'
  FROM _ke_hoach_doi k WHERE q.id = k.id
  RETURNING q.*)
INSERT INTO shared.quota_chuan_hoa_log (buoc, bang, ban_ghi_id, truoc, sau)
SELECT 'gan_lai_khoa', 'quota_thau', d.id, to_jsonb(t), to_jsonb(d)
FROM doi d JOIN truoc t ON t.id = d.id;

-- 3) Đồng bộ cột cũ trên sale_target cho cả khoá cũ lẫn khoá mới (giai đoạn chuyển tiếp)
SELECT shared.sync_quota_to_sale_target(
  (SELECT jsonb_agg(DISTINCT jsonb_build_object('fy', fy, 'ps', p, 'cust', cust, 'grp', g, 'mset', m, 'prod', s))
   FROM (SELECT fy, ps p, cust, grp g, mset m, sp s FROM _ke_hoach_doi
         UNION SELECT fy, tps, cust, k_grp, k_mset, k_sp FROM _ke_hoach_doi) u));

COMMIT;
