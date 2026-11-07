-- Đồng bộ thực hiện ghi hàng nghìn dòng sale_target trong một transaction ~50 s. _rev của
-- các dòng đó lấy từ sequence lúc ghi (sớm) nhưng chỉ thấy được lúc commit (muộn), nên
-- client nào poll getChanges trong lúc đó đã đẩy con trỏ qua → không bao giờ nhận số
-- thực hiện mới tới khi F5. Sửa: tăng shared.app_config.sale_target_epoch trong CÙNG
-- transaction; client thấy epoch đổi thì tải lại toàn bộ (edge getChanges trả epoch).
-- Giữ finished_at = clock_timestamp() (20261107120000). CREATE OR REPLACE giữ quyền cũ.
-- Hoàn tác: supabase/rollbacks/20261107130000_sync_job_tang_epoch_ROLLBACK.sql

INSERT INTO shared.app_config (key, value)
VALUES ('sale_target_epoch', to_jsonb(now()::text))
ON CONFLICT (key) DO NOTHING;

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
    INSERT INTO shared.app_config (key, value, updated_at)
    VALUES ('sale_target_epoch', to_jsonb(clock_timestamp()::text), now())
    ON CONFLICT (key) DO UPDATE SET value = excluded.value, updated_at = excluded.updated_at;
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
  IF NOT EXISTS (SELECT 1 FROM shared.app_config WHERE key = 'sale_target_epoch') THEN
    RAISE EXCEPTION 'thieu_sale_target_epoch';
  END IF;
END $$;
