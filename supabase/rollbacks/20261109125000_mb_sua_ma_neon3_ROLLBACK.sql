-- Rollback 20261109125000_mb_sua_ma_neon3.sql:
--   1. tách lại các dòng kế hoạch đã gộp (log buoc 'gop_dong_trung' sau mốc 'mb_sua_ma_neon3_20261109_moc'),
--   2. trả mã CS91 cho dòng "Vít cổ sau Neon3" của VĐ, CTCH Nghệ An, Hà Đông đã đổi.
BEGIN;
SET CONSTRAINTS shared.uq_sale_target_khoa DEFERRED;
DO $$
DECLARE v_moc bigint; cols text;
BEGIN
  SELECT max(id) INTO v_moc FROM shared.quota_chuan_hoa_log WHERE buoc = 'mb_sua_ma_neon3_20261109_moc';
  IF v_moc IS NULL THEN RETURN; END IF;
  CREATE TEMP TABLE _g ON COMMIT DROP AS
  SELECT l.ban_ghi_id, l.truoc, (l.sau->>'giu')::bigint AS giu FROM shared.quota_chuan_hoa_log l
  WHERE l.buoc = 'gop_dong_trung' AND l.id > v_moc
    AND l.id < coalesce((SELECT min(id) FROM shared.quota_chuan_hoa_log WHERE buoc = 'mb_sua_ma_neon3_20261109' AND id > v_moc), 9e18)
    AND l.truoc->>'ma_khach_hang' IN ('BV0342', 'BV1432', 'BV0655');
  -- dòng giữ lại: trả số liệu trước khi gộp
  UPDATE shared.sale_target s SET
    sl_ke_hoach_dau_nam = (g.truoc->>'sl_ke_hoach_dau_nam')::numeric, doanh_thu_kh_dau_nam = (g.truoc->>'doanh_thu_kh_dau_nam')::numeric,
    sl_ke_hoach_update = (g.truoc->>'sl_ke_hoach_update')::numeric, doanh_thu_kh_update = (g.truoc->>'doanh_thu_kh_update')::numeric,
    chenh_lech_doanh_thu_kh = (g.truoc->>'chenh_lech_doanh_thu_kh')::numeric, sl_thuc_hien = (g.truoc->>'sl_thuc_hien')::numeric,
    doanh_thu_thuc_hien = (g.truoc->>'doanh_thu_thuc_hien')::numeric, updated_at = now()
  FROM _g g WHERE s.id = g.ban_ghi_id AND g.ban_ghi_id = g.giu;
  -- dòng đã xoá: chèn lại (bỏ cột sinh nhom_ref)
  SELECT string_agg(quote_ident(column_name), ',' ORDER BY ordinal_position) INTO cols
  FROM information_schema.columns WHERE table_schema = 'shared' AND table_name = 'sale_target' AND is_generated = 'NEVER';
  EXECUTE format('INSERT INTO shared.sale_target (%1$s) OVERRIDING SYSTEM VALUE
                  SELECT %1$s FROM (SELECT (jsonb_populate_record(NULL::shared.sale_target, g.truoc)).* FROM _g g
                  WHERE g.ban_ghi_id <> g.giu AND NOT EXISTS (SELECT 1 FROM shared.sale_target s WHERE s.id = g.ban_ghi_id)) r', cols);
END $$;
UPDATE shared.sale_target s SET ma_san_pham = 'CS91', updated_at = now()
FROM shared.quota_chuan_hoa_log l
WHERE l.buoc = 'mb_sua_ma_neon3_20261109' AND l.bang = 'sale_target' AND s.id = l.ban_ghi_id AND s.ma_san_pham = 'CS 390x';
UPDATE shared.quota_thau q SET ma_san_pham = 'CS91', updated_at = now(), updated_by = 'mb_sua_ma_neon3_20261109_rollback'
FROM shared.quota_chuan_hoa_log l
WHERE l.buoc = 'mb_sua_ma_neon3_20261109' AND l.bang = 'quota_thau' AND q.id = l.ban_ghi_id AND q.ma_san_pham = 'CS 390x';
SET CONSTRAINTS shared.uq_sale_target_khoa IMMEDIATE;
COMMIT;
