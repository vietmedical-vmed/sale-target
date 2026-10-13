-- ════════════════════════════════════════════════════════════════════════
-- area_manager phụ trách NHIỀU miền.
--
-- users.scope của area_manager giờ là danh sách tên miền "Miền Bắc, Miền Trung".
-- API truyền p_mien / p_mien_scope dạng danh sách phân cách dấu phẩy; các hàm phạm vi
-- đổi `x.mien = p_mien` thành shared.mien_in(x.mien, p_mien). Giữ nguyên chữ ký hàm,
-- nên một giá trị đơn ("Miền Bắc") vẫn chạy như cũ.
--
-- Thân hàm lấy nguyên văn từ DB (pg_get_functiondef) ngày 2026-10-13, chỉ thay vế so sánh miền.
-- Hàm *_agg (sale_target_agg, stock_agg, usage_agg, usage_fy_agg) là bộ lọc hiển thị
-- MB/MN/ALL của app order, không phải phạm vi quyền → KHÔNG đổi.
-- ════════════════════════════════════════════════════════════════════════

begin;

-- Không SET search_path để Postgres inline được hàm SQL vào WHERE (giữ dùng index).
-- Thân chỉ gọi hàm builtin (pg_catalog luôn được tìm trước) nên không bị shadow.
create or replace function shared.mien_in(p_val text, p_list text)
returns boolean
language sql immutable parallel safe
as $$
  select p_list is null
      or p_val = any (regexp_split_to_array(btrim(p_list), '\s*,\s*'))
$$;

comment on function shared.mien_in(text, text) is
  'true nếu p_list null (không giới hạn miền) hoặc p_val thuộc danh sách p_list phân cách dấu phẩy.';

CREATE OR REPLACE FUNCTION public.chuyen_dia_ban(p_id bigint, p_ps_moi text, p_mien text, p_tu_thang text, p_bu text, p_mien_scope text, p_ps_scope text, p_groups text[])
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'shared', 'app_sale'
AS $function$
DECLARE
  d      dm_dia_ban;
  v_new  bigint;
  v_dong text;
BEGIN
  SELECT * INTO d FROM dm_dia_ban WHERE id = p_id;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'khong_ton_tai: không còn bản khai báo này' USING ERRCODE = '02000';
  END IF;
  IF (p_bu         IS NOT NULL AND d.bu            <>     p_bu)
  OR (p_mien_scope IS NOT NULL AND NOT shared.mien_in(d.mien, p_mien_scope))
  OR (p_ps_scope   IS NOT NULL AND d.ps            <>     p_ps_scope)
  OR (p_groups     IS NOT NULL AND NOT (d.nhom_san_pham = ANY(p_groups))) THEN
    RAISE EXCEPTION 'out_of_scope: bản khai báo nằm ngoài phạm vi quyền' USING ERRCODE = '42501';
  END IF;

  IF coalesce(btrim(p_ps_moi), '') = '' THEN
    RAISE EXCEPTION 'thieu_du_lieu: chưa chọn PS mới' USING ERRCODE = '22023';
  END IF;
  IF p_tu_thang !~ '^[0-9]{4}-[0-9]{2}$' THEN
    RAISE EXCEPTION 'thang_khong_hop_le: tháng phải dạng YYYY-MM' USING ERRCODE = '22023';
  END IF;
  -- Phải nằm TRONG khoảng của bản cũ và không phải tháng bắt đầu của nó (chuyển
  -- ngay từ tháng đầu = sửa sai, dùng đường sửa để không tạo bản rỗng).
  IF p_tu_thang <= d.tu_thang THEN
    RAISE EXCEPTION 'thang_khong_hop_le: tháng chuyển phải sau tháng bắt đầu (%) của bản đang chạy — sửa PS tại chỗ nếu chỉ muốn sửa sai', d.tu_thang
      USING ERRCODE = '22023';
  END IF;
  IF d.den_thang IS NOT NULL AND p_tu_thang > d.den_thang THEN
    RAISE EXCEPTION 'thang_khong_hop_le: tháng chuyển vượt quá tháng kết thúc (%) của bản đang chạy', d.den_thang
      USING ERRCODE = '22023';
  END IF;
  IF btrim(p_ps_moi) = d.ps THEN
    RAISE EXCEPTION 'trung_ps: PS mới trùng PS đang phụ trách' USING ERRCODE = '22023';
  END IF;

  v_dong := thang_truoc(p_tu_thang);

  BEGIN
    -- Bản mới thừa hưởng đuôi khoảng cũ (NULL = còn hiệu lực).
    INSERT INTO dm_dia_ban (bu, ma_khach_hang, khach_hang, nhom_san_pham, mien, ps,
                            active, tu_thang, den_thang)
    VALUES (d.bu, d.ma_khach_hang, d.khach_hang, d.nhom_san_pham,
            nullif(btrim(coalesce(p_mien, '')), ''), btrim(p_ps_moi),
            true, p_tu_thang, d.den_thang)
    RETURNING id INTO v_new;
  EXCEPTION WHEN unique_violation THEN
    RAISE EXCEPTION 'dup_dia_ban: đã có bản khai báo cho PS đó từ tháng %', p_tu_thang
      USING ERRCODE = '23505';
  END;

  UPDATE dm_dia_ban SET den_thang = v_dong, updated_at = now() WHERE id = p_id;

  -- Đóng+mở liền mạch nên không sinh khoảng trống, nhưng vẫn soi lại: tổ hợp có
  -- thể đã lệch từ trước và không được để lần ghi này đi qua âm thầm.
  PERFORM kiem_tra_khoang_trong(jsonb_build_array(jsonb_build_object(
    'bu', d.bu, 'cust_key', d.cust_key, 'nhom_san_pham', d.nhom_san_pham)));

  RETURN jsonb_build_object('id_cu', p_id, 'den_thang_cu', v_dong, 'id_moi', v_new);
END;
$function$
;

CREATE OR REPLACE FUNCTION public.classify_oop_sale_target(p_bu text DEFAULT NULL::text, p_mien text DEFAULT NULL::text, p_ps text DEFAULT NULL::text, p_groups text[] DEFAULT NULL::text[])
 RETURNS TABLE(target_id bigint, ly_do text, ps_dia_ban text)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'shared', 'app_sale'
AS $function$
  SELECT s.id AS target_id,
    CASE
      WHEN NOT EXISTS (SELECT 1 FROM shared.dm_ps dp WHERE lower(btrim(dp.ps)) = lower(btrim(s.ps))) THEN 'ps_la'
      WHEN NOT EXISTS (SELECT 1 FROM shared.dm_dia_ban d WHERE d.active AND d.bu = s.bu AND d.cust_key = coalesce(nullif(btrim(s.ma_khach_hang), ''), btrim(s.khach_hang)) AND d.nhom_san_pham = s.nhom_san_pham AND d.tu_thang <= s.thang_ke_hoach AND (d.den_thang IS NULL OR d.den_thang >= s.thang_ke_hoach)) THEN 'chua_co_dia_ban'
      WHEN NOT EXISTS (SELECT 1 FROM shared.dm_dia_ban d WHERE d.active AND d.bu = s.bu AND d.cust_key = coalesce(nullif(btrim(s.ma_khach_hang), ''), btrim(s.khach_hang)) AND d.nhom_san_pham = s.nhom_san_pham AND d.tu_thang <= s.thang_ke_hoach AND (d.den_thang IS NULL OR d.den_thang >= s.thang_ke_hoach) AND lower(btrim(d.ps)) = lower(btrim(s.ps))) THEN 'sai_ps'
      WHEN EXISTS (SELECT 1 FROM shared.sale_target s2 WHERE s2.ngoai_ke_hoach IS NOT TRUE AND s2.thang_ke_hoach = s.thang_ke_hoach AND lower(btrim(coalesce(s2.ma_khach_hang, ''))) = lower(btrim(coalesce(s.ma_khach_hang, ''))) AND lower(btrim(coalesce(s2.san_pham, ''))) = lower(btrim(coalesce(s.san_pham, '')))) THEN 'sai_bo_vat_tu'
      ELSE 'thieu_dong_ke_hoach'
    END AS ly_do,
    (SELECT d.ps FROM shared.dm_dia_ban d WHERE d.active AND d.bu = s.bu AND d.cust_key = coalesce(nullif(btrim(s.ma_khach_hang), ''), btrim(s.khach_hang)) AND d.nhom_san_pham = s.nhom_san_pham AND d.tu_thang <= s.thang_ke_hoach AND (d.den_thang IS NULL OR d.den_thang >= s.thang_ke_hoach) LIMIT 1) AS ps_dia_ban
  FROM shared.sale_target s
  WHERE s.ngoai_ke_hoach = true
    AND (p_bu IS NULL OR s.bu = p_bu)
    AND (shared.mien_in(s.mien, p_mien))
    AND (p_ps IS NULL OR s.ps = p_ps)
    AND (p_groups IS NULL OR s.nhom_san_pham = ANY(p_groups));
$function$
;

CREATE OR REPLACE FUNCTION public.delete_dm_dia_ban(p_ids bigint[], p_bu text, p_mien text, p_ps text, p_groups text[])
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'shared', 'app_sale'
AS $function$
DECLARE
  v_req  integer;
  v_ok   integer;
  v_del  integer := 0;
  v_keys jsonb;
BEGIN
  SELECT count(*), count(d.id) INTO v_req, v_ok
    FROM unnest(coalesce(p_ids, '{}'::bigint[])) AS u(id)
    LEFT JOIN dm_dia_ban d
           ON d.id = u.id
          AND (p_bu     IS NULL OR d.bu            =     p_bu)
          AND (shared.mien_in(d.mien, p_mien))
          AND (p_ps     IS NULL OR d.ps            =     p_ps)
          AND (p_groups IS NULL OR d.nhom_san_pham = ANY(p_groups));
  IF v_req = 0 THEN
    RETURN jsonb_build_object('deleted', 0);
  END IF;
  IF v_ok <> v_req THEN
    RAISE EXCEPTION 'out_of_scope: % / % dòng nằm ngoài phạm vi quyền hoặc không còn tồn tại',
                    v_req - v_ok, v_req
      USING ERRCODE = '42501';
  END IF;

  SELECT jsonb_agg(DISTINCT jsonb_build_object(
           'bu', d.bu, 'cust_key', d.cust_key, 'nhom_san_pham', d.nhom_san_pham))
    INTO v_keys
    FROM dm_dia_ban d WHERE d.id = ANY(p_ids);

  DELETE FROM dm_dia_ban WHERE id = ANY(p_ids);
  GET DIAGNOSTICS v_del = ROW_COUNT;

  PERFORM kiem_tra_khoang_trong(coalesce(v_keys, '[]'::jsonb));

  RETURN jsonb_build_object('deleted', v_del);
END;
$function$
;

CREATE OR REPLACE FUNCTION public.get_quota_thau(p_fy text, p_bu text, p_mien text, p_ps text, p_groups text[])
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
  ) t
  ORDER BY 1, 2, 3, 4, 5, 6, 7, 8, 9, 10;
$function$
;

CREATE OR REPLACE FUNCTION shared.scope_nhom_sp(p_fy text, p_ps text, p_cust text, p_grp text, p_bu text, p_mien text, p_ps_lock text, p_groups text[])
 RETURNS TABLE(bu text, mien text)
 LANGUAGE sql
 STABLE
 SET search_path TO 'shared', 'public'
AS $function$
  SELECT min(s.bu), min(s.mien)
  FROM   shared.sale_target s
  WHERE  s.nam_tai_chinh = p_fy
    AND  s.ps            = p_ps
    AND  coalesce(s.ma_khach_hang, '') = coalesce(p_cust, '')
    AND  coalesce(s.nhom_san_pham, '') = coalesce(p_grp, '')
    AND  (p_bu      IS NULL OR s.bu            =     p_bu)
    AND  (shared.mien_in(s.mien, p_mien))
    AND  (p_ps_lock IS NULL OR s.ps            =     p_ps_lock)
    AND  (p_groups  IS NULL OR s.nhom_san_pham = ANY(p_groups))
  HAVING count(*) > 0;
$function$
;

CREATE OR REPLACE FUNCTION public.update_sale_target_cells(p_updates jsonb, p_bu text, p_mien text, p_ps text, p_groups text[])
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'shared', 'app_sale'
AS $function$
DECLARE
  v_req        integer;
  v_ok         integer;
  v_done       integer;
  v_conflicts  jsonb;
BEGIN
  -- 1) Scope check
  SELECT count(*), count(s.id)
    INTO v_req, v_ok
    FROM (
      SELECT (e->>'id')::bigint AS id
      FROM   jsonb_array_elements(coalesce(p_updates, '[]'::jsonb)) e
      WHERE  jsonb_typeof(e->'patch') = 'object'
    ) u
    LEFT JOIN sale_target s
           ON s.id = u.id
          AND (p_bu     IS NULL OR s.bu            =     p_bu)
          AND (shared.mien_in(s.mien, p_mien))
          AND (p_ps     IS NULL OR s.ps            =     p_ps)
          AND (p_groups IS NULL OR s.nhom_san_pham = ANY(p_groups));

  IF v_req = 0 THEN
    RETURN jsonb_build_object('updated', 0, 'conflicts', '[]'::jsonb);
  END IF;

  IF v_ok <> v_req THEN
    RAISE EXCEPTION 'out_of_scope: % / % dòng nằm ngoài phạm vi quyền hoặc không còn tồn tại',
                    v_req - v_ok, v_req
      USING ERRCODE = '42501';
  END IF;

  -- 2) Collect conflicts: rows where client _rev doesn't match server _rev
  SELECT coalesce(jsonb_agg(jsonb_build_object(
    'id', s.id,
    '_rev', s._rev,
    'values', jsonb_build_object(
      'quota_thau_cu_con_lai', s.quota_thau_cu_con_lai,
      'thang_thau_chinh',      s.thang_thau_chinh,
      'thoi_gian_thau_chinh',  s.thoi_gian_thau_chinh,
      'quota_thau_chinh',      s.quota_thau_chinh,
      'thang_thau_bo_sung',    s.thang_thau_bo_sung,
      'quota_bo_sung',         s.quota_bo_sung,
      'sl_ke_hoach_update',    s.sl_ke_hoach_update,
      'don_gia',               s.don_gia,
      'bo_vat_tu',             s.bo_vat_tu,
      'san_pham',              s.san_pham,
      'sl_ke_hoach_dau_nam',   s.sl_ke_hoach_dau_nam,
      'doanh_thu_kh_dau_nam',  s.doanh_thu_kh_dau_nam
    )
  )), '[]'::jsonb)
  INTO v_conflicts
  FROM (
    SELECT (e->>'id')::bigint AS id,
           (e->>'_rev')::bigint AS client_rev
    FROM   jsonb_array_elements(coalesce(p_updates, '[]'::jsonb)) e
    WHERE  jsonb_typeof(e->'patch') = 'object'
      AND  e ? '_rev'
  ) u
  JOIN sale_target s ON s.id = u.id
  WHERE s._rev <> u.client_rev;

  -- 3) Update only rows with matching _rev (or rows without _rev = no check)
  WITH u AS (
    SELECT (e->>'id')::bigint AS id,
           e->'patch'         AS patch,
           (e->>'_rev')::bigint AS client_rev
    FROM   jsonb_array_elements(coalesce(p_updates, '[]'::jsonb)) e
    WHERE  jsonb_typeof(e->'patch') = 'object'
  )
  UPDATE sale_target s SET
    quota_thau_cu_con_lai = CASE WHEN u.patch ? 'quota_thau_cu_con_lai'
           THEN nullif(u.patch->>'quota_thau_cu_con_lai', '')::numeric
           ELSE s.quota_thau_cu_con_lai END,
    thang_thau_chinh      = CASE WHEN u.patch ? 'thang_thau_chinh'
           THEN u.patch->>'thang_thau_chinh'
           ELSE s.thang_thau_chinh END,
    thoi_gian_thau_chinh  = CASE WHEN u.patch ? 'thoi_gian_thau_chinh'
           THEN nullif(u.patch->>'thoi_gian_thau_chinh', '')::numeric
           ELSE s.thoi_gian_thau_chinh END,
    quota_thau_chinh      = CASE WHEN u.patch ? 'quota_thau_chinh'
           THEN nullif(u.patch->>'quota_thau_chinh', '')::numeric
           ELSE s.quota_thau_chinh END,
    thang_thau_bo_sung    = CASE WHEN u.patch ? 'thang_thau_bo_sung'
           THEN u.patch->>'thang_thau_bo_sung'
           ELSE s.thang_thau_bo_sung END,
    quota_bo_sung         = CASE WHEN u.patch ? 'quota_bo_sung'
           THEN nullif(u.patch->>'quota_bo_sung', '')::numeric
           ELSE s.quota_bo_sung END,
    sl_ke_hoach_update    = CASE WHEN u.patch ? 'sl_ke_hoach_update'
           THEN nullif(u.patch->>'sl_ke_hoach_update', '')::numeric
           ELSE s.sl_ke_hoach_update END,
    don_gia               = CASE WHEN u.patch ? 'don_gia'
           THEN nullif(u.patch->>'don_gia', '')::numeric
           ELSE s.don_gia END,
    bo_vat_tu             = CASE WHEN u.patch ? 'bo_vat_tu'
           THEN u.patch->>'bo_vat_tu'
           ELSE s.bo_vat_tu END,
    san_pham              = CASE WHEN u.patch ? 'san_pham'
           THEN u.patch->>'san_pham'
           ELSE s.san_pham END,
    sl_ke_hoach_dau_nam   = CASE WHEN u.patch ? 'sl_ke_hoach_dau_nam'
           THEN nullif(u.patch->>'sl_ke_hoach_dau_nam', '')::numeric
           ELSE s.sl_ke_hoach_dau_nam END,
    doanh_thu_kh_dau_nam  = CASE WHEN u.patch ? 'doanh_thu_kh_dau_nam'
           THEN nullif(u.patch->>'doanh_thu_kh_dau_nam', '')::numeric
           ELSE s.doanh_thu_kh_dau_nam END
  FROM   u
  WHERE  s.id = u.id
    AND  (u.client_rev IS NULL OR s._rev = u.client_rev)
    AND  (p_bu     IS NULL OR s.bu            =     p_bu)
    AND  (shared.mien_in(s.mien, p_mien))
    AND  (p_ps     IS NULL OR s.ps            =     p_ps)
    AND  (p_groups IS NULL OR s.nhom_san_pham = ANY(p_groups));

  GET DIAGNOSTICS v_done = ROW_COUNT;
  RETURN jsonb_build_object('updated', v_done, 'conflicts', v_conflicts);
END;
$function$
;

CREATE OR REPLACE FUNCTION public.upsert_dm_dia_ban(p_rows jsonb, p_bu text, p_mien text, p_ps text, p_groups text[])
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'shared'
AS $function$
DECLARE
  v_in   integer;
  v_ids  integer;
  v_okid integer;
  v_ins  integer := 0;
  v_upd  integer := 0;
  v_ids_touched bigint[];
  v_apply jsonb;
BEGIN
  CREATE TEMP TABLE _rows ON COMMIT DROP AS
  SELECT nullif(e->>'id', '')::bigint                            AS id,
         btrim(coalesce(e->>'bu', ''))                           AS bu,
         btrim(coalesce(e->>'ma_khach_hang', ''))                AS ma_khach_hang,
         nullif(btrim(coalesce(e->>'khach_hang', '')), '')       AS khach_hang,
         btrim(coalesce(e->>'nhom_san_pham', ''))                AS nhom_san_pham,
         nullif(btrim(coalesce(e->>'mien', '')), '')             AS mien,
         btrim(coalesce(e->>'ps', ''))                           AS ps,
         coalesce((e->>'active')::boolean, true)                 AS active,
         nullif(btrim(coalesce(e->>'tu_thang', '')), '')         AS tu_thang,
         nullif(btrim(coalesce(e->>'den_thang', '')), '')        AS den_thang,
         coalesce(nullif(btrim(coalesce(e->>'ma_khach_hang', '')), ''),
                  btrim(coalesce(e->>'khach_hang', '')))         AS cust_key
  FROM   jsonb_array_elements(coalesce(p_rows, '[]'::jsonb)) e;

  SELECT count(*) INTO v_in FROM _rows;
  IF v_in = 0 THEN
    RETURN jsonb_build_object('inserted', 0, 'updated', 0);
  END IF;

  IF EXISTS (SELECT 1 FROM _rows
              WHERE nhom_san_pham = '' OR ps = '' OR coalesce(cust_key, '') = ''
                 OR (id IS NULL AND bu = '')) THEN
    RAISE EXCEPTION 'thieu_du_lieu: bu / khach_hang / nhom_san_pham / ps không được rỗng'
      USING ERRCODE = '22023';
  END IF;

  IF EXISTS (
    SELECT 1 FROM _rows r
     WHERE (p_bu     IS NOT NULL AND r.id IS NULL AND r.bu <> p_bu)
        OR (p_mien IS NOT NULL AND NOT shared.mien_in(coalesce(r.mien, ''), p_mien))
        OR (p_ps     IS NOT NULL AND r.ps <> p_ps)
        OR (p_groups IS NOT NULL AND NOT (r.nhom_san_pham = ANY(p_groups)))
  ) THEN
    RAISE EXCEPTION 'out_of_scope: dòng ghi vào nằm ngoài phạm vi quyền'
      USING ERRCODE = '42501';
  END IF;

  SELECT count(*), count(d.id) INTO v_ids, v_okid
    FROM _rows r
    LEFT JOIN dm_dia_ban d
           ON d.id = r.id
          AND (p_bu     IS NULL OR d.bu            =     p_bu)
          AND (shared.mien_in(d.mien, p_mien))
          AND (p_ps     IS NULL OR d.ps            =     p_ps)
          AND (p_groups IS NULL OR d.nhom_san_pham = ANY(p_groups))
   WHERE r.id IS NOT NULL;
  IF v_okid <> v_ids THEN
    RAISE EXCEPTION 'out_of_scope: % / % dòng sửa nằm ngoài phạm vi quyền hoặc không còn tồn tại',
                    v_ids - v_okid, v_ids
      USING ERRCODE = '42501';
  END IF;

  BEGIN
    WITH u AS (
      UPDATE dm_dia_ban d SET
        ma_khach_hang = r.ma_khach_hang,
        khach_hang    = coalesce(r.khach_hang, d.khach_hang),
        nhom_san_pham = r.nhom_san_pham,
        mien          = r.mien,
        ps            = r.ps,
        active        = r.active,
        tu_thang      = coalesce(r.tu_thang, d.tu_thang),
        den_thang     = CASE WHEN r.tu_thang IS NULL THEN d.den_thang ELSE r.den_thang END,
        updated_at    = now()
      FROM   _rows r
      WHERE  d.id = r.id
      RETURNING d.id
    ) SELECT count(*) INTO v_upd FROM u;

    WITH i AS (
      INSERT INTO dm_dia_ban (bu, ma_khach_hang, khach_hang, nhom_san_pham, mien, ps,
                              active, tu_thang, den_thang)
      SELECT DISTINCT ON (r.bu, r.cust_key, r.nhom_san_pham, r.ps, coalesce(r.tu_thang, '2026-04'))
             r.bu, r.ma_khach_hang, r.khach_hang, r.nhom_san_pham, r.mien, r.ps,
             r.active, coalesce(r.tu_thang, '2026-04'), r.den_thang
      FROM   _rows r
      WHERE  r.id IS NULL
      ORDER  BY r.bu, r.cust_key, r.nhom_san_pham, r.ps, coalesce(r.tu_thang, '2026-04')
      ON CONFLICT (bu, cust_key, nhom_san_pham, ps, tu_thang) DO UPDATE SET
        ma_khach_hang = excluded.ma_khach_hang,
        khach_hang    = coalesce(excluded.khach_hang, dm_dia_ban.khach_hang),
        mien          = excluded.mien,
        active        = excluded.active,
        den_thang     = excluded.den_thang,
        updated_at    = now()
      RETURNING id
    ) SELECT count(*) INTO v_ins FROM i;
  EXCEPTION WHEN unique_violation THEN
    RAISE EXCEPTION 'dup_dia_ban: địa bàn này đã được khai báo cho PS đó'
      USING ERRCODE = '23505';
  END;

  -- Tự apply cho các bản vừa động vào: 1 chuyến, không cần user bấm nút.
  -- Ambiguous (nhiều PS cho cùng tổ hợp) vẫn bị bỏ qua, số trả về để UI báo.
  SELECT array_agg(DISTINCT d.id)
    INTO v_ids_touched
    FROM dm_dia_ban d
    JOIN (
      -- dòng vừa update
      SELECT d2.id FROM dm_dia_ban d2 JOIN _rows r ON r.id = d2.id
      UNION
      -- dòng vừa insert / bị đè bởi ON CONFLICT (khớp theo khoá + tổ hợp)
      SELECT d3.id FROM dm_dia_ban d3
        JOIN _rows r ON r.id IS NULL
                    AND r.bu = d3.bu
                    AND r.cust_key = d3.cust_key
                    AND r.nhom_san_pham = d3.nhom_san_pham
                    AND r.ps = d3.ps
      -- Và cả tổ hợp CŨ của dòng bị sửa (khi sửa cust_key/nhom → tổ hợp cũ
      -- có thể cần apply lại). Lấy các bản khác của tổ hợp cũ.
      UNION
      SELECT d4.id FROM dm_dia_ban d4
        JOIN dm_dia_ban dOld ON dOld.bu = d4.bu
                            AND dOld.cust_key = d4.cust_key
                            AND dOld.nhom_san_pham = d4.nhom_san_pham
        JOIN _rows r ON r.id = dOld.id
                    AND (r.cust_key <> dOld.cust_key OR r.nhom_san_pham <> dOld.nhom_san_pham)
    ) t ON t.id = d.id;

  IF v_ids_touched IS NOT NULL AND array_length(v_ids_touched, 1) > 0 THEN
    v_apply := public.apply_dia_ban_to_plan(v_ids_touched);
  END IF;

  RETURN jsonb_build_object(
    'inserted',    v_ins,
    'updated',     v_upd,
    'apply',       v_apply,
    'auto_apply',  true
  );
END;
$function$
;

commit;
