-- GĐ 2.4d: "Đồng bộ thực hiện" chạy nền, UI hiện tiến độ (P7).
-- pg_net gọi PostgREST async; edge function trả jobId ngay, client poll status.
-- ============================================================================

CREATE EXTENSION IF NOT EXISTS pg_net WITH SCHEMA extensions;

-- Config table (service_role_key + supabase_url cho pg_net).
CREATE TABLE IF NOT EXISTS shared._internal_config (
  key   text PRIMARY KEY,
  value text NOT NULL
);
REVOKE ALL ON shared._internal_config FROM PUBLIC, anon, authenticated;

-- Job tracking table
CREATE TABLE IF NOT EXISTS shared.sync_job (
  id          bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  status      text NOT NULL DEFAULT 'pending',
  started_by  text,
  started_at  timestamptz DEFAULT now(),
  finished_at timestamptz,
  result      jsonb,
  error       text
);
REVOKE ALL ON shared.sync_job FROM PUBLIC, anon, authenticated;
GRANT SELECT, INSERT, UPDATE ON shared.sync_job TO service_role;

-- Worker: runs cap_nhat_thuc_hien and updates job row.
CREATE OR REPLACE FUNCTION public.execute_sync_job(p_job_id bigint)
RETURNS void
LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public, shared
SET statement_timeout = '5min'
AS $fn$
DECLARE
  v_result jsonb;
BEGIN
  UPDATE shared.sync_job SET status = 'running', started_at = now()
    WHERE id = p_job_id;
  BEGIN
    v_result := public.cap_nhat_thuc_hien();
    UPDATE shared.sync_job
      SET status = 'done', result = v_result, finished_at = now()
      WHERE id = p_job_id;
  EXCEPTION WHEN OTHERS THEN
    UPDATE shared.sync_job
      SET status = 'error', error = SQLERRM, finished_at = now()
      WHERE id = p_job_id;
  END;
END;
$fn$;

REVOKE ALL ON FUNCTION public.execute_sync_job(bigint) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.execute_sync_job(bigint) TO service_role;

-- Starter: creates job, fires pg_net async call, returns jobId immediately.
CREATE OR REPLACE FUNCTION public.start_sync_job(p_actor text DEFAULT NULL)
RETURNS bigint
LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public, shared, extensions
AS $fn$
DECLARE
  v_id  bigint;
  v_url text;
  v_key text;
BEGIN
  SELECT j.id INTO v_id FROM shared.sync_job j
    WHERE j.status IN ('pending', 'running')
      AND j.started_at > now() - interval '10 minutes'
    LIMIT 1;
  IF v_id IS NOT NULL THEN
    RAISE EXCEPTION 'sync_already_running: job % is still running', v_id
      USING ERRCODE = '23505';
  END IF;

  INSERT INTO shared.sync_job (status, started_by)
    VALUES ('pending', p_actor)
    RETURNING id INTO v_id;

  SELECT value INTO v_url FROM shared._internal_config WHERE key = 'supabase_url';
  SELECT value INTO v_key FROM shared._internal_config WHERE key = 'service_role_key';

  PERFORM net.http_post(
    url     := v_url || '/rest/v1/rpc/execute_sync_job',
    headers := jsonb_build_object(
      'apikey', v_key,
      'Authorization', 'Bearer ' || v_key,
      'Content-Type', 'application/json'
    ),
    body    := jsonb_build_object('p_job_id', v_id)
  );

  RETURN v_id;
END;
$fn$;

REVOKE ALL ON FUNCTION public.start_sync_job(text) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.start_sync_job(text) TO service_role;

COMMENT ON FUNCTION public.start_sync_job(text) IS
  'Tạo sync job, fire pg_net async, trả jobId ngay. Client poll syncJobStatus.';
COMMENT ON FUNCTION public.execute_sync_job(bigint) IS
  'Worker: chạy cap_nhat_thuc_hien và cập nhật sync_job row. Được gọi bởi pg_net.';
