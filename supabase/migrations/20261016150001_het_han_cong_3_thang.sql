-- Đổi cách tính tháng hết hiệu lực thầu (user chốt 16/10):
--   tháng cuối còn hiệu lực = tháng thầu + 3 tháng + hiệu lực − 1
--   vd tháng thầu 2026-03, hiệu lực 24 tháng → còn hiệu lực đến hết 2028-05.
-- Trước đây: tháng thầu + hiệu lực − 1. Frontend dùng cùng công thức (lib/quota.js).

CREATE OR REPLACE FUNCTION shared.het_han_dot(p_thang text, p_hieu_luc numeric)
RETURNS text LANGUAGE sql IMMUTABLE AS $$
  SELECT CASE WHEN p_thang ~ '^\d{4}-\d{2}$' AND p_hieu_luc > 0
              THEN to_char(to_date(p_thang || '-01', 'YYYY-MM-DD')
                           + make_interval(months => 3 + p_hieu_luc::int - 1), 'YYYY-MM') END;
$$;
REVOKE ALL ON FUNCTION shared.het_han_dot(text, numeric) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION shared.het_han_dot(text, numeric) TO service_role;
