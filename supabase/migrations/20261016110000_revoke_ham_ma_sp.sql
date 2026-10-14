-- Thu hồi quyền gọi của anon / authenticated trên các hàm phụ của khoá quota theo mã
-- (20261016100000). Hàm chạy theo quyền người gọi nên RLS vẫn chặn đọc, nhưng hàm mới
-- tạo trong schema được expose luôn phải khoá lại (xem drop-function-mat-quyen).
REVOKE ALL ON FUNCTION shared.ma_sp_cua_khoa(text, text, text, text, text, text, numeric) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION shared.ma_sp_hop_le(text) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION shared.ten_sp_chuan(text) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION shared.trg_quota_thau_ma_sp() FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION shared.ma_sp_cua_khoa(text, text, text, text, text, text, numeric) TO service_role;
GRANT EXECUTE ON FUNCTION shared.ma_sp_hop_le(text) TO service_role;
GRANT EXECUTE ON FUNCTION shared.ten_sp_chuan(text) TO service_role;
