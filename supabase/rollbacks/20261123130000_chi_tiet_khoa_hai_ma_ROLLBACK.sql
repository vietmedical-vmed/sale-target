-- Rollback 20261123130000_chi_tiet_khoa_hai_ma.sql: trả chi_tiet_khoa_hop_dong về bản 20261119100000.
begin;

CREATE OR REPLACE FUNCTION app_sale.chi_tiet_khoa_hop_dong(p_ma_kh text, p_khoa text, p_nam text DEFAULT 'FY26'::text)
 RETURNS json
 LANGUAGE sql
 STABLE
 SET search_path TO 'shared', 'app_sale', 'pg_temp'
 SET statement_timeout TO '60s'
AS $function$
with q as (
  select * from app_sale.quota_theo_khoa(p_nam) q
  where q.ma_khach_hang = p_ma_kh and q.khoa_sp = p_khoa
),
h as (
  select h.*, v.ten_hang_hoa, v.don_gia, v.so_bao_gia, v.so_goi_thau
  from app_sale.hop_dong_theo_khoa() h
  left join app_sale.v_hop_dong_dong v on v.contract_item_id = h.contract_item_id
  where h.ma_kh = p_ma_kh and h.khoa_sp = p_khoa
),
l as (
  select x.* from app_sale.quota_hop_dong x
  where x.khoa_sp = p_khoa
    and (x.quota_id in (select quota_id from q) or x.contract_item_id in (select contract_item_id from h))
)
select json_build_object(
  'quota', (select coalesce(json_agg(json_build_object(
      'quotaId', q.quota_id, 'ps', q.ps, 'loai', q.loai, 'dot', q.dot, 'thang', q.thang_thau,
      'tt', q.tt, 'nhom', q.nhom_san_pham, 'sp', q.san_pham, 'maSp', q.ma_san_pham,
      'soLuong', q.so_luong, 'donGia', q.don_gia, 'sl', q.sl, 'bung', q.bung,
      'dinhMuc', q.dinh_muc, 'nKhoaBo', q.n_khoa_bo
    ) order by q.ps, q.thang_thau nulls last, q.loai, q.dot), '[]'::json) from q),
  'hopDong', (select coalesce(json_agg(json_build_object(
      'itemId', h.contract_item_id, 'maHd', h.ma_hd, 'soHd', h.so_hd, 'maChung', h.ma_chung,
      'ten', h.ten_hang_hoa, 'ps', h.ps, 'ngayKy', h.ngay_ky, 'thoiHan', h.thoi_han,
      'cuaSo', h.cua_so, 'soLuong', h.so_luong, 'conLai', h.sl_con_lai_dau_fy,
      'donGia', h.don_gia, 'thanhTien', h.thanh_tien,
      'soBaoGia', h.so_bao_gia, 'soGoiThau', h.so_goi_thau
    ) order by h.cua_so, h.ngay_ky, h.contract_item_id), '[]'::json) from h),
  'lienKet', (select coalesce(json_agg(json_build_object(
      'id', l.id, 'quotaId', l.quota_id, 'itemId', l.contract_item_id, 'maHd', l.ma_hd,
      'cuaSo', l.cua_so, 'slHd', l.sl_hd, 'slQuota', l.sl_quota, 'cachGan', l.cach_gan,
      'nguoi', l.nguoi_gan, 'luc', l.gan_luc
    ) order by l.id), '[]'::json) from l)
);
$function$;

revoke all on function app_sale.chi_tiet_khoa_hop_dong(text, text, text) from public, anon, authenticated;
grant execute on function app_sale.chi_tiet_khoa_hop_dong(text, text, text) to service_role;

commit;
