-- ════════════════════════════════════════════════════════════════════════
-- CHUẨN HOÁ TÊN PS TRONG KẾ HOẠCH THEO DANH MỤC shared.dm_ps
--
-- VẤN ĐỀ
-- 2 PS đang có tên rút gọn khác nhau giữa danh mục và dữ liệu kế hoạch:
--   dm_ps 'Thanh Nguyễn' (Ngô Nguyễn Hoàng Thanh)  ↔  sale_target 'Thanh Ngô'
--   dm_ps 'Quí Nguyễn'   (Nguyễn Thị Mỹ Quí)       ↔  sale_target 'Qúi Nguyễn'
--                                                      (dấu sắc đặt khác vị trí)
-- app_sale.hoa_don_actual dịch ten_ps → ps THEO dm_ps, mà khoá khớp actual có cột
-- ps, nên toàn bộ hoá đơn của 2 người này không bao giờ khớp dòng kế hoạch — số
-- rơi hết sang "ngoài kế hoạch" và không có lỗi nào báo ra.
--
-- CÁCH SỬA (đã chốt): lấy dm_ps làm chuẩn, đổi tên trong dữ liệu kế hoạch.
-- Phải đổi ĐỒNG THỜI 3 nơi đang neo theo tên PS, nếu không sẽ hỏng chỗ khác:
--   1) shared.sale_target.ps   — dòng kế hoạch
--   2) shared.dm_dia_ban.ps    — khai báo địa bàn (Qúi Nguyễn 26 bản, Thanh Ngô 7)
--   3) shared.users.scope      — phạm vi dữ liệu của tài khoản role 'ps';
--      KHÔNG đổi users.username vì đó là tên đăng nhập.
-- Sau đó chạy lại map actual + refresh matview báo cáo.
--
-- ⚠ KHÔNG đụng app_sale.sv_bovattu_actual (bảng của luồng cũ, app_order đang dùng).
--   Hệ quả: sau migration này, ĐỪNG chạy public.map_actual_to_sale_target() (luồng
--   cũ) nữa — nó khớp theo tên PS cũ nên sẽ zero sạch số của 2 PS này. Luồng sale
--   dùng public.map_hoadon_to_sale_target().
--
-- Idempotent: chạy lại lần 2 không còn tên cũ → 0 dòng đổi, vẫn map + refresh lại.
-- ════════════════════════════════════════════════════════════════════════

DO $$
DECLARE
  r          record;
  v_thieu    text;
  v_st       int;
  v_db       int;
  v_us       int;
  v_xoa      int;
  v_map      jsonb;
  v_tong_st  int := 0;
  v_tong_db  int := 0;
  v_tong_us  int := 0;
BEGIN
  -- Bảng đổi tên: (tên đang có trong kế hoạch) -> (tên chuẩn trong dm_ps)
  CREATE TEMP TABLE _ren(ps_cu text, ps_moi text) ON COMMIT DROP;
  INSERT INTO _ren VALUES
    ('Thanh Ngô',   'Thanh Nguyễn'),
    ('Qúi Nguyễn',  'Quí Nguyễn');

  -- Chặn gõ sai: tên đích BẮT BUỘC phải có trong danh mục PS.
  -- Alias là `x` chứ KHÔNG phải `r`: trùng tên biến record `r` thì plpgsql hiểu
  -- r.ps_moi là biến (chưa gán) chứ không phải cột → lỗi 55000.
  SELECT string_agg(x.ps_moi, ', ') INTO v_thieu
    FROM _ren x
   WHERE NOT EXISTS (SELECT 1 FROM shared.dm_ps d
                      WHERE lower(btrim(d.ps)) = lower(btrim(x.ps_moi)));
  IF v_thieu IS NOT NULL THEN
    RAISE EXCEPTION 'ten_ps_khong_co_trong_dm_ps: [%] — sửa bảng đổi tên hoặc bổ sung dm_ps trước', v_thieu;
  END IF;

  FOR r IN SELECT * FROM _ren LOOP
    -- 1) Dòng kế hoạch
    UPDATE shared.sale_target SET ps = r.ps_moi, updated_at = now()
     WHERE btrim(ps) = r.ps_cu;
    GET DIAGNOSTICS v_st = ROW_COUNT;

    -- 2) Khai báo địa bàn. Khoá unique gồm ps → xoá trước bản đã tồn tại y hệt
    --    dưới tên mới (nếu có) để UPDATE không vỡ vì trùng khoá.
    DELETE FROM shared.dm_dia_ban d
     WHERE btrim(d.ps) = r.ps_cu
       AND EXISTS (SELECT 1 FROM shared.dm_dia_ban n
                    WHERE n.bu = d.bu AND n.cust_key = d.cust_key
                      AND n.nhom_san_pham = d.nhom_san_pham
                      AND n.tu_thang = d.tu_thang
                      AND btrim(n.ps) = r.ps_moi);
    GET DIAGNOSTICS v_xoa = ROW_COUNT;
    IF v_xoa > 0 THEN
      RAISE NOTICE 'dm_dia_ban: xoá % bản trùng của "%" (đã có sẵn dưới tên "%")', v_xoa, r.ps_cu, r.ps_moi;
    END IF;

    UPDATE shared.dm_dia_ban SET ps = r.ps_moi, updated_at = now()
     WHERE btrim(ps) = r.ps_cu;
    GET DIAGNOSTICS v_db = ROW_COUNT;

    -- 3) Phạm vi dữ liệu của tài khoản role 'ps' (KHÔNG đổi username = tên đăng nhập)
    UPDATE shared.users SET scope = r.ps_moi
     WHERE lower(role) = 'ps' AND btrim(scope) = r.ps_cu;
    GET DIAGNOSTICS v_us = ROW_COUNT;

    RAISE NOTICE '% -> %: % dòng kế hoạch, % khai báo địa bàn, % tài khoản',
                 r.ps_cu, r.ps_moi, v_st, v_db, v_us;
    v_tong_st := v_tong_st + v_st;
    v_tong_db := v_tong_db + v_db;
    v_tong_us := v_tong_us + v_us;
  END LOOP;

  RAISE NOTICE 'TỔNG: % dòng kế hoạch, % khai báo địa bàn, % tài khoản đã đổi tên PS',
               v_tong_st, v_tong_db, v_tong_us;

  -- 4) Chạy lại map actual: số của 2 PS này giờ mới khớp được dòng kế hoạch.
  --    Hàm zero các tháng có trong hoa_don rồi ghi lại nên chạy lại vô hại.
  v_map := public.map_hoadon_to_sale_target();
  RAISE NOTICE 'map_hoadon_to_sale_target: %', v_map;

  -- 5) Matview báo cáo đọc sale_target → phải refresh sau khi đổi tên + map.
  PERFORM public.refresh_bao_cao_sale();
  RAISE NOTICE 'đã refresh v_th_theo_ps / v_th_theo_sp';

  -- 6) Soi lại: còn PS nào trong kế hoạch mà danh mục không có?
  --    'Giang Đỗ' (team test, dữ liệu demo/training) là trường hợp biết trước.
  SELECT string_agg(ps || ' (' || so_dong_ke_hoach || ' dòng)', ', ')
    INTO v_thieu
    FROM shared.v_dm_ps_lech_ten
   WHERE tinh_trang = 'chỉ có trong kế hoạch' AND so_dong_ke_hoach > 0;
  IF v_thieu IS NOT NULL THEN
    RAISE WARNING 'Còn PS trong kế hoạch chưa có trong dm_ps: % — hoá đơn của họ vẫn rơi sang "ngoài kế hoạch"', v_thieu;
  END IF;
END $$;

-- Soi lại sau khi chạy: view này phải KHÔNG còn dòng "chỉ có trong kế hoạch" nào
-- có số dòng > 0 (trừ PS demo/training không nằm trong danh mục).
--   select * from shared.v_dm_ps_lech_ten order by so_dong_ke_hoach desc;
