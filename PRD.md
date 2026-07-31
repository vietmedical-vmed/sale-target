# PRD — Sale Target (Kế hoạch kinh doanh)


| Phiên bản tài liệu | Nội dung | Ngày | Thực hiện bởi |
|---|---|---|---|
| 1.0 | Khởi tạo tài liệu | 2026-06-20 | Đỗ Hoàng Giang |

---

## 1. Tổng quan (Overview)

**Sale Target** là ứng dụng web một trang (single-page app) giúp đội ngũ kinh doanh **lập, theo dõi và cập nhật kế hoạch bán hàng** theo từng tháng, phân rã theo Team → Miền → Phụ trách (PS) → Khách hàng → Bộ vật tư → Sản phẩm.

Ứng dụng cho phép:
- Nhập/sửa số lượng kế hoạch & thực hiện trực tiếp trên bảng theo 12 tháng của năm tài chính.
- Đối chiếu kế hoạch với quota thầu, thực hiện lũy kế (YTD) và quota khả dụng còn lại.
- Xem 3 góc nhìn tổng hợp và xuất Excel giữ nguyên cấu trúc phân cấp.
- Phân quyền dữ liệu chặt chẽ theo vai trò và phạm vi.

**Phạm vi:** Web app quản lý & theo dõi kế hoạch bán hàng năm tài chính.

**Product Owner:** Đỗ Hoàng Giang

---

## 2. Bối cảnh & Vấn đề (Background & Problem)

### 2.1 Hiện trạng trước đây
- Kế hoạch bán hàng trước đây chạy trên nhiều file Excel của từng PS.
- Dữ liệu phân tán, khó phân quyền theo vai trò, khó tổng hợp nhiều chiều, hiệu năng kém khi dữ liệu lớn.

### 2.2 Vấn đề cần giải quyết
1. **Một nguồn tin cậy (single source of truth):** nhiều cấp (admin, quản lý team, quản lý ngành hàng, quản lý miền, PS) cần cùng nhìn một bộ số nhất quán.
2. **Phân quyền dữ liệu:** mỗi vai trò chỉ được xem/sửa đúng phạm vi của mình.
3. **Cập nhật realtime & đồng bộ:** nhiều người sửa đồng thời, cần phát hiện thay đổi và làm mới.
4. **Tổng hợp đa chiều:** theo PS và theo Sản phẩm, kèm chỉ số quota & doanh thu.
5. **Hiệu năng ở quy mô ~20.000 dòng:** tải nhanh, sửa mượt.

### 2.3 Giải pháp đã chọn
Lựa chọn **Supabase** (Postgres + Edge Functions) làm backend, frontend tĩnh (React qua CDN) host trên **GitHub Pages**. Toàn bộ nghiệp vụ đi qua một Edge Function API duy nhất với token có chữ ký HMAC.

---

## 3. Mục tiêu & Phi mục tiêu (Goals / Non-goals)

### 3.1 Mục tiêu
| # | Mục tiêu | Loại |
|---|---|---|
| G1 | Cho phép PS/Admin sửa kế hoạch & thực hiện theo tháng ngay trên bảng | Sản phẩm |
| G2 | Phân quyền dữ liệu theo 5 vai trò × phạm vi (team/miền/PS/ngành hàng) | Sản phẩm |
| G3 | Cung cấp 4 màn hình: Chi tiết + 2 màn tổng hợp + Cấu hình địa bàn | Sản phẩm |
| G4 | Xuất Excel giữ cấu trúc phân cấp (gộp/mở, header gộp) | Sản phẩm |
| G5 | Tải & thao tác mượt ở quy mô ~20k dòng | Kỹ thuật |
| G6 | Giúp quản lý bám sát quota khả dụng còn lại và chênh lệch kế hoạch | Kinh doanh |

### 3.2 Phi mục tiêu (Non-goals)
- Không phải hệ CRM/quản lý cơ hội bán hàng; không quản lý đơn hàng/hợp đồng chi tiết.
- Không tự động tính hoa hồng/lương thưởng.
- Không có quy trình phê duyệt (approval workflow) nhiều bước ở phiên bản hiện tại.
- Không import dữ liệu thực hiện bằng tay qua UI (việc đẩy `sl_thuc_hien` do pipeline ngoài đảm nhiệm — xem §8).
- Không hỗ trợ đa ngôn ngữ (chỉ tiếng Việt).

---

## 4. Đối tượng người dùng & Phân quyền (Personas & Roles)

### 4.1 Khái niệm Team (bu / business unit)
Mỗi bản ghi kế hoạch gắn với một **Team** (`bu`). Các team hiện có: **CHCS, CTTM, THNK** (và TEST cho kiểm thử/training).

**Team TEST tách biệt hoàn toàn về số liệu** (§8.10): dữ liệu demo không bao giờ được
cộng chung với team thật.

### 4.2 Năm vai trò & phạm vi

| Vai trò | Phạm vi dữ liệu | Quyền sửa | Chuyển team |
|---|---|---|---|
| **admin** | Tất cả team | ✅ Sửa & thêm SP | ✅ |
| **manager** | Tất cả team (hoặc chọn 1 team) | ✅ Sửa & thêm SP (mọi team) | ✅ |
| **product_manager** | Theo **ngành hàng** (`nhom_san_pham`), xuyên suốt mọi team | ❌ Chỉ xem | — (không khoá theo team) |
| **area_manager** | Theo **Miền** (`mien`) trong team của mình | ✅ Sửa & thêm SP (trong miền của mình) | ❌ |
| **ps** | Theo **PS** (chính mình) trong team của mình | ✅ Sửa & thêm SP | ❌ |

**Quy tắc quan trọng:**
- **Sửa số liệu** (`canEdit`: sửa ô + thêm sản phẩm): **admin, manager, area_manager, ps**. Chỉ `product_manager` là thuần xem — họ theo dõi ngành hàng xuyên team chứ không sở hữu số của PS nào.
- **Phạm vi ghi** bám đúng phạm vi xem của từng role (`scopeParams()` phải khớp `applyScope()`): manager ghi được mọi team, area_manager chỉ trong `bu` + Miền của mình, ps chỉ dòng của chính mình. RPC `update_sale_target_cells` chốt lại ở DB, không tin client.
- **Xoá dòng** (sản phẩm/khách hàng) và **mọi thao tác ghi ở Cấu hình địa bàn** vẫn **chỉ `admin`** — không đi theo `canEdit`.
- **Thêm sản phẩm**: `ps` luôn bị ép về chính mình; admin/manager/area_manager chọn PS trên giao diện (scope của họ không phải tên PS). Server kiểm lại: area_manager chỉ thêm được cho PS thuộc đúng team + miền của mình, và miền của dòng mới lấy theo miền của area_manager chứ không theo client gửi lên.
- Với các vai trò không phải admin/manager, phạm vi **luôn bị khoá theo token phía server** — client không thể ghi đè bằng payload (chống giả mạo).
- `product_manager` có thể phụ trách **nhiều ngành hàng**, ngăn cách bằng dấu phẩy trong `scope`; chưa gán ngành hàng → không thấy dữ liệu.
- **Cấu hình địa bàn** (§6.4): mọi vai trò xem được trong phạm vi của mình, nhưng **chỉ `admin` sửa/xóa/áp dụng** — kể cả `ps` (tự gán địa bàn cho mình là tự mở rộng phạm vi quyền).

### 4.3 Persona tóm tắt
- **Admin (điều phối kế hoạch):** thiết lập & sửa dữ liệu cho toàn bộ team, thêm sản phẩm.
- **Ban giám đốc / Manager:** theo dõi toàn cảnh, so sánh giữa các team.
- **Product Manager:** theo dõi một/nhiều ngành hàng xuyên team.
- **Area Manager:** theo dõi địa bàn phụ trách.
- **PS (nhân viên phụ trách khách hàng):** nhập & cập nhật kế hoạch cho khách hàng của mình.

---

## 5. Luồng nghiệp vụ chính (User Flows)

### 5.1 Đăng nhập / đổi mật khẩu
1. Người dùng nhập `username` + `password`.
2. Edge Function `login` xác thực bằng SHA-256 (khớp hash hệ cũ), phát hành **token ký HMAC** có hạn **8 giờ** (`exp`).
3. Token chứa: `{ u: username, r: role, s: scope, b: bu, exp }`.
4. Đổi mật khẩu: gửi kèm `newPassword` (≥ 6 ký tự, khác mật khẩu cũ) → cập nhật hash, yêu cầu đăng nhập lại (không phát token).

### 5.2 Luồng làm việc chính
```
Đăng nhập → (admin/manager: chọn Team) → Chọn màn hình
   → Lọc (ngành hàng / miền / khách hàng)
   → [PS/Admin] Sửa ô theo tháng / Thêm sản phẩm
   → Xem tổng hợp → Xuất Excel
```

### 5.3 Đồng bộ dữ liệu
- Mỗi lần đọc, server trả `rev` = timestamp bản ghi mới nhất.
- Client có thể gọi `getRev` để phát hiện dữ liệu đã thay đổi và làm mới, tránh ghi đè lẫn nhau.

---

## 6. Yêu cầu chức năng (Functional Requirements)

Ứng dụng có **4 màn hình chính** (tab):

### 6.1 Màn "Chi tiết kế hoạch"
Bảng dạng bảng tính, mỗi dòng = một (Khách hàng × Sản phẩm × đơn giá) với 12 cột tháng.

- **Sửa trực tiếp từng ô**: Ô đang sửa có viền nhấn; ô chưa lưu (pending) tô màu hổ phách.
- Các cột **được phép sửa** (`EDITABLE`): `qOld` (quota thầu cũ còn lại), `mMain`/`dMain`/`qMain` (tháng/thời gian/quota thầu chính), `mAdd`/`qAdd` (tháng/quota thầu bổ sung), `revUpd` (SL kế hoạch update từng tháng), `note` (giải trình), `price` (đơn giá).
- Hiển thị: SL kế hoạch đầu năm, SL update theo tháng, doanh thu, chênh lệch (tô xanh/đỏ theo dấu), quota khả dụng còn lại.
- Tháng hiện tại được highlight.

### 6.2 Màn "Tổng hợp theo PS / Khách hàng"
Cấu trúc phân cấp: **Miền → PS → Khách hàng → Nhóm SP → Sản phẩm**, có thể gập/mở.
- Cột: Số KH, Số SP, Quota/Số lượng (Tổng Quota, Thực hiện YTD, KH còn lại YTD,
  Khả dụng còn lại), Doanh thu (triệu VND), % Chênh lệch, % Thực hiện YTD, Giải trình.
- **KH còn lại YTD** = SL KH update từ tháng SAU tháng hiện tại đến hết năm (§7.2);
  **% Thực hiện YTD** = DThu thực hiện YTD / DThu KH update.
- Dòng tổng (grand total) ở cuối.
- **Ngoài kế hoạch**: xem 6.6.

### 6.3 Màn "Tổng hợp theo Sản phẩm"
Cấu trúc phân cấp: **Sản phẩm → Miền → Khách hàng**, có thể gập/mở.
- Cột: SL KH update theo 12 tháng, Tổng Quota, Thực hiện YTD, KH còn lại YTD, Quota khả dụng còn lại.
- **Ngoài kế hoạch**: xem 6.6.

### 6.4 Màn "Cấu hình địa bàn"
Khai báo **(Khách hàng × Ngành hàng `nhom_san_pham`) → PS phụ trách** trong bảng
`dm_dia_ban` — độ mịn dừng ở ngành hàng, không xuống `bo_vat_tu`.

- **Chỉ `admin` sửa**; các vai trò khác chỉ xem trong phạm vi quyền của mình
  (gán địa bàn là quyết định quản lý; để `ps` tự gán là tự mở rộng phạm vi quyền).
- **Gom nhóm theo khách hàng**: mỗi KH là một dòng tiêu đề gập/mở (mã KH · tên KH ·
  số ngành hàng · số dòng lệch), bên dưới là các ngành hàng của KH đó với cột
  Miền · PS · **Đối chiếu kế hoạch**. Trạng thái đối chiếu tính ở client từ dữ liệu
  kế hoạch đang tải: *Khớp kế hoạch* / *Lệch kế hoạch* (kèm PS mà kế hoạch đang gắn) /
  *Chưa có kế hoạch*.
- **Miền không nhập tay** — là thuộc tính của PS: UI hiển thị miền suy từ PS (chỉ khi
  PS đó thuộc đúng 1 miền trong kế hoạch), và server tự suy lại khi lưu (`mienForPs`),
  không tin `mien` do client gửi. Không suy được (PS chưa có dòng kế hoạch, hoặc đang
  ở nhiều miền) → giữ nguyên miền đang lưu; miền rỗng thì "Áp dụng" không sửa miền của
  dòng kế hoạch (`coalesce(c.mien, s.mien)`).
- **Thời gian hiệu lực (version theo tháng)** — mỗi khai báo mang khoảng
  `[tu_thang, den_thang]` dạng `'YYYY-MM'` (`den_thang` NULL = còn hiệu lực), so sánh
  chuỗi = so sánh thời gian, khớp thẳng `thang_ke_hoach`:
  - **Đổi người phụ trách giữa năm = "Chuyển PS"** (`chuyen_dia_ban`): đóng bản đang
    chạy ở **tháng liền trước** + mở bản mới từ tháng được chọn, trong **1 giao dịch**.
    Bản cũ và các tháng nó phủ **giữ nguyên vĩnh viễn** dù cấu hình sau đó đổi tiếp.
  - Sửa PS **tại chỗ** = sửa sai cho *cả khoảng hiệu lực của bản đó*, không phải chuyển.
  - Ô **"Xem theo tháng"** (mặc định tháng hiện tại) chọn xem trạng thái địa bàn tại
    thời điểm nào; *Tất cả (cả lịch sử)* hiện mọi version.
  - Khai báo **trước cho tương lai** được: nhập "từ T10 chuyển sang PS B" ngay hôm nay.
  - `dia_ban_hieu_luc(p_thang)` trả trạng thái địa bàn của một tháng — pipeline import
    dùng để suy PS đúng theo tháng của dòng actual.
- **Không được có khoảng trống** (ràng buộc dữ liệu, không phải quy ước): tổ hợp
  (KH × ngành hàng) **đã** khai báo thì mọi tháng đang có dòng kế hoạch phải được một
  bản nào đó phủ. Mọi đường ghi (`upsert_dm_dia_ban`, `chuyen_dia_ban`,
  `delete_dm_dia_ban`) kiểm tra qua `v_dia_ban_khoang_trong` **trong cùng giao dịch** và
  **huỷ cả lô** nếu sinh khoảng trống. Giao diện cảnh báo trước ở 3 chỗ: dải đỏ tổng
  (không phụ thuộc tháng đang xem), badge trên dòng tiêu đề KH, và ngay trong form thêm
  (khoá nút "Thêm địa bàn"); xóa bản sẽ tạo khoảng trống thì bị chặn tại client kèm lý do.
  Tổ hợp **chưa** khai báo gì không tính là khoảng trống — đó là mục "chưa khai báo".
- Mục **"Có kế hoạch nhưng chưa khai báo địa bàn"**: các tổ hợp (KH × ngành hàng) đang
  có dòng kế hoạch mà chưa có khai báo nào. Nút khai báo suy **từng khoảng tháng liên
  tiếp** của mỗi PS trong kế hoạch → dựng lại đúng lịch sử, không sinh khoảng trống,
  không sinh chồng lấn vô cớ.
- **Áp dụng xuống kế hoạch**: ghi PS/Miền vào các dòng `sale_target` khớp (team, KH,
  ngành hàng) **và nằm trong khoảng hiệu lực của chính bản đó** → bản mới không bao giờ
  ghi đè tháng đã qua, nên không còn tham số "áp dụng từ tháng nào" (và không còn cái
  tick "áp dụng cả tháng đã qua"). Bản có **nhiều PS chồng lấn thời gian** trong cùng tổ
  hợp thì bị bỏ qua (không đoán được dòng nào của PS nào) và được báo lại số lượng.
- Panel **"Thêm khách hàng"** ở màn Chi tiết dùng khai báo này để tự điền PS/Miền
  (PS theo địa bàn xếp lên đầu dropdown).
- Một (KH × ngành hàng) **vẫn được phép** có nhiều PS: khoá của `dm_dia_ban` gồm cả
  `ps` và `tu_thang`, đúng quy tắc §8.2 và đúng cách màn Chi tiết tách dòng theo
  (nhóm SP, PS). Hai PS **nối tiếp nhau theo thời gian** là chuyện bình thường; hai PS
  **chồng lấn thời gian** là địa bàn chia đôi — hợp lệ nhưng "Áp dụng" sẽ bỏ qua.

### 6.5 Tính năng ngang (áp dụng nhiều màn)

| Tính năng | Mô tả |
|---|---|
| **Bộ lọc** | Lọc theo Ngành hàng, Miền, Khách hàng (hiển thị theo quyền — ví dụ PS không có bộ lọc miền/KH riêng). |
| **Chuyển team (TeamSwitcher)** | Chỉ admin/manager: chọn 1 team hoặc "Tất cả". |
| **Thêm khách hàng** | Nút trên **thanh bộ lọc** (chỉ màn chi tiết, chỉ role có quyền sửa) → **popup 2 bước**. *Bước 1*: chọn Khách hàng + PS phụ trách. **Không có ô Miền** — miền là thuộc tính của PS nên suy từ PS đã chọn (PS nhiều miền thì lấy theo địa bàn đã khai báo; client không suy được thì để trống, server điền bằng `mienForPs()`). *Bước 2*: thêm luôn **sản phẩm đầu tiên** (dùng lại đúng form thêm SP, thêm được liên tiếp nhiều SP) — mỗi lần bấm là ghi thật xuống DB và KH xuất hiện trong kế hoạch. Nút **Chỉ thêm KH** / **Bỏ qua** giữ đường cũ: tạo thẻ KH tạm ở client, CHƯA vào DB cho tới khi có sản phẩm đầu tiên. Đóng bằng Hủy / X / Esc / bấm ra ngoài. |
| **Thêm sản phẩm** (nút ở thẻ KH) | Mở **popup** (trước đây bung form ngay dưới thẻ). Thêm xong form giữ nguyên nhóm/bộ để thêm tiếp SP khác. |
| **Thêm sản phẩm** (luồng chung) | Chọn Khách hàng (từ `dm_khach_hang`, có ô tìm kiếm gần đúng), Miền, PS, Nhóm SP, Bộ vật tư, Sản phẩm + **đơn giá** (đơn vị tr.VND, ghi DB theo VND) — mặc định điền sẵn **giá đang dùng nhiều nhất cho đúng (nhóm \| bộ vật tư \| sản phẩm) đó trong kế hoạch**, vì danh mục (`dm_bo_vat_tu`, `dm_bo_vat_tu_mapping`) KHÔNG có cột đơn giá; vật tư chưa từng có giá thì để trống và phải nhập tay → sinh **12 dòng** (một dòng/tháng, 04/2026 → 03/2027), gắn `bu` của người tạo. Danh mục không giữ giá nên đơn giá phải nhập. |
| **Ô tìm kiếm** | Tìm gần đúng theo tên KH / mã KH / sản phẩm / bộ vật tư. Dùng ở màn chi tiết **và 2 màn tổng hợp** (dùng chung 1 ô, giữ nguyên chữ khi chuyển tab). |
| **Header dính** | 2 màn tổng hợp: khung bảng cao gần trọn màn hình (`useFitHeight` = `vh − chiều cao thanh tiêu đề dính − 32`) nên chỉ bảng cuộn dọc, `<thead>` `position: sticky` đứng yên khi cuộn. Là `max-height` nên ở layer mặc định bảng ngắn vẫn hiện đủ, không sinh thanh cuộn; bảng dài hơn khung thì kéo trang xuống **một lần** lúc mở màn cho khung nằm ngay dưới thanh tiêu đề. Không đo được chiều cao màn hình (nhúng/snapshot) hoặc màn thấp < 400px → bỏ giới hạn chiều cao, bảng hiển thị như cũ. |
| **Xuất Excel (nút)** | Nút nằm trên **thanh bộ lọc**, không nằm trong vùng bảng. Màn tổng hợp đang mở đăng ký hàm xuất qua prop `onExport`; đổi tab thì nút tự đổi theo, sang màn chi tiết/địa bàn thì nút ẩn. |
| **Xuất Excel** | Xuất giữ nguyên cấu trúc phân cấp (gập/mở), header gộp (merge), dùng thư viện SheetJS (xlsx). |
| **Đồng bộ (rev)** | Phát hiện thay đổi dữ liệu qua `rev`/`getRev`. |
| **Đổi mật khẩu** | Ngay tại màn đăng nhập. |

---

### 6.6 Phần "Ngoài kế hoạch" (2 màn tổng hợp)
Các dòng thực hiện không khớp dòng kế hoạch nào (`v_actual_ngoai_ke_hoach`, trả về
riêng qua `oopRows`, đánh dấu `_oop` ở client — **không** trộn vào màn chi tiết).
- Ở cấp Khách hàng, tất cả gom vào **một dòng "Ngoài kế hoạch"** (badge *Ngoài KH*).
- Mở dòng đó ra là **từng khách hàng thật** ghi trong dữ liệu thực hiện (mã KH + tên đã
  chuẩn hoá như dòng kế hoạch); ở màn theo PS, dưới mỗi KH mới tới Nhóm SP → Sản phẩm.
- Cột "Số KH" của dòng "Ngoài kế hoạch" = số KH thật bên dưới; không cộng vào Số KH
  của PS/Miền (nhóm này luôn tính là 1 khách hàng).
- Không có quota → **Khả dụng còn lại = "—"** ở mọi cấp trong nhóm này.

---

## 7. Mô hình dữ liệu (Data Model)

### 7.1 Bảng chính

**`sale_target`** — bản ghi kế hoạch (một dòng / tháng / SP / KH):

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
| `quota_thau_cu_con_lai` | qOld | Quota thầu cũ còn lại |
| `thang_thau_chinh` / `thoi_gian_thau_chinh` / `quota_thau_chinh` | mMain/dMain/qMain | Thầu chính |
| `thang_thau_bo_sung` / `quota_bo_sung` | mAdd/qAdd | Thầu bổ sung |
| `sl_ke_hoach_dau_nam` | rev* | SL kế hoạch đầu năm |
| `sl_ke_hoach_update` | revUpd | SL kế hoạch update |
| `don_gia` | price | Đơn giá |
| `doanh_thu_kh_dau_nam` | dt | Doanh thu KH đầu năm |
| `sl_thuc_hien` | act | SL thực hiện (đẩy từ pipeline ngoài) |
| `giai_trinh` | note | Giải trình |
| `bu` | — | Team (business unit) |
| `updated_at` | — | Mốc cập nhật (nguồn của `rev`) |

**`dm_bo_vat_tu_mapping`** — nguồn danh mục cho form thêm SP (`getCatalog`): `bu`, `nhom_san_pham`, `bo_vat_tu`, `san_pham`, `san_pham_thay_the`, `so_luong_dinh_muc`. Dropdown chỉ dùng 3 trường `nhom_san_pham`/`bo_vat_tu`/`san_pham` và **gom trùng** (1 sản phẩm có nhiều dòng mapping khác nhau ở `bu`/`san_pham_thay_the`/`so_luong_dinh_muc`).

**`dm_bo_vat_tu`** (tên cũ `catalog`, đổi 30/07/2026) — `nhom_san_pham`, `bo_vat_tu`, `updated_at`. **Không dùng cho form thêm SP**: bảng này không có cột `san_pham`.

Không bảng danh mục nào có `don_gia` — đơn giá chỉ tồn tại trên từng dòng `sale_target`, người dùng nhập tay khi thêm sản phẩm.

**`dm_khach_hang`** — danh mục khách hàng đầy đủ: `customer_id`, `customer_name` (RLS chặn anon; không chứa PS/Miền).

**`dm_dia_ban`** — cấu hình địa bàn **có thời gian hiệu lực**: `bu`, `ma_khach_hang`,
`khach_hang`, `nhom_san_pham`, `mien`, `ps`, `tu_thang`, `den_thang` (NULL = còn hiệu lực),
`active`, `cust_key` (cột sinh tự động = mã KH, rỗng thì rơi về tên KH — dùng để đối chiếu
với `sale_target`). Unique theo (`bu`, `cust_key`, `nhom_san_pham`, `ps`, `tu_thang`).
RPC: `upsert_dm_dia_ban` (ghi lô), `chuyen_dia_ban` (đóng bản cũ + mở bản mới),
`delete_dm_dia_ban` (xóa có kiểm khoảng trống), `apply_dia_ban_to_plan` (đẩy xuống kế
hoạch theo đúng khoảng hiệu lực), `dia_ban_hieu_luc(thang)` (trạng thái tại 1 tháng).
View `v_dia_ban_khoang_trong` — tháng có kế hoạch mà không bản nào phủ (dùng để chặn ghi).

**`users`** — tài khoản: `username`, `password_hash` (SHA-256), `role`, `scope`, `bu`.

### 7.2 Chỉ số & công thức
- **Thực hiện YTD** = tổng `sl_thuc_hien` luỹ kế **đến hết tháng hiện tại** (mốc dùng
  chung: `isYtdMonth(mo)` = `mo <= CURRENT_MONTH`, áp dụng cho cả màn chi tiết và 2 màn
  tổng hợp). Trước đây chỉ tính các tháng đã đóng, nên phát sinh của chính tháng hiện tại
  — nhất là phần **ngoài kế hoạch** vốn không có số kế hoạch nào khác — không hiện ở đâu.
- **KH còn lại YTD** = tổng SL kế hoạch update **từ tháng SAU tháng hiện tại** trở đi
  (`sumFromNow`); tháng hiện tại đã tính theo thực hiện nên không đếm hai lần.
- Mốc này **khác** mốc "tháng đã đóng" (`mo < CURRENT_MONTH`) — mốc đó vẫn quyết định
  tháng nào bị khoá sửa và tháng nào lấy thực hiện làm số chốt cho **DThu update**.
  Tháng hiện tại vẫn sửa được `revUpd` và số đó vẫn vào DThu update / % Chênh lệch.
- **Tổng Quota** = quota thầu cũ còn lại + quota thầu chính + quota bổ sung (theo cấp tổng hợp).
- **Quota khả dụng còn lại** = Tổng Quota − (Thực hiện YTD + KH còn lại YTD).
- **Doanh thu** = SL × đơn giá (đầu năm vs update) → **chênh lệch doanh thu** (tô xanh nếu dương, đỏ nếu âm).
- **% Chênh lệch**: so sánh kế hoạch update với kế hoạch đầu năm.

---

## 8. Quy tắc nghiệp vụ (Business Rules)

1. **Một sản phẩm có thể có nhiều dòng** nếu **đơn giá khác nhau** giữa các khách hàng.
2. **Đẩy `sl_thuc_hien` khớp theo PS**: một khách hàng có thể do nhiều PS phụ trách; import thực hiện phải khớp đúng PS tương ứng (qua pipeline ngoài).
3. **Năm tài chính**: 12 tháng từ **Tháng 04 năm nay → Tháng 03 năm sau**.
4. **Chỉ các cột `EDITABLE`** được sửa qua `updateCells`; mọi cột khác bị bỏ qua ở server (kể cả nếu client gửi lên).
5. **Sản phẩm mới** luôn gắn `bu` của người tạo (kể cả admin), khởi tạo `sl_ke_hoach_dau_nam = 0`, `sl_thuc_hien = 0`.
6. **Phạm vi quyền khoá phía server**: role không phải admin/manager không thể mở rộng phạm vi bằng payload.
7. **Cấu hình địa bàn chỉ `admin` ghi**; khai báo địa bàn **không tự đổi** dữ liệu kế hoạch — phải chủ động "Áp dụng", và mỗi bản chỉ ghi vào **các tháng nằm trong khoảng hiệu lực của nó** nên tháng đã qua không bị bản mới ghi đè (giữ khớp actual — §8.2).
8. **Đổi người phụ trách giữa năm = đóng bản cũ + mở bản mới** (không sửa bản cũ): quá khứ giữ nguyên PS của nó, vĩnh viễn.
9. **Không có khoảng trống**: tổ hợp (KH × ngành hàng) đã khai báo thì mọi tháng đang có dòng kế hoạch phải có người phụ trách — mọi đường ghi bị chặn nếu vi phạm.
10. **Team TEST (`bu = 'test'`) là dữ liệu demo/training, tách biệt về hiển thị**: chỉ hiện khi nhìn đúng team đó — admin/manager chọn TEST trên TeamSwitcher, hoặc user có `bu = 'test'` trong token. Mọi truy vấn "xem nhiều team" đều loại nó ra (`excludeDemo()` trong `applyScope`), gồm cả "Tất cả team" của admin/manager và phạm vi xuyên team của `product_manager`. Lọc bằng `or(bu.is.null,bu.neq.test)` chứ không dùng `neq` trần, vì `neq` loại luôn dòng `bu` null (null <> 'test' ra null).

---

## 9. Yêu cầu phi chức năng (Non-functional Requirements)

### 9.1 Bảo mật
- Token phiên có **chữ ký HMAC-SHA256**; hết hạn sau 8 giờ; server verify chữ ký + `exp` trước mọi action.
- Mật khẩu lưu dạng **SHA-256**. *Ghi chú rủi ro: SHA-256 không salt — xem §12.*
- **RLS** bật trên mọi bảng; anon không đọc trực tiếp được `dm_khach_hang`. Mọi truy cập dữ liệu đi qua Edge Function dùng service role.
- CORS mở cho web app; API dùng `--no-verify-jwt` (tự xác thực bằng token nội bộ).

### 9.2 Hiệu năng
- Đọc toàn bộ dữ liệu theo phạm vi quyền, **phân trang 1000 dòng/lần** (giới hạn PostgREST), **tải song song 6 trang** để giảm thời gian chờ ở ~20k dòng (~21 trang).
- Đếm tổng số dòng trước (`head:true`) rồi tải trang song song, sắp xếp theo `id` để phân trang ổn định.
- Có index hiệu năng (migration `perf_indexes`).

### 9.3 Khả dụng & UX
- Giao diện tiếng Việt, phong cách bảng tính quen thuộc, highlight tháng hiện tại, màu sắc trực quan cho chênh lệch.
- Màn hình boot có spinner + báo lỗi rõ ràng.

### 9.4 Tương thích
- Frontend chỉ cần trình duyệt hiện đại; không cần cài đặt (React/Tailwind/xlsx nạp qua CDN).

---

## 10. Kiến trúc & Triển khai (Architecture & Deployment)

```
[Browser: index.html (React CDN + Tailwind + SheetJS)]
        │  POST { action, token, payload }
        ▼
[Supabase Edge Function: sale_target-api]  ← xác thực token HMAC, áp phạm vi quyền
[Supabase Edge Function: sale_target-login] ← xác thực mật khẩu, phát token
        │  service role
        ▼
[Postgres: sale_target, dm_bo_vat_tu, dm_khach_hang, dm_dia_ban, users]  (RLS bật)
```

### 10.1 Điểm triển khai quan trọng
- **Frontend**: `index.html` deploy tự động qua **GitHub Pages** (GitHub Actions).
- **Edge Functions**: **phải deploy tay riêng** (`supabase functions deploy ... --no-verify-jwt`); **không** đi theo pipeline Pages. Cần secret `SESSION_SECRET` giống nhau cho cả login & api.
- **Endpoint API duy nhất** xử lý mọi action: `ping`, `getData`, `getRev`, `getCatalog`, `getCustomers`, `updateCells`, `addProduct`, `deleteProduct`, `deleteCustomer`, `getDiaBan`, `saveDiaBan`, `chuyenDiaBan`, `deleteDiaBan`, `applyDiaBan`.
- **Migration mới phải `supabase db push`** (hoặc dán vào SQL Editor) — bảng/RPC mới không tự lộ qua Data API (`auto_expose_new_tables` tắt) nên migration tự `GRANT` cho `service_role`.

---

## 11. Chỉ số thành công (Success Metrics / KPIs)

| Nhóm | Chỉ số |
|---|---|
| **Áp dụng** | % PS đăng nhập & cập nhật kế hoạch hàng tháng; số bản ghi được sửa/tháng |
| **Chất lượng dữ liệu** | Tỷ lệ dòng có giải trình khi chênh lệch lớn; số lần dữ liệu lệch được phát hiện qua `rev` |
| **Hiệu năng** | Thời gian tải màn Chi tiết ở ~20k dòng (< X giây) |
| **Tin cậy** | Số lỗi 401/500 từ Edge Function; uptime |
| **Kinh doanh** | Mức độ bám sát Quota khả dụng còn lại theo thời gian |

*(Ngưỡng cụ thể cần chốt với chủ sở hữu sản phẩm.)*

---

## 12. Rủi ro, Giả định & Hướng phát triển

### 12.1 Rủi ro
- **Mật khẩu SHA-256 không salt** → yếu trước tấn công dò bảng băm. Cân nhắc chuyển bcrypt/argon2.
- **Không có khoá lạc quan (optimistic lock)** ở cấp ô: hai người sửa cùng dòng có thể ghi đè; hiện chỉ giảm nhẹ bằng `rev`.
- **CORS `*`** + API `--no-verify-jwt`: an toàn dựa hoàn toàn vào token HMAC; cần bảo vệ `SESSION_SECRET`.

### 12.2 Giả định
- `sl_thuc_hien` được đẩy đúng, đúng PS, bởi pipeline ngoài.
- Danh mục khách hàng/sản phẩm được quản trị ngoài UI.

### 12.3 Hướng phát triển (Future)
- Ghi log/audit trail cho `updateCells`.
- Quy trình phê duyệt kế hoạch.
- Khoá phiên bản ô (concurrency control) rõ ràng.
- Dashboard biểu đồ trực quan (xu hướng, so sánh team).
- Nâng cấp cơ chế lưu mật khẩu.

---

## 13. Phụ lục — Từ điển thuật ngữ & Ánh xạ field ↔ cột DB

### 13.1 Thuật ngữ
- **PS**: người phụ trách (sales phụ trách khách hàng).
- **bu**: business unit / Team.
- **Quota thầu**: hạn ngạch theo gói thầu (chính, bổ sung, thầu cũ còn lại).
- **YTD**: lũy kế từ đầu năm tới hiện tại.
- **Quota khả dụng còn lại**: phần quota chưa được tiêu bởi thực hiện + kế hoạch còn lại.

### 13.2 Ánh xạ field ↔ cột
Xem bảng đầy đủ ở §7.1. Thứ tự field khi trả `getData`:
`fy, mo, region, ps, cust, custId, grp, prod, mset, qOld, mMain, dMain, qMain, mAdd, qAdd, rev, revUpd, price, note, act, dt`

### 13.3 Danh sách action API
`ping` · `getData` · `getRev` · `getCatalog` · `getCustomers` · `updateCells` · `addProduct` ·
`deleteProduct` · `deleteCustomer` · `getDiaBan` · `saveDiaBan` · `chuyenDiaBan` · `deleteDiaBan` · `applyDiaBan`

---
