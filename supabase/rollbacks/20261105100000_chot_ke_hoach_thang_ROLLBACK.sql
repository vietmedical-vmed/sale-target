-- Hoàn tác 20261105100000_chot_ke_hoach_thang.sql
-- Xoá lịch cron, hàm và bảng chụp. Mất mọi bản chụp kế hoạch đã có: chép ra backup trước
-- nếu cần giữ (CREATE TABLE backup.bak_ke_hoach_chot AS SELECT * FROM shared.ke_hoach_chot ...).

BEGIN;

SELECT cron.unschedule('chot-ke-hoach-thang')
WHERE EXISTS (SELECT 1 FROM cron.job WHERE jobname = 'chot-ke-hoach-thang');

DROP FUNCTION IF EXISTS public.so_sanh_chot_ke_hoach(text, text);
DROP FUNCTION IF EXISTS public.chot_ke_hoach_tu_dong();
DROP FUNCTION IF EXISTS public.chot_ke_hoach(text, text, text, boolean);
DROP FUNCTION IF EXISTS shared.nam_tai_chinh_cua_thang(text);

DROP TABLE IF EXISTS shared.ke_hoach_chot;
DROP TABLE IF EXISTS shared.ke_hoach_chot_ky;

COMMIT;
