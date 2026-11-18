-- Rollback 20261112100000_doi_chieu_quota_hop_dong: chỉ gỡ view + hàm đối chiếu (không có dữ liệu).
drop function if exists shared.doi_chieu_quota_hop_dong(text, date, text);
drop view if exists shared.v_hop_dong_dong;
drop view if exists shared.v_khoa_so_sanh_sp;
