-- ════════════════════════════════════════════════════════════════════════
-- SEED shared.dm_ps — bảng dịch PS: Tên PS (đầy đủ) ↔ ps (rút gọn) + BU/Area/Team
--
-- Nguồn: file "Danh mục Địa bàn.xlsx", sheet "Danh mục PS" (29 dòng).
-- Dùng để chuẩn hoá app_sale.hoa_don_bovattu.ten_ps ("Nguyễn Văn Pháp")
-- → sale_target.ps ("Pháp Nguyễn"). Phủ 100% ten_ps đang có trong hoa_don.
--   - area  → dùng làm "mien" (hoa_don không có cột miền)
--   - GIỮ CẢ PS Inactive: doanh số lịch sử vẫn thuộc về họ, cần map đủ.
--
-- Idempotent: xoá sạch rồi nạp lại (bảng đang rỗng; master data dùng chung).
-- ════════════════════════════════════════════════════════════════════════

delete from shared.dm_ps;

-- Đồng bộ đúng shared.dm_ps trên production (30 dòng, gồm 'Hồ Hoàng Hiếu' user thêm).
insert into shared.dm_ps (bu, area, team, ps, ten_ps, trang_thai) values
  ('CH&CS', 'Miền Nam', 'CHCS 1 MN', 'Hiếu Hồ', 'Hồ Hoàng Hiếu', 'Active'),
  ('CH&CS', 'Miền Nam', 'CHCS 1 MN', 'Linh Tăng', 'Tăng Phụng Linh', 'Active'),
  ('CH&CS', 'Miền Nam', 'CHCS 1 MN', 'Ly Đào', 'Đào Mỹ Ly', 'Active'),
  ('CH&CS', 'Miền Nam', 'CHCS 1 MN', 'Pháp Nguyễn', 'Nguyễn Văn Pháp', 'Active'),
  ('CH&CS', 'Miền Nam', 'CHCS 1 MN', 'Tính Trương', 'Trương Trung Tính', 'Active'),
  ('CH&CS', 'Miền Nam', 'CHCS 2 MN', 'Dung Trần', 'Trần Thị Kim Dung', 'Active'),
  ('CH&CS', 'Miền Nam', 'CHCS 2 MN', 'Hạnh Hoàng', 'Hoàng Mỹ Hạnh', 'Active'),
  ('CH&CS', 'Miền Nam', 'CHCS 2 MN', 'Tám Nguyễn', 'Nguyễn Thị Bé Tám', 'Inactive'),
  ('CH&CS', 'Miền Nam', 'CHCS 2 MN', 'Thanh Nguyễn', 'Ngô Nguyễn Hoàng Thanh', 'Active'),
  ('CH&CS', 'Miền Bắc', 'CHCS MB', 'Mậu Cao', 'Cao Văn Mậu', 'Active'),
  ('CH&CS', 'Miền Bắc', 'CHCS MB', 'Mỹ Đỗ', 'Đỗ Thị Mỹ', 'Active'),
  ('CH&CS', 'Miền Bắc', 'CHCS MB', 'Nam Lê', 'Lê Đình Nam', 'Inactive'),
  ('CH&CS', 'Miền Bắc', 'CHCS MB', 'Tấn Phạm', 'Phạm Công Tấn', 'Active'),
  ('CH&CS', 'Miền Bắc', 'CHCS MB', 'Tứ Nguyễn', 'Nguyễn Đình Tứ', 'Active'),
  ('CH&CS', 'Miền Bắc', 'CHCS MB', 'Tùng Phạm', 'Phạm Ngọc Tùng', 'Active'),
  ('CH&CS', 'Miền Bắc', 'CHCS MB', 'Tuyên Phạm', 'Phạm Văn Tuyên', 'Active'),
  ('CTTM & CTUT', 'Miền Bắc', 'CTTM', 'Hương Đồng', 'Đồng Thị Hương', 'Active'),
  ('CTTM & CTUT', 'Miền Nam', 'CTTM', 'Nhật Trang', 'Trần Thị Nhật Trang', 'Active'),
  ('CTTM & CTUT', 'Miền Nam', 'CTTM', 'Phương Hoàng', 'Lê Thị Phương Hoàng', 'Active'),
  ('CTTM & CTUT', 'Miền Nam', 'CTTM', 'Quí Nguyễn', 'Nguyễn Thị Mỹ Quí', 'Inactive'),
  ('THNS & CSVT', 'Miền Bắc', 'NSCT', 'Đinh Kiên', 'Đinh Quang Kiên', 'Active'),
  ('THNS & CSVT', 'Miền Bắc', 'NSCT', 'Đức Nguyễn', 'Nguyễn Mạnh Đức', 'Active'),
  ('THNS & CSVT', 'Miền Bắc', 'NSCT', 'Duyên Nguyễn', 'Nguyễn Thị Duyên', 'Active'),
  ('THNS & CSVT', 'Miền Bắc', 'NSCT', 'Huy Hoàng', 'Hoàng Văn Huy', 'Inactive'),
  ('THNS & CSVT', 'Miền Nam', 'NSCT', 'Lợi Phan', 'Phan Đỗ Ngọc Lợi', 'Active'),
  ('THNS & CSVT', 'Miền Bắc', 'NSCT', 'Mai Trịnh', 'Trịnh Thị Ngọc Mai', 'Active'),
  ('THNS & CSVT', 'Miền Bắc', 'NSCT', 'Nga Trần', 'Trần Thị Mỹ Nga', 'Active'),
  ('THNS & CSVT', 'Miền Bắc', 'NSCT', 'Ngân Nguyễn', 'Nguyễn Thị Kim Ngân', 'Active'),
  ('THNS & CSVT', 'Miền Nam', 'NSCT', 'Phương Nguyễn', 'Nguyễn Thị Kim Phương', 'Active'),
  ('THNS & CSVT', 'Miền Trung', 'NSCT', 'Trang Trần', 'Trần Ngọc Đoan Trang', 'Active');

-- Cảnh báo trùng ten_ps (sẽ nhân đôi dòng khi join) — nên trả 0.
do $$
declare n int;
begin
  select count(*) into n from (
    select lower(btrim(ten_ps)) k from shared.dm_ps group by 1 having count(*) > 1
  ) t;
  if n > 0 then
    raise warning 'dm_ps: có % ten_ps trùng (chuẩn hoá lower/trim) — kiểm tra lại!', n;
  end if;
end $$;
