-- ════════════════════════════════════════════════════════════════════════
-- Trước đây SP chưa có mã → sale_target.ma_san_pham = "Chưa có" (placeholder).
-- Nay dm_vat_tu đã cập nhật mã thực → cần đồng bộ sale_target theo dm.
--
-- Coi dm_vat_tu / dm_bo_vat_tu là source of truth cho mã. Overwrite
-- sale_target khi mã dm khác mã hiện tại (bao gồm cả "Chưa có" → mã thực).
-- Không đụng nếu dm không có san_pham/bo_vat_tu tương ứng.
--
-- Trường hợp san_pham là "bộ gộp" (fallback dm_bo_vat_tu): resync theo
-- dm_bo_vat_tu chỉ khi dm_vat_tu không có san_pham đó.
-- ════════════════════════════════════════════════════════════════════════

-- (A) ma_san_pham theo dm_vat_tu
update shared.sale_target s
   set ma_san_pham = dvt.ma_san_pham, updated_at = now()
  from shared.dm_vat_tu dvt
 where dvt.ma_san_pham is not null
   and lower(btrim(dvt.san_pham)) = lower(btrim(s.san_pham))
   and s.ma_san_pham is distinct from dvt.ma_san_pham;

-- (B) ma_san_pham fallback theo dm_bo_vat_tu (SP là "bộ gộp")
update shared.sale_target s
   set ma_san_pham = dbvt.ma_bo_vat_tu, updated_at = now()
  from shared.dm_bo_vat_tu dbvt
 where dbvt.ma_bo_vat_tu is not null
   and lower(btrim(dbvt.bo_vat_tu)) = lower(btrim(s.san_pham))
   and s.ma_san_pham is distinct from dbvt.ma_bo_vat_tu
   and not exists (
     select 1 from shared.dm_vat_tu dvt
      where dvt.ma_san_pham is not null
        and lower(btrim(dvt.san_pham)) = lower(btrim(s.san_pham))
   );

-- (C) ma_bo_vat_tu theo dm_bo_vat_tu
update shared.sale_target s
   set ma_bo_vat_tu = dbvt.ma_bo_vat_tu, updated_at = now()
  from shared.dm_bo_vat_tu dbvt
 where dbvt.ma_bo_vat_tu is not null
   and lower(btrim(dbvt.bo_vat_tu)) = lower(btrim(s.bo_vat_tu))
   and s.ma_bo_vat_tu is distinct from dbvt.ma_bo_vat_tu;
