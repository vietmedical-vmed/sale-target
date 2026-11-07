-- Kiểm sau mỗi migration: anon key nằm công khai trong frontend, PostgREST mở các schema
-- trong pgrst.db_schemas. Kết quả PHẢI rỗng. Chạy:
--   supabase db query --linked -f supabase/checks/kiem_quyen_anon.sql
-- Mỗi dòng trả về là một đối tượng anon/authenticated đọc/ghi/gọi được mà không qua edge.
-- (Từng lọt: view hoa_don_bovattu_chia GRANT anon, policy giai_trinh_service TO PUBLIC,
-- update_sale_target_cells mở EXECUTE sau DROP + CREATE.)

WITH sch AS (
  SELECT unnest(ARRAY['public','shared','app_sale']) AS s
),
bang AS (
  SELECT 'bang/view' AS loai, c.relnamespace::regnamespace::text || '.' || c.relname AS ten,
         CASE c.relkind WHEN 'v' THEN 'view chạy quyền chủ (không security_invoker)'
                        WHEN 'm' THEN 'materialized view'
                        ELSE CASE WHEN NOT c.relrowsecurity THEN 'bảng tắt RLS' ELSE 'policy mở cho anon/PUBLIC' END
         END AS ly_do
  FROM pg_class c
  WHERE c.relnamespace::regnamespace::text IN (SELECT s FROM sch)
    AND c.relkind IN ('r','v','m','p')
    AND (has_table_privilege('anon', c.oid, 'SELECT,INSERT,UPDATE,DELETE')
         OR has_table_privilege('authenticated', c.oid, 'SELECT,INSERT,UPDATE,DELETE'))
    AND (
      (c.relkind IN ('v','m') AND NOT coalesce('security_invoker=true' = ANY (c.reloptions), false))
      OR (c.relkind IN ('r','p') AND (NOT c.relrowsecurity OR EXISTS (
            SELECT 1 FROM pg_policy p WHERE p.polrelid = c.oid
              AND (0 = ANY (p.polroles) OR 'anon'::regrole::oid = ANY (p.polroles)
                   OR 'authenticated'::regrole::oid = ANY (p.polroles)))))
    )
),
ham AS (
  SELECT 'ham' AS loai, n.nspname || '.' || p.proname || '(' || pg_get_function_identity_arguments(p.oid) || ')' AS ten,
         'SECURITY DEFINER gọi được bằng anon/authenticated' AS ly_do
  FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
  WHERE n.nspname IN (SELECT s FROM sch)
    AND p.prosecdef
    AND (has_function_privilege('anon', p.oid, 'EXECUTE') OR has_function_privilege('authenticated', p.oid, 'EXECUTE'))
    AND NOT EXISTS (SELECT 1 FROM pg_depend d WHERE d.objid = p.oid AND d.deptype = 'e')
    AND p.proname NOT IN ('rls_auto_enable', 'kpi_is_admin', 'kpi_is_manager_of')  -- của Supabase / app KPI (dùng Supabase Auth)
)
SELECT * FROM bang
UNION ALL
SELECT * FROM ham
ORDER BY 1, 2;
