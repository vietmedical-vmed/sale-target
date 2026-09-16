# Kế hoạch nâng cấp & tối ưu — Sale Target

| Phiên bản | Nội dung | Ngày | Thực hiện |
|---|---|---|---|
| 1.0 | Khởi tạo: đánh giá hiện trạng, danh sách lỗi/rủi ro, lộ trình nâng cấp, đề xuất tính năng | 2026-09-16 | Claude (soạn), Đỗ Hoàng Giang (duyệt) |

> Số dòng code trong tài liệu (`index.html:6348`…) tính tại commit `aa485ab`. Code đổi thì số dòng lệch, hãy tìm theo tên hàm.

---

## 0. Tóm tắt

App chạy được và nghiệp vụ đã khá đầy đủ. Tuy vậy, nợ kỹ thuật đang tăng nhanh: từ 15/08 tới nay có 93 commit, trong đó 33 commit là `fix`. Riêng thanh cuộn ngang màn Chi tiết mất khoảng 10 commit sửa liên tiếp. Đây là dấu hiệu của việc thiếu môi trường chạy thử, thiếu test và code quá khó sửa an toàn.

**5 vấn đề lớn nhất cần xử lý:**

1. **Giao diện bị "reset" ngoài ý muốn.** Cứ 45 giây app kiểm tra dữ liệu. Chỉ cần *bất kỳ ai, ở bất kỳ team nào* lưu một ô, app của mọi người khác tự tải lại toàn bộ ~20k dòng. Khi tải, cả màn hình bị thay bằng spinner, nên mọi thẻ khách hàng đang mở bị đóng và mất vị trí cuộn.
2. **Năm tài chính bị gắn cứng FY26** ở cả frontend lẫn edge function. Tới tháng 04/2027 (FY27), app không tạo được kế hoạch năm mới.
3. **Frontend là 1 file 398 KB (7.689 dòng)**, dạng code đã biên dịch (`React.createElement`) nhưng lại được sửa tay. Không có build, lint hay test. Mỗi lần sửa dễ gây lỗi dây chuyền.
4. **Một số lỗ hổng phân quyền nhỏ nhưng có thật:** giải trình không kiểm phạm vi; quyền ghi Cấu hình địa bàn lệch với PRD; GitHub Pages đang public cả `schema.sql`, migration và tài liệu nội bộ.
5. **Cơ chế đồng bộ dữ liệu còn thô:** mỗi lần làm mới tải lại toàn bộ dữ liệu; `rev` tính chung cho mọi team; không phát hiện được dòng bị xoá; không có khoá lạc quan (optimistic lock) theo dòng.

**Lộ trình đề xuất:**

| Giai đoạn | Mục tiêu | Thời lượng ước tính (1 dev) |
|---|---|---|
| **GĐ 0 — Chữa cháy** | Sửa các bug & lỗ hổng rõ ràng, không đổi kiến trúc | 1 tuần |
| **GĐ 1 — Nền móng** | Build step, tách module, lint/test, staging, CI/CD cho edge function | 2–3 tuần |
| **GĐ 2 — Hiệu năng & đồng bộ** | Đồng bộ tăng dần, khoá lạc quan, giảm render, chạy nền tác vụ nặng | 2–3 tuần |
| **GĐ 3 — Bảo mật & vận hành** | Mật khẩu, rate-limit, giám sát lỗi, backup | 1–2 tuần (song song GĐ 2) |
| **GĐ 4 — Sẵn sàng FY27** | Đa năm tài chính, sao chép kế hoạch sang năm mới | 1–2 tuần, **phải xong trước 01/2027** |
| **GĐ 5 — Tính năng mới** | Theo danh sách ưu tiên ở §5 | Liên tục |

---

## 1. Hiện trạng (số liệu đo được)

### 1.1 Frontend — `index.html`
- 7.689 dòng, 398 KB, không minify. Toàn bộ JS nằm trong 1 thẻ `<script>` bọc `try`.
- Code ở dạng **đầu ra của Babel** (`/*#__PURE__*/React.createElement(...)`), không có file JSX nguồn.
- Thư viện nạp qua CDN:
  - Tailwind **Play CDN** (`cdn.tailwindcss.com`): biên dịch CSS ngay trong trình duyệt, Tailwind khuyến cáo không dùng cho production.
  - React 18 từ unpkg, **không ghim phiên bản** (`react@18`).
  - SheetJS 0.18.5 và Chart.js 4.4.1 (~200 KB, chỉ dùng cho 1 biểu đồ).
  - Không có SRI (`integrity`).
- `App()` dài ~1.900 dòng (dòng 4902–6817), gồm **45 `useState`** và **17 `useEffect`**.
- Toàn file có 140 `useState`, 51 `useEffect`, 73 `useMemo`, 30 `useCallback`, **0 `React.memo`**.
- 19 chỗ dùng `confirm()`/`alert()`/`prompt()` gốc của trình duyệt.
- Có biến toàn cục bị gán lại **trong lúc render**: `CURRENT_MONTH`, `MASK_MONEY`, `ALIAS_MAP`.

### 1.2 Backend — Supabase
- `sale_target-api/index.ts`: 1.133 dòng, **29 action** trong một chuỗi `if` dài.
- `sale_target-login/index.ts`: 125 dòng.
- 48 file migration. `schema.sql` lệch xa DB thật, không dùng làm nguồn tin cậy.
- Edge function deploy tay. Migration chạy tay (`supabase db push`). Không có môi trường staging.
- GitHub Actions chỉ deploy Pages, và upload **toàn bộ repo** (`path: '.'`).

---

## 2. Danh sách vấn đề phát hiện

Mức độ: **🔴 Cao** (sai số liệu, mất dữ liệu, lỗ hổng quyền) · **🟠 Trung bình** (UX kém, rủi ro vận hành) · **🟢 Thấp**.

### 2.1 Lỗi logic / nghiệp vụ

**B1 🔴 Tự tải lại làm reset giao diện**
- Vị trí: `checkForUpdates` (`index.html:5585`), `loadData` (`index.html:5097`), `if (loading) return …` (`index.html:6348`).
- Hiện tượng: `getRev` thấy `rev` đổi và user không có bản nháp → gọi `loadData()`. Hàm này bật `loading = true`, nên `App` trả về spinner toàn màn hình. Mọi `CustomerCard` bị unmount, trạng thái mở/đóng và vị trí cuộn mất hết.
- Làm nặng thêm: `getRev` (`api/index.ts:210`) lấy `max(updated_at)` của **cả bảng**, không theo phạm vi user. PS team CHCS vẫn bị reload khi team CTTM lưu. Sau mỗi lần "Đồng bộ thực hiện", toàn bộ user bị reload.
- Hướng sửa:
  - Tách `initialLoading` (spinner lần đầu) khỏi `refreshing` (chỉ hiện thanh tiến trình nhỏ, giữ nguyên UI).
  - Đưa trạng thái mở/đóng thẻ KH lên state cấp App, lưu theo mã KH.
  - `getRev` nhận phạm vi (bu/ps/miền) giống `applyScope`.
  - Về lâu dài: đồng bộ tăng dần (xem GĐ 2).

**B2 🔴 `rev` không phát hiện dòng bị xoá**
- Vị trí: `getRev` (`api/index.ts:210`).
- Hiện tượng: xoá dòng không làm `max(updated_at)` thay đổi (trừ khi dòng bị xoá chính là dòng mới nhất). Client khác vẫn giữ dòng đã xoá, sửa tiếp, rồi lưu thì nhận lỗi `forbidden_rows` khó hiểu.
- Hướng sửa: dùng số `rev` tăng dần do trigger cấp cho insert/update, kèm bảng tombstone ghi id bị xoá (GĐ 2).

**B3 🔴 Màn Chi tiết gom khách hàng theo *tên hiển thị*, không theo mã KH → có thể xoá nhầm**
- Vị trí: `tree` (`index.html:5984`: `const cKey = r.cust || '—'`), `deleteCustomer` (`index.html:5657`: `if (r.cust !== customer) return`).
- Hiện tượng: tên hiển thị là alias hoặc tên đã chuẩn hoá (`fmtCust`). Hai KH khác mã nhưng trùng alias/tên chuẩn hoá bị **gộp vào một thẻ**. Thẻ đó lấy `custId` của dòng đầu tiên. Bấm "Xoá khách hàng" sẽ **xoá kế hoạch của cả hai KH**.
- Hướng sửa: gom theo `custId` (không có mã thì mới dùng tên gốc `custRaw`). `deleteCustomer` lọc theo cùng khoá đó. Key React của thẻ bỏ phần `+ i`.

**B4 🔴 Quota thầu ghi 2 nơi, không nguyên tử**
- Vị trí: `saveQuota` / `deleteDot` / `syncQuotaVeSaleTarget` (`index.html:5000–5069`).
- Hiện tượng: client gọi `saveQuotaThau`, rồi `getData` (tải lại **toàn bộ ~20k dòng** chỉ để lấy quota), rồi `updateCells` để ghi đè các cột quota cũ trên `sale_target`. Ba lượt gọi rời nhau. Nếu lỗi mạng hoặc token hết hạn ở giữa, `quota_thau` và cột cũ bị lệch, và 2 màn tổng hợp hiện sai.
- Hướng sửa:
  - Ngắn hạn: thêm action `getQuotaThau` riêng (không gọi `getData`).
  - Đúng: RPC `upsert_quota_thau` tự cập nhật cột cũ **trong cùng transaction** (hoặc dùng trigger).
  - Dài hạn: cho 2 màn tổng hợp đọc từ `quota_thau`, rồi bỏ hẳn các cột quota cũ.

**B5 🔴 Giải trình không kiểm phạm vi quyền**
- Vị trí: `getGiaiTrinh`, `saveGiaiTrinh` (`api/index.ts:1084–1113`).
- Hiện tượng: `getGiaiTrinh` không kiểm role hay phạm vi. `saveGiaiTrinh` chỉ kiểm `canEdit`. PS A gửi `ps = "B"` là đọc hoặc ghi được giải trình của PS B.
- Hướng sửa: `ps` role bị ép `ps = sess.s`. `area_manager` phải kiểm PS thuộc miền của mình. `product_manager` kiểm ngành hàng. Viết thành hàm dùng chung `assertInScope()`.

**B6 🟠 Quyền ghi Cấu hình địa bàn lệch PRD, có action "mồ côi"**
- Vị trí: `saveDiaBan`, `chuyenDiaBan`, `deleteDiaBan`, `applyDiaBan` (`api/index.ts:920, 979, 1019, 1033`). Client: `canEdit: isAdmin || auth.role === 'manager'` (`index.html:6670`).
- Hiện tượng: code cho `manager` ghi, nhưng PRD §4.2 và §8.7 ghi "chỉ admin". Ngoài ra `applyDiaBan` **không truyền `scopeParams`**, không ghi audit log, và client không còn gọi action này.
- Hướng sửa: **chốt quyết định** (xem §7), rồi sửa code hoặc PRD cho khớp. Xoá `applyDiaBan` nếu không dùng.

**B7 🔴 Năm tài chính gắn cứng — hết hạn 04/2027**
- Vị trí: `MONTHS` (`index.html:175`), `MONTHS` + `fy` trong `addProduct` (`api/index.ts:813–816`).
- Hiện tượng:
  - Cả hai phía gắn cứng `2026-04 … 2027-03`.
  - `fy` của sản phẩm mới lấy từ **một dòng bất kỳ** (`select nam_tai_chinh limit 1`, không có `order`).
  - `getData` không lọc theo năm, nên khi có FY27 dữ liệu 2 năm sẽ trộn vào nhau.
- Hướng sửa: xem GĐ 4.

**B8 🟠 Token hết hạn giữa phiên làm mất bản nháp**
- Vị trí: `api()` (`index.html:357`), `drafts` chỉ nằm trong RAM.
- Hiện tượng: token sống 8 giờ. Hết hạn thì `api()` xoá token và báo lỗi. User phải reload để đăng nhập lại, nên **mất toàn bộ ô chưa lưu**.
- Hướng sửa:
  - Lưu `drafts` vào `localStorage`/IndexedDB theo user; khi mở lại app thì hỏi "Khôi phục N thay đổi chưa lưu?".
  - Khi gặp `unauthorized`, hiện modal đăng nhập lại tại chỗ, không reload trang.
  - Cảnh báo trước khi token hết hạn 10 phút.

**B9 🟠 Thêm sản phẩm hàng loạt: tuần tự, dễ tạo trùng**
- Vị trí: `bulkAddProducts` (`index.html:5506`), `addProduct` (`api/index.ts:809`).
- Hiện tượng:
  - Gọi `addProduct` N lần nối tiếp.
  - `useCallback` thiếu `reloadOop` trong deps, nên có thể dùng closure cũ sau khi đổi team.
  - Server không kiểm trùng, và trong migrations chưa thấy ràng buộc unique cho `sale_target`. Bấm 2 lần hoặc mở 2 tab là sinh 24 dòng trùng.
- Hướng sửa:
  - Action `addProducts` nhận mảng và ghi trong 1 transaction.
  - Server chặn trùng theo khoá (fy, tháng, ps, mã KH, nhóm, bộ VT, SP, đơn giá). Lưu ý: cùng SP khác đơn giá là hợp lệ, không được chặn.
  - Nút bấm khoá lại trong lúc đang gửi.

**B10 🟠 Audit log thiếu và bị cắt**
- Hiện tượng:
  - Không ghi log cho `chuyenDiaBan`, `applyDiaBan`, `dopChongLan`, `savePs`, `suaPsHoaDon`, `suaPsHoaDonBulk`.
  - `updateCells` chỉ lưu diff của **50 dòng đầu**.
  - Giá trị cũ đọc *trước* khi gọi RPC, không cùng transaction, nên có thể sai nếu 2 người lưu cùng lúc.
- Hướng sửa: ghi audit **trong** RPC (hoặc bằng trigger trên `sale_target`), đủ mọi dòng. Bổ sung log cho các action còn thiếu.

**B11 🟢 Tìm kiếm màn Chi tiết không bỏ dấu**
- Vị trí: `index.html:5983` dùng `toLowerCase().includes`, trong khi đã có hàm `deaccent`.
- Hiện tượng: gõ "benh vien" không ra "Bệnh viện". Không khớp mô tả "tìm gần đúng" trong PRD.

**B12 🟠 Lỗi bị "nuốt" nên UI hiện trống như mất dữ liệu**
- Vị trí:
  - `getCatalog`, `getCustomers` dùng `.catch(() => {})`.
  - `fetchQuotaThau(...).catch(() => ({dots:[],quotas:[]}))`.
  - `fetchOopClassify` gặp lỗi thì `break`.
  - Nhiều chỗ `catch {}`.
- Hiện tượng: edge function lỗi thì dropdown rỗng, quota trống, nhãn lý do OOP mất, nhưng không có thông báo nào.
- Hướng sửa: trả cờ `partial: ['quota', …]` cho client; hiện banner "Một phần dữ liệu chưa tải được — Thử lại".

**B13 🟢 Code chết và tài liệu lệch**
- `fetchOutOfPlan` (`api/index.ts:345`) không còn được gọi.
- README ghi secret `SESSION_SECRET` và "4 màn / chỉ admin & ps sửa". Code thật dùng `TOKEN_SECRET`, có 5 màn và 4 role được sửa.
- PRD §5.1 mô tả token `{u,r,s,b}`, nhưng token hiện tại dùng key đầy đủ (`username`, `role`…).
- Comment đầu 2 edge function vẫn ghi `deploy api` / `deploy login` (tên cũ).

**B14 🔴 Hai migration trùng số version**
- `20260915100000_cap_nhat_thuc_hien_timeout.sql` và `20260915100000_get_quota_thau_sap_xep.sql`.
- README đã cấm việc này: `supabase db push` dùng version làm khoá trong `schema_migrations`, nên sẽ lỗi hoặc bỏ sót một file.
- Hướng sửa: đổi tên một file sang version mới. Kiểm tra `supabase migration list` trên DB thật xem file nào đã chạy.

### 2.2 Hiệu năng

**P1 🔴 `effectiveRows` có độ phức tạp O(số dòng × số ô nháp)**
- Vị trí: `index.html:5757`.
- Hiện tượng: với mỗi dòng, code duyệt lại **toàn bộ** `drafts`. 23k dòng × 300 ô nháp ≈ 7 triệu phép so sánh cho mỗi lần sửa một ô. Gõ càng nhiều, app càng chậm.
- Hướng sửa (vài dòng, làm ngay):
  ```js
  const effectiveRows = useMemo(() => {
    if (draftCount === 0) return rows;
    const patchByRow = new Map();
    for (const [k, v] of Object.entries(drafts)) {
      const i = k.indexOf(':');
      const id = Number(k.slice(0, i));
      let p = patchByRow.get(id);
      if (!p) patchByRow.set(id, (p = {}));
      p[k.slice(i + 1)] = v;
    }
    return rows.map(r => {
      const p = patchByRow.get(r._row);
      return p ? { ...r, ...p } : r;
    });
  }, [rows, drafts, draftCount]);
  ```

**P2 🟠 Ô tìm kiếm không debounce**
- Mỗi phím gõ tính lại `tree` trên ~20k dòng, cộng với 2 màn tổng hợp.
- Hướng sửa: `useDeferredValue(search)` hoặc debounce 200 ms.

**P3 🟠 Không dùng `React.memo`, nên mọi thẻ render lại khi sửa 1 ô**
- `draftKeys` là `Set` mới mỗi khi `drafts` đổi, và được truyền vào **mọi** `CustomerCard`.
- Hướng sửa:
  - Bọc `CustomerCard`, `ProductGroupSection`, `ProductRow`, `EditableCell` bằng `React.memo`.
  - Truyền cho từng thẻ chỉ tập ô nháp của chính nó.
  - Các callback truyền xuống phải ổn định (`useCallback` với deps đúng, hoặc đọc qua ref).

**P4 🔴 `getData` quá nặng và bị gọi quá nhiều**
- Mỗi lần gọi tải toàn bộ dòng trong phạm vi (~20k × 23 trường).
- Kèm `classify_oop_sale_target` chạy trên **toàn DB, không lọc phạm vi**, kể cả với user PS (`api/index.ts:325, 410`).
- Bị gọi lại sau: mỗi lần lưu quota, lưu/dọn địa bàn, đổi tháng hiện tại, và mỗi lần `rev` đổi.
- Hướng sửa:
  - Đồng bộ tăng dần theo `rev` (GĐ 2).
  - Chỉ phân loại OOP khi mở màn tổng hợp hoặc modal OOP, và lọc theo phạm vi.
  - Kiểm tra response đã được nén gzip/br chưa (xem header `content-encoding` trong DevTools).
  - Cache danh mục ít đổi (catalog, KH, dm_ps) trên client, làm mới khi có `updated_at` mới.

**P5 🟠 Tải trang lần đầu chậm và phụ thuộc CDN**
- Tailwind Play CDN biên dịch CSS lúc chạy, gây nháy giao diện (FOUC).
- React không ghim phiên bản, nên unpkg đổi bản 18.x là app đổi theo mà không ai kiểm.
- Chart.js tải sẵn dù chỉ dùng ở 1 chỗ.
- HTML 398 KB không minify.
- Hướng sửa: build step (GĐ 1). Tailwind biên dịch sẵn chỉ còn vài chục KB. Lazy-load Chart.js và SheetJS khi cần.

**P6 🟢 Truy vấn lặp trong edge function**
- `psInfo` đọc toàn bộ `dm_ps` (limit 500) ở **mỗi lần gọi**.
- `saveDiaBan` gọi `buForPs`/`mienForPs` cho từng PS, tức 2–4 query mỗi PS.
- Hướng sửa: đọc `dm_ps` một lần cho mỗi request rồi tra bằng `Map`.

**P7 🟠 "Đồng bộ thực hiện" chạy đồng bộ trong edge function**
- `cap_nhat_thuc_hien` đã phải nới timeout (migration `20260915100000`).
- Edge function có giới hạn thời gian chạy. Dữ liệu hoá đơn tăng thì sẽ vượt giới hạn, và user nhận lỗi dù DB có thể vẫn đang chạy.
- Hướng sửa: tạo job (bảng `shared.job` + `pg_cron`, hoặc gọi bất đồng bộ). API trả `jobId`; UI hỏi trạng thái và hiện tiến độ.

### 2.3 Bảo mật

**S1 🔴 Mật khẩu băm SHA-256 và không giới hạn đăng nhập sai**
- SHA-256 (kể cả có salt) quá nhanh, lộ bảng `users` là dò được mật khẩu yếu.
- Không có rate-limit hay khoá tài khoản, nên có thể dò online.
- Hướng sửa:
  - Chuyển sang bcrypt/argon2id. Băm lại *trong suốt* ngay lần đăng nhập đúng tiếp theo, không bắt user đổi mật khẩu.
  - Thêm bảng `login_attempts`: sai 5 lần trong 15 phút thì khoá tạm.

**S2 🟢 So sánh chữ ký HMAC bằng `!==`**
- Vị trí: `api/index.ts:48`. So sánh chuỗi thường không phải constant-time.
- Hướng sửa: so sánh constant-time, hoặc dùng `crypto.subtle.verify`.

**S3 🟠 CORS `*`**
- Hướng sửa: giới hạn theo origin của GitHub Pages hoặc domain thật; cho phép thêm `localhost` khi phát triển.

**S4 🟠 Token dùng chung qua `localStorage.vmed_token`**
- `localStorage` dùng chung theo origin. Nếu app chạy trên `<tài-khoản>.github.io/<repo>`, mọi trang Pages khác của cùng tài khoản đều đọc được token. Chỉ cần 1 lỗi XSS ở bất kỳ app nào là lộ token 8 giờ.
- Hướng sửa:
  - Rút ngắn thời hạn token; có cơ chế làm mới token.
  - Dùng domain riêng cho bộ app nội bộ.
  - Thêm Content-Security-Policy sau khi đã bỏ các script inline (GĐ 1 giúp làm được việc này).

**S5 🔴 GitHub Pages public cả repo**
- `static.yml` upload `path: '.'`, nên `schema.sql`, `supabase/migrations/*` (tên bảng, RPC, logic phân quyền), `PRD.md` và file kế hoạch này đều truy cập được qua URL Pages.
- Hướng sửa: chỉ upload thư mục build (`dist/`) hoặc danh sách file cần thiết (`index.html`, `favicon.svg`, `logo.png`, `version.json`).

**S6 🟢 Lộ thông báo lỗi DB thô ra client**
- `catch` cuối (`api/index.ts:1132`) trả nguyên `err.message`.
- Hướng sửa: log chi tiết ở server kèm `requestId`; client chỉ nhận mã lỗi và `requestId`.

**S7 🟠 41 hàm `security definer` chưa được rà soát tập trung**
- Hướng sửa:
  - Chạy Supabase Security Advisor.
  - Kiểm `search_path` cố định, `GRANT EXECUTE` chỉ cho `service_role`.
  - Kiểm các view ở schema `app_sale` không lộ qua Data API cho `anon`.

### 2.4 Khả năng bảo trì

| Mã | Vấn đề | Hệ quả |
|---|---|---|
| M1 | Sửa tay code đã biên dịch, không có JSX nguồn | Khó đọc, khó review diff, dễ sai ngoặc |
| M2 | 1 file 7.689 dòng; `App()` ~1.900 dòng / 45 state | Sửa một chỗ dễ ảnh hưởng chỗ khác; không test riêng được |
| M3 | Edge function 1 file, chuỗi `if` 29 action; `FIELDS`/`EDITABLE`/`COL` khai báo lặp ở client | Thêm cột phải sửa nhiều nơi, dễ quên |
| M4 | Không lint, typecheck, test hay staging; edge function deploy tay | Bug chỉ lộ ra trên production |
| M5 | Biến toàn cục đổi trong render (`CURRENT_MONTH`, `MASK_MONEY`, `ALIAS_MAP`) | Component memo hoá hiển thị giá trị cũ; khó bật Strict Mode |
| M6 | 19 `confirm()`/`alert()` gốc | Không định dạng được, chặn luồng, trải nghiệm kém |
| M7 | `esm.sh/@supabase/supabase-js@2` không ghim phiên bản | Bản mới của thư viện có thể làm gãy function khi deploy lại |

---

## 3. Lộ trình chi tiết

### GĐ 0 — Chữa cháy (1 tuần, không đổi kiến trúc)

Mục tiêu: sửa các lỗi rõ ràng với rủi ro thấp, ngay trên cấu trúc hiện tại.

| # | Việc | Liên quan | Ước lượng |
|---|---|---|---|
| 0.1 | Sửa `effectiveRows` theo đoạn code ở P1 | P1 | 0,5 giờ |
| 0.2 | `useDeferredValue` cho ô tìm kiếm; tìm kiếm bỏ dấu | P2, B11 | 1 giờ |
| 0.3 | Tách `initialLoading` / `refreshing`; không unmount UI khi tải lại; giữ trạng thái mở thẻ ở App | B1 | 1 ngày |
| 0.4 | `getRev` theo phạm vi user | B1 | 0,5 ngày |
| 0.5 | Gom thẻ KH theo `custId`; `deleteCustomer` lọc theo `custId` | B3 | 0,5 ngày |
| 0.6 | Kiểm phạm vi cho `getGiaiTrinh` / `saveGiaiTrinh` | B5 | 0,5 ngày |
| 0.7 | Đổi version migration trùng; đối chiếu `supabase migration list` | B14 | 1 giờ |
| 0.8 | Workflow Pages chỉ upload file cần thiết | S5 | 1 giờ |
| 0.9 | Action `getQuotaThau` riêng thay cho việc gọi `getData` trong `napLaiQuota` | B4, P4 | 0,5 ngày |
| 0.10 | Lưu `drafts` vào `localStorage` và khôi phục khi mở lại | B8 | 0,5 ngày |
| 0.11 | Chốt quyền địa bàn cho `manager`; xoá `applyDiaBan` nếu không dùng; xoá `fetchOutOfPlan` | B6, B13 | 0,5 ngày |
| 0.12 | Ghim phiên bản React (`react@18.3.1`), supabase-js (`npm:@supabase/supabase-js@2.x.y`) | P5, M7 | 1 giờ |

**Tiêu chí xong:**
- User khác lưu dữ liệu thì thẻ đang mở không đóng lại.
- Gõ 300 ô liên tiếp không thấy giật.
- PS không đọc được giải trình của PS khác (kiểm bằng token PS gọi thẳng API).

### GĐ 1 — Nền móng (2–3 tuần)

**1.1 Build step cho frontend (Vite + React + JSX)**
- Chuyển `React.createElement` → JSX bằng codemod (ví dụ `babel-plugin-transform-react-createelement-to-jsx`), rồi format bằng Prettier. Không đổi logic trong bước này.
- Tailwind cài qua npm và biên dịch lúc build. Giữ nguyên bảng màu đang override trong `tailwind.config`.
- Deploy: GitHub Actions chạy `npm ci && npm run build` → upload `dist/`. Vẫn ghi `version.json` như hiện nay.
- Cách kiểm: chụp màn hình 5 tab trước/sau chuyển đổi trên cùng dữ liệu, so sánh bằng mắt hoặc dùng Playwright screenshot diff.

**1.2 Tách module theo tính năng**
```
src/
  main.jsx
  api/client.js            # api(), mã lỗi, retry, xử lý unauthorized
  config/fiscal.js         # năm tài chính, tháng hiện tại (đọc từ app_config)
  lib/format.js            # fmtM, fmtTy3, money…
  lib/text.js              # deaccent, fmtCust, custLabel
  lib/calc.js              # YTD, KH còn lại, quota khả dụng, DThu update — HÀM THUẦN
  lib/tree.js              # dựng cây KH → nhóm SP → SP từ rows
  state/                   # store: rows, drafts, filters, auth (Zustand hoặc useReducer + context)
  components/              # Modal, MultiSelect, EditableCell, PriceCell, ConfirmDialog…
  features/detail/         # CustomerCard, ProductGroupSection, ProductRow, QuotaThauModal
  features/summary-ps/
  features/summary-product/
  features/dia-ban/
  features/audit/
  features/oop/
```
- Bỏ biến toàn cục: `CURRENT_MONTH`, `MASK_MONEY`, `ALIAS_MAP` chuyển thành context hoặc store.
- Thay `confirm()`/`alert()` bằng `ConfirmDialog` và toast dùng chung.

**1.3 Tách edge function theo action**
```
supabase/functions/
  _shared/auth.ts          # verifyToken (constant-time), session
  _shared/scope.ts         # applyScope, scopeParams, assertInScope — 1 nơi duy nhất
  _shared/fields.ts        # COL, FIELDS, EDITABLE, ADMIN_EDITABLE
  _shared/errors.ts        # mã lỗi chuẩn + requestId
  sale_target-api/index.ts # router: action → handler
  sale_target-api/actions/{data,cells,quota,product,diaBan,oop,audit,config,giaiTrinh,sync}.ts
```
- `fields.ts` viết TypeScript thuần (không dùng API riêng của Deno), để frontend import được qua alias của Vite. Như vậy danh sách cột chỉ khai báo ở một nơi.

**1.4 Chất lượng code**
- ESLint (`eslint-plugin-react-hooks` bắt thiếu deps như B9) + Prettier.
- TypeScript tăng dần: bật `checkJs` trước, chuyển `lib/` sang `.ts` trước.
- **Vitest cho `lib/calc.js` và `lib/tree.js`.** Đây là nơi sai số liệu gây hậu quả lớn nhất: YTD, quota khả dụng, OOP, tách dòng theo đơn giá, loại team TEST.
- **Test "số vàng" (golden numbers):** script tính tổng DThu KH, TH YTD, quota khả dụng theo PS/miền/team từ một bản dữ liệu cố định. Refactor xong, số phải khớp 100%.

**1.5 Staging & CI/CD**
- Tạo project Supabase staging (hoặc dùng Supabase Branching nếu gói trả phí cho phép). Seed bằng bản sao dữ liệu đã ẩn danh hoá.
- Workflow GitHub Actions:
  - PR: lint + test + build.
  - Merge `main`: deploy Pages, và `supabase functions deploy` bằng `SUPABASE_ACCESS_TOKEN` (hết cảnh quên deploy edge function).
  - Migration: job `supabase db push` chạy **thủ công** qua environment có bước duyệt. Kèm kiểm tra tự động: không có version trùng, không có file `*ROLLBACK*` trong `migrations/`.
- Thêm file `.nvmrc` / `package.json` để máy nào cũng build giống nhau.

### GĐ 2 — Hiệu năng & đồng bộ dữ liệu (2–3 tuần)

**2.1 Đồng bộ tăng dần thay cho tải lại toàn bộ**
- DB:
  - Thêm cột `rev bigint` trên `sale_target`, lấy từ sequence. Trigger gán `rev` mới ở mọi INSERT/UPDATE.
  - Bảng `sale_target_tombstone(id, bu, ps, mien, rev)` ghi lại dòng bị xoá (trigger AFTER DELETE).
  - Index `(bu, rev)`.
- API: `getChanges({ sinceRev })` trả các dòng có `rev > sinceRev` trong phạm vi user, cùng danh sách id đã xoá và `rev` mới nhất.
- Client: mở app gọi `getData` 1 lần. Sau đó poll `getChanges` và vá thẳng vào state. Không còn reload toàn bộ, không mất UI.
- Có thể thay polling bằng Supabase Realtime (broadcast `rev` theo team) để giảm số request. Làm sau khi polling tăng dần đã ổn định.

**2.2 Khoá lạc quan theo dòng**
- `updateCells` gửi kèm `rev` của từng dòng lúc client tải về.
- RPC chỉ ghi dòng có `rev` khớp. Dòng lệch trả về danh sách `conflicts: [{id, key, giaTriServer}]`.
- UI tô đỏ đúng ô xung đột và cho chọn "giữ của tôi" hoặc "lấy bản mới". Bỏ hộp `confirm()` hỏi chung "người khác vừa cập nhật" (hiện hộp này hiện ra cả khi người khác sửa dòng không liên quan).

**2.3 Giảm render**
- Store tách lát cắt (slice): component chỉ subscribe phần dữ liệu nó cần.
- `React.memo` cho thẻ KH, nhóm SP, dòng SP, ô.
- Ảo hoá danh sách (TanStack Virtual) khi admin/manager mở "Tất cả team" có hàng trăm thẻ.
- Tính cây và số tổng hợp trong Web Worker nếu đo thấy tác vụ dài quá 50 ms.

**2.4 Backend**
- Gộp quota: `upsert_quota_thau` / `delete_dot_thau` cập nhật luôn cột cũ trong cùng transaction (B4). Sau đó chuyển 2 màn tổng hợp sang đọc từ `quota_thau` rồi bỏ cột cũ.
- `classify_oop_sale_target` nhận tham số phạm vi; chỉ gọi khi cần.
- `addProducts` theo lô, có chặn trùng (B9).
- "Đồng bộ thực hiện" chạy nền qua bảng job; UI hiện tiến độ (P7).
- Dùng `pg_stat_statements` tìm 10 truy vấn tốn nhất rồi bổ sung index (áp dụng hướng dẫn `supabase-postgres-best-practices` khi viết migration).

**Mục tiêu đo:**

| Chỉ số | Hiện tại | Mục tiêu |
|---|---|---|
| Tải lần đầu (tới lúc thao tác được), ~20k dòng | cần đo | < 3 s |
| Độ trễ khi gõ vào ô (INP) | cần đo | < 100 ms |
| Payload làm mới định kỳ | toàn bộ (vài MB) | chỉ các dòng thay đổi (vài KB) |
| Số lần UI bị reset ngoài ý muốn | mỗi khi có người lưu | 0 |

> Trước khi bắt đầu GĐ 2, đo các số "hiện tại" bằng Chrome DevTools (Performance, Network) để có mốc so sánh.

### GĐ 3 — Bảo mật & vận hành (1–2 tuần, song song GĐ 2)

- **Mật khẩu:** argon2id/bcrypt; băm lại trong suốt khi đăng nhập đúng; bảng `login_attempts` + khoá tạm (S1).
- **Token:** so sánh constant-time (S2); thời hạn ngắn hơn + làm mới; modal đăng nhập lại giữ nguyên bản nháp (B8).
- **CORS** theo danh sách origin (S3); **CSP** sau khi đã có build step (S4).
- **Lỗi chuẩn hoá:** mã lỗi + `requestId`; log có cấu trúc ở edge function (action, user, thời gian xử lý, số dòng) (S6).
- **Giám sát:**
  - Sentry (hoặc tương đương) bắt lỗi JS phía client.
  - Dashboard log edge function: tỷ lệ 4xx/5xx, p95 thời gian theo action.
  - Cảnh báo khi 5xx tăng đột biến.
- **Rà soát DB:** Security Advisor, `security definer`, grant, RLS cho mọi bảng/view (S7).
- **Sao lưu:** bật PITR nếu gói cho phép; nếu không thì `pg_dump` định kỳ bằng GitHub Actions lưu vào kho riêng tư. Mỗi quý diễn tập khôi phục 1 lần.
- **Audit đầy đủ:** ghi trong RPC hoặc trigger; bổ sung các action còn thiếu (B10).

### GĐ 4 — Sẵn sàng FY27 (1–2 tuần, **hạn chót 01/2027**)

Kế hoạch FY27 thường phải lập từ quý 1/2027, nên phần này cần xong trước khi người dùng bắt đầu nhập.

- **Mô hình năm tài chính:** bảng `shared.nam_tai_chinh(fy, thang_bat_dau, trang_thai: 'dang_lap' | 'dang_chay' | 'da_khoa')`.
  - `MONTHS` sinh từ `thang_bat_dau`, không gắn cứng nữa.
  - `current_month` gắn với năm tài chính đang chạy.
- **API:**
  - `getData`, `getChanges`, `getQuotaThau` nhận `fy` và lọc theo năm (index `(nam_tai_chinh, bu)`).
  - `addProduct` dùng `fy` có kiểm tra, không lấy "dòng bất kỳ".
- **UI:** bộ chọn năm tài chính trên header. Năm `da_khoa` chỉ cho xem.
- **Trình hướng dẫn "Lập kế hoạch năm mới":** sao chép danh mục (KH × SP × đơn giá × PS) từ FY26 sang FY27. Tuỳ chọn: SL = 0, SL = thực hiện FY26, hoặc SL = kế hoạch FY26 × hệ số. Có bước xem trước và ghi trong 1 transaction.
- **Địa bàn:** kiểm tra `dm_dia_ban` (khoảng hiệu lực theo `YYYY-MM`) hoạt động qua mốc năm; `v_dia_ban_khoang_trong` tính đúng cho FY27.
- **Test:** chạy thử toàn bộ quy trình trên staging với dữ liệu giả lập tháng 04/2027.

---

## 4. Nguyên tắc khi thực hiện

1. **Không viết lại toàn bộ một lần.** Tách dần từng phần (strangler pattern); mỗi PR nhỏ, chạy được, deploy được.
2. **Số liệu là tối thượng.** Mọi thay đổi chạm vào cách tính hoặc cách tải dữ liệu phải qua test "số vàng" (§GĐ 1.4).
3. **Thay đổi DB luôn có rollback**, để ở `supabase/rollbacks/`, và chạy trên staging trước.
4. **Feature flag qua `app_config`** cho các thay đổi lớn (ví dụ `sync_mode = 'full' | 'incremental'`) để bật/tắt không cần deploy lại.
5. **Cập nhật PRD/README trong cùng PR** với thay đổi hành vi, tránh tài liệu lệch như B13.
6. **Đo trước, tối ưu sau.** Ghi số đo trước và sau vào mô tả PR.

---

## 5. Đề xuất tính năng bổ sung

Xếp theo giá trị cho người dùng so với công sức. ⭐ = nên làm sớm.

### 5.1 Nhập liệu nhanh hơn (cho PS)
- ⭐ **Dán vùng từ Excel:** copy một khối ô trong Excel rồi dán thẳng vào bảng 12 tháng. PS vốn quen làm việc trên Excel.
- ⭐ **Điền nhanh:** kéo giá trị sang phải, "copy từ tháng trước", phân bổ tổng năm theo tỷ trọng mùa vụ.
- **Hoàn tác / làm lại** (Ctrl+Z / Ctrl+Y) cho bản nháp; phím tắt di chuyển giữa các ô như bảng tính.
- **Import kế hoạch từ file Excel mẫu:** tải lên → xem trước chênh lệch → kiểm tra lỗi → ghi trong 1 transaction.

### 5.2 Theo dõi & cảnh báo (cho quản lý)
- ⭐ **Cảnh báo tự động trong app:**
  - Quota khả dụng âm hoặc còn dưới 10%.
  - Chênh lệch kế hoạch vượt X% mà chưa có giải trình.
  - PS chưa cập nhật trước hạn (mở rộng từ Deadline Dashboard đã có).
- **Bản tin tuần** qua email hoặc Teams/Zalo: tóm tắt TH YTD, top chênh lệch, danh sách chưa cập nhật.
- ⭐ **Dashboard biểu đồ:**
  - Xu hướng KH vs TH theo tháng.
  - So sánh team/miền.
  - Bản đồ nhiệt PS × tháng.
  - Bấm vào biểu đồ để đi tới màn Chi tiết.
- **Dự báo cuối năm** từ tốc độ thực hiện YTD (run-rate), so với kế hoạch và quota.

### 5.3 Quản trị & chất lượng dữ liệu (cho admin)
- ⭐ **Trang "Sức khoẻ dữ liệu"** gom một chỗ:
  - PS lệch tên (`v_dm_ps_lech_ten`).
  - OOP theo lý do.
  - Khoảng trống địa bàn.
  - Dòng trùng, dòng thiếu đơn giá, dòng `bu` rỗng.
- **Quản lý người dùng trong app:** tạo tài khoản, reset mật khẩu, gán role/phạm vi/ngành hàng; không phải sửa DB tay nữa.
- **Lịch sử theo ô:** di chuột vào ô để xem ai sửa, lúc nào, giá trị cũ (dựa trên audit log đầy đủ ở GĐ 3).
- **Khoá sổ tháng:** admin khoá tháng đã chốt; chỉ admin mở lại, có ghi log.

### 5.4 Quy trình & cộng tác
- **Phiên bản kế hoạch (baseline):** chụp kế hoạch tại các mốc (đầu năm, giữa năm) và so sánh 2 phiên bản bất kỳ. Hiện chỉ có "đầu năm" và "update".
- **Duyệt kế hoạch nhẹ:** PS nộp → quản lý miền duyệt hoặc trả lại kèm ghi chú → khoá. PRD đang xếp vào hướng phát triển (§12.3).
- **Bình luận theo dòng/nhóm SP có @nhắc tên**, mở rộng từ giải trình.

### 5.5 Tiện ích
- **Lưu bộ lọc (saved views)** và **URL chia sẻ** trạng thái tab/bộ lọc/KH đang mở.
- **Xuất báo cáo PDF** theo tháng; hẹn giờ gửi tự động.
- **PWA + bản nháp bền (IndexedDB):** mạng chập chờn vẫn nhập được, có mạng lại thì đồng bộ.

---

## 6. Theo dõi tiến độ

| Chỉ số | Cách đo | Mục tiêu sau GĐ 2–3 |
|---|---|---|
| Tỷ lệ commit `fix` / tổng commit | `git log` hàng tháng | < 20% (hiện ~35%) |
| Lỗi JS phía client / tuần | Sentry | giảm 80% |
| Tỷ lệ 5xx edge function | Log Supabase | < 0,5% |
| p95 `getData` / `getChanges` | Log có cấu trúc | < 3 s / < 300 ms |
| Độ phủ test `lib/calc` + `lib/tree` | Vitest coverage | > 80% |
| Bug phát hiện trên staging trước production | Ghi nhận trong PR | tăng dần |

---

## 7. Các quyết định cần chốt

1. **`manager` có được ghi Cấu hình địa bàn không?** Code đang cho phép, PRD nói không (B6).
2. **Chấp nhận thêm build step (Node/Vite)?** Quy trình deploy frontend sẽ đổi từ "push file HTML" sang "CI build rồi deploy".
3. **Gói Supabase:** có dùng được Branching/PITR không, hay dùng project staging riêng và `pg_dump`?
4. **FY27:** khi lập kế hoạch năm mới, sao chép từ FY26 theo cách nào (SL = 0, theo thực hiện, hay theo kế hoạch × hệ số)? Có khoá FY26 sau khi kết thúc không?
5. **Kênh thông báo** cho cảnh báo và bản tin tuần: email, Teams hay Zalo?
6. **Thứ tự tính năng ở §5:** ưu tiên nhóm nào trước (nhập liệu PS, cảnh báo quản lý, hay quản trị dữ liệu)?

---

## Phụ lục A — Checklist GĐ 0

- [ ] 0.1 Sửa `effectiveRows` (P1)
- [ ] 0.2 `useDeferredValue` + tìm kiếm bỏ dấu (P2, B11)
- [ ] 0.3 Không unmount UI khi tải lại; giữ trạng thái mở thẻ (B1)
- [ ] 0.4 `getRev` theo phạm vi (B1)
- [ ] 0.5 Gom thẻ và xoá KH theo `custId` (B3)
- [ ] 0.6 Kiểm phạm vi giải trình (B5)
- [ ] 0.7 Sửa migration trùng version (B14)
- [ ] 0.8 Pages chỉ upload file cần thiết (S5)
- [ ] 0.9 Action `getQuotaThau` (B4, P4)
- [ ] 0.10 Lưu và khôi phục bản nháp (B8)
- [ ] 0.11 Chốt quyền địa bàn; xoá code chết (B6, B13)
- [ ] 0.12 Ghim phiên bản thư viện (P5, M7)
- [ ] Cập nhật README/PRD theo các thay đổi trên
