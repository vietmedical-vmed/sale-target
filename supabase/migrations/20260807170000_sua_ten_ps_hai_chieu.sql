-- ════════════════════════════════════════════════════════════════════════
-- SỬA LỆCH TÊN PS — MỖI NGƯỜI MỘT CHIỀU (theo xác nhận nghiệp vụ)
--
-- Hai PS lệch tên giữa shared.dm_ps và dữ liệu kế hoạch, nhưng bên đúng KHÁC
-- NHAU nên không thể xử lý bằng một chiều duy nhất như 20260807130000 (đã
-- hoàn tác bằng 20260807160000):
--
--   Ngô Nguyễn Hoàng Thanh : kế hoạch 'Thanh Ngô'   ĐÚNG → sửa DANH MỤC
--   Nguyễn Thị Mỹ Quí      : dm_ps    'Quí Nguyễn'  ĐÚNG → sửa KẾ HOẠCH
--
-- Sau file này, hoa_don_actual (dịch ten_ps → ps theo dm_ps) sẽ ra đúng tên mà
-- kế hoạch đang dùng cho cả hai người → hoá đơn của họ khớp được dòng kế hoạch
-- thay vì rơi hết sang "ngoài kế hoạch".
--
-- Idempotent: chạy lại → 0 dòng đổi, vẫn map + refresh lại.
-- ════════════════════════════════════════════════════════════════════════

DO $$
DECLARE
  v_dm   int;
  v_st   int;
  v_db   int;
  v_us   int;
  v_map  jsonb;
  v_con  text;
BEGIN
  -- ── A) Danh mục sai → sửa dm_ps theo kế hoạch ────────────────────────────
  -- Khoá theo ten_ps (tên đầy đủ, là thứ hoá đơn mang) chứ không theo ps.
  UPDATE shared.dm_ps
     SET ps = 'Thanh Ngô'
   WHERE lower(btrim(ten_ps)) = lower(btrim('Ngô Nguyễn Hoàng Thanh'))
     AND btrim(ps) <> 'Thanh Ngô';
  GET DIAGNOSTICS v_dm = ROW_COUNT;
  RAISE NOTICE 'dm_ps: % dòng đổi ps -> Thanh Ngô (theo kế hoạch)', v_dm;

  -- ── B) Kế hoạch sai → sửa 3 nơi neo theo tên PS, theo danh mục ───────────
  UPDATE shared.sale_target SET ps = 'Quí Nguyễn', updated_at = now()
   WHERE btrim(ps) = 'Qúi Nguyễn';
  GET DIAGNOSTICS v_st = ROW_COUNT;

  -- Khoá unique của dm_dia_ban gồm ps → dọn bản đã tồn tại dưới tên đúng trước.
  DELETE FROM shared.dm_dia_ban d
   WHERE btrim(d.ps) = 'Qúi Nguyễn'
     AND EXISTS (SELECT 1 FROM shared.dm_dia_ban n
                  WHERE n.bu = d.bu AND n.cust_key = d.cust_key
                    AND n.nhom_san_pham = d.nhom_san_pham
                    AND n.tu_thang = d.tu_thang
                    AND btrim(n.ps) = 'Quí Nguyễn');
  GET DIAGNOSTICS v_db = ROW_COUNT;
  IF v_db > 0 THEN
    RAISE NOTICE 'dm_dia_ban: xoá % bản trùng của "Qúi Nguyễn"', v_db;
  END IF;

  UPDATE shared.dm_dia_ban SET ps = 'Quí Nguyễn', updated_at = now()
   WHERE btrim(ps) = 'Qúi Nguyễn';
  GET DIAGNOSTICS v_db = ROW_COUNT;

  UPDATE shared.users SET scope = 'Quí Nguyễn'
   WHERE lower(role) = 'ps' AND btrim(scope) = 'Qúi Nguyễn';
  GET DIAGNOSTICS v_us = ROW_COUNT;

  RAISE NOTICE 'Qúi Nguyễn -> Quí Nguyễn: % dòng kế hoạch, % khai báo địa bàn, % tài khoản',
               v_st, v_db, v_us;

  -- ── C) Map lại actual + refresh báo cáo ─────────────────────────────────
  v_map := public.map_hoadon_to_sale_target();
  RAISE NOTICE 'map_hoadon_to_sale_target: %', v_map;
  PERFORM public.refresh_bao_cao_sale();
  RAISE NOTICE 'đã refresh v_th_theo_ps / v_th_theo_sp';

  -- ── D) Soi lại: chỉ được còn PS demo/training của team test ─────────────
  SELECT string_agg(ps || ' (' || so_dong_ke_hoach || ' dòng)', ', ')
    INTO v_con
    FROM shared.v_dm_ps_lech_ten
   WHERE tinh_trang = 'chỉ có trong kế hoạch' AND so_dong_ke_hoach > 0;
  IF v_con IS NOT NULL THEN
    RAISE NOTICE 'Còn PS trong kế hoạch không có trong dm_ps: % (Giang Đỗ = team test, bỏ qua)', v_con;
  END IF;
END $$;
