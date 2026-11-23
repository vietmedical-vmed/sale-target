-- Rollback 20261123110000_thong_tin_thau_cu.sql: bỏ dòng đợt thầu cũ (loai 'cu') trong
-- shared.dot_thau, trả ràng buộc + upsert_dot_thau / delete_dot_thau / chay_gan_quota_hop_dong /
-- goi_y_dot_tu_hop_dong về bản trước, xoá app_sale.dien_dot_cu_tu_hop_dong.
-- Thông tin thầu cũ người dùng đã sửa tay sẽ mất: sao lưu trước nếu cần
--   select * from shared.dot_thau where loai = 'cu';
-- Deploy lại web bản trước TRƯỚC khi chạy (bản mới gửi loai 'cu' lên upsert_dot_thau).
begin;

delete from shared.dot_thau where loai = 'cu';
alter table shared.dot_thau drop constraint if exists dot_thau_cu_mot_dot;
alter table shared.dot_thau drop constraint dot_thau_loai_check;
alter table shared.dot_thau add constraint dot_thau_loai_check
  check (loai = any (array['chinh'::text, 'bo_sung'::text]));

CREATE OR REPLACE FUNCTION public.upsert_dot_thau(p_rows jsonb, p_bu text, p_mien text, p_ps text, p_groups text[], p_actor text DEFAULT NULL::text)
 RETURNS integer
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'shared'
AS $function$
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

    IF v_loai NOT IN ('chinh', 'bo_sung') THEN
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

    v_dot := nullif(r->>'dot', '')::int;
    IF v_dot IS NULL THEN
      SELECT coalesce(max(d.dot), 0) + 1 INTO v_dot
      FROM   shared.dot_thau d
      WHERE  d.nam_tai_chinh = v_fy AND d.ps = v_ps
        AND  d.ma_khach_hang = v_cust AND d.nhom_san_pham = v_grp
        AND  d.loai = v_loai;
    END IF;

    -- Đợt mới chỉ tạo cùng quota (qua luu_quota_thau), không tạo đợt rỗng.
    IF coalesce(current_setting('app.cho_tao_dot', true), '') <> '1' AND NOT EXISTS (
         SELECT 1 FROM shared.dot_thau d
         WHERE d.nam_tai_chinh = v_fy AND d.ps = v_ps AND d.ma_khach_hang = v_cust
           AND d.nhom_san_pham = v_grp AND d.loai = v_loai AND d.dot = v_dot) THEN
      RAISE EXCEPTION 'dot_moi_phai_kem_quota: thêm đợt trong bảng nhập quota, điền tháng thầu, hiệu lực và quota rồi lưu một lần'
        USING ERRCODE = '22023';
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

CREATE OR REPLACE FUNCTION public.delete_dot_thau(p_fy text, p_ps_row text, p_cust text, p_grp text, p_loai text, p_dot integer, p_bu text, p_mien text, p_ps text, p_groups text[])
 RETURNS integer
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'shared'
AS $function$
DECLARE
  v_cust text := coalesce(p_cust, '');
  v_grp  text := coalesce(p_grp, '');
  v_n    int;
  v_keys jsonb;
BEGIN
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
       || jsonb_build_object('luc', now(), 'nguoi', p_actor);
  insert into shared.app_config (key, value, updated_at)
  values ('gan_quota_hop_dong_lan_cuoi', v, now())
  on conflict (key) do update set value = excluded.value, updated_at = excluded.updated_at;
  return v::json;
end;
$$;

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
    and d.loai in ('chinh', 'bo_sung')
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

drop function if exists app_sale.dien_dot_cu_tu_hop_dong(text);

revoke all on function app_sale.chay_gan_quota_hop_dong(text) from public, anon, authenticated;
grant execute on function app_sale.chay_gan_quota_hop_dong(text) to service_role;
revoke all on function app_sale.goi_y_dot_tu_hop_dong(text) from public, anon, authenticated;
grant execute on function app_sale.goi_y_dot_tu_hop_dong(text) to service_role;

commit;
