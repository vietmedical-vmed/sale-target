-- Thông tin thầu cũ (Quota 1.4) theo định dạng đợt thầu chính / bổ sung: tháng thầu + hiệu lực.
--
-- Thầu cũ trước đây không có dòng nào trong shared.dot_thau (quota 'cu' luôn dot = 1, tính đủ
-- vào on hand). Nay mỗi nhóm KH × nhóm SP × PS có quota thầu cũ được MỘT dòng dot_thau
-- loai = 'cu', dot = 1, chỉ để mang thông tin. Cách tính quota KHÔNG đổi: lib/quota.js,
-- quota_theo_khoa, các view app_ccdc / v_quota_thau_xuat vẫn xử lý 'cu' riêng (không theo
-- tháng thầu / hiệu lực).
--
-- 1. dot_thau_loai_check nhận 'cu'; thêm CHECK thầu cũ chỉ có đợt 1.
-- 2. upsert_dot_thau nhận 'cu' (ép dot = 1). Dòng thầu cũ mới được tạo khi nhóm đã có quota
--    thầu cũ (quota có sẵn, đợt chỉ mang thông tin).
-- 3. delete_dot_thau từ chối 'cu' (xoá đợt = xoá quota của đợt; quota thầu cũ sửa trong bảng nhập).
-- 4. app_sale.dien_dot_cu_tu_hop_dong(p_nam): điền tháng thầu / hiệu lực thầu cũ theo HĐ đã
--    liên kết (app_sale.quota_hop_dong, cửa sổ quota_1_4). Nhóm có nhiều HĐ: lấy HĐ có giá trị
--    liên kết lớn nhất, hoà thì ký gần nhất. Tháng = tháng ký; hiệu lực = số tháng từ tháng ký
--    tới tháng hết hạn HĐ (1..120), như goi_y_dot_tu_hop_dong / quy tắc R1. Nhóm chưa liên kết
--    được thì tạo dòng trống → hiện ở bước 1 tab Kiểm tra thông tin thầu.
--    Chỉ ghi đè dòng do hàm này tạo (updated_by = 'tu_dong_hop_dong') hoặc dòng còn trống;
--    người dùng sửa tay (upsert_dot_thau ghi updated_by = người sửa) thì giữ nguyên.
-- 5. chay_gan_quota_hop_dong gọi thêm hàm (4) sau khi gắn liên kết (cron đêm + nút admin).
-- 6. goi_y_dot_tu_hop_dong gợi ý cả thầu cũ thiếu thông tin (chỉ HĐ ký trước năm tài chính).
-- Rollback: supabase/rollbacks/20261123110000_thong_tin_thau_cu_ROLLBACK.sql

begin;

-- ---------- 1. ràng buộc ----------
alter table shared.dot_thau drop constraint dot_thau_loai_check;
alter table shared.dot_thau add constraint dot_thau_loai_check
  check (loai = any (array['cu'::text, 'chinh'::text, 'bo_sung'::text]));
alter table shared.dot_thau add constraint dot_thau_cu_mot_dot
  check (loai <> 'cu' or dot = 1);

-- ---------- 2. upsert_dot_thau ----------
create or replace function public.upsert_dot_thau(p_rows jsonb, p_bu text, p_mien text, p_ps text, p_groups text[], p_actor text default null::text)
 returns integer
 language plpgsql
 security definer
 set search_path to 'public', 'shared'
as $function$
DECLARE
  r      jsonb;
  v_bu   text;
  v_mien text;
  v_fy   text;
  v_ps   text;
  v_cust text;
  v_grp  text;
  v_loai text;
  v_dot  int;
  v_thang text;
  v_tg   numeric;
  v_done int := 0;
BEGIN
  FOR r IN SELECT * FROM jsonb_array_elements(coalesce(p_rows, '[]'::jsonb))
  LOOP
    v_fy   := r->>'fy';
    v_ps   := r->>'ps';
    v_cust := coalesce(r->>'custId', '');
    v_grp  := coalesce(r->>'grp', '');
    v_loai := r->>'loai';
    v_thang := nullif(r->>'thang', '');

    IF v_loai IS NULL OR v_loai NOT IN ('cu', 'chinh', 'bo_sung') THEN
      RAISE EXCEPTION 'loai_khong_hop_le: %', v_loai USING ERRCODE = '22023';
    END IF;
    IF v_thang IS NOT NULL AND v_thang !~ '^\d{4}-\d{2}$' THEN
      RAISE EXCEPTION 'thang_sai_dinh_dang: % (cần yyyy-mm)', v_thang USING ERRCODE = '22023';
    END IF;

    SELECT s.bu, s.mien INTO v_bu, v_mien
    FROM shared.scope_nhom_sp(v_fy, v_ps, v_cust, v_grp, p_bu, p_mien, p_ps, p_groups) s;

    IF NOT FOUND THEN
      RAISE EXCEPTION 'out_of_scope: nhóm % / KH % / PS % nằm ngoài phạm vi quyền hoặc không tồn tại',
                      v_grp, v_cust, v_ps USING ERRCODE = '42501';
    END IF;

    -- Thầu cũ chỉ có 1 đợt.
    v_dot := CASE WHEN v_loai = 'cu' THEN 1 ELSE nullif(r->>'dot', '')::int END;
    IF v_dot IS NULL THEN
      SELECT coalesce(max(d.dot), 0) + 1 INTO v_dot
      FROM   shared.dot_thau d
      WHERE  d.nam_tai_chinh = v_fy AND d.ps = v_ps
        AND  d.ma_khach_hang = v_cust AND d.nhom_san_pham = v_grp
        AND  d.loai = v_loai;
    END IF;

    IF NOT EXISTS (
         SELECT 1 FROM shared.dot_thau d
         WHERE d.nam_tai_chinh = v_fy AND d.ps = v_ps AND d.ma_khach_hang = v_cust
           AND d.nhom_san_pham = v_grp AND d.loai = v_loai AND d.dot = v_dot) THEN
      IF v_loai = 'cu' THEN
        -- Thầu cũ: quota có sẵn, đợt chỉ mang tháng thầu / hiệu lực.
        IF NOT EXISTS (
             SELECT 1 FROM shared.quota_thau q
             WHERE q.nam_tai_chinh = v_fy AND q.ps = v_ps AND q.ma_khach_hang = v_cust
               AND q.nhom_san_pham = v_grp AND q.loai = 'cu' AND q.so_luong > 0) THEN
          RAISE EXCEPTION 'dot_moi_phai_kem_quota: nhóm chưa có quota thầu cũ — nhập quota thầu cũ trước'
            USING ERRCODE = '22023';
        END IF;
      ELSIF coalesce(current_setting('app.cho_tao_dot', true), '') <> '1' THEN
        -- Đợt chính / bổ sung mới chỉ tạo cùng quota (qua luu_quota_thau), không tạo đợt rỗng.
        RAISE EXCEPTION 'dot_moi_phai_kem_quota: thêm đợt trong bảng nhập quota, điền tháng thầu, hiệu lực và quota rồi lưu một lần'
          USING ERRCODE = '22023';
      END IF;
    END IF;

    -- Bắt buộc tháng thầu + hiệu lực (số tháng). Không gửi thoiGian = giữ hiệu lực đang có.
    IF r ? 'thoiGian' THEN
      v_tg := nullif(r->>'thoiGian', '')::numeric;
    ELSE
      SELECT d.thoi_gian INTO v_tg FROM shared.dot_thau d
      WHERE d.nam_tai_chinh = v_fy AND d.ps = v_ps AND d.ma_khach_hang = v_cust
        AND d.nhom_san_pham = v_grp AND d.loai = v_loai AND d.dot = v_dot;
    END IF;
    IF v_thang IS NULL THEN
      RAISE EXCEPTION 'dot_thieu_thong_tin: đợt thầu phải có tháng thầu (yyyy-mm)' USING ERRCODE = '22023';
    END IF;
    IF v_tg IS NULL OR v_tg <= 0 OR v_tg > 120 OR v_tg <> trunc(v_tg) THEN
      RAISE EXCEPTION 'dot_thieu_thong_tin: đợt thầu phải có hiệu lực (số tháng nguyên, 1–120)' USING ERRCODE = '22023';
    END IF;

    INSERT INTO shared.dot_thau
      (nam_tai_chinh, bu, mien, ps, ma_khach_hang, nhom_san_pham,
       loai, dot, thang_thau, thoi_gian, updated_by)
    VALUES
      (v_fy, v_bu, v_mien, v_ps, v_cust, v_grp,
       v_loai, v_dot, v_thang, v_tg, p_actor)
    ON CONFLICT (nam_tai_chinh, ps, ma_khach_hang, nhom_san_pham, loai, dot)
    DO UPDATE SET
      trang_thai = 'chinh_thuc',
      thang_thau = EXCLUDED.thang_thau,
      thoi_gian  = EXCLUDED.thoi_gian,
      updated_at = now(),
      updated_by = p_actor;

    v_done := v_done + 1;
  END LOOP;

  RETURN v_done;
END;
$function$;

-- ---------- 3. delete_dot_thau ----------
create or replace function public.delete_dot_thau(p_fy text, p_ps_row text, p_cust text, p_grp text, p_loai text, p_dot integer, p_bu text, p_mien text, p_ps text, p_groups text[])
 returns integer
 language plpgsql
 security definer
 set search_path to 'public', 'shared'
as $function$
DECLARE
  v_cust text := coalesce(p_cust, '');
  v_grp  text := coalesce(p_grp, '');
  v_n    int;
  v_keys jsonb;
BEGIN
  -- Xoá đợt kéo theo xoá quota của đợt: thầu cũ không xoá theo đường này.
  IF p_loai IS NULL OR p_loai NOT IN ('chinh', 'bo_sung') THEN
    RAISE EXCEPTION 'loai_khong_hop_le: %', p_loai USING ERRCODE = '22023';
  END IF;

  PERFORM 1 FROM shared.scope_nhom_sp(p_fy, p_ps_row, v_cust, v_grp,
                                      p_bu, p_mien, p_ps, p_groups);
  IF NOT FOUND THEN
    RAISE EXCEPTION 'out_of_scope: nhóm % / KH % / PS % nằm ngoài phạm vi quyền hoặc không tồn tại',
                    v_grp, v_cust, p_ps_row USING ERRCODE = '42501';
  END IF;

  WITH deleted_quotas AS (
    DELETE FROM shared.quota_thau q
    WHERE q.nam_tai_chinh = p_fy AND q.ps = p_ps_row
      AND q.ma_khach_hang = v_cust AND q.nhom_san_pham = v_grp
      AND q.loai = p_loai AND q.dot = p_dot
    RETURNING q.bo_vat_tu, q.san_pham
  )
  SELECT jsonb_agg(DISTINCT jsonb_build_object(
    'fy', p_fy, 'ps', p_ps_row, 'cust', v_cust, 'grp', v_grp,
    'mset', bo_vat_tu, 'prod', san_pham
  ))
  FROM deleted_quotas INTO v_keys;

  DELETE FROM shared.dot_thau d
  WHERE d.nam_tai_chinh = p_fy AND d.ps = p_ps_row
    AND d.ma_khach_hang = v_cust AND d.nhom_san_pham = v_grp
    AND d.loai = p_loai AND d.dot = p_dot;

  GET DIAGNOSTICS v_n = ROW_COUNT;

  RETURN v_n;
END;
$function$;

-- ---------- 4. điền thầu cũ theo HĐ đã liên kết ----------
create or replace function app_sale.dien_dot_cu_tu_hop_dong(p_nam text default 'FY26')
returns json
language plpgsql
volatile
set search_path = shared, app_sale, pg_temp
set statement_timeout = '60s'
as $$
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
$$;

-- ---------- 5. chạy cùng lần gắn quota ↔ HĐ ----------
create or replace function app_sale.chay_gan_quota_hop_dong(p_actor text default 'cron')
returns json
language plpgsql
volatile
set search_path = shared, app_sale, pg_temp
as $$
declare
  v jsonb;
begin
  if not pg_try_advisory_xact_lock(hashtext('app_sale.gan_quota_hop_dong')) then
    return json_build_object('dang_chay', true);
  end if;
  v := app_sale.gan_quota_hop_dong_tu_dong()::jsonb
       || jsonb_build_object('dot_cu', app_sale.dien_dot_cu_tu_hop_dong()::jsonb)
       || jsonb_build_object('luc', now(), 'nguoi', p_actor);
  insert into shared.app_config (key, value, updated_at)
  values ('gan_quota_hop_dong_lan_cuoi', v, now())
  on conflict (key) do update set value = excluded.value, updated_at = excluded.updated_at;
  return v::json;
end;
$$;

-- ---------- 6. gợi ý theo HĐ: thêm thầu cũ ----------
create or replace function app_sale.goi_y_dot_tu_hop_dong(p_nam text default 'FY26')
returns json
language sql
stable
set search_path = shared, app_sale, pg_temp
set statement_timeout = '60s'
as $$
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
$$;

revoke all on function app_sale.dien_dot_cu_tu_hop_dong(text) from public, anon, authenticated;
grant execute on function app_sale.dien_dot_cu_tu_hop_dong(text) to service_role;
-- create or replace giữ quyền cũ; nhắc lại cho chắc (xem memory drop-function-mat-quyen).
revoke all on function app_sale.chay_gan_quota_hop_dong(text) from public, anon, authenticated;
grant execute on function app_sale.chay_gan_quota_hop_dong(text) to service_role;
revoke all on function app_sale.goi_y_dot_tu_hop_dong(text) from public, anon, authenticated;
grant execute on function app_sale.goi_y_dot_tu_hop_dong(text) to service_role;

-- Điền lần đầu.
select app_sale.dien_dot_cu_tu_hop_dong('FY26');

commit;
