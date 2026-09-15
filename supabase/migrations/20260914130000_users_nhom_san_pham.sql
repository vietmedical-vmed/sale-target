-- ════════════════════════════════════════════════════════════════════════
-- PR-1: Bổ sung chiều "nhom_san_pham" cho shared.users.
--
-- Bối cảnh: hôm nay chỉ có 3 chiều phạm vi (bu, mien, ps qua cột scope).
-- Case Hạnh Hoàng cần "area_manager MN + hạn chế nhóm Khớp Zimmer" → thêm
-- cột nhom_san_pham để diễn tả chiều thứ 4 mà không overload lại scope.
--
-- PR này CHỈ đụng schema — chưa sửa login/edge function/RPC nào. Cột mới để
-- null cho MỌI user hiện tại nghĩa là "thấy mọi nhóm" (tương thích ngược).
-- PR-2 sẽ nhét cột này vào token + filter đọc + verify RPC ghi.
--
-- Ràng buộc TỐI THIỂU:
--   • CHECK: đã set nhom_san_pham thì bu phải khác NULL (nhóm sản phẩm luôn
--     thuộc 1 BU cụ thể; không cho "toàn BU nhưng khoá 1 nhóm").
--
-- CỐ Ý KHÔNG add FK trỏ shared.dm_nhom_san_pham vì:
--   1) vocab `bu` lệch:
--         users.bu / sale_target.bu = chcs, cttm, thnk (mã ngắn)
--         dm_nhom_san_pham.bu       = CH&CS, CTTM & CTUT, THNS & CSVT (tên dài)
--      → FK composite (bu, nhom_san_pham) sẽ không match được.
--   2) dm_nhom_san_pham (13 nhóm) THIẾU so với thực tế trong sale_target
--      (19 nhóm khác nhau). FK cột đơn nhom_san_pham cũng chặn nhiều nhóm
--      hợp lệ đang chạy (BSC - IC, IC, IO, TH DHM, TH DMĐ, ...).
--   Chuẩn hoá vocab bu + đồng bộ danh mục là 2 task riêng, sẽ làm sau. Trước
--   mắt validate ở admin panel (PR-2, mức mềm — suggest từ dm nhưng cho tự do
--   nhập).
--
-- CỐ Ý KHÔNG add CHECK "role=admin phải null hết" vì dữ liệu hiện tại admin
-- đang có bu/mien không null; đụng vào là break rows đang chạy.
-- ════════════════════════════════════════════════════════════════════════

begin;

alter table shared.users
  add column if not exists nhom_san_pham text;

alter table shared.users
  drop constraint if exists chk_nhom_sp_requires_bu;

alter table shared.users
  add constraint chk_nhom_sp_requires_bu
  check (nhom_san_pham is null or bu is not null);

commit;

-- ─── KIỂM TRA SAU KHI CHẠY ────────────────────────────────────────────────
-- (a) Cột đã có, tất cả null (tương thích ngược):
--   select count(*) filter (where nhom_san_pham is null) as null_count,
--          count(*) as total from shared.users;
--   -- Kỳ vọng: null_count = total
--
-- (b) CHECK constraint đã hiện diện:
--   select conname, pg_get_constraintdef(oid) from pg_constraint
--   where conrelid = 'shared.users'::regclass
--     and conname = 'chk_nhom_sp_requires_bu';
--
-- (c) Thử vi phạm CHECK (kỳ vọng LỖI):
--   begin;
--     update shared.users set nhom_san_pham = 'X', bu = null
--     where username = 'Hạnh Hoàng';
--   rollback;
--
-- (d) Gán nhóm cho Hạnh Hoàng — CHỈ chạy sau khi PR-2 xong (bây giờ chạy
--     cũng không ảnh hưởng vì chưa ai đọc cột này, nhưng chờ để log rõ):
--   update shared.users
--   set    nhom_san_pham = 'Khớp Zimmer'
--   where  username = 'Hạnh Hoàng' and bu = 'chcs';
