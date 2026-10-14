-- Duyệt / loại đợt thầu chờ duyệt KHÔNG gắn quota (chỉ có tháng thầu, chuyển từ cột
-- cũ sale_target ở 20261015120000). Đợt có quota chờ duyệt đi theo duyet_quota_thau.
-- Loại = xoá, chỉ khi không còn quota nào dùng đợt đó.

CREATE OR REPLACE FUNCTION public.duyet_dot_thau(p_ids bigint[], p_duyet boolean, p_actor text DEFAULT NULL)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, shared
AS $$
DECLARE
  v_n int := 0;
BEGIN
  IF p_duyet THEN
    WITH doi AS (
      UPDATE shared.dot_thau d SET trang_thai = 'chinh_thuc', updated_at = now(), updated_by = p_actor
      WHERE d.id = ANY(p_ids) AND d.trang_thai = 'cho_duyet'
      RETURNING d.*)
    , log AS (
      INSERT INTO shared.quota_chuan_hoa_log (buoc, bang, ban_ghi_id, sau)
      SELECT 'duyet', 'dot_thau', id, to_jsonb(doi) FROM doi RETURNING 1)
    SELECT count(*) INTO v_n FROM doi;
  ELSE
    WITH xoa AS (
      DELETE FROM shared.dot_thau d
      WHERE d.id = ANY(p_ids) AND d.trang_thai = 'cho_duyet'
        AND NOT EXISTS (SELECT 1 FROM shared.quota_thau q
                        WHERE q.nam_tai_chinh = d.nam_tai_chinh AND q.ps = d.ps AND q.ma_khach_hang = d.ma_khach_hang
                          AND q.nhom_san_pham = d.nhom_san_pham AND q.loai = d.loai AND q.dot = d.dot)
      RETURNING d.*)
    , log AS (
      INSERT INTO shared.quota_chuan_hoa_log (buoc, bang, ban_ghi_id, truoc)
      SELECT 'loai', 'dot_thau', id, to_jsonb(xoa) FROM xoa RETURNING 1)
    SELECT count(*) INTO v_n FROM xoa;
  END IF;
  RETURN jsonb_build_object('dot', v_n);
END;
$$;

REVOKE ALL ON FUNCTION public.duyet_dot_thau(bigint[], boolean, text) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.duyet_dot_thau(bigint[], boolean, text) TO service_role;
