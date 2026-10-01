-- ════════════════════════════════════════════════════════════════════════
-- LOẠI TRỪ HÓA ĐƠN KHỎI DOANH THU THỰC HIỆN (có thể bật/tắt)
--
-- Bối cảnh: một số hóa đơn không muốn tính vào thực hiện, nhưng sau này có thể
-- tính lại. Không xoá/sửa hoa_don_bovattu (bảng bị xoá + nạp lại theo tháng,
-- id đổi) mà khai báo hóa đơn cần loại trong app_sale.hoa_don_loai_tru, khoá
-- theo (so_tai_lieu, ngay_tai_lieu) — so_tai_lieu đánh lại mỗi năm nên phải
-- kèm ngày mới định danh được 1 hóa đơn.
--
-- dang_loai_tru = true  -> hóa đơn bị bỏ khỏi thực hiện
-- dang_loai_tru = false -> giữ khai báo (lý do, lịch sử) nhưng tính lại bình thường
--
-- Lọc ở NGUỒN: view hoa_don_bovattu_hieu_luc = hoa_don_bovattu trừ hóa đơn
-- đang loại. v_chia_ps + hoa_don_bovattu_chia đọc từ view này, nên hóa đơn bị
-- loại cũng không "ăn" phiếu SV trong hàng đợi FIFO. hoa_don_actual ->
-- map_hoadon_to_sale_target / OOP tự nhận số đã loại.
--
-- Sau khi đổi cấu hình phải chạy "Đồng bộ thực hiện" (cap_nhat_thuc_hien) để
-- sale_target nhận số mới.
-- Không có dòng nào đang loại -> kết quả y hệt trước.
-- ════════════════════════════════════════════════════════════════════════

-- 1) Bảng cấu hình ---------------------------------------------------------
create table if not exists app_sale.hoa_don_loai_tru (
  id             bigint generated always as identity primary key,
  so_tai_lieu    text not null,
  ngay_tai_lieu  date not null,
  dang_loai_tru  boolean not null default true,
  ly_do          text,
  -- ảnh chụp lúc khai báo, để vẫn đọc được khi hóa đơn không còn trong dữ liệu
  ma_kh          text,
  ten_kh         text,
  thang          text,
  created_by     text,
  created_at     timestamptz not null default now(),
  updated_by     text,
  updated_at     timestamptz not null default now(),
  unique (so_tai_lieu, ngay_tai_lieu)
);

comment on table app_sale.hoa_don_loai_tru is
  'Hóa đơn (so_tai_lieu + ngay_tai_lieu) loại khỏi doanh thu thực hiện. dang_loai_tru=false: giữ khai báo nhưng tính lại. Đổi xong phải chạy cap_nhat_thuc_hien.';

alter table app_sale.hoa_don_loai_tru enable row level security;
grant select, insert, update, delete on app_sale.hoa_don_loai_tru to service_role;

-- 2) Hóa đơn còn hiệu lực ---------------------------------------------------
create or replace view app_sale.hoa_don_bovattu_hieu_luc as
select h.*
  from app_sale.hoa_don_bovattu h
 where not exists (
   select 1 from app_sale.hoa_don_loai_tru x
    where x.dang_loai_tru
      and x.so_tai_lieu = h.so_tai_lieu
      and x.ngay_tai_lieu = h.ngay_tai_lieu
 );

comment on view app_sale.hoa_don_bovattu_hieu_luc is
  'hoa_don_bovattu trừ các hóa đơn đang khai báo loại trong hoa_don_loai_tru. Nguồn của v_chia_ps / hoa_don_bovattu_chia.';

grant select on app_sale.hoa_don_bovattu_hieu_luc to service_role;

-- 3) Luồng chia PS đọc từ hóa đơn còn hiệu lực (thân view giữ nguyên như
--    20261001100000_chia_hoa_don_theo_phieu_sv.sql, chỉ đổi nguồn) ----------
create or replace view app_sale.v_chia_ps as
with hd as (
  -- đơn vị hóa đơn trong phạm vi, khoá theo 1 tài liệu (ngày + số + KH)
  select h.ma_kh, h.nhom_san_pham, h.ngay_tai_lieu, h.so_tai_lieu,
         coalesce(nullif(btrim(h.ma_vat_tu), ''), h.bo_vat_tu) as khoa,
         sum(h.so_luong) as sl,
         pv.tu_ngay
    from app_sale.hoa_don_bovattu_hieu_luc h
    join app_sale.chia_ps_pham_vi pv
      on pv.ma_kh = h.ma_kh and pv.nhom_san_pham = h.nhom_san_pham
   group by 1, 2, 3, 4, 5, 7
  having sum(h.so_luong) > 0
),
sv as (
  -- đơn vị phiếu: 'bo' -> 1/phiếu; 'vat_tu' -> tổng SL theo mã
  select p.ma_kh, p.nhom_san_pham, p.so_phieu, p.ngay, p.ten_ps, p.so_tai_lieu_ghi,
         case when pv.don_vi = 'bo' then p.bo_vat_tu else p.ma_vat_tu end as khoa,
         case when pv.don_vi = 'bo' then 1 else sum(p.so_luong) end       as sl
    from app_sale.phieu_su_dung p
    join app_sale.chia_ps_pham_vi pv
      on pv.ma_kh = p.ma_kh and pv.nhom_san_pham = p.nhom_san_pham
   where pv.don_vi = 'vat_tu' or p.bo_vat_tu is not null
   group by 1, 2, 3, 4, 5, 6, 7, pv.don_vi
  having pv.don_vi = 'bo' or sum(p.so_luong) > 0
),
-- Bước 1: phiếu ghi số HĐ -> đúng dòng HĐ đó (gần ngày phiếu nhất nếu số trùng)
gan as (
  select s.*, h.ngay_tai_lieu, h.so_tai_lieu, h.sl as h_sl
    from sv s
    join lateral (
      select h.*
        from hd h
       where h.ma_kh = s.ma_kh and h.nhom_san_pham = s.nhom_san_pham
         and h.khoa = s.khoa and h.so_tai_lieu = s.so_tai_lieu_ghi
         and h.ngay_tai_lieu between s.ngay - 366 and s.ngay + 31
       order by abs(h.ngay_tai_lieu - s.ngay)
       limit 1
    ) h on true
),
gan_cum as (
  select g.*,
         sum(g.sl) over (partition by g.ma_kh, g.nhom_san_pham, g.ngay_tai_lieu,
                                      g.so_tai_lieu, g.khoa
                         order by g.ngay, g.so_phieu) - g.sl as c0
    from gan g
),
b1 as (
  select ma_kh, nhom_san_pham, ngay_tai_lieu, so_tai_lieu, khoa, ten_ps, so_phieu, ngay,
         least(c0 + sl, h_sl) - c0 as sl
    from gan_cum
   where c0 < h_sl
),
-- Phần còn lại cho bước 2
sv_con as (
  select s.ma_kh, s.nhom_san_pham, s.khoa, s.so_phieu, s.ngay, s.ten_ps,
         s.sl - coalesce(sum(b.sl), 0) as sl
    from sv s
    left join b1 b
      on b.ma_kh = s.ma_kh and b.nhom_san_pham = s.nhom_san_pham
     and b.khoa = s.khoa and b.so_phieu = s.so_phieu
   group by 1, 2, 3, 4, 5, 6, s.sl
  having s.sl - coalesce(sum(b.sl), 0) > 0
),
hd_con as (
  select h.ma_kh, h.nhom_san_pham, h.khoa, h.ngay_tai_lieu, h.so_tai_lieu,
         h.sl - coalesce(sum(b.sl), 0) as sl
    from hd h
    left join b1 b
      on b.ma_kh = h.ma_kh and b.nhom_san_pham = h.nhom_san_pham and b.khoa = h.khoa
     and b.ngay_tai_lieu = h.ngay_tai_lieu and b.so_tai_lieu = h.so_tai_lieu
   where h.ngay_tai_lieu >= h.tu_ngay
   group by 1, 2, 3, 4, 5, h.sl
  having h.sl - coalesce(sum(b.sl), 0) > 0
),
-- Bước 2: FIFO theo khoảng cộng dồn
sv_cum as (
  select s.*,
         sum(s.sl) over (partition by ma_kh, nhom_san_pham, khoa
                         order by ngay, so_phieu) as c1
    from sv_con s
),
hd_cum as (
  select h.*,
         sum(h.sl) over (partition by ma_kh, nhom_san_pham, khoa
                         order by ngay_tai_lieu, so_tai_lieu) as c1
    from hd_con h
),
b2 as (
  select h.ma_kh, h.nhom_san_pham, h.ngay_tai_lieu, h.so_tai_lieu, h.khoa,
         s.ten_ps, s.so_phieu, s.ngay,
         least(h.c1, s.c1) - greatest(h.c1 - h.sl, s.c1 - s.sl) as sl
    from hd_cum h
    join sv_cum s
      on s.ma_kh = h.ma_kh and s.nhom_san_pham = h.nhom_san_pham and s.khoa = h.khoa
     and s.c1 - s.sl < h.c1 and h.c1 - h.sl < s.c1
)
select ma_kh, nhom_san_pham, ngay_tai_lieu, so_tai_lieu, khoa, ten_ps,
       so_phieu, ngay as ngay_phieu, sl, 'so_hd'::text as buoc
  from b1
union all
select ma_kh, nhom_san_pham, ngay_tai_lieu, so_tai_lieu, khoa, ten_ps,
       so_phieu, ngay, sl, 'fifo'
  from b2;

comment on view app_sale.v_chia_ps is
  'Ghép phiếu SV vào hóa đơn: mỗi dòng = phần số lượng của 1 phiếu nằm trên 1 hóa đơn (ngày + số tài liệu + khoa). buoc: so_hd = ghép theo số HĐ ghi trên phiếu, fifo = ghép theo thứ tự ngày.';

-- 4) Hóa đơn sau khi chia ------------------------------------------------
create or replace view app_sale.hoa_don_bovattu_chia as
with a as (
  select ma_kh, nhom_san_pham, ngay_tai_lieu, so_tai_lieu, khoa, ten_ps, sum(sl) as sl
    from app_sale.v_chia_ps
   group by 1, 2, 3, 4, 5, 6
),
k as (
  -- tổng SL hóa đơn + tổng đã chia theo từng khoá có chia
  select h.ma_kh, h.nhom_san_pham, h.ngay_tai_lieu, h.so_tai_lieu,
         coalesce(nullif(btrim(h.ma_vat_tu), ''), h.bo_vat_tu) as khoa,
         sum(h.so_luong) as q,
         max(t.tot) as tot
    from app_sale.hoa_don_bovattu_hieu_luc h
    join (select ma_kh, nhom_san_pham, ngay_tai_lieu, so_tai_lieu, khoa, sum(sl) as tot
            from a group by 1, 2, 3, 4, 5) t
      on t.ma_kh = h.ma_kh and t.nhom_san_pham = h.nhom_san_pham
     and t.ngay_tai_lieu = h.ngay_tai_lieu and t.so_tai_lieu = h.so_tai_lieu
     and t.khoa = coalesce(nullif(btrim(h.ma_vat_tu), ''), h.bo_vat_tu)
   group by 1, 2, 3, 4, 5
),
h as (
  select h.*, k.q, k.tot
    from app_sale.hoa_don_bovattu_hieu_luc h
    left join k
      on k.ma_kh = h.ma_kh and k.nhom_san_pham = h.nhom_san_pham
     and k.ngay_tai_lieu = h.ngay_tai_lieu and k.so_tai_lieu = h.so_tai_lieu
     and k.khoa = coalesce(nullif(btrim(h.ma_vat_tu), ''), h.bo_vat_tu)
)
-- dòng không chia
select h.id, h.thang, h.ngay_tai_lieu, h.so_tai_lieu, h.so_eo, h.ma_kh, h.ten_kh, h.bu,
       h.nhom_san_pham, h.bo_vat_tu, h.san_pham, h.ma_vat_tu, h.ten_ps,
       h.so_luong, h.tong_gia_ban, 'goc'::text as chia
  from h
 where h.q is null
union all
-- phần đã ghép phiếu -> PS trên phiếu
select h.id, h.thang, h.ngay_tai_lieu, h.so_tai_lieu, h.so_eo, h.ma_kh, h.ten_kh, h.bu,
       h.nhom_san_pham, h.bo_vat_tu, h.san_pham, h.ma_vat_tu, a.ten_ps,
       h.so_luong * a.sl / h.q, h.tong_gia_ban * a.sl / h.q, 'chia'
  from h
  join a
    on a.ma_kh = h.ma_kh and a.nhom_san_pham = h.nhom_san_pham
   and a.ngay_tai_lieu = h.ngay_tai_lieu and a.so_tai_lieu = h.so_tai_lieu
   and a.khoa = coalesce(nullif(btrim(h.ma_vat_tu), ''), h.bo_vat_tu)
 where h.q is not null
union all
-- phần chưa có phiếu -> giữ PS đứng tên
select h.id, h.thang, h.ngay_tai_lieu, h.so_tai_lieu, h.so_eo, h.ma_kh, h.ten_kh, h.bu,
       h.nhom_san_pham, h.bo_vat_tu, h.san_pham, h.ma_vat_tu, h.ten_ps,
       h.so_luong * (h.q - h.tot) / h.q, h.tong_gia_ban * (h.q - h.tot) / h.q, 'con_lai'
  from h
 where h.q is not null and h.q > h.tot;

comment on view app_sale.hoa_don_bovattu_chia is
  'hoa_don_bovattu sau khi chia PS theo phiếu SV (v_chia_ps). chia: goc = không chia, chia = phần ghép phiếu (ten_ps lấy từ phiếu), con_lai = phần chưa có phiếu (giữ PS gốc). Tổng so_luong/tong_gia_ban theo id bằng dòng gốc.';

grant select on app_sale.v_chia_ps, app_sale.hoa_don_bovattu_chia
  to service_role, anon, authenticated;

-- 4) RPC cho app (edge function gọi bằng service_role) ---------------------

-- Danh sách khai báo + tổng hiện tại của hóa đơn trong dữ liệu gốc
create or replace function public.get_hoa_don_loai_tru()
returns jsonb
language sql
stable
security definer
set search_path = public, app_sale
as $$
  select coalesce(jsonb_agg(to_jsonb(r) order by r.dang_loai_tru desc, r.ngay_tai_lieu desc, r.so_tai_lieu), '[]'::jsonb)
    from (
      select x.id, x.so_tai_lieu, x.ngay_tai_lieu, x.dang_loai_tru, x.ly_do,
             coalesce(h.ma_kh, x.ma_kh)   as ma_kh,
             coalesce(h.ten_kh, x.ten_kh) as ten_kh,
             coalesce(h.thang, x.thang)   as thang,
             h.ten_ps, h.nhom_san_pham, h.so_dong, h.so_luong, h.doanh_thu,
             h.so_dong is not null        as con_du_lieu,
             x.created_by, x.created_at, x.updated_by, x.updated_at
        from app_sale.hoa_don_loai_tru x
        left join lateral (
          select max(b.ma_kh) as ma_kh, max(b.ten_kh) as ten_kh, max(b.thang) as thang,
                 string_agg(distinct b.ten_ps, ', ')        as ten_ps,
                 string_agg(distinct b.nhom_san_pham, ', ') as nhom_san_pham,
                 count(*)                                   as so_dong,
                 sum(b.so_luong)                            as so_luong,
                 sum(b.tong_gia_ban)                        as doanh_thu
            from app_sale.hoa_don_bovattu b
           where b.so_tai_lieu = x.so_tai_lieu and b.ngay_tai_lieu = x.ngay_tai_lieu
          having count(*) > 0
        ) h on true
    ) r;
$$;

-- Tìm hóa đơn theo số tài liệu / số HĐ / mã hoặc tên KH (gộp theo hóa đơn)
create or replace function public.tim_hoa_don(p_q text, p_limit int default 50)
returns jsonb
language sql
stable
security definer
set search_path = public, app_sale
as $$
  with q as (select btrim(coalesce(p_q, '')) as s)
  select coalesce(jsonb_agg(to_jsonb(r) order by r.ngay_tai_lieu desc, r.so_tai_lieu), '[]'::jsonb)
    from (
      select b.so_tai_lieu, b.ngay_tai_lieu,
             max(b.thang)  as thang,
             max(b.ma_kh)  as ma_kh,
             max(b.ten_kh) as ten_kh,
             string_agg(distinct b.ten_ps, ', ')        as ten_ps,
             string_agg(distinct b.nhom_san_pham, ', ') as nhom_san_pham,
             count(*)            as so_dong,
             sum(b.so_luong)     as so_luong,
             sum(b.tong_gia_ban) as doanh_thu,
             coalesce(bool_or(x.dang_loai_tru), false) as dang_loai_tru,
             bool_or(x.id is not null)                 as da_khai_bao
        from app_sale.hoa_don_bovattu b
        cross join q
        left join app_sale.hoa_don_loai_tru x
          on x.so_tai_lieu = b.so_tai_lieu and x.ngay_tai_lieu = b.ngay_tai_lieu
       where length(q.s) >= 2
         and (b.so_tai_lieu ilike q.s || '%'
              or b.so_hd    ilike '%' || q.s || '%'
              or b.ma_kh    ilike q.s
              or b.ten_kh   ilike '%' || q.s || '%')
       group by b.so_tai_lieu, b.ngay_tai_lieu
       order by b.ngay_tai_lieu desc, b.so_tai_lieu
       limit greatest(1, least(coalesce(p_limit, 50), 200))
    ) r;
$$;

-- Thêm / sửa khai báo (bật-tắt loại trừ, đổi lý do).
-- p_dang_loai_tru / p_ly_do null = giữ giá trị cũ (khai báo mới: loại, không lý do).
create or replace function public.luu_hoa_don_loai_tru(
  p_so_tai_lieu   text,
  p_ngay_tai_lieu date,
  p_dang_loai_tru boolean,
  p_ly_do         text,
  p_actor         text
)
returns jsonb
language plpgsql
security definer
set search_path = public, app_sale
as $$
declare
  v_so  text := btrim(coalesce(p_so_tai_lieu, ''));
  v_row app_sale.hoa_don_loai_tru;
  v_kh  record;
begin
  if v_so = '' or p_ngay_tai_lieu is null then
    raise exception 'thieu_du_lieu';
  end if;

  select max(ma_kh) as ma_kh, max(ten_kh) as ten_kh, max(thang) as thang, count(*) as n
    into v_kh
    from app_sale.hoa_don_bovattu
   where so_tai_lieu = v_so and ngay_tai_lieu = p_ngay_tai_lieu;

  -- Khai báo mới phải trỏ đúng hóa đơn đang có; sửa khai báo cũ thì không bắt buộc
  if v_kh.n = 0 and not exists (
       select 1 from app_sale.hoa_don_loai_tru
        where so_tai_lieu = v_so and ngay_tai_lieu = p_ngay_tai_lieu) then
    raise exception 'khong_tim_thay_hoa_don';
  end if;

  insert into app_sale.hoa_don_loai_tru as t
         (so_tai_lieu, ngay_tai_lieu, dang_loai_tru, ly_do, ma_kh, ten_kh, thang,
          created_by, updated_by)
  values (v_so, p_ngay_tai_lieu, coalesce(p_dang_loai_tru, true),
          nullif(btrim(coalesce(p_ly_do, '')), ''),
          v_kh.ma_kh, v_kh.ten_kh, v_kh.thang, p_actor, p_actor)
  on conflict (so_tai_lieu, ngay_tai_lieu) do update
     set dang_loai_tru = coalesce(p_dang_loai_tru, t.dang_loai_tru),
         ly_do         = case when p_ly_do is null then t.ly_do
                              else nullif(btrim(p_ly_do), '') end,
         ma_kh         = coalesce(excluded.ma_kh, t.ma_kh),
         ten_kh        = coalesce(excluded.ten_kh, t.ten_kh),
         thang         = coalesce(excluded.thang, t.thang),
         updated_by    = p_actor,
         updated_at    = now()
  returning * into v_row;

  return to_jsonb(v_row);
end;
$$;

-- Xoá hẳn khai báo (hóa đơn tính lại bình thường)
create or replace function public.xoa_hoa_don_loai_tru(p_id bigint)
returns jsonb
language plpgsql
security definer
set search_path = public, app_sale
as $$
declare
  v_row app_sale.hoa_don_loai_tru;
begin
  delete from app_sale.hoa_don_loai_tru where id = p_id returning * into v_row;
  if v_row.id is null then
    raise exception 'khong_ton_tai';
  end if;
  return to_jsonb(v_row);
end;
$$;

revoke all on function public.get_hoa_don_loai_tru()                                from public, anon, authenticated;
revoke all on function public.tim_hoa_don(text, int)                               from public, anon, authenticated;
revoke all on function public.luu_hoa_don_loai_tru(text, date, boolean, text, text) from public, anon, authenticated;
revoke all on function public.xoa_hoa_don_loai_tru(bigint)                         from public, anon, authenticated;
grant execute on function public.get_hoa_don_loai_tru()                                to service_role;
grant execute on function public.tim_hoa_don(text, int)                               to service_role;
grant execute on function public.luu_hoa_don_loai_tru(text, date, boolean, text, text) to service_role;
grant execute on function public.xoa_hoa_don_loai_tru(bigint)                         to service_role;
