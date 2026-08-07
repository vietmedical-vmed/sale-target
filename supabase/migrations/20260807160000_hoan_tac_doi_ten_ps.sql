-- ════════════════════════════════════════════════════════════════════════
-- HOÀN TÁC 20260807130000_chuan_hoa_ten_ps.sql — ĐỔI SAI CHIỀU
--
-- Migration đó lấy dm_ps làm chuẩn và đổi tên trong kế hoạch theo danh mục.
-- SAI: tên trong kế hoạch mới là tên đúng ('Thanh Ngô'), dm_ps mới là bên
-- cần sửa. File này đưa 3 nơi về đúng tên cũ:
--     'Thanh Nguyễn' -> 'Thanh Ngô'
--     'Quí Nguyễn'   -> 'Qúi Nguyễn'
--   1) shared.sale_target.ps   (đã đổi 324 + 856 dòng)
--   2) shared.dm_dia_ban.ps    (đã đổi 7 + 26 bản)
--   3) shared.users.scope      (đã đổi 1 tài khoản)
-- rồi chạy lại map actual + refresh matview để số về đúng trạng thái cũ.
--
-- KHÔNG có guard "tên đích phải có trong dm_ps" như bản gốc — ở đây tên đích
-- CỐ Ý không nằm trong danh mục; việc sửa dm_ps cho khớp là bước riêng.
--
-- Idempotent: chạy lại không còn tên mới → 0 dòng đổi, vẫn map + refresh lại.
-- ════════════════════════════════════════════════════════════════════════

DO $$
DECLARE
  r         record;
  v_st      int;
  v_db      int;
  v_us      int;
  v_xoa     int;
  v_map     jsonb;
  v_tong_st int := 0;
  v_tong_db int := 0;
  v_tong_us int := 0;
BEGIN
  CREATE TEMP TABLE _ren(ps_cu text, ps_moi text) ON COMMIT DROP;
  INSERT INTO _ren VALUES
    ('Thanh Nguyễn', 'Thanh Ngô'),
    ('Quí Nguyễn',   'Qúi Nguyễn');

  FOR r IN SELECT * FROM _ren LOOP
    UPDATE shared.sale_target SET ps = r.ps_moi, updated_at = now()
     WHERE btrim(ps) = r.ps_cu;
    GET DIAGNOSTICS v_st = ROW_COUNT;

    DELETE FROM shared.dm_dia_ban d
     WHERE btrim(d.ps) = r.ps_cu
       AND EXISTS (SELECT 1 FROM shared.dm_dia_ban n
                    WHERE n.bu = d.bu AND n.cust_key = d.cust_key
                      AND n.nhom_san_pham = d.nhom_san_pham
                      AND n.tu_thang = d.tu_thang
                      AND btrim(n.ps) = r.ps_moi);
    GET DIAGNOSTICS v_xoa = ROW_COUNT;
    IF v_xoa > 0 THEN
      RAISE NOTICE 'dm_dia_ban: xoá % bản trùng của "%"', v_xoa, r.ps_cu;
    END IF;

    UPDATE shared.dm_dia_ban SET ps = r.ps_moi, updated_at = now()
     WHERE btrim(ps) = r.ps_cu;
    GET DIAGNOSTICS v_db = ROW_COUNT;

    UPDATE shared.users SET scope = r.ps_moi
     WHERE lower(role) = 'ps' AND btrim(scope) = r.ps_cu;
    GET DIAGNOSTICS v_us = ROW_COUNT;

    RAISE NOTICE '% -> %: % dòng kế hoạch, % khai báo địa bàn, % tài khoản',
                 r.ps_cu, r.ps_moi, v_st, v_db, v_us;
    v_tong_st := v_tong_st + v_st;
    v_tong_db := v_tong_db + v_db;
    v_tong_us := v_tong_us + v_us;
  END LOOP;

  RAISE NOTICE 'TỔNG hoàn tác: % dòng kế hoạch, % khai báo địa bàn, % tài khoản',
               v_tong_st, v_tong_db, v_tong_us;

  v_map := public.map_hoadon_to_sale_target();
  RAISE NOTICE 'map_hoadon_to_sale_target: %', v_map;

  PERFORM public.refresh_bao_cao_sale();
  RAISE NOTICE 'đã refresh v_th_theo_ps / v_th_theo_sp';
END $$;
