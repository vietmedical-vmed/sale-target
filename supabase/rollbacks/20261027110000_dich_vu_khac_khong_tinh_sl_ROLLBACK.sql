-- Hoàn tác 20261027110000: dòng "Dịch vụ khác" tính lại số lượng như hoá đơn gốc.
-- Chạy lại "Cập nhật thực hiện" sau khi hoàn tác.

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
    so_luong,
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
