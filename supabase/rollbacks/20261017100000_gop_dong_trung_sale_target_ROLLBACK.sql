-- Hoàn tác 20261017100000: bỏ ràng buộc trùng, trả apply_dia_ban_to_plan bản cũ,
-- dựng lại các dòng trùng từ bản chụp bak_20261017_gop_trung (cả dòng giữ lẫn dòng đã xoá).
-- Lưu ý: số thực hiện / KH update ghi SAU khi gộp lên dòng giữ sẽ bị thay bằng bản chụp;
-- chạy lại "Cập nhật thực hiện" sau khi hoàn tác.

BEGIN;

ALTER TABLE shared.sale_target DROP CONSTRAINT IF EXISTS uq_sale_target_khoa;

DELETE FROM shared.sale_target s
USING shared.bak_20261017_gop_trung b
WHERE s.id = b.id;

INSERT INTO shared.sale_target OVERRIDING SYSTEM VALUE
  (id, nam_tai_chinh, thang_ke_hoach, mien, ps, khach_hang, ma_khach_hang, nhom_san_pham, san_pham,
   bo_vat_tu, sl_ke_hoach_dau_nam, sl_ke_hoach_update, don_gia, doanh_thu_kh_dau_nam,
   doanh_thu_kh_update, chenh_lech_doanh_thu_kh, sl_thuc_hien, updated_at, bu, bo, ma_bo_vat_tu,
   ma_chung, ma_san_pham, doanh_thu_thuc_hien, ngoai_ke_hoach, _rev)
SELECT id, nam_tai_chinh, thang_ke_hoach, mien, ps, khach_hang, ma_khach_hang, nhom_san_pham, san_pham,
       bo_vat_tu, sl_ke_hoach_dau_nam, sl_ke_hoach_update, don_gia, doanh_thu_kh_dau_nam,
       doanh_thu_kh_update, chenh_lech_doanh_thu_kh, sl_thuc_hien, now(), bu, bo, ma_bo_vat_tu,
       ma_chung, ma_san_pham, doanh_thu_thuc_hien, ngoai_ke_hoach, _rev
FROM shared.bak_20261017_gop_trung;

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
    -- Ghi cho MỌI dòng kế hoạch của tổ hợp (bu, KH, ngành hàng), không giới
    -- hạn theo tháng. Tổ hợp chồng lấn nhiều PS -> bỏ qua ở filter so_ps=1.
    UPDATE sale_target s SET
      ps         = c.ps,
      mien       = coalesce(c.mien, s.mien),
      updated_at = now()
    FROM  (SELECT * FROM _cfg WHERE so_ps = 1) c
    WHERE s.bu            = c.bu
      AND s.nhom_san_pham = c.nhom_san_pham
      AND coalesce(nullif(btrim(coalesce(s.ma_khach_hang, '')), ''), btrim(s.khach_hang)) = c.cust_key
      AND (s.ps IS DISTINCT FROM c.ps
           OR s.mien IS DISTINCT FROM coalesce(c.mien, s.mien));
    GET DIAGNOSTICS v_upd = ROW_COUNT;
  END IF;

  RETURN jsonb_build_object('applied', v_cfg, 'ambiguous', v_amb, 'updated_rows', v_upd);
END;
$function$;

REVOKE ALL ON FUNCTION public.apply_dia_ban_to_plan(bigint[]) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.apply_dia_ban_to_plan(bigint[]) TO service_role;

DROP FUNCTION IF EXISTS shared.gop_dong_trung_sale_target(bigint[]);

COMMIT;
