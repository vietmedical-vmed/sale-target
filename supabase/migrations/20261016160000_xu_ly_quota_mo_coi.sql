-- Xử lý quota mồ côi theo cảnh báo của v_quota_thau_xuat (user chốt 16/10):
--   * Khác tên - khác mã (SP không còn trên kế hoạch)          → xoá.
--   * Khớp tên - khác nhóm / BVT / cách viết, Mức giá không còn,
--     SP còn ở KH nhưng PS khác → ánh xạ sang dòng kế hoạch đúng (nhóm / BVT / tên /
--     giá / PS theo sale_target):
--       - khoá đích đã có quota cùng loại × đợt (cùng hoặc khác SL) → xoá dòng mồ côi,
--         giữ số đang hiện;
--       - khoá đích chưa có quota, hoặc có quota nhưng khác loại / đợt → cập nhật sang;
--       - nhiều SP / nhiều mức giá đích, nhiều dòng dồn vào cùng khoá đích, hoặc đợt
--         cùng số ở nhóm đích khác tháng / hiệu lực → để nguyên (duyệt tay).
-- Xoá chỉ đụng dòng không hiện trên app nên không đổi tổng; cập nhật làm quota hiện
-- ra (tổng tăng đúng phần đó). Backup + log từng dòng ở quota_chuan_hoa_log.

BEGIN;

CREATE TABLE shared.bak_20261016_quota_thau AS TABLE shared.quota_thau;
CREATE TABLE shared.bak_20261016_dot_thau   AS TABLE shared.dot_thau;
ALTER TABLE shared.bak_20261016_quota_thau ENABLE ROW LEVEL SECURITY;
ALTER TABLE shared.bak_20261016_dot_thau   ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON shared.bak_20261016_quota_thau, shared.bak_20261016_dot_thau FROM PUBLIC, anon, authenticated;

CREATE TEMP TABLE _kh ON COMMIT DROP AS
  select nam_tai_chinh fy, coalesce(ps,'') ps, coalesce(ma_khach_hang,'') cust, coalesce(nhom_san_pham,'') grp,
         coalesce(bo_vat_tu,'') mset, coalesce(san_pham,'') prod, coalesce(don_gia,0) gia,
         shared.ten_sp_chuan(san_pham) ten, shared.ma_sp_hop_le(ma_san_pham) ma, min(bu) bu, min(mien) mien, min(khach_hang) kh
  from shared.sale_target where nam_tai_chinh is not null and not coalesce(ngoai_ke_hoach,false) and coalesce(bu,'')<>'test'
  group by 1,2,3,4,5,6,7,8,9;
CREATE TEMP TABLE _mo ON COMMIT DROP AS
  select q.*, shared.ten_sp_chuan(q.san_pham) ten from shared.quota_thau q
  where coalesce(q.bu,'')<>'test' and q.trang_thai='chinh_thuc'
    and not exists (select 1 from _kh k where k.fy=q.nam_tai_chinh and k.ps=q.ps and k.cust=q.ma_khach_hang
         and k.grp=q.nhom_san_pham and k.mset=q.bo_vat_tu and k.prod=q.san_pham and k.gia=q.don_gia);
alter table _mo add column nhom text;
update _mo m set nhom = case
  when exists (select 1 from _kh k where k.fy=m.nam_tai_chinh and k.ps=m.ps and k.cust=m.ma_khach_hang and k.grp=m.nhom_san_pham and k.mset=m.bo_vat_tu and k.prod=m.san_pham) then 'P'
  when exists (select 1 from _kh k where k.fy=m.nam_tai_chinh and k.ps=m.ps and k.cust=m.ma_khach_hang and k.ten=m.ten) then 'T'
  when m.ma_san_pham is not null and exists (select 1 from _kh k where k.fy=m.nam_tai_chinh and k.ps=m.ps and k.cust=m.ma_khach_hang and k.ma=m.ma_san_pham) then 'M'
  when exists (select 1 from _kh k where k.fy=m.nam_tai_chinh and k.cust=m.ma_khach_hang and k.ps<>m.ps and (k.ten=m.ten or (m.ma_san_pham is not null and k.ma=m.ma_san_pham))) then 'S'
  else 'X' end;
CREATE TEMP TABLE _ung ON COMMIT DROP AS
  select m.id, k.ps, k.grp, k.mset, k.prod, k.gia, k.bu, k.mien, k.kh
  from _mo m join _kh k on k.fy=m.nam_tai_chinh and k.cust=m.ma_khach_hang and (
       (m.nhom='P' and k.ps=m.ps and k.grp=m.nhom_san_pham and k.mset=m.bo_vat_tu and k.prod=m.san_pham)
    or (m.nhom='T' and k.ps=m.ps and k.ten=m.ten)
    or (m.nhom='M' and k.ps=m.ps and k.ma=m.ma_san_pham)
    or (m.nhom='S' and k.ps<>m.ps and (k.ten=m.ten or (m.ma_san_pham is not null and k.ma=m.ma_san_pham))));
CREATE TEMP TABLE _d ON COMMIT DROP AS
  select m.*, s.n_sp, s.ps t_ps, s.grp t_grp, s.mset t_mset, s.prod t_prod, s.gias, s.bu t_bu, s.mien t_mien, s.kh t_kh,
    case when m.nhom='X' or s.n_sp is distinct from 1 then null
         when m.nhom<>'P' and m.don_gia = any(s.gias) then m.don_gia
         when cardinality(s.gias)=1 then s.gias[1] end t_gia
  from _mo m left join (
    select id, count(distinct (ps,grp,mset,prod)) n_sp, min(ps) ps, min(grp) grp, min(mset) mset, min(prod) prod,
           array_agg(distinct gia) gias, min(bu) bu, min(mien) mien, min(kh) kh
    from _ung group by id) s on s.id=m.id;
alter table _d add column hanh_dong text;
update _d d set hanh_dong = case
  when nhom='X' then 'XOA'
  when t_gia is null then 'DUYET_TAY: nhiều SP / nhiều mức giá đích'
  when exists (select 1 from shared.quota_thau x where x.nam_tai_chinh=d.nam_tai_chinh and x.ps=d.t_ps and x.ma_khach_hang=d.ma_khach_hang
               and x.nhom_san_pham=d.t_grp and x.bo_vat_tu=d.t_mset and x.san_pham=d.t_prod and x.don_gia=d.t_gia) then 'XOA_TRUNG'
  when loai<>'cu' and (t_ps, t_grp) is distinct from (ps, nhom_san_pham)
       and exists (select 1 from shared.dot_thau t join shared.dot_thau s
                     on s.nam_tai_chinh=d.nam_tai_chinh and s.ps=d.ps and s.ma_khach_hang=d.ma_khach_hang and s.nhom_san_pham=d.nhom_san_pham and s.loai=d.loai and s.dot=d.dot
                   where t.nam_tai_chinh=d.nam_tai_chinh and t.ps=d.t_ps and t.ma_khach_hang=d.ma_khach_hang and t.nhom_san_pham=d.t_grp and t.loai=d.loai and t.dot=d.dot
                     and (t.thang_thau is distinct from s.thang_thau or t.thoi_gian is distinct from s.thoi_gian)) then 'DUYET_TAY: đợt cùng số ở nhóm đích khác tháng / hiệu lực'
  else 'CAP_NHAT' end;
update _d d set hanh_dong = 'DUYET_TAY: nhiều dòng dồn vào cùng khoá đích'
where hanh_dong='CAP_NHAT' and (select count(*) from _d x where x.hanh_dong='CAP_NHAT' and x.nam_tai_chinh=d.nam_tai_chinh and x.t_ps=d.t_ps and x.ma_khach_hang=d.ma_khach_hang
      and x.t_grp=d.t_grp and x.t_mset=d.t_mset and x.t_prod=d.t_prod and x.t_gia=d.t_gia and x.loai=d.loai and x.dot=d.dot) > 1;

-- Dòng "xoá trùng" mà khoá đích chỉ có quota KHÁC loại / đợt → cập nhật sang (user chốt)
UPDATE _d d SET hanh_dong = 'CAP_NHAT'
WHERE d.hanh_dong = 'XOA_TRUNG'
  AND NOT EXISTS (SELECT 1 FROM shared.quota_thau x
                  WHERE x.nam_tai_chinh = d.nam_tai_chinh AND x.ps = d.t_ps AND x.ma_khach_hang = d.ma_khach_hang
                    AND x.nhom_san_pham = d.t_grp AND x.bo_vat_tu = d.t_mset AND x.san_pham = d.t_prod
                    AND x.don_gia = d.t_gia AND x.loai = d.loai AND x.dot = d.dot)
  AND NOT (loai <> 'cu' AND (t_ps, t_grp) IS DISTINCT FROM (ps, nhom_san_pham)
           AND EXISTS (SELECT 1 FROM shared.dot_thau t JOIN shared.dot_thau s
                         ON s.nam_tai_chinh = d.nam_tai_chinh AND s.ps = d.ps AND s.ma_khach_hang = d.ma_khach_hang
                        AND s.nhom_san_pham = d.nhom_san_pham AND s.loai = d.loai AND s.dot = d.dot
                       WHERE t.nam_tai_chinh = d.nam_tai_chinh AND t.ps = d.t_ps AND t.ma_khach_hang = d.ma_khach_hang
                         AND t.nhom_san_pham = d.t_grp AND t.loai = d.loai AND t.dot = d.dot
                         AND (t.thang_thau IS DISTINCT FROM s.thang_thau OR t.thoi_gian IS DISTINCT FROM s.thoi_gian)));

-- Kiểm lại: sau khi thêm dòng cập nhật, nhiều dòng dồn vào cùng khoá đích → duyệt tay
UPDATE _d d SET hanh_dong = 'DUYET_TAY: nhiều dòng dồn vào cùng khoá đích'
WHERE hanh_dong = 'CAP_NHAT' AND (SELECT count(*) FROM _d x WHERE x.hanh_dong = 'CAP_NHAT'
      AND x.nam_tai_chinh = d.nam_tai_chinh AND x.t_ps = d.t_ps AND x.ma_khach_hang = d.ma_khach_hang
      AND x.t_grp = d.t_grp AND x.t_mset = d.t_mset AND x.t_prod = d.t_prod AND x.t_gia = d.t_gia
      AND x.loai = d.loai AND x.dot = d.dot) > 1;

-- Xoá: không còn SP trên kế hoạch + trùng (khoá đích đã có cùng loại × đợt)
WITH xoa AS (
  DELETE FROM shared.quota_thau q USING _d d
  WHERE q.id = d.id AND d.hanh_dong IN ('XOA', 'XOA_TRUNG')
  RETURNING q.*, d.hanh_dong)
INSERT INTO shared.quota_chuan_hoa_log (buoc, bang, ban_ghi_id, truoc)
SELECT CASE hanh_dong WHEN 'XOA' THEN 'xoa_mo_coi_khac_ten_ma' ELSE 'xoa_mo_coi_trung' END,
       'quota_thau', id, to_jsonb(xoa) - 'hanh_dong'
FROM xoa;

-- Đợt chưa có ở nhóm / PS đích → chép từ đợt nguồn
WITH moi AS (
  INSERT INTO shared.dot_thau (nam_tai_chinh, bu, mien, ps, ma_khach_hang, nhom_san_pham, loai, dot,
                               thang_thau, thoi_gian, updated_by, trang_thai, nguon)
  SELECT DISTINCT ON (d.nam_tai_chinh, d.t_ps, d.ma_khach_hang, d.t_grp, d.loai, d.dot)
         d.nam_tai_chinh, d.t_bu, d.t_mien, d.t_ps, d.ma_khach_hang, d.t_grp, d.loai, d.dot,
         s.thang_thau, s.thoi_gian, 'xu_ly_mo_coi_20261016', s.trang_thai, s.nguon
  FROM _d d
  JOIN shared.dot_thau s ON s.nam_tai_chinh = d.nam_tai_chinh AND s.ps = d.ps AND s.ma_khach_hang = d.ma_khach_hang
                        AND s.nhom_san_pham = d.nhom_san_pham AND s.loai = d.loai AND s.dot = d.dot
  WHERE d.hanh_dong = 'CAP_NHAT' AND d.loai <> 'cu'
    AND NOT EXISTS (SELECT 1 FROM shared.dot_thau t
                    WHERE t.nam_tai_chinh = d.nam_tai_chinh AND t.ps = d.t_ps AND t.ma_khach_hang = d.ma_khach_hang
                      AND t.nhom_san_pham = d.t_grp AND t.loai = d.loai AND t.dot = d.dot)
  ORDER BY d.nam_tai_chinh, d.t_ps, d.ma_khach_hang, d.t_grp, d.loai, d.dot
  RETURNING *)
INSERT INTO shared.quota_chuan_hoa_log (buoc, bang, ban_ghi_id, sau)
SELECT 'xu_ly_mo_coi_chep_dot', 'dot_thau', id, to_jsonb(moi) FROM moi;

-- Cập nhật quota sang khoá đích
WITH truoc AS (SELECT q.* FROM shared.quota_thau q JOIN _d d ON d.id = q.id AND d.hanh_dong = 'CAP_NHAT'),
doi AS (
  UPDATE shared.quota_thau q SET
    ps = d.t_ps, nhom_san_pham = d.t_grp, bo_vat_tu = d.t_mset, san_pham = d.t_prod, don_gia = d.t_gia,
    bu = coalesce(d.t_bu, q.bu), mien = coalesce(d.t_mien, q.mien), khach_hang = coalesce(d.t_kh, q.khach_hang),
    updated_at = now(), updated_by = 'xu_ly_mo_coi_20261016'
  FROM _d d WHERE d.id = q.id AND d.hanh_dong = 'CAP_NHAT'
  RETURNING q.*)
INSERT INTO shared.quota_chuan_hoa_log (buoc, bang, ban_ghi_id, truoc, sau)
SELECT 'xu_ly_mo_coi_cap_nhat', 'quota_thau', d.id, to_jsonb(t), to_jsonb(d) FROM doi d JOIN truoc t ON t.id = d.id;

COMMIT;
