-- Vá quyền: public.update_sale_target_cells đang cho anon / authenticated EXECUTE.
--
-- Migration 20260917110000_optimistic_lock_update_cells DROP rồi CREATE lại hàm
-- nhưng không REVOKE/GRANT lại, nên hàm mới nhận quyền mặc định (PUBLIC + default
-- privileges của Supabase cho anon/authenticated). Hàm là SECURITY DEFINER và phạm
-- vi do tham số quyết định → ai có anon key (nằm sẵn trong frontend) đều gọi được
-- /rest/v1/rpc/update_sale_target_cells với p_bu/p_mien/p_ps = NULL và ghi đè bất
-- kỳ dòng kế hoạch nào. Chỉ edge function (service_role) được gọi hàm này.

REVOKE ALL ON FUNCTION public.update_sale_target_cells(jsonb, text, text, text, text[]) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.update_sale_target_cells(jsonb, text, text, text, text[]) FROM anon, authenticated;
GRANT EXECUTE ON FUNCTION public.update_sale_target_cells(jsonb, text, text, text, text[]) TO service_role;
