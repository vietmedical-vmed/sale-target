-- Lịch sử cập nhật phân quyền theo vai trò của tài khoản xem.
--
-- Trước đây chỉ admin/manager mở được tab và thấy mọi log, kể cả log của admin.
-- Từ nay mọi vai trò mở được tab, nhưng chỉ thấy log trong phạm vi của mình:
--   admin          : mọi log.
--   manager        : mọi log trừ log của admin.
--   area_manager   : log của chính mình + log PS cùng BU thuộc miền phụ trách.
--   vai trò khác   : chỉ log của chính mình (ps, product_manager, purchasing).
-- "Log của admin" = log ghi lúc người thao tác có role 'admin', hoặc role trống (script nạp
-- dữ liệu như admin_script). Luật này áp cho cả log của chính mình: chỉ admin thấy log admin.
--
-- Mọi hàm nhận phạm vi xem qua p_xem_role / p_xem_user / p_xem_bu / p_xem_mien do edge function
-- truyền từ phiên đăng nhập. p_xem_role NULL thì không thấy gì.

-- Tập log mà tài khoản xem được. Miền của PS lấy từ dm_ps (theo tên PS = users.scope), không có
-- thì quy từ users.mien (MB/MN/MT).
CREATE OR REPLACE FUNCTION public.audit_log_xem(
  p_xem_role text, p_xem_user text, p_xem_bu text, p_xem_mien text[]
)
RETURNS SETOF shared.audit_log
LANGUAGE sql STABLE
SET search_path = ''
AS $$
  SELECT a.*
  FROM shared.audit_log a
  WHERE CASE
    WHEN p_xem_role = 'admin' THEN true
    WHEN coalesce(a.role, 'admin') = 'admin' THEN false
    WHEN p_xem_role = 'manager' THEN true
    WHEN a.username = p_xem_user THEN true
    WHEN p_xem_role = 'area_manager' THEN
      a.role = 'ps' AND a.bu = p_xem_bu
      AND EXISTS (
        SELECT 1 FROM shared.users u
        WHERE u.username = a.username
          AND coalesce(
                (SELECT min(d.area) FROM shared.dm_ps d WHERE lower(trim(d.ps)) = lower(trim(u.scope))),
                CASE u.mien WHEN 'MB' THEN 'Miền Bắc' WHEN 'MN' THEN 'Miền Nam' WHEN 'MT' THEN 'Miền Trung' END
              ) = ANY (p_xem_mien)
      )
    ELSE false
  END;
$$;

DROP FUNCTION IF EXISTS public.audit_nhom(timestamptz, timestamptz, text, text[], text, text, int, int);
DROP FUNCTION IF EXISTS public.audit_lich_su_dong(bigint[]);
DROP FUNCTION IF EXISTS public.audit_deadline(text, int, text);

-- Danh sách nhóm (ngày VN + người + thao tác), phân trang theo nhóm, chỉ trong phạm vi xem.
CREATE OR REPLACE FUNCTION public.audit_nhom(
  p_from timestamptz DEFAULT NULL,
  p_to timestamptz DEFAULT NULL,
  p_username text DEFAULT NULL,
  p_actions text[] DEFAULT NULL,
  p_bu text DEFAULT NULL,
  p_q text DEFAULT NULL,
  p_offset int DEFAULT 0,
  p_limit int DEFAULT 50,
  p_xem_role text DEFAULT NULL,
  p_xem_user text DEFAULT NULL,
  p_xem_bu text DEFAULT NULL,
  p_xem_mien text[] DEFAULT NULL
)
RETURNS jsonb
LANGUAGE sql STABLE
SET search_path = ''
AS $$
  WITH xem AS (
    SELECT * FROM public.audit_log_xem(p_xem_role, p_xem_user, p_xem_bu, p_xem_mien)
  ),
  l AS (
    SELECT a.id, a.username, a.ho_ten, a.role, a.bu, a.action, a.row_count, a.details, a.created_at,
           (a.created_at AT TIME ZONE 'Asia/Ho_Chi_Minh')::date AS ngay
    FROM xem a
    WHERE (p_from IS NULL OR a.created_at >= p_from)
      AND (p_to IS NULL OR a.created_at < p_to)
      AND (p_username IS NULL OR a.username = p_username)
      AND (p_actions IS NULL OR a.action = ANY (p_actions))
      AND (p_bu IS NULL OR a.bu = p_bu)
      AND (
        nullif(trim(p_q), '') IS NULL
        OR concat_ws(' ', a.ho_ten, a.username, a.details::text)
           ILIKE '%' || replace(replace(replace(trim(p_q), '\', '\\'), '%', '\%'), '_', '\_') || '%'
      )
  ),
  g AS (
    SELECT ngay, username, action,
           (array_agg(ho_ten ORDER BY created_at DESC))[1] AS ho_ten,
           (array_agg(role ORDER BY created_at DESC))[1] AS role,
           (array_agg(bu ORDER BY created_at DESC))[1] AS bu,
           count(*) AS so_lan, sum(row_count) AS tong_dong,
           min(created_at) AS first_at, max(created_at) AS last_at,
           array_agg(id ORDER BY created_at DESC) AS log_ids
    FROM l
    GROUP BY ngay, username, action
  ),
  kh AS (
    SELECT l.ngay, l.username, l.action,
           coalesce(c->>'cust', l.details->>'cust') AS kh,
           coalesce(c->>'ps', l.details->>'ps') AS ps
    FROM l
    LEFT JOIN LATERAL jsonb_array_elements(
      CASE WHEN jsonb_typeof(l.details->'changes') = 'array' THEN l.details->'changes'
           WHEN jsonb_typeof(l.details->'rows') = 'array' THEN l.details->'rows'
           ELSE '[]'::jsonb END
    ) c ON true
  ),
  khg AS (
    SELECT ngay, username, action,
           (array_agg(DISTINCT kh) FILTER (WHERE kh IS NOT NULL))[1:3] AS khach_hang,
           count(DISTINCT kh) AS so_kh,
           (array_agg(DISTINCT ps) FILTER (WHERE ps IS NOT NULL))[1:3] AS ps,
           count(DISTINCT ps) AS so_ps
    FROM kh
    GROUP BY ngay, username, action
  ),
  cot AS (
    SELECT l.ngay, l.username, l.action, array_agg(DISTINCT c) AS cot
    FROM l
    CROSS JOIN LATERAL jsonb_array_elements_text(
      CASE WHEN jsonb_typeof(l.details->'columns') = 'array' THEN l.details->'columns' ELSE '[]'::jsonb END
    ) c
    GROUP BY l.ngay, l.username, l.action
  ),
  trang AS (
    SELECT g.ngay, g.username, g.action, coalesce(nullif(u.ho_va_ten, ''), g.ho_ten) AS ho_ten,
           g.role, g.bu, g.so_lan, g.tong_dong, g.first_at, g.last_at, g.log_ids,
           khg.khach_hang, khg.so_kh, khg.ps, khg.so_ps, cot.cot
    FROM g
    LEFT JOIN shared.users u ON u.username = g.username
    LEFT JOIN khg ON khg.ngay = g.ngay AND khg.username = g.username AND khg.action = g.action
    LEFT JOIN cot ON cot.ngay = g.ngay AND cot.username = g.username AND cot.action = g.action
    ORDER BY g.last_at DESC
    OFFSET greatest(p_offset, 0)
    LIMIT least(greatest(p_limit, 1), 200)
  )
  SELECT jsonb_build_object(
    'total', (SELECT count(*) FROM g),
    'tong_ban_ghi', (SELECT count(*) FROM l),
    'groups', coalesce((SELECT jsonb_agg(to_jsonb(t) ORDER BY t.last_at DESC) FROM trang t), '[]'::jsonb),
    -- Bộ lọc người dùng chỉ liệt kê người có log trong phạm vi xem.
    'users', coalesce((
      SELECT jsonb_agg(jsonb_build_object('username', username, 'ho_ten', ho_ten) ORDER BY ho_ten)
      FROM (
        SELECT a.username,
               coalesce(nullif(max(u.ho_va_ten), ''), (array_agg(a.ho_ten ORDER BY a.created_at DESC))[1]) AS ho_ten
        FROM xem a
        LEFT JOIN shared.users u ON u.username = a.username
        GROUP BY a.username
      ) x
    ), '[]'::jsonb)
  );
$$;

-- Chi tiết một nhóm: log thô + thay đổi từng ô, chỉ với log id nằm trong phạm vi xem.
CREATE OR REPLACE FUNCTION public.audit_chi_tiet(
  p_log_ids bigint[],
  p_xem_role text, p_xem_user text, p_xem_bu text, p_xem_mien text[]
)
RETURNS jsonb
LANGUAGE sql STABLE
SET search_path = ''
AS $$
  WITH ok AS (
    SELECT a.id, a.created_at, a.action, a.row_count, a.details, a.thang_ke_hoach
    FROM public.audit_log_xem(p_xem_role, p_xem_user, p_xem_bu, p_xem_mien) a
    WHERE a.id = ANY (p_log_ids)
  )
  SELECT jsonb_build_object(
    'logs', coalesce((SELECT jsonb_agg(to_jsonb(ok) ORDER BY ok.created_at DESC) FROM ok), '[]'::jsonb),
    'thay_doi', public.audit_thay_doi(coalesce((SELECT array_agg(id) FROM ok), '{}'::bigint[]), NULL)
  );
$$;

-- Lịch sử của một sản phẩm (tập id sale_target, mọi tháng), chỉ các lượt sửa trong phạm vi xem.
CREATE OR REPLACE FUNCTION public.audit_lich_su_dong(
  p_row_ids bigint[],
  p_xem_role text DEFAULT NULL,
  p_xem_user text DEFAULT NULL,
  p_xem_bu text DEFAULT NULL,
  p_xem_mien text[] DEFAULT NULL
)
RETURNS jsonb
LANGUAGE sql STABLE
SET search_path = ''
AS $$
  WITH l AS (
    SELECT a.id, a.username, coalesce(nullif(u.ho_va_ten, ''), a.ho_ten) AS ho_ten, a.created_at, a.details
    FROM public.audit_log_xem(p_xem_role, p_xem_user, p_xem_bu, p_xem_mien) a
    LEFT JOIN shared.users u ON u.username = a.username
    WHERE a.action = 'updateCells'
      AND jsonb_typeof(a.details->'ids') = 'array'
      AND EXISTS (
        SELECT 1 FROM jsonb_array_elements_text(a.details->'ids') i
        WHERE i::bigint = ANY (p_row_ids)
      )
  ),
  co_chi_tiet AS (
    SELECT DISTINCT l.id
    FROM l
    CROSS JOIN LATERAL jsonb_array_elements(
      CASE WHEN jsonb_typeof(l.details->'changes') = 'array' THEN l.details->'changes' ELSE '[]'::jsonb END
    ) c
    WHERE (c->>'id')::bigint = ANY (p_row_ids)
  )
  SELECT jsonb_build_object(
    'thay_doi', public.audit_thay_doi(coalesce((SELECT array_agg(id) FROM co_chi_tiet), '{}'::bigint[]), p_row_ids),
    'thieu_chi_tiet', coalesce((
      SELECT jsonb_agg(jsonb_build_object(
        'log_id', l.id, 'at', l.created_at, 'username', l.username, 'ho_ten', l.ho_ten,
        'cot', l.details->'columns'
      ) ORDER BY l.created_at DESC)
      FROM l WHERE l.id NOT IN (SELECT id FROM co_chi_tiet)
    ), '[]'::jsonb)
  );
$$;

-- Tổng quan deadline kỳ tháng p_thang. Danh sách PS gốc cũng theo phạm vi xem:
-- admin/manager mọi PS, area_manager PS cùng BU thuộc miền phụ trách, vai trò khác chỉ chính mình.
CREATE OR REPLACE FUNCTION public.audit_deadline(
  p_thang text, p_han int, p_bu text DEFAULT NULL,
  p_xem_role text DEFAULT NULL,
  p_xem_user text DEFAULT NULL,
  p_xem_bu text DEFAULT NULL,
  p_xem_mien text[] DEFAULT NULL
)
RETURNS jsonb
LANGUAGE sql STABLE
SET search_path = ''
AS $$
  WITH ky AS (
    SELECT ((to_date(p_thang || '-01', 'YYYY-MM-DD') - interval '1 month' + make_interval(days => p_han))
              AT TIME ZONE 'Asia/Ho_Chi_Minh') AS tu,
           ((to_date(p_thang || '-01', 'YYYY-MM-DD') + make_interval(days => p_han))
              AT TIME ZONE 'Asia/Ho_Chi_Minh') AS den
  ),
  sua AS (
    SELECT a.username,
           (array_agg(a.ho_ten ORDER BY a.created_at DESC))[1] AS ho_ten,
           (array_agg(a.role ORDER BY a.created_at DESC))[1] AS role,
           (array_agg(a.bu ORDER BY a.created_at DESC))[1] AS bu,
           count(*) AS so_lan, sum(a.row_count) AS so_dong,
           min(a.created_at) AS lan_dau, max(a.created_at) AS lan_cuoi
    FROM public.audit_log_xem(p_xem_role, p_xem_user, p_xem_bu, p_xem_mien) a, ky
    WHERE a.action = 'updateCells'
      AND a.created_at >= ky.tu AND a.created_at < ky.den
      AND a.details->'columns' ? 'revUpd'
      AND (p_bu IS NULL OR a.bu = p_bu)
    GROUP BY a.username
  ),
  ps AS (
    SELECT u.username, coalesce(u.ho_va_ten, u.username) AS ho_ten, u.role, u.bu
    FROM shared.users u
    WHERE u.role = 'ps' AND u.active IS NOT FALSE
      AND (p_bu IS NULL OR u.bu = p_bu)
      AND (
        p_xem_role IN ('admin', 'manager')
        OR u.username = p_xem_user
        OR (
          p_xem_role = 'area_manager' AND u.bu = p_xem_bu
          AND coalesce(
                (SELECT min(d.area) FROM shared.dm_ps d WHERE lower(trim(d.ps)) = lower(trim(u.scope))),
                CASE u.mien WHEN 'MB' THEN 'Miền Bắc' WHEN 'MN' THEN 'Miền Nam' WHEN 'MT' THEN 'Miền Trung' END
              ) = ANY (p_xem_mien)
        )
      )
  ),
  ds AS (
    SELECT coalesce(ps.username, sua.username) AS username,
           coalesce(ps.ho_ten, sua.ho_ten) AS ho_ten,
           coalesce(ps.role, sua.role) AS role,
           coalesce(ps.bu, sua.bu) AS bu,
           coalesce(sua.so_lan, 0) AS so_lan,
           coalesce(sua.so_dong, 0) AS so_dong,
           sua.lan_dau, sua.lan_cuoi
    FROM ps FULL JOIN sua ON sua.username = ps.username
  )
  SELECT jsonb_build_object(
    'tu', (SELECT tu FROM ky),
    'den', (SELECT den FROM ky),
    'users', coalesce((
      SELECT jsonb_agg(to_jsonb(ds) ORDER BY (ds.so_lan = 0) DESC, ds.bu, ds.ho_ten) FROM ds
    ), '[]'::jsonb)
  );
$$;

-- DROP + CREATE làm mất quyền cũ: chỉ service_role (edge function) được gọi.
REVOKE ALL ON FUNCTION public.audit_log_xem(text, text, text, text[]) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.audit_nhom(timestamptz, timestamptz, text, text[], text, text, int, int, text, text, text, text[]) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.audit_chi_tiet(bigint[], text, text, text, text[]) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.audit_lich_su_dong(bigint[], text, text, text, text[]) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.audit_deadline(text, int, text, text, text, text, text[]) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.audit_log_xem(text, text, text, text[]) TO service_role;
GRANT EXECUTE ON FUNCTION public.audit_nhom(timestamptz, timestamptz, text, text[], text, text, int, int, text, text, text, text[]) TO service_role;
GRANT EXECUTE ON FUNCTION public.audit_chi_tiet(bigint[], text, text, text, text[]) TO service_role;
GRANT EXECUTE ON FUNCTION public.audit_lich_su_dong(bigint[], text, text, text, text[]) TO service_role;
GRANT EXECUTE ON FUNCTION public.audit_deadline(text, int, text, text, text, text, text[]) TO service_role;
