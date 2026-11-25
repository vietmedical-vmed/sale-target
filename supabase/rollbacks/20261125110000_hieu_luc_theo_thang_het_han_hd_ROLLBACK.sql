-- Rollback 20261125110000_hieu_luc_theo_thang_het_han_hd: trả HL về giá trị trước và
-- khôi phục 3 hàm về công thức cũ (HL = tháng hết hạn − tháng ký).
-- Chỉ trả những đợt mà HL hiện tại vẫn đúng giá trị migration đã ghi (chưa bị sửa sau đó).
update shared.dot_thau d set thoi_gian = (l.truoc->>'thoi_gian')::numeric, updated_at = now()
from app_sale.quota_chuan_hoa_log l
where l.buoc = 'hl_theo_thang_het_han_hd_20261125' and l.bang = 'shared.dot_thau'
  and d.id = l.ban_ghi_id and d.thoi_gian = (l.sau->>'thoi_gian')::numeric;
delete from app_sale.quota_chuan_hoa_log where buoc = 'hl_theo_thang_het_han_hd_20261125';

CREATE OR REPLACE FUNCTION app_sale.dien_dot_cu_tu_hop_dong(p_nam text DEFAULT 'FY26'::text)
 RETURNS json
 LANGUAGE plpgsql
 SET search_path TO 'shared', 'app_sale', 'pg_temp'
 SET statement_timeout TO '60s'
AS $function$
declare
  v_nhom int;
  v_co_hd int;
  v_them int;
  v_sua int;
  v_xoa int;
begin
  drop table if exists _dien_dot_cu;
  create temp table _dien_dot_cu on commit drop as
  with g as (
    select q.nam_tai_chinh as fy, q.ps, q.ma_khach_hang as kh, q.nhom_san_pham as grp,
      min(q.bu) as bu, min(q.mien) as mien
    from shared.quota_thau q
    where q.nam_tai_chinh = p_nam and q.loai = 'cu' and q.so_luong > 0 and q.trang_thai = 'chinh_thuc'
    group by 1, 2, 3, 4
  ),
  l as (
    select q.nam_tai_chinh as fy, q.ps, q.ma_khach_hang as kh, q.nhom_san_pham as grp,
      c.ma_hd, c.ngay_ky, c.thoi_han, sum(x.sl_quota * q.don_gia) as tien
    from app_sale.quota_hop_dong x
    join shared.quota_thau q on q.id = x.quota_id and q.loai = 'cu' and q.nam_tai_chinh = p_nam
    join app_contract.contract_contracts c on c.ma_hd = x.ma_hd
    where x.cua_so = 'quota_1_4' and c.ngay_ky is not null
    group by 1, 2, 3, 4, 5, 6, 7
  ),
  chon as (
    select distinct on (fy, ps, kh, grp) *
    from l
    order by fy, ps, kh, grp, tien desc nulls last, ngay_ky desc, ma_hd
  )
  select g.*, c.ma_hd,
    to_char(c.ngay_ky, 'YYYY-MM') as thang,
    case when c.thoi_han > c.ngay_ky then
      least(120, greatest(1,
        (extract(year from c.thoi_han) * 12 + extract(month from c.thoi_han))
        - (extract(year from c.ngay_ky) * 12 + extract(month from c.ngay_ky))))::numeric end as hl
  from g left join chon c using (fy, ps, kh, grp);

  select count(*), count(ma_hd) into v_nhom, v_co_hd from _dien_dot_cu;

  -- Dòng tự động (hoặc còn trống): cập nhật theo HĐ hiện tại; không còn HĐ thì để trống.
  update shared.dot_thau d set
    thang_thau = x.thang, thoi_gian = x.hl,
    nguon = case when x.ma_hd is not null then 'hop_dong:' || x.ma_hd end,
    trang_thai = 'chinh_thuc', updated_at = now(), updated_by = 'tu_dong_hop_dong'
  from _dien_dot_cu x
  where d.nam_tai_chinh = x.fy and d.ps = x.ps and d.ma_khach_hang = x.kh
    and d.nhom_san_pham = x.grp and d.loai = 'cu' and d.dot = 1
    and (d.updated_by = 'tu_dong_hop_dong'
         or (x.ma_hd is not null and (d.thang_thau is null or d.thoi_gian is null)))
    and (d.thang_thau, d.thoi_gian, d.trang_thai) is distinct from (x.thang, x.hl, 'chinh_thuc');
  get diagnostics v_sua = row_count;

  insert into shared.dot_thau
    (nam_tai_chinh, ps, ma_khach_hang, nhom_san_pham, loai, dot, thang_thau, thoi_gian,
     bu, mien, trang_thai, nguon, updated_at, updated_by)
  select x.fy, x.ps, x.kh, x.grp, 'cu', 1, x.thang, x.hl, x.bu, x.mien, 'chinh_thuc',
    case when x.ma_hd is not null then 'hop_dong:' || x.ma_hd end, now(), 'tu_dong_hop_dong'
  from _dien_dot_cu x
  where not exists (
    select 1 from shared.dot_thau d
    where d.nam_tai_chinh = x.fy and d.ps = x.ps and d.ma_khach_hang = x.kh
      and d.nhom_san_pham = x.grp and d.loai = 'cu' and d.dot = 1);
  get diagnostics v_them = row_count;

  -- Dòng tự động mà nhóm không còn quota thầu cũ: bỏ (dòng người dùng sửa tay thì giữ).
  delete from shared.dot_thau d
  where d.nam_tai_chinh = p_nam and d.loai = 'cu' and d.updated_by = 'tu_dong_hop_dong'
    and not exists (
      select 1 from _dien_dot_cu x
      where x.fy = d.nam_tai_chinh and x.ps = d.ps and x.kh = d.ma_khach_hang and x.grp = d.nhom_san_pham);
  get diagnostics v_xoa = row_count;

  return json_build_object('nhom', v_nhom, 'coHd', v_co_hd, 'them', v_them, 'sua', v_sua, 'xoa', v_xoa);
end;
$function$;

CREATE OR REPLACE FUNCTION app_sale.goi_y_dot_tu_hop_dong(p_nam text DEFAULT 'FY26'::text)
 RETURNS json
 LANGUAGE sql
 STABLE
 SET search_path TO 'shared', 'app_sale', 'pg_temp'
 SET statement_timeout TO '60s'
AS $function$
with thieu as (
  select d.nam_tai_chinh, d.ps, d.ma_khach_hang, d.nhom_san_pham, d.loai, d.dot
  from shared.dot_thau d
  where d.nam_tai_chinh = p_nam
    and d.trang_thai = 'chinh_thuc'
    and d.loai in ('cu', 'chinh', 'bo_sung')
    and (coalesce(d.thang_thau, '') !~ '^\d{4}-\d{2}$'
         or d.thoi_gian is null or d.thoi_gian <> trunc(d.thoi_gian)
         or d.thoi_gian not between 1 and 120)
),
qk as (
  select distinct t.ps, t.ma_khach_hang, t.nhom_san_pham, t.loai, t.dot, q.khoa_sp
  from thieu t
  join app_sale.quota_theo_khoa(p_nam) q
    on q.ps = t.ps and q.ma_khach_hang = t.ma_khach_hang
   and q.nhom_san_pham = t.nhom_san_pham and q.loai = t.loai and q.dot = t.dot
),
so_khoa as (
  select ps, ma_khach_hang, nhom_san_pham, loai, dot, count(*) as n
  from qk group by 1, 2, 3, 4, 5
),
hd as (
  select qk.ps, qk.ma_khach_hang, qk.nhom_san_pham, qk.loai, qk.dot,
    h.so_hd, min(h.ngay_ky) as ngay_ky, max(h.thoi_han) as thoi_han,
    count(distinct qk.khoa_sp) as n_khop
  from qk
  join app_sale.v_hop_dong_dong h on h.ma_kh = qk.ma_khach_hang and h.khoa_sp = qk.khoa_sp
  where h.ngay_ky is not null
    -- thầu cũ (Quota 1.4) = HĐ ký trước năm tài chính (cùng mốc quota_theo_khoa)
    and (qk.loai <> 'cu' or h.ngay_ky < date '2026-04-01')
  group by 1, 2, 3, 4, 5, 6
),
chon as (
  select distinct on (ps, ma_khach_hang, nhom_san_pham, loai, dot) *
  from hd
  order by ps, ma_khach_hang, nhom_san_pham, loai, dot, n_khop desc, ngay_ky desc, so_hd
)
select coalesce(json_agg(json_build_object(
  'fy', p_nam, 'ps', c.ps, 'custId', c.ma_khach_hang, 'grp', c.nhom_san_pham,
  'loai', c.loai, 'dot', c.dot,
  'thang', to_char(c.ngay_ky, 'YYYY-MM'),
  'hieuLuc', case when c.thoi_han > c.ngay_ky then
    least(120, greatest(1,
      (extract(year from c.thoi_han) * 12 + extract(month from c.thoi_han))
      - (extract(year from c.ngay_ky) * 12 + extract(month from c.ngay_ky))))::int end,
  'soHd', c.so_hd, 'ngayKy', c.ngay_ky, 'thoiHan', c.thoi_han,
  'khop', c.n_khop, 'tong', s.n
)), '[]'::json)
from chon c
join so_khoa s using (ps, ma_khach_hang, nhom_san_pham, loai, dot);
$function$;

CREATE OR REPLACE FUNCTION app_sale.chuyen_quota_theo_hop_dong(p_quota_id bigint, p_contract_item_id integer, p_khoa text, p_sl numeric, p_sl_dich numeric, p_loai_dich text, p_dot_dich integer, p_thang text, p_hieu_luc numeric, p_nguoi text)
 RETURNS json
 LANGUAGE plpgsql
 SET search_path TO 'shared', 'app_sale', 'pg_temp'
 SET statement_timeout TO '60s'
AS $function$
declare
  src shared.quota_thau;
  dst shared.quota_thau;
  moi shared.quota_thau;
  d shared.dot_thau;
  h record;
  b text;
  v_bung boolean;
  v_tt text;
  v_thang_hien text;
  v_sl_dich numeric := coalesce(p_sl_dich, p_sl);
  v_dot int;
  v_thang text;
  v_hl numeric;
  v_tao_dot boolean := false;
  v_dich_id bigint;
  v_xoa_lk int;
begin
  if p_loai_dich not in ('chinh', 'bo_sung') then raise exception 'loai_dich_khong_hop_le'; end if;
  if p_sl is null or p_sl <= 0 or v_sl_dich <= 0 then raise exception 'sl_khong_hop_le'; end if;
  v_thang_hien := coalesce((select value #>> '{}' from shared.app_config where key = 'current_month'),
                           to_char(now() at time zone 'Asia/Ho_Chi_Minh', 'YYYY-MM'));

  select * into src from shared.quota_thau where id = p_quota_id for update;
  if not found then raise exception 'khong_tim_thay_quota'; end if;
  if src.trang_thai <> 'chinh_thuc' then raise exception 'quota_chua_chinh_thuc'; end if;
  if p_sl > src.so_luong then raise exception 'sl_vuot_quota: còn %', src.so_luong; end if;

  select bool_or(q.bung), max(q.tt) into v_bung, v_tt
  from app_sale.quota_theo_khoa(src.nam_tai_chinh) q
  where q.quota_id = src.id and q.khoa_sp = p_khoa;
  if v_bung is null then raise exception 'quota_khong_thuoc_khoa'; end if;
  if v_bung then raise exception 'bo_bung_linh_kien_lam_tay'; end if;
  if v_tt not in ('cu', 'up') then raise exception 'quota_khong_phai_1_4_hay_upcoming'; end if;
  b := case when v_tt = 'cu' then 'app_chuyen_1_4_theo_hd' else 'app_chuyen_up_theo_hd' end;

  select * into h from app_sale.hop_dong_theo_khoa() x
  where x.contract_item_id = p_contract_item_id and x.khoa_sp = p_khoa limit 1;
  if not found then raise exception 'khong_tim_thay_dong_hd'; end if;
  if h.cua_so is distinct from 'trong' then raise exception 'hd_khong_ky_trong_nam'; end if;
  if h.ma_kh is distinct from src.ma_khach_hang then raise exception 'hd_khac_khach_hang'; end if;

  -- ---- đợt đích ----
  if p_dot_dich is not null then
    select * into d from shared.dot_thau
    where nam_tai_chinh = src.nam_tai_chinh and ps = src.ps and ma_khach_hang = src.ma_khach_hang
      and nhom_san_pham = src.nhom_san_pham and loai = p_loai_dich and dot = p_dot_dich
      and trang_thai = 'chinh_thuc';
    if not found then raise exception 'khong_tim_thay_dot_dich'; end if;
    if coalesce(d.thang_thau, '') !~ '^\d{4}-\d{2}$' or d.thoi_gian is null then
      raise exception 'dot_dich_thieu_thang_hoac_hieu_luc';
    end if;
    -- HĐ đã ký: đợt đích chưa tới tháng thầu thì quota vẫn là upcoming → sai.
    if d.thang_thau > v_thang_hien then raise exception 'dot_dich_chua_toi_thang_thau'; end if;
    if src.loai = p_loai_dich and src.dot = d.dot then raise exception 'dot_dich_trung_dot_nguon'; end if;
    v_dot := d.dot;
    v_thang := d.thang_thau;
    v_hl := d.thoi_gian;
  else
    v_thang := coalesce(nullif(btrim(p_thang), ''), to_char(h.ngay_ky, 'YYYY-MM'));
    v_hl := coalesce(p_hieu_luc,
      case when h.thoi_han > h.ngay_ky then
        (extract(year from h.thoi_han) * 12 + extract(month from h.thoi_han))
        - (extract(year from h.ngay_ky) * 12 + extract(month from h.ngay_ky)) end);
    if v_thang !~ '^\d{4}-\d{2}$' then raise exception 'thang_khong_hop_le'; end if;
    if v_thang > v_thang_hien then raise exception 'thang_moi_chua_toi: %', v_thang; end if;
    if v_hl is null or v_hl <> trunc(v_hl) or v_hl not between 1 and 120 then
      raise exception 'hieu_luc_khong_hop_le';
    end if;
    select coalesce(max(x.dot), 0) + 1 into v_dot from (
      select dot from shared.dot_thau
      where nam_tai_chinh = src.nam_tai_chinh and ps = src.ps and ma_khach_hang = src.ma_khach_hang
        and nhom_san_pham = src.nhom_san_pham and loai = p_loai_dich
      union all
      select dot from shared.quota_thau
      where nam_tai_chinh = src.nam_tai_chinh and ps = src.ps and ma_khach_hang = src.ma_khach_hang
        and nhom_san_pham = src.nhom_san_pham and loai = p_loai_dich
    ) x;
    insert into shared.dot_thau
      (nam_tai_chinh, ps, ma_khach_hang, nhom_san_pham, loai, dot, thang_thau, thoi_gian, bu, mien,
       trang_thai, nguon, updated_at, updated_by)
    values (src.nam_tai_chinh, src.ps, src.ma_khach_hang, src.nhom_san_pham, p_loai_dich, v_dot,
            v_thang, v_hl, src.bu, src.mien, 'chinh_thuc', b, now(), coalesce(p_nguoi, b))
    returning * into d;
    insert into app_sale.quota_chuan_hoa_log (buoc, bang, ban_ghi_id, truoc, sau)
    values (b, 'dot_thau', d.id, null, to_jsonb(d));
    v_tao_dot := true;
  end if;

  -- ---- chuyển SL ----
  select * into dst from shared.quota_thau q
  where q.nam_tai_chinh = src.nam_tai_chinh and q.ps = src.ps and q.ma_khach_hang = src.ma_khach_hang
    and q.nhom_san_pham = src.nhom_san_pham and q.bo_vat_tu is not distinct from src.bo_vat_tu
    and q.san_pham = src.san_pham and q.don_gia = src.don_gia
    and q.loai = p_loai_dich and q.dot = v_dot and q.id <> src.id
  for update;
  if found then
    -- cộng vào dòng đích sẵn có
    update shared.quota_thau set so_luong = so_luong + v_sl_dich, updated_at = now(), updated_by = coalesce(p_nguoi, b)
    where id = dst.id returning * into moi;
    insert into app_sale.quota_chuan_hoa_log (buoc, bang, ban_ghi_id, truoc, sau)
    values (b, 'quota_thau', dst.id, to_jsonb(dst), to_jsonb(moi));
    v_dich_id := dst.id;
    if src.so_luong = p_sl then
      delete from shared.quota_thau where id = src.id;
      insert into app_sale.quota_chuan_hoa_log (buoc, bang, ban_ghi_id, truoc, sau)
      values (b, 'quota_thau', src.id, to_jsonb(src), null);
    else
      update shared.quota_thau set so_luong = so_luong - p_sl, updated_at = now(), updated_by = coalesce(p_nguoi, b)
      where id = src.id returning * into moi;
      insert into app_sale.quota_chuan_hoa_log (buoc, bang, ban_ghi_id, truoc, sau)
      values (b, 'quota_thau', src.id, to_jsonb(src), to_jsonb(moi));
    end if;
  elsif src.so_luong = p_sl then
    -- chuyển nguyên dòng (SL đích có thể khác)
    update shared.quota_thau
      set loai = p_loai_dich, dot = v_dot, so_luong = v_sl_dich, updated_at = now(), updated_by = coalesce(p_nguoi, b)
    where id = src.id returning * into moi;
    insert into app_sale.quota_chuan_hoa_log (buoc, bang, ban_ghi_id, truoc, sau)
    values (b, 'quota_thau', src.id, to_jsonb(src), to_jsonb(moi));
    v_dich_id := src.id;
  else
    -- tách dòng
    update shared.quota_thau set so_luong = so_luong - p_sl, updated_at = now(), updated_by = coalesce(p_nguoi, b)
    where id = src.id returning * into moi;
    insert into app_sale.quota_chuan_hoa_log (buoc, bang, ban_ghi_id, truoc, sau)
    values (b, 'quota_thau', src.id, to_jsonb(src), to_jsonb(moi));
    insert into shared.quota_thau
      (nam_tai_chinh, ps, ma_khach_hang, nhom_san_pham, bo_vat_tu, san_pham, don_gia, loai, dot,
       so_luong, bu, mien, khach_hang, updated_by, trang_thai, nguon, ma_san_pham)
    values (src.nam_tai_chinh, src.ps, src.ma_khach_hang, src.nhom_san_pham, src.bo_vat_tu, src.san_pham,
            src.don_gia, p_loai_dich, v_dot, v_sl_dich, src.bu, src.mien, src.khach_hang, coalesce(p_nguoi, b),
            src.trang_thai, b, src.ma_san_pham)
    returning * into moi;
    insert into app_sale.quota_chuan_hoa_log (buoc, bang, ban_ghi_id, truoc, sau)
    values (b, 'quota_thau', moi.id, null, to_jsonb(moi));
    v_dich_id := moi.id;
  end if;

  delete from app_sale.quota_hop_dong
  where cua_so = 'quota_1_4' and quota_id in (src.id, v_dich_id);
  get diagnostics v_xoa_lk = row_count;

  return json_build_object(
    'nguon', v_tt, 'quotaIdDich', v_dich_id, 'loai', p_loai_dich, 'dot', v_dot, 'thang', v_thang,
    'hieuLuc', v_hl, 'taoDotMoi', v_tao_dot, 'sl', p_sl, 'slDich', v_sl_dich, 'xoaLienKet', v_xoa_lk
  );
end;
$function$;
