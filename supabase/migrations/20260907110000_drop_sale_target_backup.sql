-- Xoá MỘT bản chụp theo nhãn.
--
-- Bổ sung cho 20260907100000: ở đó chỉ có cleanup_sale_target_backup(N) giữ N bản
-- mới nhất, nên khi đặt nhãn sai hoặc chụp nhầm thì không xoá riêng bản đó được
-- (bảng nằm ở schema shared, không thao tác qua Data API được).

CREATE OR REPLACE FUNCTION public.drop_sale_target_backup(p_label text)
RETURNS int
LANGUAGE plpgsql SECURITY DEFINER
SET search_path = shared, public
AS $fn$
DECLARE deleted int;
BEGIN
  IF coalesce(btrim(p_label), '') = '' THEN
    RAISE EXCEPTION 'Phai truyen nhan ban chup can xoa';
  END IF;

  DELETE FROM shared.sale_target_backup WHERE snapshot_label = p_label;
  GET DIAGNOSTICS deleted = ROW_COUNT;

  IF deleted = 0 THEN
    RAISE EXCEPTION 'Khong co ban chup nao ten "%"', p_label;
  END IF;

  RETURN deleted;
END
$fn$;

REVOKE ALL ON FUNCTION public.drop_sale_target_backup(text) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.drop_sale_target_backup(text) TO service_role;
