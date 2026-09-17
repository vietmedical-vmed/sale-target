-- GĐ 2.4e: Index optimization based on pg_stat_statements analysis.
-- Top bottleneck: v_actual_ngoai_ke_hoach (1155ms mean, 1031 calls).
-- ============================================================================

-- 1. Partial index for OOP queries (classify_oop, getOop).
--    Scoped queries filter on bu/ps/nhom_san_pham WHERE ngoai_ke_hoach = true.
--    ~8211 of ~31271 rows match (26%), partial index much smaller.
CREATE INDEX CONCURRENTLY IF NOT EXISTS idx_sale_target_oop_partial
  ON shared.sale_target (bu, ps, nhom_san_pham)
  WHERE ngoai_ke_hoach = true;

-- 2. Composite index for hoa_don_bovattu GROUP BY in hoa_don_actual view.
--    View groups by (thang, ps, ma_kh, bo_vat_tu, san_pham).
CREATE INDEX CONCURRENTLY IF NOT EXISTS idx_hdbvt_group
  ON app_sale.hoa_don_bovattu (thang, ten_ps, ma_kh, bo_vat_tu, san_pham);

-- 3. Drop duplicate indexes on hoa_don_bovattu.
--    idx_hdbvt_sale_* duplicates idx_hoa_don_bovattu_* on same columns.
DROP INDEX IF EXISTS app_sale.idx_hdbvt_sale_bo_vat_tu;
DROP INDEX IF EXISTS app_sale.idx_hdbvt_sale_ma_kh;
DROP INDEX IF EXISTS app_sale.idx_hdbvt_sale_thang;

-- 4. Index for dm_dia_ban lookups in v_actual_ngoai_ke_hoach CASE.
--    View does 4 EXISTS checks on dm_dia_ban(bu, cust_key, nhom_san_pham, tu_thang, den_thang, ps).
CREATE INDEX CONCURRENTLY IF NOT EXISTS idx_dm_dia_ban_lookup
  ON shared.dm_dia_ban (bu, cust_key, nhom_san_pham, tu_thang)
  WHERE active = true;
