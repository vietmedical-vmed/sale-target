# PRD — Sale Target (Kế hoạch kinh doanh)


| Phiên bản tài liệu | Nội dung | Ngày | Thực hiện bởi |
|---|---|---|---|
| 1.0 | Khởi tạo tài liệu | 2026-06-20 | Đỗ Hoàng Giang |
| 1.1 | Cập nhật theo các thay đổi tới 2026-09-15: chuyển toàn bộ bảng sang schema `shared`; tách đợt thầu & quota thầu ra bảng riêng (nhập nhiều mức giá); giải trình chuyển sang log append-only; thêm tab "Lịch sử cập nhật" (audit log); nút "Đồng bộ thực hiện"; admin sửa được một số cột danh mục; product summary 5 cột quota; cột Mã SP; danh sách action & mô hình dữ liệu cập nhật lại | 2026-09-15 | Đỗ Hoàng Giang |
| 1.2 | Cập nhật theo code tới commit 72a2161 (2026-11-19): frontend chuyển sang Vite + JSX; 8 tab (thêm Kiểm tra thông tin thầu, So sánh đơn giá, So sánh KH update); quota chỉ còn ở `quota_thau`/`dot_thau` (DROP 6 cột quota trên `sale_target`), khoá theo mã SP; liên kết quota ↔ hợp đồng; chia hoá đơn cho nhiều PS, loại trừ hoá đơn; bản chụp kế hoạch hằng tháng + khoá sửa sau hạn chót; cột Đánh giá dự kiến, KD định mức; manager được sửa; bảng riêng của app chuyển sang schema `app_sale`; phiên 2 giờ/tối đa 24 giờ, khoá đăng nhập; delta sync | 2026-11-20 | Đỗ Hoàng Giang |

---

## 1. Tổng quan (Overview)

**Sale Target** là ứng dụng web một trang giúp đội ngũ kinh doanh **lập, cập nhật và theo dõi kế hoạch bán hàng** năm tài chính, đối chiếu với **thực hiện từ hoá đơn** và **quota thầu**. Dữ liệu phân rã theo Team (BU) → Miền → Phụ trách (PS) → Khách hàng → Nhóm SP → Bộ vật tư → Sản phẩm, 12 cột tháng.

Ứng dụng giải quyết 4 việc:
- PS cập nhật SL kế hoạch từng tháng ngay trên bảng, có hạn chót hằng tháng.
- Quản lý xem tổng hợp theo PS và theo sản phẩm, so với target đầu năm và quota thầu.
- Admin giữ dữ liệu sạch: địa bàn PS, đợt thầu/quota, liên kết quota với hợp đồng, loại trừ hoá đơn.
- Lưu vết mọi thay đổi: lịch sử cập nhật, giải trình, bản chụp kế hoạch hằng tháng.

**Phạm vi:** năm tài chính đang chạy (FY26 = 04/2026 → 03/2027).

**Product Owner:** Đỗ Hoàng Giang

---

## 2. Bối cảnh & Vấn đề (Background & Problem)

### 2.1 Hiện trạng trước đây
- Kế hoạch bán hàng trước đây chạy trên nhiều file Excel của từng PS.
- Dữ liệu phân tán, khó phân quyền theo vai trò, khó tổng hợp nhiều chiều, hiệu năng kém khi dữ liệu lớn.

### 2.2 Vấn đề cần giải quyết
1. **Một nguồn tin cậy:** nhiều cấp (admin, manager, quản lý ngành hàng, quản lý miền, PS) cùng nhìn một bộ số.
2. **Phân quyền dữ liệu:** mỗi vai trò chỉ xem/sửa đúng phạm vi của mình.
3. **Đồng bộ khi nhiều người sửa:** phát hiện thay đổi, không ghi đè lẫn nhau.
4. **Tổng hợp đa chiều:** theo PS và theo sản phẩm, kèm quota và doanh thu.
5. **Kiểm soát chất lượng kế hoạch:** kế hoạch có hợp lý so với quota thầu, hợp đồng, target không.
6. **Hiệu năng ở quy mô ~20.000 dòng.**

### 2.3 Giải pháp đã chọn
Backend **Supabase** (Postgres + Edge Functions). Frontend React build bằng **Vite**, host trên **GitHub Pages**. Mọi nghiệp vụ đi qua một Edge Function API với token ký HMAC; frontend không đọc DB trực tiếp.

---

## 3. Mục tiêu & Phi mục tiêu (Goals / Non-goals)

### 3.1 Mục tiêu
| # | Mục tiêu | Loại |
|---|---|---|
| G1 | PS/manager/admin sửa kế hoạch theo tháng ngay trên bảng, có hạn chót | Sản phẩm |
| G2 | Phân quyền dữ liệu theo 5 vai trò × phạm vi (team/miền/PS/ngành hàng) | Sản phẩm |
| G3 | 8 tab: Chi tiết, 2 màn tổng hợp, Cấu hình địa bàn, 3 tab kiểm soát, Lịch sử cập nhật | Sản phẩm |
| G4 | Xuất Excel giữ cấu trúc phân cấp | Sản phẩm |
| G5 | Tải & thao tác mượt ở quy mô ~20k dòng | Kỹ thuật |
| G6 | Quản lý bám sát quota khả dụng, quota định mức và chênh lệch kế hoạch | Kinh doanh |
| G7 | Đối chiếu quota thầu với hợp đồng, theo dõi việc cần xử lý | Kinh doanh |

### 3.2 Phi mục tiêu (Non-goals)
- Không phải CRM; không quản lý đơn hàng; hợp đồng do app khác nạp, app này chỉ đọc.
- Không tự động tính hoa hồng/lương thưởng.
- Không có quy trình phê duyệt kế hoạch nhiều bước.
- Không nhập tay số thực hiện: `sl_thuc_hien`/`doanh_thu_thuc_hien` luôn sinh từ hoá đơn qua "Đồng bộ thực hiện" (§5.3).
- Chỉ tiếng Việt.

---

## 4. Đối tượng người dùng & Phân quyền (Personas & Roles)

### 4.1 Team (bu)
Mỗi dòng kế hoạch gắn một **Team** (`bu`): **CHCS, CTTM, THNK**, và **TEST** cho demo/training. Team TEST tách biệt hoàn toàn về số liệu (§8).

### 4.2 Năm vai trò & phạm vi

| Vai trò | Phạm vi dữ liệu | Sửa kế hoạch | Tab riêng |
|---|---|---|---|
| **admin** | Mọi team, chọn BU | SL KH update, đơn giá, SL/DThu đầu năm, bộ vật tư, tên SP; xoá SP/KH | Tất cả, gồm thẻ Cấu hình hệ thống |
| **manager** | Mọi team hoặc 1 team | SL KH update, đơn giá, SL đầu năm | Kiểm tra thông tin thầu, So sánh đơn giá, So sánh KH update |
| **area_manager** | Miền phụ trách trong team (được nhiều miền) | SL KH update, đơn giá | — |
| **ps** | Dòng của chính mình trong team | SL KH update, đơn giá | — |
| **product_manager** | Ngành hàng phụ trách (nhiều ngành, ngăn cách dấu phẩy), xuyên team | Chỉ xem | — |

**Quy tắc quan trọng:**
- Cột ghi được chia 3 nhóm trong `supabase/functions/sale_target-api/config.ts`: `EDITABLE` (`revUpd`, `price`) cho mọi vai trò có quyền sửa; `MANAGER_EDITABLE` (`rev`; DThu đầu năm do server tính = SL × đơn giá); `ADMIN_EDITABLE` (`mset`, `prod`, `rev`, `dt`). RPC `update_sale_target_cells` chốt lại ở DB, không tin client.
- **Khoá sau hạn chót:** từ ngày `deadline_day` + 1 của tháng M (giờ VN, theo lịch), non-admin không sửa được SL KH update của tháng M và mọi tháng trước. Đơn giá không khoá.
- Phạm vi ghi bám đúng phạm vi xem; với vai trò không phải admin/manager, phạm vi khoá theo token phía server.
- **Thêm sản phẩm:** `ps` luôn bị ép về chính mình; area_manager chỉ thêm cho PS thuộc đúng team + miền của mình.
- **Cấu hình địa bàn:** admin và manager sửa/chuyển/xoá; `ps` chỉ được tự thêm địa bàn cho KH chưa có trong cấu hình.
- **Chỉ admin:** xoá SP/KH, đồng bộ thực hiện, loại trừ hoá đơn, sửa PS trên hoá đơn, chụp kế hoạch tay, gắn quota ↔ hợp đồng, gắn tay/bỏ gắn/thêm alias mã trong Kiểm tra thông tin thầu, xuất quota thầu, sửa `app_config`, sửa danh mục PS.

### 4.3 Persona tóm tắt
- **Admin:** điều phối kế hoạch, giữ dữ liệu sạch, chạy đồng bộ.
- **Manager:** theo dõi toàn cảnh, kiểm soát kế hoạch và quota, sửa SL đầu năm.
- **Product Manager:** theo dõi ngành hàng xuyên team.
- **Area Manager:** theo dõi và cập nhật địa bàn phụ trách.
- **PS:** cập nhật kế hoạch và giải trình cho khách hàng của mình.

---

## 5. Luồng nghiệp vụ chính (User Flows)

### 5.1 Đăng nhập / đổi mật khẩu
1. Người dùng nhập `username` + `password`. Edge `sale_target-login` kiểm trên `shared.users` (bảng dùng chung với portal, order, kpi-review, contract, ccdc).
2. `password_hash` (SHA-256, có salt nếu có) là gốc; `password_bcrypt` chỉ là cache của app này — phải khớp cả hai. Tài khoản `active = false` bị chặn.
3. Khoá khi sai mật khẩu trong 15 phút: 5 lần theo user × IP, 20 lần theo user, 50 lần theo IP.
4. Token ký HMAC sống **2 giờ**, gia hạn qua `refreshToken`; phiên tối đa **24 giờ** từ lúc đăng nhập. Vai trò/phạm vi đọc lại từ `shared.users` mỗi request.
5. Đổi mật khẩu: ghi salt + `password_hash` mới, làm mới cache của app này, xoá cache của app khác; yêu cầu đăng nhập lại.

### 5.2 Chu kỳ cập nhật hằng tháng
1. Admin đặt tháng hiện tại và ngày hạn chót (`shared.app_config`: `current_month`, `deadline_day`).
2. PS sửa SL KH update các tháng còn lại và ghi giải trình trước hạn chót.
3. 23:59 (giờ VN) từ ngày hạn chót, cron `chot-ke-hoach-thang` chụp toàn bộ kế hoạch FY vào `app_sale.ke_hoach_chot` nếu kỳ chưa có. Admin chụp tay trước thì cron bỏ qua kỳ đó.
4. Sau hạn chót, non-admin không sửa được SL KH update của tháng đó trở về trước.
5. Admin, manager so 2 kỳ ở tab So sánh KH update và xuất giải trình theo tháng.

### 5.3 Số thực hiện từ hoá đơn
```
app_sale.hoa_don_bovattu                (hoá đơn thô, script ngoài repo nạp theo tháng)
  → hoa_don_bovattu_hieu_luc            (bỏ HĐ đang loại trừ — §6.11)
  → v_chia_ps → hoa_don_bovattu_chia    (chia cho nhiều PS: phiếu SV → số tiền ngành hàng → tỷ lệ tạm)
  → hoa_don_actual                      (ten_ps → ps qua shared.dm_ps; miền = dm_ps.area)
  → map_hoadon_to_sale_target()         (admin bấm "Đồng bộ thực hiện" → start_sync_job, ~50 s)
       ├─ khớp   → sale_target.sl_thuc_hien, doanh_thu_thuc_hien
       └─ không khớp → xoá rồi tạo lại dòng ngoai_ke_hoach = true (§6.6)
```
- Khoá khớp: tháng | PS | mã KH | bộ VT | SP, gộp khoảng trắng (`regexp_replace(lower(btrim(x)),'\s+',' ','g')`).
- Chỉ cặp KH × nhóm khai ở `app_sale.chia_ps_pham_vi` mới bị chia PS. Chia tính live từ khoá tài liệu, không lưu theo id (hoá đơn nạp lại thì id đổi).
- Doanh thu tính theo **tháng hoá đơn**, không theo tháng sử dụng. Dòng "Dịch vụ khác" không tính SL.
- Đổi cấu hình loại trừ / chia PS / danh mục PS xong phải chạy lại đồng bộ; popup Loại trừ hoá đơn tự chạy khi đóng nếu có thay đổi.

### 5.4 Đồng bộ giữa nhiều người dùng
- Mỗi dòng có `_rev`. Client gọi `getChanges` theo chu kỳ, chỉ lấy dòng mới (đọc lùi 500 rev để không sót transaction commit muộn).
- `shared.app_config.sale_target_epoch` tăng sau đồng bộ thực hiện hoặc sửa PS hàng loạt; client thấy epoch đổi thì tải lại toàn bộ.
- Ghi ô có khoá lạc quan: dòng đã bị người khác sửa thì báo xung đột, không ghi đè.

---

## 6. Yêu cầu chức năng (Functional Requirements)

Ứng dụng có **8 tab**. Trên cùng mọi tab dữ liệu là thẻ BU (DThu dự kiến / Target đầu năm, ngưỡng màu 90%) và dashboard (Số KH, % TH YTD, top 5 nhóm SP theo % hoàn thành YTD, biểu đồ waterfall).

| Tab | Ai thấy | Nội dung chính |
|---|---|---|
| Chi tiết kế hoạch | Mọi vai trò | Thẻ KH, dòng KH × SP × đơn giá × 12 tháng; sửa ô, thêm KH/SP, quota, giải trình, ngoài kế hoạch, xuất Excel |
| Tổng hợp theo PS | Mọi vai trò | Miền → PS → KH → Nhóm SP → SP; 2 chế độ Doanh thu / Số lượng; cột Đánh giá (admin) |
| Tổng hợp theo SP | Mọi vai trò | Miền → Nhóm SP → SP → KH; SL 12 tháng + cột quota |
| Cấu hình địa bàn | Mọi vai trò (ghi: admin, manager; PS tự thêm) | KH × ngành hàng → PS theo khoảng hiệu lực |
| Kiểm tra thông tin thầu | Admin, manager | 3 bước theo dõi việc: đợt thiếu thông tin, SP quota âm, quota ↔ hợp đồng |
| So sánh đơn giá | Admin, manager | Đơn giá kế hoạch so với giá bình quân hoá đơn |
| So sánh KH update | Admin, manager | So 2 bản chụp kế hoạch, hoặc bản chụp với hiện tại |
| Lịch sử cập nhật | Mọi vai trò, lọc theo vai trò | Log gom theo ngày × người × thao tác, chi tiết từng ô, hạn chót |

### 6.1 Chi tiết kế hoạch
- Mỗi dòng = KH × SP × đơn giá, 12 cột tháng. SP cùng tên **khác đơn giá** tách dòng riêng (§8); đơn giá làm tròn để không sinh dòng gần trùng.
- Thẻ KH xếp theo mã bệnh viện; danh sách ảo hoá (`@tanstack/react-virtual`); header dính.
- Cột: SL đầu năm, SL KH update từng tháng, đơn giá, doanh thu, chênh lệch (xanh/đỏ), KH còn lại, quota khả dụng. Tháng đã qua lấy thực hiện; tháng hiện tại highlight.
- Ô đang sửa có viền nhấn; ô chưa lưu tô màu hổ phách. Ô số parse chặt (`parseNumStrict`).
- **Thêm khách hàng:** popup 2 bước (KH + PS, rồi SP đầu tiên). Không có ô Miền — suy từ PS (server `mienForPs()`). Kiểm trùng KH theo BU đang xem.
- **Thêm sản phẩm:** popup chọn PS / Nhóm SP / Bộ vật tư; kiểu thêm *Vật tư riêng lẻ* hoặc *Cả bộ* (bộ "Vật tư riêng lẻ - …" luôn chọn từng vật tư); tick nhiều SP (sắp A→Z), mỗi SP có ô đơn giá, mỗi SP sinh 12 dòng. Đơn giá mặc định: CTTM theo `dm_vat_tu.don_gia_thau_moi`; vật tư lẻ gợi ý giá danh mục; còn lại giá đang dùng nhiều nhất trong kế hoạch. Form **không còn ô tháng thầu** (tháng thầu nằm ở đợt thầu).
- **Đợt thầu & quota:** modal nhập nhiều đợt, nhiều mức giá, cả nhóm SP một lần; đợt mới lưu cùng quota; bắt buộc tháng thầu + hiệu lực cho mọi đợt.
- **Giải trình:** nút trên dòng mở log append-only (`getGiaiTrinh`/`saveGiaiTrinh`).
- **Lịch sử dòng:** nút trên thẻ SP mở lịch sử sửa của riêng SP đó (`getLichSuSanPham`).
- **Ngoài kế hoạch:** khối riêng trên Chi tiết hiện thực hiện không khớp dòng kế hoạch nào.
- Admin điền SL đầu năm vào tháng thiếu dòng thì app tự tạo dòng (`ensureMonthRow`).
- **Xuất Excel** tab Chi tiết, kèm tháng thầu và hiệu lực.
- Dòng "Dữ liệu cập nhật đến ngày" dưới thanh lọc; nút "Tìm hiểu thêm" mở định nghĩa & công thức.

### 6.2 Tổng hợp theo PS
- Phân cấp **Miền → PS → Khách hàng → Nhóm SP → Sản phẩm**, gập/mở; 2 chế độ **Doanh thu / Số lượng**.
- Cột: Target đầu năm, DThu dự kiến, DThu dự kiến / Target, TH YTD, % TH YTD, KH còn lại, Chênh lệch, quota (On hand, Upcoming, Tổng, Khả dụng, KD định mức), CL tốc độ.
- **Cột Đánh giá (chỉ admin):** §7.3. Bỏ BV tư và KH ngoài kế hoạch; cấp trên đếm theo màu.
- **Xuất giải trình:** chọn tháng; theo PS × KH × nhóm SP, kèm DThu KH và TH YTD.
- Xuất Excel giữ phân cấp; sheet SL có cột Đơn giá.

### 6.3 Tổng hợp theo Sản phẩm
- Phân cấp **Miền → Nhóm SP → SP → KH**; 2 chế độ Doanh thu / Số lượng; Miền mở sẵn; nhóm SP sắp theo DThu update; bộ vật tư đứng trước vật tư lẻ.
- Cột: SL KH update 12 tháng, rồi On hand, Upcoming, Tổng quota, TH YTD, Khả dụng, KD định mức; so TH với target năm.
- Cột Hết HL đang ẩn (`HIEN_HET_HIEU_LUC = false` trong `src/config/constants.js`); phần hết hiệu lực trước đầu FY vẫn không vào tổng.

### 6.4 Cấu hình địa bàn
Khai báo **(Khách hàng × Ngành hàng) → PS phụ trách** trong `shared.dm_dia_ban`, độ mịn dừng ở ngành hàng.

- Bảng phẳng kèm thẻ thống kê; trạng thái đối chiếu tính ở client: *Khớp kế hoạch* / *Lệch kế hoạch* / *Chưa có kế hoạch*.
- Danh sách PS lấy từ `shared.dm_ps`; PS không có trong `dm_ps` bị đánh dấu đỏ (hoá đơn của họ sẽ không bao giờ khớp kế hoạch).
- **Miền không nhập tay** — là thuộc tính của PS, server tự suy lại khi lưu.
- **Thời gian hiệu lực:** mỗi khai báo có `[tu_thang, den_thang]` dạng `'YYYY-MM'` (`den_thang` NULL = còn hiệu lực).
  - Đổi người phụ trách giữa năm = **Chuyển PS** (`chuyen_dia_ban`): đóng bản cũ ở tháng liền trước + mở bản mới, trong 1 giao dịch. Quá khứ giữ nguyên.
  - Sửa PS tại chỗ = sửa sai cho cả khoảng hiệu lực của bản đó.
  - Ô "Xem theo tháng" chọn thời điểm; khai báo trước cho tương lai được.
- **Không được có khoảng trống:** tổ hợp đã khai báo thì mọi tháng có dòng kế hoạch phải được phủ; mọi đường ghi kiểm qua `v_dia_ban_khoang_trong` trong cùng giao dịch và huỷ cả lô nếu vi phạm.
- **Áp vào kế hoạch:** nút "Áp N lệch vào KH" và nút áp từng dòng ghi PS/Miền xuống `sale_target` trong đúng khoảng hiệu lực của bản đó. Bản có nhiều PS chồng lấn thời gian bị bỏ qua và báo lại.
- **Thẻ Cấu hình hệ thống (admin):** tháng hiện tại, hạn chót, Đồng bộ thực hiện, Đối chiếu thực hiện, Loại trừ hoá đơn, danh mục PS.

### 6.5 Tính năng ngang

| Tính năng | Mô tả |
|---|---|
| **Bộ lọc** | Ngành hàng, Miền, PS, Khách hàng (multi-select), hiển thị theo quyền. |
| **Thanh BU** | Admin/manager chọn 1 team hoặc "Tất cả"; thẻ BU có tỷ lệ DThu dự kiến / Target. |
| **Ô tìm kiếm** | Gần đúng theo tên KH / mã KH / SP / bộ vật tư; dùng chung cho Chi tiết và 2 màn tổng hợp. |
| **Header dính** | Bảng tổng hợp cao gần trọn màn hình, chỉ bảng cuộn dọc. |
| **Xuất Excel** | Nút trên thanh bộ lọc, đổi theo tab; giữ phân cấp, header gộp (SheetJS). |
| **Đồng bộ** | Delta sync qua `getChanges` + epoch (§5.4); banner "dữ liệu cũ" khi cần tải lại. |
| **Đổi mật khẩu** | Ngay tại màn đăng nhập. |

### 6.6 Ngoài kế hoạch (OOP)
Dòng thực hiện không khớp dòng kế hoạch nào (`ngoai_ke_hoach = true`).
- Ở 2 màn tổng hợp: cấp KH gom vào một dòng "Ngoài kế hoạch"; mở ra là từng KH thật, rồi Nhóm SP → SP. Không có quota → Khả dụng = "—".
- Ở Chi tiết: khối riêng, không trộn vào thẻ KH.
- Nguyên nhân thường gặp: thiếu dòng tháng, lệch tên bộ VT, lệch PS (địa bàn / `dm_ps`), hoặc ngoài kế hoạch thật.

### 6.7 Lịch sử cập nhật
- RPC phía server gom log theo ngày VN × người × thao tác, phân trang theo nhóm (`audit_nhom`); chi tiết từng ô có SP, tháng, cũ → mới (`audit_chi_tiet`); thống kê sửa SL KH update trong kỳ hạn chót (`audit_deadline`).
- Ai thấy gì (`audit_log_xem`): admin thấy hết; manager thấy hết trừ log admin/script; area_manager thấy log mình + PS cùng BU và miền; vai trò khác chỉ log của mình.
- Tên hiển thị lấy từ `shared.users.ho_va_ten`.

### 6.8 Kiểm tra thông tin thầu (admin, manager)
Ba bước, mỗi bước ra danh sách việc cùng một dạng:
1. **Đợt thiếu thông tin:** đợt thiếu tháng thầu hoặc hiệu lực, kèm tên KH và giá trị thầu.
2. **SP quota âm:** SP trên Chi tiết có on hand − TH YTD < 0, nhóm theo lý do; cột loại bệnh viện, giá trị quota khả dụng.
3. **Quota ↔ hợp đồng:** khoá KH × SP không khớp (`kiem_tra_doi_chieu_hop_dong`), chia 7 nhóm nguyên nhân. Popup chi tiết cho:
   - Chuyển **Quota 1.4 → thầu chính** theo hợp đồng ký trong năm (tháng = tháng ký, hiệu lực tới hạn HĐ).
   - Chuyển **Upcoming → On hand** khi đã ký HĐ (tách SP có HĐ sang đợt mới, SL theo HĐ).
   - Admin gắn tay, bỏ gắn, thêm alias mã (`khoa_sp_alias`).

Mỗi việc có trạng thái (chưa xử lý / đang xử lý / bỏ qua kèm ghi chú / xong), người phụ trách và xu hướng theo ngày (`app_sale.kiem_tra_thau_xu_ly`, `kiem_tra_thau_snapshot`). Ảnh chụp số liệu do client ghi mỗi lần mở tab. Việc đã biến khỏi danh sách tự chuyển "xong"; việc xong mà xuất hiện lại tính là tái phát. Admin có thêm nút **Gắn quota ↔ HĐ** và **Xuất quota thầu**.

### 6.9 So sánh đơn giá (admin, manager)
- Theo dòng KH × SP × PS × mức giá: đơn giá kế hoạch so với giá bình quân hoá đơn = Σ DThu TH / Σ SL TH. Các dòng cùng SP đứng liền nhau.
- Sửa đơn giá tại chỗ.

### 6.10 So sánh KH update (admin, manager)
- So 2 kỳ chụp (`so_sanh_chot_ke_hoach`), gộp BU → miền → PS → KH → nhóm × tháng; mọi BU mở tới PS.
- Bản chụp giữ nguyên như lúc chụp: mỗi bên tính theo tháng hiện tại của chính nó. Tháng đã có TH thì hiện KH bên cạnh TH.
- Luật chênh: admin sửa đơn giá **không** tính vào chênh (`ap_gia_admin_vao_ban_chup` áp giá mới vào mọi kỳ); PS sửa giá thì có. Giá gốc giữ ở `don_gia_goc`, lịch sử ở `ke_hoach_chot_dieu_chinh`.
- Admin có 2 ô tick: loại điều chỉnh giá của admin, loại chênh do đồng bộ thực hiện. Manager luôn nhận số đã loại.

### 6.11 Loại trừ hoá đơn (admin, trong thẻ Cấu hình hệ thống)
- Bảng `app_sale.hoa_don_loai_tru`, khoá (`so_tai_lieu`, `ngay_tai_lieu`) vì số tài liệu đánh lại mỗi năm; cờ `dang_loai_tru` bật/tắt, giữ lý do và người sửa.
- Lọc ở nguồn (trước khi chia PS) để HĐ bị loại không ăn phiếu SV trong FIFO.

---

## 7. Mô hình dữ liệu (Data Model)

> **Schema:** bảng dùng chung với app khác ở **`shared`**; bảng chỉ app này dùng ở **`app_sale`** (chuyển 2026-11-12); hợp đồng ở **`app_contract`** (app khác nạp). Migration mới phải `GRANT` cho `service_role` và REVOKE anon. `schema.sql` lệch xa DB thật — không dùng làm tài liệu.

### 7.1 Bảng chính

**`shared.sale_target`** — một dòng / tháng / SP / KH / mức giá:

| Cột DB | Field app | Ý nghĩa |
|---|---|---|
| `nam_tai_chinh` | fy | Năm tài chính (vd FY26) |
| `thang_ke_hoach` | mo | Tháng kế hoạch (YYYY-MM) |
| `mien` | region | Miền |
| `ps` | ps | Người phụ trách |
| `khach_hang` | cust | Tên khách hàng |
| `ma_khach_hang` | custId | Mã khách hàng |
| `nhom_san_pham` | grp | Nhóm/Ngành sản phẩm |
| `san_pham` | prod | Sản phẩm |
| `bo_vat_tu` | mset | Bộ vật tư |
| `sl_ke_hoach_dau_nam` | rev | SL kế hoạch đầu năm |
| `sl_ke_hoach_update` | revUpd | SL kế hoạch update |
| `don_gia` | price | Đơn giá |
| `doanh_thu_kh_dau_nam` | dt | Doanh thu KH đầu năm |
| `sl_thuc_hien` | act | SL thực hiện (từ hoá đơn) |
| `doanh_thu_thuc_hien` | dtAct | Doanh thu thực hiện (từ hoá đơn) |
| `ngoai_ke_hoach` | oop | Dòng thực hiện không khớp kế hoạch |
| `bu` | bu | Team |
| `_rev` | — | Số phiên bản dòng cho delta sync |

> Đã bỏ khỏi `sale_target`: cột `giai_trinh` (2026-09) và 6 cột quota/tháng/thời gian thầu (DROP 2026-10-16; giá trị cũ ở `shared.bak_20261014_*`, `bak_20261015_*`). Có thêm cột mã SP/mã bộ (`ma_san_pham`, `ma_bo_vat_tu`) do trigger điền theo danh mục.
> Khoá duy nhất `uq_sale_target_khoa` (deferrable); dòng trùng gộp bằng `gop_dong_trung_sale_target`. View đọc `sale_target` phải liệt kê cột, không `SELECT *`.

**Quota thầu** — `shared.dot_thau` (đợt: loại `cu`/`chinh`/`bo_sung`, tháng thầu, hiệu lực `thoi_gian` số tháng, trạng thái, nguồn) + `shared.quota_thau` (SL theo KH × SP × PS × mức giá, `ma_san_pham` do trigger điền). Đọc `get_quota_thau` (phân trang); ghi `upsert_dot_thau` / `luu_quota_thau` / `delete_dot_thau`. Trigger giữ liên kết quota khi khoá kế hoạch đổi; nhật ký ở `app_sale.quota_chuan_hoa_log` (giữ, không drop).

**Danh mục (`shared`)**
- `dm_ps` — nguồn chuẩn PS/miền/team: `ps`, `ten_ps` (tên đầy đủ trên hoá đơn), `bu_code` (khớp `sale_target.bu`), `area`, `team`, `trang_thai`.
- `dm_dia_ban` — địa bàn có hiệu lực (§6.4); RPC `upsert_dm_dia_ban`, `chuyen_dia_ban`, `delete_dm_dia_ban`, `dep_dia_ban_chong_lan`, `apply_dia_ban_to_plan`, `dia_ban_hieu_luc`.
- `dm_vat_tu` (có `ma_san_pham`, `ma_chung`, `don_gia_thau_moi`), `dm_bo_vat_tu`, `dm_bo_vat_tu_mapping` (bộ → linh kiện, định mức), `dm_khach_hang` (`customer_id`, `customer_name`), `dm_nhom_san_pham`.
- `users` — tài khoản dùng chung nhiều app (§5.1); `app_config` — `current_month`, `deadline_day`, `sale_target_epoch`, `gan_quota_hop_dong_lan_cuoi`.

**Hoá đơn & thực hiện (`app_sale`)**
- `hoa_don_bovattu` (thô), `hoa_don_bovattu_hieu_luc` (view, trừ loại trừ), `hoa_don_loai_tru`.
- `chia_ps_pham_vi`, `phieu_su_dung`, `chia_ps_so_tien`, `chia_ps_ty_le_tam`, `v_chia_ps`, `hoa_don_bovattu_chia`, `hoa_don_actual`.
- `sync_job` — job đồng bộ thực hiện.

**Lưu vết (`app_sale`)**
- `audit_log` — nhật ký sửa; đọc qua `audit_log_xem` và các RPC `audit_*`.
- `giai_trinh` — log append-only theo PS × KH × nhóm SP × tháng.
- `ke_hoach_chot_ky`, `ke_hoach_chot`, `ke_hoach_chot_dieu_chinh` — bản chụp kế hoạch (~18 MB/kỳ).
- `sale_target_tombstone`, `login_attempts`.

**Quota ↔ hợp đồng**
- `app_contract.contract_contracts`, `contract_items`, `contract_items_remaining_view` — app hợp đồng nạp; không có `updated_at`.
- `app_sale.quota_hop_dong` (liên kết `tu_dong`/`tay`), `khoa_sp_alias`, `v_khoa_so_sanh_sp`, `v_hop_dong_dong`, `v_quota_lien_ket_hop_dong`, `v_quota_hop_dong_mo_coi`; hàm `quota_theo_khoa`, `hop_dong_theo_khoa`, `gan_quota_hop_dong_tu_dong`, `chay_gan_quota_hop_dong`, `chuyen_quota_theo_hop_dong`.
- `app_sale.kiem_tra_thau_xu_ly`, `kiem_tra_thau_snapshot` — trạng thái việc tab Kiểm tra thông tin thầu.

### 7.2 Quota thầu — quy tắc
- Khoá quota: **KH × SP (theo mã) × PS × mức giá**. Nhóm SP, bộ vật tư chỉ là thuộc tính. Mã thiếu/"Chưa có" thì theo tên.
- Loại: **Quota 1.4** (thầu cũ, ký trước 1/4), **thầu chính**, **thầu bổ sung**.
- Hết hạn đợt (tháng cuối còn bán) = tháng thầu + 3 + hiệu lực − 1 (vd 2026-03, 24 tháng → 2028-05).
- Trạng thái đợt so với tháng hiện tại: **On hand** (đã tới tháng thầu và còn hiệu lực, hoặc hết hạn trong FY đang xem); **Upcoming** (chưa tới tháng thầu, hoặc thiếu tháng/hiệu lực); **Hết HL** (hết trước đầu FY — không vào on hand, không vào tổng).

### 7.3 Chỉ số & công thức

| Chỉ số | Công thức |
|---|---|
| TH YTD | Σ thực hiện các tháng ≤ tháng hiện tại (`isYtdMonth(mo)` = `mo <= CURRENT_MONTH`) |
| KH còn lại | Σ SL KH update từ tháng sau tháng hiện tại |
| DThu dự kiến | Thực hiện các tháng đã qua (`dtAct`) + max(thực hiện, KH update × đơn giá) tháng hiện tại + KH update × đơn giá các tháng sau (`duKienThang`) |
| Tổng quota | On hand + Upcoming |
| Khả dụng | On hand − TH YTD; BV tư âm tính là 0 ở mọi cấp |
| Quota định mức | Quota 1.4 (100%) + quota chính/BS × số tháng hiệu lực rơi vào FY / hiệu lực |
| KD định mức | Quota định mức − TH YTD |
| CL tốc độ | Tốc độ cần cho các tháng còn lại so với tốc độ TH YTD |
| % Chênh lệch | Kế hoạch update so với kế hoạch đầu năm |

Mốc "tháng đã đóng" (`mo < CURRENT_MONTH`) vẫn quyết định tháng nào lấy thực hiện làm số chốt cho DThu update; tháng hiện tại vẫn sửa `revUpd` được (trừ khi đã qua hạn chót).

**Đánh giá dự kiến** (cột admin, `src/lib/danhGia.js`) — xét từng nhóm PS × KH × nhóm SP theo 2 trục:

| | Dự kiến < 90% target | Dự kiến ≥ 90% target |
|---|---|---|
| **> 110% quota định mức** | Thiếu quota | Vượt quota |
| **90–110% quota định mức** | Target > quota | Phù hợp |
| **< 90% quota định mức** | Dưới năng lực | Còn dư địa |

Cờ phụ: dồn cuối năm (tốc độ cần > 1,3 × tốc độ TH YTD); độ tin cậy thấp (Quota 1.4 > 50% quota định mức). BV tư không đánh giá. Ngưỡng màu chưa chốt.

---

## 8. Quy tắc nghiệp vụ (Business Rules)

1. **Một sản phẩm có thể có nhiều dòng** nếu đơn giá khác nhau; không dedup.
2. **Thực hiện khớp theo PS**: một KH có thể do nhiều PS phụ trách; hoá đơn xuất theo lô đứng tên 1 PS được chia lại theo phiếu SV / số tiền / tỷ lệ tạm (§5.3).
3. **Năm tài chính**: tháng 04 năm nay → tháng 03 năm sau. App chỉ tải 12 tháng FY đang chạy (`PLAN_MONTHS`).
4. **Chỉ cột trong `EDITABLE` / `MANAGER_EDITABLE` / `ADMIN_EDITABLE`** được sửa qua `updateCells`; RPC `update_sale_target_cells` từ chối mọi cột khác, kể cả cột quota.
5. **Khoá sau hạn chót** cho non-admin (§4.2).
6. **Sản phẩm mới** gắn `bu` của người tạo, SL đầu năm = 0, SL thực hiện = 0.
7. **Phạm vi quyền khoá phía server**; quyền đọc lại từ `shared.users` mỗi request.
8. **Địa bàn**: không tự đổi kế hoạch — phải chủ động "Áp"; mỗi bản chỉ ghi vào tháng trong khoảng hiệu lực; đổi PS giữa năm = đóng bản cũ + mở bản mới; không được có khoảng trống.
9. **Quota chỉ ở `quota_thau`/`dot_thau`**; bắt buộc tháng thầu + hiệu lực; quota > 0 không vào đợt thiếu thông tin.
10. **Đơn giá CTTM FY26** = `dm_vat_tu.don_gia_thau_moi` (giữ VAT).
11. **Đổi tên SP theo danh mục**: trigger hoá đơn lấy SP theo `dm_vat_tu` (`ma_bravo` + nhóm); kế hoạch THNS & CSVT đã ánh xạ sang danh mục mới (28/10).
12. **Admin sửa giá không tính vào chênh** giữa các bản chụp (§6.10).
13. **Team TEST (`bu = 'test'`)** chỉ hiện khi xem đúng team đó; mọi truy vấn nhiều team loại nó ra bằng `or(bu.is.null,bu.neq.test)`.

---

## 9. Yêu cầu phi chức năng (Non-functional Requirements)

### 9.1 Bảo mật
- Token HMAC-SHA256 sống 2 giờ, phiên tối đa 24 giờ; server verify chữ ký + `exp` trước mọi action.
- Khoá đăng nhập theo user × IP / user / IP (§5.1).
- Mật khẩu: `password_hash` SHA-256 (có salt nếu có) là gốc, `password_bcrypt` là cache.
- **RLS** bật trên mọi bảng; mọi truy cập dữ liệu qua Edge Function dùng service role. 07/11/2026 đã thu hồi quyền anon trên `hoa_don_bovattu_chia` và `giai_trinh`. Sau mỗi migration chạy `supabase/checks/kiem_quyen_anon.sql` (kết quả phải rỗng).
- DROP + CREATE một RPC phải REVOKE/GRANT lại, nếu không anon gọi được.
- Repo để public.

### 9.2 Hiệu năng
- Đọc theo phạm vi quyền, chỉ 12 tháng FY, phân trang 1000 dòng, tải song song 6 trang.
- Delta sync (`getChanges`) thay vì tải lại toàn bộ.
- Index biểu thức cho khoá khớp thực hiện (`idx_sale_target_mapkey_ws`), index tra dòng kế hoạch cho phân loại OOP.
- Đồng bộ thực hiện chạy nền (`start_sync_job`, trung bình ~51 s, `statement_timeout` 5 phút).

### 9.3 Khả dụng & UX
- Tiếng Việt, phong cách bảng tính, highlight tháng hiện tại, ngưỡng màu 90%.
- Màn boot có spinner + báo lỗi rõ; `ErrorBoundary` + Sentry (cần `VITE_SENTRY_DSN`).

### 9.4 Chất lượng mã
- ESLint, Prettier, Vitest (`src/lib/*.test.js`, `supabase/functions/**/*.test.ts`).

---

## 10. Kiến trúc & Triển khai (Architecture & Deployment)

```
[Browser: React (Vite build) trên GitHub Pages /sale-target/]
        │  POST { action, token, payload }
        ▼
[Edge Function: sale_target-login]  ← xác thực mật khẩu, khoá đăng nhập, phát token
[Edge Function: sale_target-api]    ← verify token, áp phạm vi quyền, gọi RPC (service role)
        ▼
[Postgres]
  shared       : sale_target, dot_thau, quota_thau, dm_*, users, app_config
  app_sale     : hoa_don_*, chia_ps_*, audit_log, giai_trinh, ke_hoach_chot*,
                 quota_hop_dong, kiem_tra_thau_*, sync_job
  app_contract : contract_contracts, contract_items (app hợp đồng nạp)
  pg_cron      : chot-ke-hoach-thang 23:59 · gan-quota-hop-dong 01:30 · kiem-tra-thau-don-xong 02:20 (giờ VN)
Nguồn ngoài   : script Python ngoài repo nạp hoá đơn, phiếu SV, số tiền chia PS
```

### 10.1 Điểm triển khai quan trọng
- **Frontend** (`src/`, `index.html`, Vite): deploy tự động qua GitHub Pages khi push `main`.
- **Edge Functions**: **deploy tay riêng** (`supabase functions deploy <tên> --no-verify-jwt`); cần secret `SESSION_SECRET` giống nhau cho cả login & api.
- **Migration**: `supabase db push`. Áp bằng cách khác (`db query`, SQL Editor) thì phải `supabase migration repair --status applied <version> --linked` ngay. Script hoàn tác ở `supabase/rollbacks/`, **không** để trong `supabase/migrations/`.
- **Thứ tự** khi đổi giao thức đồng bộ: frontend trước, rồi edge + migration.

---

## 11. Chỉ số thành công (Success Metrics / KPIs)

| Nhóm | Chỉ số |
|---|---|
| **Áp dụng** | % PS cập nhật kế hoạch trước hạn chót mỗi tháng (thống kê ở Lịch sử cập nhật) |
| **Chất lượng dữ liệu** | Số việc còn mở ở 3 bước Kiểm tra thông tin thầu; % quota on hand đã liên kết hợp đồng; giá trị ngoài kế hoạch |
| **Hiệu năng** | Thời gian tải lần đầu; thời gian đồng bộ thực hiện |
| **Tin cậy** | Số lỗi 401/500 từ Edge Function; lỗi Sentry |
| **Kinh doanh** | DThu dự kiến / Target; phân bố nhãn Đánh giá dự kiến |

*(Ngưỡng cụ thể cần chốt với chủ sở hữu sản phẩm.)*

---

## 12. Rủi ro, Giả định & Hướng phát triển

### 12.1 Rủi ro
- **Lịch sử migration lệch DB:** một số migration 09/11–19/11 áp bằng `db query` chưa `migration repair`; chạy `db push` trước khi đồng bộ sẽ chạy lại chúng.
- **Dữ liệu hợp đồng chưa đủ:** chỉ ~24% dòng HĐ map được mã SP; Medtronic DHM/DMĐ không có HĐ. Đối chiếu quota ↔ HĐ có thể báo lệch giả.
- **CORS `*`** + `--no-verify-jwt`: an toàn dựa hoàn toàn vào token HMAC; cần bảo vệ `SESSION_SECRET`.
- **FY hard-code:** `PLAN_MONTHS` còn viết cứng FY26; phải đổi trước FY27.

### 12.2 Giả định
- Hoá đơn, phiếu SV, số tiền chia được nạp đúng và đủ bởi script ngoài repo; admin chạy đồng bộ sau mỗi lần nạp.
- `dm_ps` phủ mọi `ten_ps` trên hoá đơn.
- Danh mục khách hàng/sản phẩm được quản trị ngoài UI.

### 12.3 Hướng phát triển
- Liên kết quota ↔ HĐ: P4 (số báo giá cho upcoming), P5 (on hand theo liên kết); duyệt R3 (chính → 1.4).
- Năm tài chính động, sẵn sàng FY27 (hạn 01/2027).
- Chốt ngưỡng màu cột Đánh giá; cân nhắc so "KH thuần" ở So sánh KH update.
- Quy trình phê duyệt kế hoạch.

---

## 13. Phụ lục — Thuật ngữ & Danh sách action

### 13.1 Thuật ngữ
- **PS**: người phụ trách (sales phụ trách khách hàng).
- **bu**: business unit / Team.
- **Quota 1.4**: quota thầu cũ, hợp đồng ký trước 1/4 của FY.
- **On hand / Upcoming**: quota đợt đã tới / chưa tới tháng thầu.
- **Quota định mức**: phần quota dùng được trong FY (§7.3).
- **YTD**: luỹ kế từ đầu năm tới tháng hiện tại.
- **OOP**: thực hiện ngoài kế hoạch.
- **BV tư**: bệnh viện tư — không cần thầu, khả dụng âm tính là 0, không đánh giá.

### 13.2 Thứ tự field khi trả `getData`
`fy, mo, region, ps, cust, custId, grp, prod, mset, rev, revUpd, price, act, dtAct, dt, bu, oop`

### 13.3 Danh sách action API (`sale_target-api`)
- **Chung:** `ping` · `refreshToken` · `getData` · `getRev` · `getChanges` · `getCatalog` · `getCustomers` · `getPs` · `getAppConfig`
- **Kế hoạch:** `updateCells` · `addProduct` · `addProducts` · `ensureMonthRow` · `deleteProduct` · `deleteCustomer` · `getGiaiTrinh` · `getGiaiTrinhThang` · `saveGiaiTrinh`
- **Quota:** `getQuotaThau` · `saveDotThau` · `deleteDotThau` · `saveQuotaThau` · `exportQuotaThau` · `ganQuotaHopDong` · `getQuotaChoDuyet` · `duyetQuotaThau` · `duyetDotThau` (3 action cuối không còn dùng)
- **Kiểm tra thông tin thầu:** `ktGetTrangThai` · `ktCapNhatXuLy` · `ktLuuSnapshot` · `ktDoiChieuHopDong` · `ktGoiYDot` · `ktHopDongTheoSanPham` · `ktChiTietKhoa` · `ktGanTay` · `ktBoGanTay` · `ktThemAlias` · `ktChuyenTheoHd`
- **Địa bàn & PS:** `getDiaBan` · `saveDiaBan` · `chuyenDiaBan` · `dopChongLan` · `deleteDiaBan` · `savePs`
- **Thực hiện & hoá đơn:** `getOop` · `syncThucHien` · `syncJobStatus` · `suaPsHoaDon` · `suaPsHoaDonBulk` · `getHoaDonLoaiTru` · `timHoaDon` · `luuHoaDonLoaiTru` · `xoaHoaDonLoaiTru`
- **Bản chụp:** `getChotKy` · `chotKeHoach` · `xoaChotKy` · `soSanhChot`
- **Lịch sử:** `getAuditNhom` · `getAuditChiTiet` · `getAuditDeadline` · `getLichSuSanPham` · `getAuditLog` (giữ cho frontend cũ)
- **Cấu hình:** `setAppConfig`

---
