-- HOÀN TÁC 20261107120000_sync_job_thoi_gian_that.sql: finished_at quay lại now().
-- Chạy tay qua SQL Editor; KHÔNG để file này trong supabase/migrations/.

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
    UPDATE shared.sync_job SET status = 'done', result = v_result, finished_at = now() WHERE id = p_job_id;
  EXCEPTION WHEN OTHERS THEN
    UPDATE shared.sync_job SET status = 'error', error = SQLERRM, finished_at = now() WHERE id = p_job_id;
  END;
END;
$function$;
