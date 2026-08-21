-- ════════════════════════════════════════════════════════════════════════
-- Vá search_path cho dep_dia_ban_chong_lan — 'dm_dia_ban' nằm ở schema
-- 'shared' (di dời trong migration phase_shared_A 2026-08-05), nhưng RPC mới
-- viết chỉ có `SET search_path = public` → chạy trên app thật ném lỗi
-- "relation dm_dia_ban does not exist".
--
-- Các RPC khác cùng loại (apply_dia_ban_to_plan / upsert_dm_dia_ban /
-- update_sale_target_cells / …) cũng có nguy cơ khi CREATE OR REPLACE làm
-- reset search_path. Vá cả 3 cho chắc.
-- ════════════════════════════════════════════════════════════════════════

ALTER FUNCTION public.dep_dia_ban_chong_lan(text)
  SET search_path = public, shared;

ALTER FUNCTION public.apply_dia_ban_to_plan(bigint[])
  SET search_path = public, shared;

ALTER FUNCTION public.upsert_dm_dia_ban(jsonb, text, text, text, text[])
  SET search_path = public, shared;
