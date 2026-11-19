-- Tab Kiểm tra thông tin thầu, popup chi tiết khoá: "Chuyển 1.4 → thầu chính theo HĐ".
-- Quy tắc R1 (user duyệt 18/11): HĐ ký trong năm tài chính thì quota phải là thầu chính / bổ
-- sung, đợt có tháng thầu = tháng ký, hiệu lực = số tháng từ tháng ký tới tháng hết hạn HĐ.
--
-- app_sale.chuyen_quota_1_4_theo_hop_dong(quota, dòng HĐ, khoá, SL, loại đích, đợt đích, tháng, HL):
--   - nguồn phải là quota 1.4 (loai 'cu'), không phải bộ bung linh kiện; dòng HĐ phải cùng khoá
--     và ký trong năm (cửa sổ 'trong' của app_sale.hop_dong_theo_khoa);
--   - đợt đích: p_dot_dich có sẵn (phải đủ tháng + hiệu lực, đã tới tháng thầu), hoặc null = tạo đợt mới số kế tiếp
--     (tháng mặc định = tháng ký, HL mặc định = tháng ký → tháng hết hạn HĐ);
--   - chuyển SL như migration V3: cộng vào dòng đích cùng khoá duy nhất nếu có, không thì đổi
--     loại/đợt nguyên dòng hoặc tách dòng; dòng nguồn hết SL thì xoá;
--   - xoá liên kết quota ↔ HĐ cửa sổ 'quota_1_4' của dòng nguồn (đã sai cửa sổ). Edge chạy lại
--     app_sale.chay_gan_quota_hop_dong() ngay sau để gắn lại theo cửa sổ trong năm.
--   - mọi dòng bị chạm ghi app_sale.quota_chuan_hoa_log buoc 'app_chuyen_1_4_theo_hd'.
-- Kế hoạch (sale_target) không đổi. Rollback:
-- supabase/rollbacks/20261119110000_chuyen_1_4_theo_hop_dong_ROLLBACK.sql

begin;

create or replace function app_sale.chuyen_quota_1_4_theo_hop_dong(
  p_quota_id bigint,
  p_contract_item_id integer,
  p_khoa text,
  p_sl numeric,
  p_loai_dich text,
  p_dot_dich integer,
  p_thang text,
  p_hieu_luc numeric,
  p_nguoi text
)
returns json
language plpgsql
volatile
set search_path = shared, app_sale, pg_temp
set statement_timeout = '60s'
as $$
declare
  b constant text := 'app_chuyen_1_4_theo_hd';
  src shared.quota_thau;
  dst shared.quota_thau;
  moi shared.quota_thau;
  d shared.dot_thau;
  h record;
  v_bung boolean;
  v_dot int;
  v_thang text;
  v_hl numeric;
  v_tao_dot boolean := false;
  v_dich_id bigint;
  v_xoa_lk int;
begin
  if p_loai_dich not in ('chinh', 'bo_sung') then raise exception 'loai_dich_khong_hop_le'; end if;
  if p_sl is null or p_sl <= 0 then raise exception 'sl_khong_hop_le'; end if;

  select * into src from shared.quota_thau where id = p_quota_id for update;
  if not found then raise exception 'khong_tim_thay_quota'; end if;
  if src.loai <> 'cu' then raise exception 'quota_khong_phai_1_4'; end if;
  if src.trang_thai <> 'chinh_thuc' then raise exception 'quota_chua_chinh_thuc'; end if;
  if p_sl > src.so_luong then raise exception 'sl_vuot_quota: còn %', src.so_luong; end if;

  select bool_or(q.bung) into v_bung
  from app_sale.quota_theo_khoa(src.nam_tai_chinh) q
  where q.quota_id = src.id and q.khoa_sp = p_khoa;
  if v_bung is null then raise exception 'quota_khong_thuoc_khoa'; end if;
  if v_bung then raise exception 'bo_bung_linh_kien_lam_tay'; end if;

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
    if d.thang_thau > coalesce((select value #>> '{}' from shared.app_config where key = 'current_month'),
                               to_char(now() at time zone 'Asia/Ho_Chi_Minh', 'YYYY-MM')) then
      raise exception 'dot_dich_chua_toi_thang_thau';
    end if;
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

  -- ---- chuyển SL (như migration V3) ----
  select * into dst from shared.quota_thau q
  where q.nam_tai_chinh = src.nam_tai_chinh and q.ps = src.ps and q.ma_khach_hang = src.ma_khach_hang
    and q.nhom_san_pham = src.nhom_san_pham and q.bo_vat_tu is not distinct from src.bo_vat_tu
    and q.san_pham = src.san_pham and q.don_gia = src.don_gia
    and q.loai = p_loai_dich and q.dot = v_dot and q.id <> src.id
  for update;
  if found then
    update shared.quota_thau set so_luong = so_luong + p_sl, updated_at = now(), updated_by = coalesce(p_nguoi, b)
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
    update shared.quota_thau set loai = p_loai_dich, dot = v_dot, updated_at = now(), updated_by = coalesce(p_nguoi, b)
    where id = src.id returning * into moi;
    insert into app_sale.quota_chuan_hoa_log (buoc, bang, ban_ghi_id, truoc, sau)
    values (b, 'quota_thau', src.id, to_jsonb(src), to_jsonb(moi));
    v_dich_id := src.id;
  else
    update shared.quota_thau set so_luong = so_luong - p_sl, updated_at = now(), updated_by = coalesce(p_nguoi, b)
    where id = src.id returning * into moi;
    insert into app_sale.quota_chuan_hoa_log (buoc, bang, ban_ghi_id, truoc, sau)
    values (b, 'quota_thau', src.id, to_jsonb(src), to_jsonb(moi));
    insert into shared.quota_thau
      (nam_tai_chinh, ps, ma_khach_hang, nhom_san_pham, bo_vat_tu, san_pham, don_gia, loai, dot,
       so_luong, bu, mien, khach_hang, updated_by, trang_thai, nguon, ma_san_pham)
    values (src.nam_tai_chinh, src.ps, src.ma_khach_hang, src.nhom_san_pham, src.bo_vat_tu, src.san_pham,
            src.don_gia, p_loai_dich, v_dot, p_sl, src.bu, src.mien, src.khach_hang, coalesce(p_nguoi, b),
            src.trang_thai, b, src.ma_san_pham)
    returning * into moi;
    insert into app_sale.quota_chuan_hoa_log (buoc, bang, ban_ghi_id, truoc, sau)
    values (b, 'quota_thau', moi.id, null, to_jsonb(moi));
    v_dich_id := moi.id;
  end if;

  -- liên kết cửa sổ 1.4 của dòng nguồn đã sai cửa sổ → bỏ (dòng bị xoá thì FK cascade đã bỏ)
  delete from app_sale.quota_hop_dong
  where cua_so = 'quota_1_4' and quota_id in (src.id, v_dich_id);
  get diagnostics v_xoa_lk = row_count;

  return json_build_object(
    'quotaIdDich', v_dich_id, 'loai', p_loai_dich, 'dot', v_dot, 'thang', v_thang,
    'hieuLuc', v_hl, 'taoDotMoi', v_tao_dot, 'sl', p_sl, 'xoaLienKet', v_xoa_lk
  );
end;
$$;

revoke all on function app_sale.chuyen_quota_1_4_theo_hop_dong(bigint, integer, text, numeric, text, integer, text, numeric, text)
  from public, anon, authenticated;
grant execute on function app_sale.chuyen_quota_1_4_theo_hop_dong(bigint, integer, text, numeric, text, integer, text, numeric, text)
  to service_role;

commit;
