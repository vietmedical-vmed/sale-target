-- Rollback 20261123120000_het_han_theo_hop_dong.sql: trả get_quota_thau (không cột co_hd) và
-- v_quota_thau_xuat về bản trước; bỏ het_han_dot 3 tham số và v_dot_lien_ket_hop_dong.
-- Edge bản mới đọc r.co_hd (thiếu thì coi như false) nên không bắt buộc deploy lại edge.
begin;

drop function public.get_quota_thau(text, text, text, text, text[]);
CREATE FUNCTION public.get_quota_thau(p_fy text, p_bu text, p_mien text, p_ps text, p_groups text[])
 RETURNS TABLE(kind text, fy text, ps text, cust_id text, grp text, mset text, prod text, price numeric, loai text, dot integer, thang text, thoi_gian numeric, qty numeric)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'shared'
AS $function$

  SELECT * FROM (

    SELECT 'dot'::text AS kind, d.nam_tai_chinh, d.ps, d.ma_khach_hang, d.nhom_san_pham,

           NULL::text, NULL::text, NULL::numeric, d.loai, d.dot, d.thang_thau, d.thoi_gian, NULL::numeric

    FROM   shared.dot_thau d

    WHERE  (p_fy     IS NULL OR d.nam_tai_chinh = p_fy)

      AND  (p_bu     IS NULL OR d.bu            =     p_bu)

      AND  (shared.mien_in(d.mien, p_mien))

      AND  (p_ps     IS NULL OR d.ps            =     p_ps)

      AND  (p_groups IS NULL OR d.nhom_san_pham = ANY(p_groups))

      AND  (p_bu IS NOT NULL OR d.bu IS NULL OR d.bu <> 'test')
      AND  d.trang_thai = 'chinh_thuc'

    UNION ALL

    SELECT 'quota'::text, q.nam_tai_chinh, q.ps, q.ma_khach_hang, q.nhom_san_pham,

           q.bo_vat_tu, q.san_pham, q.don_gia, q.loai, q.dot, NULL::text, NULL::numeric, q.so_luong

    FROM   shared.quota_thau q

    WHERE  (p_fy     IS NULL OR q.nam_tai_chinh = p_fy)

      AND  (p_bu     IS NULL OR q.bu            =     p_bu)

      AND  (shared.mien_in(q.mien, p_mien))

      AND  (p_ps     IS NULL OR q.ps            =     p_ps)

      AND  (p_groups IS NULL OR q.nhom_san_pham = ANY(p_groups))

      AND  (p_bu IS NOT NULL OR q.bu IS NULL OR q.bu <> 'test')
      AND  q.trang_thai = 'chinh_thuc'

  ) t

  ORDER BY 1, 2, 3, 4, 5, 6, 7, 8, 9, 10;

$function$;
revoke all on function public.get_quota_thau(text, text, text, text, text[]) from public, anon, authenticated;
grant execute on function public.get_quota_thau(text, text, text, text, text[]) to service_role;

create or replace view app_sale.v_quota_thau_xuat as
WITH cur AS (
         SELECT app_config.value #>> '{}'::text[] AS thang
           FROM shared.app_config
          WHERE app_config.key = 'current_month'::text
        ), ke_hoach AS (
         SELECT sale_target.nam_tai_chinh,
            sale_target.ps,
            sale_target.ma_khach_hang,
            sale_target.nhom_san_pham,
            sale_target.bo_vat_tu,
            sale_target.san_pham,
            sale_target.don_gia,
            sale_target.ma_san_pham
           FROM shared.sale_target
          WHERE sale_target.nam_tai_chinh IS NOT NULL AND NOT COALESCE(sale_target.ngoai_ke_hoach, false)
        ), kh_gia AS (
         SELECT DISTINCT ke_hoach.nam_tai_chinh,
            ke_hoach.ps,
            COALESCE(ke_hoach.ma_khach_hang, ''::text) AS ma_khach_hang,
            COALESCE(ke_hoach.nhom_san_pham, ''::text) AS nhom_san_pham,
            COALESCE(ke_hoach.bo_vat_tu, ''::text) AS bo_vat_tu,
            COALESCE(ke_hoach.san_pham, ''::text) AS san_pham,
            COALESCE(ke_hoach.don_gia, 0::numeric) AS don_gia
           FROM ke_hoach
        ), kh_sp AS (
         SELECT DISTINCT kh_gia.nam_tai_chinh,
            kh_gia.ps,
            kh_gia.ma_khach_hang,
            kh_gia.nhom_san_pham,
            kh_gia.bo_vat_tu,
            kh_gia.san_pham
           FROM kh_gia
        ), kh_ten AS (
         SELECT DISTINCT ke_hoach.nam_tai_chinh,
            ke_hoach.ps,
            COALESCE(ke_hoach.ma_khach_hang, ''::text) AS ma_khach_hang,
            shared.ten_sp_chuan(ke_hoach.san_pham) AS ten
           FROM ke_hoach
        ), kh_ma AS (
         SELECT DISTINCT ke_hoach.nam_tai_chinh,
            ke_hoach.ps,
            COALESCE(ke_hoach.ma_khach_hang, ''::text) AS ma_khach_hang,
            shared.ma_sp_hop_le(ke_hoach.ma_san_pham) AS ma
           FROM ke_hoach
          WHERE shared.ma_sp_hop_le(ke_hoach.ma_san_pham) IS NOT NULL
        ), kh_kh_ten AS (
         SELECT DISTINCT ke_hoach.nam_tai_chinh,
            COALESCE(ke_hoach.ma_khach_hang, ''::text) AS ma_khach_hang,
            shared.ten_sp_chuan(ke_hoach.san_pham) AS ten
           FROM ke_hoach
        ), kh_kh_ma AS (
         SELECT DISTINCT ke_hoach.nam_tai_chinh,
            COALESCE(ke_hoach.ma_khach_hang, ''::text) AS ma_khach_hang,
            shared.ma_sp_hop_le(ke_hoach.ma_san_pham) AS ma
           FROM ke_hoach
          WHERE shared.ma_sp_hop_le(ke_hoach.ma_san_pham) IS NOT NULL
        ), moi AS (
         SELECT q.nam_tai_chinh,
            q.bu,
            q.mien,
            q.ps,
            q.ma_khach_hang,
            q.khach_hang,
            q.nhom_san_pham,
            q.bo_vat_tu,
            q.san_pham,
            q.don_gia,
            q.loai,
            q.dot,
            d.thang_thau,
            q.so_luong,
            'quota_thau'::text AS nguon,
                CASE
                    WHEN q.trang_thai = 'cho_duyet'::text THEN 'Chờ duyệt (chưa hiện trên app)'::text
                    WHEN g.san_pham IS NOT NULL THEN NULL::text
                    WHEN p.san_pham IS NOT NULL THEN 'Mức giá không còn trên kế hoạch'::text
                    WHEN t.ten IS NOT NULL THEN 'Khớp tên - khác nhóm / BVT / cách viết'::text
                    WHEN m.ma IS NOT NULL THEN 'Khác tên - khớp mã'::text
                    WHEN kt.ten IS NOT NULL OR km.ma IS NOT NULL THEN 'SP còn ở KH nhưng PS khác'::text
                    ELSE 'Khác tên - khác mã (SP không còn trên kế hoạch)'::text
                END AS canh_bao,
            d.thoi_gian AS hieu_luc
           FROM shared.quota_thau q
             LEFT JOIN shared.dot_thau d ON d.nam_tai_chinh = q.nam_tai_chinh AND d.ps = q.ps AND d.ma_khach_hang = q.ma_khach_hang AND d.nhom_san_pham = q.nhom_san_pham AND d.loai = q.loai AND d.dot = q.dot AND q.loai <> 'cu'::text
             LEFT JOIN kh_gia g ON g.nam_tai_chinh = q.nam_tai_chinh AND g.ps = q.ps AND g.ma_khach_hang = q.ma_khach_hang AND g.nhom_san_pham = q.nhom_san_pham AND g.bo_vat_tu = q.bo_vat_tu AND g.san_pham = q.san_pham AND g.don_gia = q.don_gia
             LEFT JOIN kh_sp p ON p.nam_tai_chinh = q.nam_tai_chinh AND p.ps = q.ps AND p.ma_khach_hang = q.ma_khach_hang AND p.nhom_san_pham = q.nhom_san_pham AND p.bo_vat_tu = q.bo_vat_tu AND p.san_pham = q.san_pham
             LEFT JOIN kh_ten t ON t.nam_tai_chinh = q.nam_tai_chinh AND t.ps = q.ps AND t.ma_khach_hang = q.ma_khach_hang AND t.ten = shared.ten_sp_chuan(q.san_pham)
             LEFT JOIN kh_ma m ON m.nam_tai_chinh = q.nam_tai_chinh AND m.ps = q.ps AND m.ma_khach_hang = q.ma_khach_hang AND m.ma = q.ma_san_pham
             LEFT JOIN kh_kh_ten kt ON kt.nam_tai_chinh = q.nam_tai_chinh AND kt.ma_khach_hang = q.ma_khach_hang AND kt.ten = shared.ten_sp_chuan(q.san_pham)
             LEFT JOIN kh_kh_ma km ON km.nam_tai_chinh = q.nam_tai_chinh AND km.ma_khach_hang = q.ma_khach_hang AND km.ma = q.ma_san_pham
          WHERE q.so_luong <> 0::numeric
        )
 SELECT row_number() OVER (ORDER BY u.nam_tai_chinh, u.bu, u.ps, u.ma_khach_hang, u.nhom_san_pham, u.bo_vat_tu, u.san_pham, u.don_gia, u.loai, u.dot, u.thang_thau, u.nguon) AS stt,
    u.nam_tai_chinh,
    u.bu,
    u.mien,
    u.ps,
    u.ma_khach_hang,
    u.khach_hang,
    u.nhom_san_pham,
    u.bo_vat_tu,
    u.san_pham,
    u.don_gia,
    u.loai,
    u.dot,
    u.thang_thau,
    u.so_luong,
    u.nguon,
        CASE
            WHEN u.bu = 'test'::text THEN 'Dữ liệu demo (BU test)'::text
            ELSE u.canh_bao
        END AS canh_bao,
    u.so_luong * u.don_gia AS thanh_tien,
        CASE
            WHEN u.loai = 'cu'::text THEN 'On hand'::text
            WHEN u.thang_thau IS NULL OR u.hieu_luc IS NULL OR u.hieu_luc <= 0::numeric OR u.thang_thau > cur.thang THEN 'Upcoming'::text
            WHEN shared.het_han_dot(u.thang_thau, u.hieu_luc) < cur.thang THEN 'Hết hiệu lực'::text
            ELSE 'On hand'::text
        END AS trang_thai,
    u.hieu_luc,
    shared.het_han_dot(u.thang_thau, u.hieu_luc) AS het_han
   FROM moi u
     LEFT JOIN cur ON true;

drop function if exists shared.het_han_dot(text, numeric, boolean);
drop view if exists app_sale.v_dot_lien_ket_hop_dong;

commit;
