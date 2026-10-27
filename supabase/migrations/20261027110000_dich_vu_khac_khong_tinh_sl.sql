-- Dòng "Dịch vụ khác" trên hoá đơn: chỉ tính doanh thu, không tính số lượng khi cùng hoá đơn
-- đã có dòng hàng của chính sản phẩm đó với giá 0.
--
-- Một số hoá đơn tách mỗi sản phẩm làm 2 phần: dòng vật tư thật (SL đúng, tiền 0) + dòng
-- "Dịch vụ khác" (cùng SL, mang toàn bộ tiền), cả hai map vào cùng sản phẩm → SL thực hiện
-- bị đếm gấp đôi, đơn giá bình quân còn một nửa.
-- Ca gốc 27/10: BV0320 T7 hoá đơn C26TTA2048 — Interlock 18 thật 35 cái (app hiện 70),
-- Coil đẩy 10 cái (app hiện 20); doanh thu 533,5tr là đúng. Quét ra 20 dòng "Dịch vụ khác"
-- T4–T8/2026 có dòng hàng giá 0 đi kèm (Hương Đồng, Nhật Trang, Anh Trương).
-- Dòng "Dịch vụ khác" đứng một mình (không có dòng hàng giá 0) vẫn giữ SL.
--
-- Sửa ở view hiệu lực nên mọi tầng sau (chia PS, hoa_don_actual, đồng bộ thực hiện) cùng nhận.
-- Sau migration chạy "Cập nhật thực hiện" (start_sync_job).
-- Hoàn tác: supabase/rollbacks/20261027110000_dich_vu_khac_khong_tinh_sl_ROLLBACK.sql

CREATE OR REPLACE VIEW app_sale.hoa_don_bovattu_hieu_luc AS
SELECT id,
    thang,
    nam,
    ngay_tai_lieu,
    so_tai_lieu,
    so_hd,
    so_eo,
    ma_kh,
    ten_kh,
    bu,
    nhom_san_pham,
    bo_vat_tu,
    san_pham,
    ma_vat_tu,
    ten_vat_tu,
    don_vi,
    CASE
      WHEN h.ten_vat_tu ILIKE 'dịch vụ khác%'
       AND EXISTS (SELECT 1
                     FROM app_sale.hoa_don_bovattu g
                    WHERE g.so_tai_lieu = h.so_tai_lieu
                      AND g.ngay_tai_lieu = h.ngay_tai_lieu
                      AND g.ma_kh = h.ma_kh
                      AND g.san_pham = h.san_pham
                      AND g.id <> h.id
                      AND coalesce(g.tong_gia_ban, 0) = 0
                      AND coalesce(g.so_luong, 0) <> 0
                      AND g.ten_vat_tu NOT ILIKE 'dịch vụ khác%')
      THEN 0::numeric
      ELSE so_luong
    END AS so_luong,
    tong_gia_ban,
    do_phu,
    nghi_van,
    bo_thay_the,
    num_items,
    item_codes,
    ten_ps,
    ma_bo_phan,
    ten_bo_phan,
    ma_nhan_vien,
    ten_nhan_vien,
    created_at,
    ma_hd,
    ma_chung,
    ma_san_pham,
    ma_ho_san_pham,
    ten_ho_san_pham
   FROM app_sale.hoa_don_bovattu h
  WHERE NOT (EXISTS ( SELECT 1
           FROM app_sale.hoa_don_loai_tru x
          WHERE x.dang_loai_tru AND x.so_tai_lieu = h.so_tai_lieu AND x.ngay_tai_lieu = h.ngay_tai_lieu));
