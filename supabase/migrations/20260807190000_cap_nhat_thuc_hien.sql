-- ════════════════════════════════════════════════════════════════════════
-- Một lệnh duy nhất sau khi cập nhật hoá đơn + app tự biết có số mới
--
-- VẤN ĐỀ 1 — app không tự nhận số mới
-- App phát hiện dữ liệu thay đổi bằng rev = max(sale_target.updated_at), poll
-- 45 giây/lần. Nhưng map_hoadon_to_sale_target() chỉ ghi sl_thuc_hien, KHÔNG
-- đụng updated_at, và sale_target KHÔNG có trigger set_updated_at → rev không
-- đổi → người đang mở app vẫn thấy số cũ cho tới khi tự bấm Reload.
--   (Kiểm chứng: các dòng map vừa ghi lại vẫn giữ updated_at của lần import cũ.)
-- → Thêm updated_at = now() vào cả 2 câu UPDATE của hàm map.
--
-- VẤN ĐỀ 2 — phải nhớ chạy 2 lệnh
-- Sau mỗi lần đẩy hoa_don_bovattu phải chạy map rồi refresh matview báo cáo;
-- quên cái thứ hai thì báo cáo lệch số so với app mà không có dấu hiệu gì.
-- → Gói thành cap_nhat_thuc_hien(): pipeline chỉ gọi ĐÚNG MỘT lần.
--
-- Thân hàm map giữ nguyên logic của 20260807110000, chỉ thêm updated_at.
-- ════════════════════════════════════════════════════════════════════════

create or replace function public.map_hoadon_to_sale_target()
returns jsonb
language plpgsql
security definer
set search_path to 'public', 'shared', 'app_sale'
as $function$
declare
  v_months  text[];
  v_zeroed  int := 0;
  v_set     int := 0;
  v_matched int := 0;
  v_total   int := 0;
begin
  select array_agg(distinct thang_ke_hoach) into v_months from hoa_don_actual;
  if v_months is null then
    return jsonb_build_object('months', 0, 'zeroed', 0, 'set_rows', 0,
                              'matched_keys', 0, 'total_keys', 0, 'unmatched_keys', 0);
  end if;

  -- (1) Zero các tháng CÓ trong hoa_don. LƯU Ý: tháng không có trong hoa_don
  --     sẽ KHÔNG bị zero — số cũ trong sale_target còn nguyên.
  update sale_target set sl_thuc_hien = 0, updated_at = now()
   where thang_ke_hoach = any(v_months)
     and sl_thuc_hien is distinct from 0;
  get diagnostics v_zeroed = row_count;

  -- (2) Gộp theo khoá chuẩn hoá + tìm dòng plan id nhỏ nhất (LEFT JOIN LATERAL)
  create temp table _agg on commit drop as
  with a as (
    select thang_ke_hoach,
           lower(btrim(ps))            as ps_n,
           lower(btrim(ma_khach_hang)) as kh_n,
           lower(btrim(bo_vat_tu))     as bo_n,
           lower(btrim(san_pham))      as sp_n,
           sum(sl_thuc_hien)           as sl
      from hoa_don_actual
     group by 1, 2, 3, 4, 5
  )
  select a.*, t.id as target_id
    from a
    left join lateral (
      select s.id from sale_target s
       where s.thang_ke_hoach                = a.thang_ke_hoach
         and lower(btrim(s.ps))            = a.ps_n
         and lower(btrim(s.ma_khach_hang)) = a.kh_n
         and lower(btrim(s.bo_vat_tu))     = a.bo_n
         and lower(btrim(s.san_pham))      = a.sp_n
       order by s.id
       limit 1
    ) t on true;

  -- (3) Ghi SL vào dòng khớp. updated_at đổi -> rev của app đổi -> client tự tải lại.
  update sale_target s
     set sl_thuc_hien = a.sl, updated_at = now()
    from _agg a
   where a.target_id = s.id;
  get diagnostics v_set = row_count;

  select count(*), count(*) filter (where target_id is not null)
    into v_total, v_matched
    from _agg;

  return jsonb_build_object(
    'months',         array_length(v_months, 1),
    'zeroed',         v_zeroed,
    'set_rows',       v_set,
    'matched_keys',   v_matched,
    'total_keys',     v_total,
    'unmatched_keys', v_total - v_matched
  );
end;
$function$;

grant execute on function public.map_hoadon_to_sale_target() to service_role;


-- ── Một lệnh cho pipeline: map + refresh báo cáo ──────────────────────────
-- Gọi sau khi ghi xong app_sale.hoa_don_bovattu. Chạy lại nhiều lần vô hại.
-- Trả về thống kê của map + số tháng đang có trong hoá đơn, để pipeline log lại
-- và phát hiện sớm khi tỉ lệ khớp tụt.
create or replace function public.cap_nhat_thuc_hien()
returns jsonb
language plpgsql
security definer
set search_path to 'public', 'shared', 'app_sale'
as $function$
declare
  v_map    jsonb;
  v_thang  text[];
begin
  v_map := public.map_hoadon_to_sale_target();
  perform public.refresh_bao_cao_sale();

  select array_agg(distinct thang_ke_hoach order by thang_ke_hoach)
    into v_thang from hoa_don_actual;

  return v_map
       || jsonb_build_object('refreshed_bao_cao', true,
                             'thang_trong_hoa_don', to_jsonb(coalesce(v_thang, '{}'::text[])));
end;
$function$;

revoke all on function public.cap_nhat_thuc_hien() from public, anon, authenticated;
grant execute on function public.cap_nhat_thuc_hien() to service_role;

comment on function public.cap_nhat_thuc_hien() is
  'Chạy sau mỗi lần cập nhật app_sale.hoa_don_bovattu: map actual sang sale_target rồi refresh matview báo cáo. Trả thống kê khớp/không khớp + danh sách tháng đang có trong hoá đơn.';
