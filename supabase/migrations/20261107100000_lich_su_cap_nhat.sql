-- Lịch sử cập nhật: gom nhóm, chi tiết thay đổi, lịch sử theo sản phẩm và tổng quan deadline
-- đều tính ở server. Trước đây frontend gom nhóm trên đúng 50 bản ghi thô của trang hiện tại nên
-- một nhóm (ngày + người + thao tác) bị cắt qua nhiều trang, còn tổng quan deadline chỉ đếm 50 log.
--
-- Mọi hàm là SECURITY INVOKER, chỉ service_role (edge function) gọi được. Edge function tự kiểm
-- quyền: getAuditLog cho admin/manager, lịch sử sản phẩm lọc id theo phạm vi của phiên.
-- Ngày giờ quy về giờ Việt Nam (Asia/Ho_Chi_Minh).

-- Lọc theo thao tác + thời gian (tổng quan deadline, lịch sử sản phẩm).
CREATE INDEX IF NOT EXISTS idx_audit_log_action_created
  ON shared.audit_log (action, created_at DESC);

-- Danh sách thay đổi đã trải phẳng của các log updateCells: mỗi phần tử là một ô (dòng × cột).
-- Bổ sung sản phẩm / bộ / nhóm / tháng từ sale_target cho log cũ (log trước 07/11/2026 không lưu
-- các trường này). Bỏ các "thay đổi" rỗng: null ↔ 0 khi ghi 0 vào các dòng phụ của cùng tháng.
CREATE OR REPLACE FUNCTION public.audit_thay_doi(p_log_ids bigint[], p_row_ids bigint[] DEFAULT NULL)
RETURNS jsonb
LANGUAGE sql STABLE
SET search_path = ''
AS $$
  SELECT coalesce(jsonb_agg(x ORDER BY x->>'at' DESC, x->>'kh', x->>'sp', x->>'thang', x->>'cot'), '[]'::jsonb)
  FROM (
    SELECT jsonb_build_object(
      'log_id', l.id,
      'at', l.created_at,
      'username', l.username,
      'ho_ten', coalesce(nullif(u.ho_va_ten, ''), l.ho_ten),
      'row_id', (c->>'id')::bigint,
      'ps', c->>'ps',
      'kh', c->>'cust',
      'ma_kh', c->>'custId',
      'nhom', coalesce(c->>'grp', st.nhom_san_pham),
      'bo', coalesce(c->>'mset', st.bo_vat_tu),
      'sp', coalesce(c->>'prod', st.san_pham),
      'thang', coalesce(c->>'mo', st.thang_ke_hoach),
      'cot', d.key,
      'cu', d.value->'old',
      'moi', d.value->'new'
    ) AS x
    FROM shared.audit_log l
    CROSS JOIN LATERAL jsonb_array_elements(
      CASE WHEN jsonb_typeof(l.details->'changes') = 'array' THEN l.details->'changes' ELSE '[]'::jsonb END
    ) c
    CROSS JOIN LATERAL jsonb_each(
      CASE WHEN jsonb_typeof(c->'diff') = 'object' THEN c->'diff' ELSE '{}'::jsonb END
    ) d
    LEFT JOIN shared.sale_target st ON st.id = (c->>'id')::bigint
    LEFT JOIN shared.users u ON u.username = l.username
    WHERE l.id = ANY (p_log_ids)
      AND l.action = 'updateCells'
      AND (p_row_ids IS NULL OR (c->>'id')::bigint = ANY (p_row_ids))
      AND coalesce(nullif(d.value->>'old', ''), '0') IS DISTINCT FROM coalesce(nullif(d.value->>'new', ''), '0')
  ) s;
$$;

-- Danh sách nhóm (ngày VN + người + thao tác), phân trang theo nhóm.
-- p_q tìm trong họ tên / username / nội dung details (tên khách hàng, sản phẩm, PS...).
CREATE OR REPLACE FUNCTION public.audit_nhom(
  p_from timestamptz DEFAULT NULL,
  p_to timestamptz DEFAULT NULL,
  p_username text DEFAULT NULL,
  p_actions text[] DEFAULT NULL,
  p_bu text DEFAULT NULL,
  p_q text DEFAULT NULL,
  p_offset int DEFAULT 0,
  p_limit int DEFAULT 50
)
RETURNS jsonb
LANGUAGE sql STABLE
SET search_path = ''
AS $$
  WITH l AS (
    SELECT a.id, a.username, a.ho_ten, a.role, a.bu, a.action, a.row_count, a.details, a.created_at,
           (a.created_at AT TIME ZONE 'Asia/Ho_Chi_Minh')::date AS ngay
    FROM shared.audit_log a
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
  -- Khách hàng / PS / cột chạm tới, để dòng tóm tắt đọc được ngay mà không phải mở chi tiết.
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
  -- Họ tên lấy từ shared.users (log cũ có lượt ghi họ tên = "PS").
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
    'users', coalesce((
      SELECT jsonb_agg(jsonb_build_object('username', username, 'ho_ten', ho_ten) ORDER BY ho_ten)
      FROM (
        SELECT a.username,
               coalesce(nullif(max(u.ho_va_ten), ''), (array_agg(a.ho_ten ORDER BY a.created_at DESC))[1]) AS ho_ten
        FROM shared.audit_log a
        LEFT JOIN shared.users u ON u.username = a.username
        GROUP BY a.username
      ) x
    ), '[]'::jsonb)
  );
$$;

-- Lịch sử của một sản phẩm (tập id sale_target, mọi tháng). Gồm cả các lượt sửa có chạm id
-- nhưng không lưu chi tiết (log cũ chỉ lưu 50 dòng đầu): trả trong 'thieu_chi_tiet'.
CREATE OR REPLACE FUNCTION public.audit_lich_su_dong(p_row_ids bigint[])
RETURNS jsonb
LANGUAGE sql STABLE
SET search_path = ''
AS $$
  WITH l AS (
    SELECT a.id, a.username, coalesce(nullif(u.ho_va_ten, ''), a.ho_ten) AS ho_ten, a.created_at, a.details
    FROM shared.audit_log a
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
    'thay_doi', public.audit_thay_doi((SELECT array_agg(id) FROM co_chi_tiet), p_row_ids),
    'thieu_chi_tiet', coalesce((
      SELECT jsonb_agg(jsonb_build_object(
        'log_id', l.id, 'at', l.created_at, 'username', l.username, 'ho_ten', l.ho_ten,
        'cot', l.details->'columns'
      ) ORDER BY l.created_at DESC)
      FROM l WHERE l.id NOT IN (SELECT id FROM co_chi_tiet)
    ), '[]'::jsonb)
  );
$$;

-- Tổng quan deadline cho kỳ tháng p_thang ('YYYY-MM'): kỳ chạy từ ngày (p_han + 1) tháng trước
-- đến hết ngày p_han của tháng p_thang (giờ VN) — khớp lịch chụp kế hoạch và khoá SL KH update.
-- Chỉ đếm lượt sửa SL KH update (cột revUpd). Danh sách gốc = mọi PS đang hoạt động, cộng người
-- khác (quản lý miền, admin...) có sửa trong kỳ.
CREATE OR REPLACE FUNCTION public.audit_deadline(p_thang text, p_han int, p_bu text DEFAULT NULL)
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
    FROM shared.audit_log a, ky
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

REVOKE ALL ON FUNCTION public.audit_thay_doi(bigint[], bigint[]) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.audit_nhom(timestamptz, timestamptz, text, text[], text, text, int, int) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.audit_lich_su_dong(bigint[]) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.audit_deadline(text, int, text) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.audit_thay_doi(bigint[], bigint[]) TO service_role;
GRANT EXECUTE ON FUNCTION public.audit_nhom(timestamptz, timestamptz, text, text[], text, text, int, int) TO service_role;
GRANT EXECUTE ON FUNCTION public.audit_lich_su_dong(bigint[]) TO service_role;
GRANT EXECUTE ON FUNCTION public.audit_deadline(text, int, text) TO service_role;
