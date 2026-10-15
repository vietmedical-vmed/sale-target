-- Gộp dòng trùng trong shared.sale_target và chặn phát sinh mới.
--
-- Vấn đề: cùng khoá (FY × tháng × PS × KH × nhóm × bộ VT × SP × mã SP × đơn giá × OOP) có
-- 2–3 dòng (1.619 nhóm ngày 15/10, phần lớn chcs). Đồng bộ thực hiện ghi vào dòng id nhỏ
-- nhất, KH update có thể nằm ở dòng khác → tháng hiện tại một dòng lấy DThu thực hiện,
-- dòng kia lấy SL update × giá → DThu KH update đếm 2 lần (vd Stent XD @ DN0191 T9:
-- 910tr thay vì 864,5tr).
-- Nguồn phát sinh: import một lần ngoài repo (importKHKD 30/09), apply_dia_ban_to_plan
-- dời PS hàng loạt (dòng 2 PS dồn về cùng khoá), ensureMonthRow (kiểm tra trùng hỏng),
-- và sửa giá / tên SP trên lưới.
--
-- Cách làm:
--   1. shared.gop_dong_trung_sale_target(p_ids): gộp mỗi nhóm trùng vào dòng id nhỏ nhất.
--      SL/DThu cộng dồn. SL KH update: nếu có dòng nào đã nhập update thì
--      = Σ coalesce(update, đầu năm) để tổng hiệu lực không đổi; không có thì để null.
--      Dòng bị xoá + bản trước của dòng giữ ghi vào quota_chuan_hoa_log (buoc 'gop_dong_trung').
--   2. Chạy gộp toàn bảng (bản chụp: bak_20261017_gop_trung).
--   3. Ràng buộc uq_sale_target_khoa (NULLS NOT DISTINCT, DEFERRABLE) → mọi đường ghi
--      tạo trùng đều bị chặn.
--   4. apply_dia_ban_to_plan hoãn ràng buộc, dời PS rồi tự gộp dòng trùng mới sinh.
-- Quota không bị ảnh hưởng: dòng giữ lại cùng khoá với dòng bị xoá.
-- Hoàn tác: supabase/rollbacks/20261017100000_gop_dong_trung_sale_target_ROLLBACK.sql

BEGIN;

CREATE OR REPLACE FUNCTION shared.gop_dong_trung_sale_target(p_ids bigint[] DEFAULT NULL)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'shared', 'public'
AS $function$
DECLARE
  v_nhom integer := 0;
  v_xoa  integer := 0;
BEGIN
  DROP TABLE IF EXISTS pg_temp._gt;
  CREATE TEMP TABLE _gt ON COMMIT DROP AS
  SELECT id, giu
  FROM (
    SELECT id,
           min(id) OVER w AS giu,
           count(*) OVER w AS n,
           bool_or(p_ids IS NULL OR id = ANY(p_ids)) OVER w AS cham
    FROM shared.sale_target
    WINDOW w AS (PARTITION BY nam_tai_chinh, thang_ke_hoach, ps, ma_khach_hang, nhom_san_pham,
                              bo_vat_tu, san_pham, ma_san_pham, don_gia, ngoai_ke_hoach)
  ) x
  WHERE n > 1 AND cham;

  IF NOT EXISTS (SELECT 1 FROM _gt) THEN
    RETURN jsonb_build_object('nhom', 0, 'xoa', 0);
  END IF;

  INSERT INTO shared.quota_chuan_hoa_log (buoc, bang, ban_ghi_id, truoc, sau)
  SELECT 'gop_dong_trung', 'sale_target', s.id, to_jsonb(s), jsonb_build_object('giu', g.giu)
  FROM _gt g JOIN shared.sale_target s ON s.id = g.id;

  WITH t AS (
    SELECT g.giu,
           sum(s.sl_ke_hoach_dau_nam)     AS sl_dn,
           sum(s.doanh_thu_kh_dau_nam)    AS dt_dn,
           CASE WHEN bool_or(s.sl_ke_hoach_update IS NOT NULL)
                THEN sum(coalesce(s.sl_ke_hoach_update, s.sl_ke_hoach_dau_nam, 0)) END AS sl_upd,
           sum(s.doanh_thu_kh_update)     AS dt_upd,
           sum(s.chenh_lech_doanh_thu_kh) AS chenh,
           sum(s.sl_thuc_hien)            AS sl_th,
           sum(s.doanh_thu_thuc_hien)     AS dt_th,
           (array_agg(s.mien         ORDER BY s.id) FILTER (WHERE s.mien IS NOT NULL))[1]         AS mien,
           (array_agg(s.khach_hang   ORDER BY s.id) FILTER (WHERE s.khach_hang IS NOT NULL))[1]   AS khach_hang,
           (array_agg(s.bu           ORDER BY s.id) FILTER (WHERE s.bu IS NOT NULL))[1]           AS bu,
           (array_agg(s.bo           ORDER BY s.id) FILTER (WHERE s.bo IS NOT NULL))[1]           AS bo,
           (array_agg(s.ma_bo_vat_tu ORDER BY s.id) FILTER (WHERE s.ma_bo_vat_tu IS NOT NULL))[1] AS ma_bo_vat_tu,
           (array_agg(s.ma_chung     ORDER BY s.id) FILTER (WHERE s.ma_chung IS NOT NULL))[1]     AS ma_chung
    FROM _gt g JOIN shared.sale_target s ON s.id = g.id
    GROUP BY g.giu
  )
  UPDATE shared.sale_target s SET
    sl_ke_hoach_dau_nam     = t.sl_dn,
    doanh_thu_kh_dau_nam    = t.dt_dn,
    sl_ke_hoach_update      = t.sl_upd,
    doanh_thu_kh_update     = t.dt_upd,
    chenh_lech_doanh_thu_kh = t.chenh,
    sl_thuc_hien            = t.sl_th,
    doanh_thu_thuc_hien     = t.dt_th,
    mien                    = t.mien,
    khach_hang              = t.khach_hang,
    bu                      = t.bu,
    bo                      = t.bo,
    ma_bo_vat_tu            = t.ma_bo_vat_tu,
    ma_chung                = t.ma_chung,
    updated_at              = now()
  FROM t
  WHERE s.id = t.giu;
  GET DIAGNOSTICS v_nhom = ROW_COUNT;

  DELETE FROM shared.sale_target s
  USING _gt g
  WHERE s.id = g.id AND g.id <> g.giu;
  GET DIAGNOSTICS v_xoa = ROW_COUNT;

  RETURN jsonb_build_object('nhom', v_nhom, 'xoa', v_xoa);
END;
$function$;

REVOKE ALL ON FUNCTION shared.gop_dong_trung_sale_target(bigint[]) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION shared.gop_dong_trung_sale_target(bigint[]) TO service_role;

-- Bản chụp mọi dòng thuộc nhóm trùng trước khi gộp.
CREATE TABLE shared.bak_20261017_gop_trung AS
SELECT s.*
FROM shared.sale_target s
JOIN (
  SELECT id, count(*) OVER (PARTITION BY nam_tai_chinh, thang_ke_hoach, ps, ma_khach_hang, nhom_san_pham,
                                         bo_vat_tu, san_pham, ma_san_pham, don_gia, ngoai_ke_hoach) AS n
  FROM shared.sale_target
) d ON d.id = s.id AND d.n > 1;
ALTER TABLE shared.bak_20261017_gop_trung ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON shared.bak_20261017_gop_trung FROM PUBLIC, anon, authenticated;

SELECT shared.gop_dong_trung_sale_target(NULL);

ALTER TABLE shared.sale_target
  ADD CONSTRAINT uq_sale_target_khoa UNIQUE NULLS NOT DISTINCT
    (nam_tai_chinh, thang_ke_hoach, ps, ma_khach_hang, nhom_san_pham, bo_vat_tu, san_pham,
     ma_san_pham, don_gia, ngoai_ke_hoach)
  DEFERRABLE INITIALLY IMMEDIATE;

CREATE OR REPLACE FUNCTION public.apply_dia_ban_to_plan(p_ids bigint[])
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'shared'
AS $function$
DECLARE
  v_upd integer := 0;
  v_amb integer := 0;
  v_cfg integer := 0;
  v_ids bigint[];
  v_gop jsonb := jsonb_build_object('nhom', 0, 'xoa', 0);
BEGIN
  CREATE TEMP TABLE _cfg ON COMMIT DROP AS
  SELECT d.id, d.bu, d.cust_key, d.nhom_san_pham, d.mien, d.ps,
         (SELECT count(DISTINCT d2.ps)
            FROM dm_dia_ban d2
           WHERE d2.bu            = d.bu
             AND d2.cust_key      = d.cust_key
             AND d2.nhom_san_pham = d.nhom_san_pham
             AND d2.active) AS so_ps
  FROM   dm_dia_ban d
  WHERE  d.id = ANY(coalesce(p_ids, '{}'::bigint[]))
    AND  d.active;

  SELECT count(*) FILTER (WHERE so_ps > 1), count(*) FILTER (WHERE so_ps = 1)
    INTO v_amb, v_cfg
    FROM _cfg;

  IF v_cfg > 0 THEN
    -- Dời PS có thể dồn dòng của 2 PS về cùng khoá → hoãn ràng buộc trùng,
    -- gộp các dòng vừa dời, rồi kiểm tra lại ngay.
    SET CONSTRAINTS shared.uq_sale_target_khoa DEFERRED;

    -- Ghi cho MỌI dòng kế hoạch của tổ hợp (bu, KH, ngành hàng), không giới
    -- hạn theo tháng. Tổ hợp chồng lấn nhiều PS -> bỏ qua ở filter so_ps=1.
    WITH u AS (
      UPDATE sale_target s SET
        ps         = c.ps,
        mien       = coalesce(c.mien, s.mien),
        updated_at = now()
      FROM  (SELECT * FROM _cfg WHERE so_ps = 1) c
      WHERE s.bu            = c.bu
        AND s.nhom_san_pham = c.nhom_san_pham
        AND coalesce(nullif(btrim(coalesce(s.ma_khach_hang, '')), ''), btrim(s.khach_hang)) = c.cust_key
        AND (s.ps IS DISTINCT FROM c.ps
             OR s.mien IS DISTINCT FROM coalesce(c.mien, s.mien))
      RETURNING s.id
    )
    SELECT array_agg(id), count(*) INTO v_ids, v_upd FROM u;

    IF v_upd > 0 THEN
      v_gop := shared.gop_dong_trung_sale_target(v_ids);
    END IF;

    SET CONSTRAINTS shared.uq_sale_target_khoa IMMEDIATE;
  END IF;

  RETURN jsonb_build_object('applied', v_cfg, 'ambiguous', v_amb, 'updated_rows', v_upd,
                            'merged_rows', v_gop->'xoa');
END;
$function$;

REVOKE ALL ON FUNCTION public.apply_dia_ban_to_plan(bigint[]) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.apply_dia_ban_to_plan(bigint[]) TO service_role;

COMMIT;
