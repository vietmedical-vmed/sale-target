-- execute_sync_job ghi started_at và finished_at cùng bằng now() trong MỘT transaction,
-- nên mọi job đều hiện chạy 0 giây (thực tế ~50 s theo pg_stat_statements). now() là giờ
-- bắt đầu transaction → giữ cho started_at; finished_at dùng clock_timestamp() (giờ thật
-- lúc ghi) để đo được thời gian đồng bộ thực hiện.
-- CREATE OR REPLACE giữ nguyên quyền EXECUTE hiện có (chỉ service_role/postgres).
-- Hoàn tác: supabase/rollbacks/20261107120000_sync_job_thoi_gian_that_ROLLBACK.sql

CREATE OR REPLACE FUNCTION public.execute_sync_job(p_job_id bigint)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'shared'
 SET statement_timeout TO '5min'
AS $function$
DECLARE v_result jsonb;
BEGIN
  UPDATE shared.sync_job SET status = 'running', started_at = now() WHERE id = p_job_id;
  BEGIN
    v_result := public.cap_nhat_thuc_hien();
    UPDATE shared.sync_job SET status = 'done', result = v_result, finished_at = clock_timestamp() WHERE id = p_job_id;
  EXCEPTION WHEN OTHERS THEN
    UPDATE shared.sync_job SET status = 'error', error = SQLERRM, finished_at = clock_timestamp() WHERE id = p_job_id;
  END;
END;
$function$;

DO $$
BEGIN
  IF has_function_privilege('anon', 'public.execute_sync_job(bigint)', 'EXECUTE')
     OR has_function_privilege('authenticated', 'public.execute_sync_job(bigint)', 'EXECUTE') THEN
    RAISE EXCEPTION 'execute_sync_job_mo_cho_anon';
  END IF;
END $$;
