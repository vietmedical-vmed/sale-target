// Supabase Edge Function: api
// Endpoint duy nhất xử lý mọi action của web app.
// Body: { action, token, payload }
//
// Deploy:  supabase functions deploy api --no-verify-jwt
// Cần secret: supabase secrets set TOKEN_SECRET=<chuoi_bi_mat_dai>  (GIỐNG login, CHUẨN CHUNG mọi app)

import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const cors = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
};
function json(body, status = 200) {
  return new Response(JSON.stringify(body), {
    status, headers: { ...cors, "Content-Type": "application/json" },
  });
}
const enc = new TextEncoder();
function b64url(bytes) {
  return btoa(String.fromCharCode(...bytes)).replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/, "");
}
async function hmac(secret, msg) {
  const key = await crypto.subtle.importKey("raw", enc.encode(secret),
    { name: "HMAC", hash: "SHA-256" }, false, ["sign"]);
  return new Uint8Array(await crypto.subtle.sign("HMAC", key, enc.encode(msg)));
}
async function verifyToken(token, secret) {
  if (!token || token.indexOf(".") < 0) return null;
  const [p, sig] = token.split(".");
  const expect = b64url(await hmac(secret, p));
  if (sig !== expect) return null;
  let payload;
  try {
    const bin = atob(p.replace(/-/g, "+").replace(/_/g, "/"));
    const bytes = Uint8Array.from(bin, (ch) => ch.charCodeAt(0));
    const jsonStr = new TextDecoder("utf-8").decode(bytes);
    payload = JSON.parse(jsonStr);
  } catch { return null; }
  if (!payload.exp || Math.floor(Date.now() / 1000) > payload.exp) return null; // exp: giây (chuẩn chung)
  // Token chuẩn chung dùng key đầy đủ -> map về {u,r,s,b} cho code bên dưới.
  // Vẫn nhận token cũ {u,r,s,b} để không gãy trong lúc chuyển đổi.
  return {
    u: payload.username ?? payload.u,
    r: payload.role ?? payload.r,
    s: payload.scope ?? payload.s,
    b: payload.bu ?? payload.b,
    exp: payload.exp,
  };
}

// ---- Mapping field key (app) <-> cột Supabase ----
const COL = {
  fy: "nam_tai_chinh", mo: "thang_ke_hoach", region: "mien", ps: "ps",
  cust: "khach_hang", custId: "ma_khach_hang", grp: "nhom_san_pham",
  prod: "san_pham", mset: "bo_vat_tu", qOld: "quota_thau_cu_con_lai",
  mMain: "thang_thau_chinh", dMain: "thoi_gian_thau_chinh", qMain: "quota_thau_chinh",
  mAdd: "thang_thau_bo_sung", qAdd: "quota_bo_sung", rev: "sl_ke_hoach_dau_nam",
  revUpd: "sl_ke_hoach_update", price: "don_gia", note: "giai_trinh",
  act: "sl_thuc_hien", dt: "doanh_thu_kh_dau_nam",
};
// Thứ tự field khi trả getData (app đọc theo fields[])
const FIELDS = ["fy","mo","region","ps","cust","custId","grp","prod","mset",
  "qOld","mMain","dMain","qMain","mAdd","qAdd","rev","revUpd","price","note","act","dt"];
// Chỉ các cột này được phép sửa qua updateCells
const EDITABLE = new Set(["qOld","mMain","dMain","qMain","mAdd","qAdd","revUpd","note","price"]);
// Các cột nhận diện (bộ vật tư / sản phẩm) — CHỈ admin được sửa qua updateCells.
const ADMIN_EDITABLE = new Set(["mset","prod"]);

// Lọc dữ liệu theo quyền của user.
// - admin/manager: xem tất cả team (bu); nếu client gửi payload.bu cụ thể → lọc theo team đó.
// - Các role khác: LUÔN khoá theo bu trong token (không được ghi đè bằng payload).
// - Sau đó lọc tiếp theo phạm vi hẹp hơn: area_manager theo Miền, ps theo PS.
function applyScope(query, sess, payload = {}) {
  const role = String(sess.r || "").toLowerCase(); // phòng DB trả role viết HOA ("ADMIN"/"PS"...)
  let q = query;

  // --- Khoá theo team (bu) ---
  if (role === "admin" || role === "manager") {
    if (payload && payload.bu) q = q.eq("bu", payload.bu); // admin/manager chọn xem 1 team cụ thể
    // không chọn gì → xem tất cả team
  } else if (role === "product_manager") {
    // PM quản theo NGÀNH HÀNG, xuyên suốt các team → KHÔNG khoá theo bu.
    // (Muốn giới hạn PM trong 1 team thì bỏ comment dòng dưới.)
    // q = q.eq("bu", sess.b);
  } else {
    q = q.eq("bu", sess.b); // các role còn lại luôn khoá theo bu của chính họ (không tin payload)
  }

  // --- Phạm vi trong phạm vi trên ---
  if (role === "admin" || role === "manager") return q;
  if (role === "product_manager") {
    // sess.s = ngành hàng PM phụ trách; cho phép nhiều ngành, ngăn cách bởi dấu phẩy.
    const groups = String(sess.s || "").split(",").map((x) => x.trim()).filter(Boolean);
    if (groups.length === 0) return q.eq("nhom_san_pham", "__none__"); // chưa gán ngành → không thấy gì
    return groups.length > 1 ? q.in("nhom_san_pham", groups) : q.eq("nhom_san_pham", groups[0]);
  }
  if (role === "area_manager") return q.eq("mien", sess.s);
  if (role === "ps") return q.eq("ps", sess.s);
  return q.eq("ps", sess.s); // mặc định: hẹp nhất
}

// Phạm vi quyền dưới dạng tham số cho RPC ghi dữ liệu (update_sale_target_cells).
// Phải khớp applyScope() ở trên: null = không giới hạn theo cột đó.
// applyScope dùng cho phần ĐỌC (query builder), hàm này cho phần GHI (RPC) —
// sửa một bên thì phải sửa bên kia.
function scopeParams(sess) {
  const role = String(sess.r || "").toLowerCase();
  const nil = { p_bu: null, p_mien: null, p_ps: null, p_groups: null };
  // admin/manager: xem & sửa mọi team (giống applyScope khi không có payload.bu)
  if (role === "admin" || role === "manager") return nil;
  if (role === "product_manager") {
    const groups = String(sess.s || "").split(",").map((x) => x.trim()).filter(Boolean);
    // chưa gán ngành hàng -> không khớp dòng nào (giống "__none__" ở applyScope)
    return { ...nil, p_groups: groups.length ? groups : ["__none__"] };
  }
  if (role === "area_manager") return { ...nil, p_bu: sess.b, p_mien: sess.s };
  return { ...nil, p_bu: sess.b, p_ps: sess.s }; // ps + mặc định: hẹp nhất
}

function admin() {
  return createClient(
    Deno.env.get("SUPABASE_URL") ?? "",
    Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "",
  );
}

async function getRev(db) {
  const { data } = await db.from("sale_target")
    .select("updated_at").order("updated_at", { ascending: false }).limit(1);
  if (data && data[0] && data[0].updated_at) return Date.parse(data[0].updated_at);
  return 0;
}

// Suy team (bu) của một PS từ chính dữ liệu kế hoạch của họ.
// Dùng khi admin/manager tạo dữ liệu HỘ một PS (thêm SP, khai báo địa bàn): gắn bu
// của người tạo là gán sai team, dòng đó sẽ lọt vào báo cáo của team khác.
// 1 tên PS có dữ liệu ở nhiều team → KHÔNG đoán, ném lỗi để người dùng biết.
// Trả về `fallback` khi PS chưa có dòng kế hoạch nào.
async function buForPs(db, psName, fallback) {
  const { data, error } = await db.from("sale_target")
    .select("bu").eq("ps", psName).not("bu", "is", null).limit(1000);
  if (error) throw new Error(error.message);
  const list = [...new Set((data || []).map((r) => r.bu).filter(Boolean))];
  if (list.length === 1) return list[0];
  if (list.length > 1) {
    throw new Error(
      `PS "${psName}" đang có dữ liệu ở ${list.length} team (${list.join(", ")}) ` +
      `— không xác định được team để gắn cho dòng mới`,
    );
  }
  return fallback;
}

// Đọc TẤT CẢ dòng (PostgREST giới hạn 1000/lần → phân trang).
// Tối ưu: đếm tổng số dòng trước, rồi TẢI CÁC TRANG SONG SONG (thay vì tuần tự)
// để giảm mạnh thời gian chờ khi dữ liệu lớn (vd ~20k dòng = 21 trang).
const PAGE = 1000;      // = max_rows của PostgREST (config.toml) → không được vượt
const CONCURRENCY = 6;  // số trang tải đồng thời

async function fetchAll(db, sess, payload) {
  const cols = FIELDS.map((f) => COL[f]).join(",") + ",id";

  // 1) Đếm số dòng trong phạm vi quyền của user (head:true → không kéo data).
  let countQ = db.from("sale_target").select("id", { count: "exact", head: true });
  countQ = applyScope(countQ, sess, payload);
  const { count, error: cErr } = await countQ;
  if (cErr) throw new Error(cErr.message);
  const total = count || 0;
  if (total === 0) return [];

  const pages = Math.ceil(total / PAGE);
  const out = new Array(total);

  // 2) Tải các trang song song (có giới hạn CONCURRENCY). Sắp xếp theo id để
  //    phân trang ổn định (tránh trùng/thiếu dòng giữa các trang).
  let next = 0;
  async function worker() {
    for (let p = next++; p < pages; p = next++) {
      const from = p * PAGE;
      let q = db.from("sale_target").select(cols)
        .order("id", { ascending: true })
        .range(from, from + PAGE - 1);
      q = applyScope(q, sess, payload);
      const { data, error } = await q;
      if (error) throw new Error(error.message);
      for (let i = 0; i < data.length; i++) out[from + i] = data[i];
    }
  }
  await Promise.all(
    Array.from({ length: Math.min(CONCURRENCY, pages) }, worker),
  );

  // Loại bỏ ô trống (phòng khi count lệch do dữ liệu thay đổi giữa chừng).
  return out.filter(Boolean);
}

// ---- Actual NGOÀI KẾ HOẠCH ----
// Các dòng thực hiện không khớp dòng kế hoạch nào (view v_actual_ngoai_ke_hoach).
// Trả về DƯỚI DẠNG RIÊNG (oopRows), KHÔNG trộn vào rows: app chỉ dùng ở 2 màn tổng
// hợp cho đủ số, còn màn chi tiết vẫn chỉ hiển thị/sửa được dòng kế hoạch thật.
// Nhãn khách hàng cố định = "Ngoài kế hoạch" → khi app gộp theo KH sẽ ra đúng 1 dòng.
const OOP_CUST = "Ngoài kế hoạch";

async function fetchOutOfPlan(db, sess, payload) {
  const out = [];
  for (let from = 0; ; from += PAGE) {
    let q = db.from("v_actual_ngoai_ke_hoach")
      .select("thang_ke_hoach,mien,ps,bu,nhom_san_pham,bo_vat_tu,san_pham,sl_thuc_hien")
      .range(from, from + PAGE - 1);
    q = applyScope(q, sess, payload); // cùng phân quyền như sale_target
    const { data, error } = await q;
    if (error) throw new Error(error.message);
    out.push(...(data || []));
    if (!data || data.length < PAGE) break;
  }
  // Ánh xạ sang đúng thứ tự FIELDS; các cột kế hoạch để rỗng (KHÔNG phải 0)
  // để app hiển thị "—" và không tính % hoàn thành cho dòng này.
  return out.map((r) => {
    const o = {
      mo: r.thang_ke_hoach, region: r.mien, ps: r.ps,
      cust: OOP_CUST, grp: r.nhom_san_pham, prod: r.san_pham,
      mset: r.bo_vat_tu, act: r.sl_thuc_hien,
    };
    return FIELDS.map((f) => (o[f] === null || o[f] === undefined ? "" : o[f]));
  });
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: cors });
  if (req.method !== "POST") return json({ ok: false, error: "method" }, 405);

  const secret = Deno.env.get("TOKEN_SECRET");
  if (!secret) return json({ ok: false, error: "TOKEN_SECRET chua duoc set" }, 500);

  let body;
  try { body = await req.json(); } catch { return json({ ok: false, error: "bad_body" }, 400); }

  const { action, token, payload = {} } = body;
  const sess = await verifyToken(token, secret);
  if (!sess) return json({ ok: false, error: "unauthorized" }, 401);
  sess.r = String(sess.r || "").toLowerCase(); // chuẩn hoá role: "ADMIN" → "admin", "PS" → "ps"...

  const db = admin();
  const canEdit = sess.r === "admin" || sess.r === "ps"; // PM KHÔNG nằm trong đây → chỉ xem

  try {
    if (action === "ping") {
      return json({ ok: true, role: sess.r, scope: sess.s, bu: sess.b, username: sess.u });
    }

    if (action === "getData") {
      // fetchAll / fetchOutOfPlan / getRev độc lập → chạy song song để tiết kiệm lượt chờ.
      // fetchOutOfPlan hỏng KHÔNG được làm sập getData (vd view chưa tạo) → nuốt lỗi, trả [].
      const [dbRows, oopRows, rev] = await Promise.all([
        fetchAll(db, sess, payload),
        fetchOutOfPlan(db, sess, payload).catch(() => []),
        getRev(db),
      ]);
      const rows = dbRows.map((r) => FIELDS.map((f) => {
        const v = r[COL[f]];
        return v === null || v === undefined ? "" : v;
      }));
      const rowNums = dbRows.map((r) => r.id);
      return json({
        ok: true, fields: FIELDS, rows, rowNums, oopRows, rev,
        role: sess.r, scope: sess.s, bu: sess.b, username: sess.u,
      });
    }

    if (action === "getRev") {
      return json({ ok: true, rev: await getRev(db) });
    }

    // Danh mục cho form thêm SP: đọc từ dm_bo_vat_tu_mapping.
    // dm_bo_vat_tu KHÔNG dùng được — bảng đó không có cột san_pham.
    // KHÔNG select don_gia: không bảng danh mục nào có cột này (chỉ sale_target
    // mới có) → đơn giá do người dùng nhập tay ở form thêm SP.
    // Tên action giữ nguyên "getCatalog" để không phải đổi frontend.
    if (action === "getCatalog") {
      // Phân trang: PostgREST chặn ở max_rows (1000). Trước đây .range(0,4999) nên
      // danh mục > 1000 dòng đã bị cắt âm thầm → thiếu bộ vật tư / sản phẩm trong
      // form thêm SP mà không có lỗi nào. order theo id cho phân trang ổn định.
      const catalog = [];
      // Bảng mapping có nhiều dòng cho cùng 1 (nhóm, bộ vật tư, sản phẩm) — khác nhau
      // ở bu / san_pham_thay_the / so_luong_dinh_muc. Dropdown chỉ cần 3 trường đầu
      // nên gom trùng ngay tại đây, tránh 1 sản phẩm hiện nhiều lần và tránh gửi
      // payload thừa.
      const seen = new Set();
      for (let from = 0; ; from += PAGE) {
        const { data, error } = await db.from("dm_bo_vat_tu_mapping")
          .select("nhom_san_pham, bo_vat_tu, san_pham")
          .order("id", { ascending: true })
          .range(from, from + PAGE - 1);
        if (error) throw new Error(error.message);
        if (!data || data.length === 0) break;
        for (const c of data) {
          const key = `${c.nhom_san_pham || ""}||${c.bo_vat_tu || ""}||${c.san_pham || ""}`;
          if (seen.has(key)) continue;
          seen.add(key);
          catalog.push({
            grp: c.nhom_san_pham, mset: c.bo_vat_tu, prod: c.san_pham,
          });
        }
        if (data.length < PAGE) break;
      }
      return json({ ok: true, catalog });
    }

    if (action === "getCustomers") {
      // Danh mục khách hàng ĐẦY ĐỦ từ dm_khach_hang (không giới hạn theo dữ liệu sale_target).
      // Phân trang vì PostgREST giới hạn 1000 dòng/lần.
      const out = [];
      for (let from = 0; ; from += PAGE) {
        const { data, error } = await db.from("dm_khach_hang")
          .select("customer_id, customer_name")
          .order("customer_id", { ascending: true })
          .range(from, from + PAGE - 1);
        if (error) throw new Error(error.message);
        if (!data || data.length === 0) break;
        for (const c of data) out.push({ custId: c.customer_id ?? "", cust: c.customer_name ?? "" });
        if (data.length < PAGE) break;
      }
      const customers = out.filter((c) => c.cust || c.custId);
      return json({ ok: true, customers });
    }

    if (action === "updateCells") {
      if (!canEdit) return json({ ok: false, error: "forbidden" }, 403);
      const isAdmin = sess.r === "admin";
      const updates = payload.updates || [];
      // Gom mọi ô đã sửa theo id dòng -> 1 patch/dòng, rồi ghi TẤT CẢ bằng đúng
      // 1 lượt RPC (update_sale_target_cells). Trước đây update tuần tự từng ô:
      // 600 ô = 600 lượt gọi nối tiếp ~ 30-40s.
      const byRow = new Map();
      for (const u of updates) {
        // cột thường: ai edit được (admin/ps); cột nhận diện (mset/prod): chỉ admin.
        const allowed = EDITABLE.has(u.key) || (isAdmin && ADMIN_EDITABLE.has(u.key));
        if (!allowed) continue; // bỏ qua cột không cho sửa / không đủ quyền
        const id = Number(u.row);
        if (!Number.isFinite(id)) continue;
        let patch = byRow.get(id);
        if (!patch) { patch = {}; byRow.set(id, patch); }
        patch[COL[u.key]] = u.value === "" ? null : u.value;
      }
      if (byRow.size > 0) {
        const p_updates = Array.from(byRow, ([id, patch]) => ({ id, patch }));
        // Phạm vi quyền do RPC kiểm tra: có id nào ngoài phạm vi -> lỗi 42501,
        // KHÔNG ghi dòng nào (client vẫn giữ nguyên draft để thử lại).
        const { error } = await db.rpc("update_sale_target_cells", {
          p_updates, ...scopeParams(sess),
        });
        if (error) {
          if (String(error.message || "").includes("out_of_scope")) {
            return json({ ok: false, error: "forbidden_rows" }, 403);
          }
          throw new Error(error.message);
        }
      }
      return json({ ok: true, rev: await getRev(db) });
    }

    if (action === "deleteProduct") {
      // Xóa toàn bộ dòng của 1 sản phẩm (mọi tháng / mọi mức giá) theo danh sách id.
      // CHỈ admin. Front-end gửi payload.rows = [id, ...].
      if (sess.r !== "admin") return json({ ok: false, error: "forbidden" }, 403);
      const ids = (payload.rows || []).map(Number).filter((n) => Number.isFinite(n));
      if (!ids.length) return json({ ok: false, error: "no_rows" }, 400);
      const { error } = await db.from("sale_target").delete().in("id", ids);
      if (error) throw new Error(error.message);
      return json({ ok: true, rev: await getRev(db) });
    }

    if (action === "deleteCustomer") {
      // Xóa TOÀN BỘ kế hoạch của 1 khách hàng — CHỈ admin.
      // Client gửi payload.rows = [id, ...] (đúng những dòng nó đang có), nên không
      // phải đoán theo tên/mã KH. 1 KH có thể vài nghìn dòng mà .in() đi trong query
      // string -> phải xóa theo lô, không thì URL quá dài.
      if (sess.r !== "admin") return json({ ok: false, error: "forbidden" }, 403);
      const ids = (payload.rows || []).map(Number).filter((n) => Number.isFinite(n));
      if (!ids.length) return json({ ok: false, error: "no_rows" }, 400);
      const CHUNK = 200;
      for (let i = 0; i < ids.length; i += CHUNK) {
        const { error } = await db.from("sale_target").delete().in("id", ids.slice(i, i + CHUNK));
        if (error) throw new Error(error.message);
      }
      return json({ ok: true, deleted: ids.length, rev: await getRev(db) });
    }

    if (action === "addProduct") {
      if (!canEdit) return json({ ok: false, error: "forbidden" }, 403);
      const s = payload;
      // Lấy fy (năm tài chính) từ 1 dòng có sẵn
      const { data: any1 } = await db.from("sale_target").select("nam_tai_chinh").limit(1);
      const fy = any1 && any1[0] ? any1[0].nam_tai_chinh : "FY26";
      const MONTHS = ["2026-04","2026-05","2026-06","2026-07","2026-08","2026-09",
        "2026-10","2026-11","2026-12","2027-01","2027-02","2027-03"];
      // PS chỉ được thêm sản phẩm cho CHÍNH MÌNH: không tin payload.ps (client
      // có thể gửi tên PS khác). Admin thì giữ nguyên PS đã chọn trên giao diện.
      const psName = sess.r === "admin" ? s.ps : sess.s;
      // Đơn giá do client nhập tay (danh mục không còn giữ giá) → chặn NaN/chuỗi rác
      // lọt vào cột numeric; không nhập gì thì để NULL, KHÔNG phải 0.
      const priceNum = Number(s.price);
      const price = Number.isFinite(priceNum) && priceNum > 0 ? priceNum : null;
      // bu gắn theo PS ĐƯỢC CHỌN, không theo account tạo: admin/manager thêm hộ PS
      // của team khác thì gắn bu người tạo là gán sai team, dòng đó sẽ lọt vào báo
      // cáo của team sai. Suy bu từ chính dữ liệu kế hoạch của PS đó (PS chưa có
      // dòng nào → giữ bu của người tạo). PS ở nhiều team → chặn, không đoán.
      let bu;
      try {
        bu = await buForPs(db, psName, sess.b);
      } catch (e) {
        return json({ ok: false, error: String(e && e.message || e) }, 409);
      }
      const rowsIns = MONTHS.map((mo) => ({
        nam_tai_chinh: fy, thang_ke_hoach: mo, mien: s.region, ps: psName,
        khach_hang: s.cust, ma_khach_hang: s.custId, nhom_san_pham: s.grp,
        san_pham: s.prod, bo_vat_tu: s.mset, don_gia: price,
        bu,
        sl_ke_hoach_dau_nam: 0, sl_thuc_hien: 0,
      }));
      // Trả luôn 12 dòng vừa tạo (đúng thứ tự FIELDS) để app chèn thẳng vào state,
      // khỏi phải getData lại toàn bộ ~20k dòng sau mỗi lần thêm sản phẩm.
      const cols = FIELDS.map((f) => COL[f]).join(",") + ",id";
      const { data: ins, error } = await db.from("sale_target").insert(rowsIns).select(cols);
      if (error) throw new Error(error.message);
      const inserted = ins || [];
      return json({
        ok: true,
        rows: inserted.map((r) =>
          FIELDS.map((f) => {
            const v = r[COL[f]];
            return v === null || v === undefined ? "" : v;
          })
        ),
        rowNums: inserted.map((r) => r.id),
        rev: await getRev(db),
      });
    }

    // ---- CẤU HÌNH ĐỊA BÀN (dm_dia_ban) ----
    // (team, khách hàng, nhóm sản phẩm) -> PS phụ trách. Đọc: mọi role, theo đúng
    // phạm vi quyền như sale_target (dm_dia_ban dùng CÙNG tên cột bu/mien/ps/
    // nhom_san_pham nên applyScope() áp được nguyên xi).
    // Ghi: CHỈ admin — để PS tự gán địa bàn cho mình là tự mở rộng phạm vi quyền.
    if (action === "getDiaBan") {
      const out = [];
      for (let from = 0; ; from += PAGE) {
        let q = db.from("dm_dia_ban")
          .select("id, bu, ma_khach_hang, khach_hang, nhom_san_pham, mien, ps, active")
          .order("id", { ascending: true })
          .range(from, from + PAGE - 1);
        q = applyScope(q, sess, payload);
        const { data, error } = await q;
        if (error) throw new Error(error.message);
        if (!data || data.length === 0) break;
        for (const d of data) {
          out.push({
            id: d.id, bu: d.bu ?? "", custId: d.ma_khach_hang ?? "",
            cust: d.khach_hang ?? "", grp: d.nhom_san_pham ?? "",
            mien: d.mien ?? "", ps: d.ps ?? "", active: d.active !== false,
          });
        }
        if (data.length < PAGE) break;
      }
      return json({ ok: true, diaBan: out });
    }

    if (action === "saveDiaBan") {
      if (sess.r !== "admin") return json({ ok: false, error: "forbidden" }, 403);
      const rows = payload.rows || [];
      if (!rows.length) return json({ ok: false, error: "no_rows" }, 400);
      // bu chỉ cần cho dòng THÊM MỚI (dòng sửa giữ nguyên bu trong DB). Suy theo PS
      // được chọn, cache theo tên PS để không hỏi lại DB cho từng dòng cùng PS.
      const buCache = new Map();
      const p_rows = [];
      for (const r of rows) {
        const ps = String(r.ps || "").trim();
        const id = Number(r.id);
        let bu = "";
        if (!Number.isFinite(id)) {
          if (!buCache.has(ps)) {
            try {
              buCache.set(ps, await buForPs(db, ps, sess.b));
            } catch (e) {
              return json({ ok: false, error: String(e && e.message || e) }, 409);
            }
          }
          bu = buCache.get(ps) || "";
        }
        p_rows.push({
          id: Number.isFinite(id) ? id : null,
          bu,
          ma_khach_hang: r.custId ?? "",
          khach_hang: r.cust ?? "",
          nhom_san_pham: r.grp ?? "",
          mien: r.mien ?? "",
          ps,
          active: r.active !== false,
        });
      }
      const { data, error } = await db.rpc("upsert_dm_dia_ban", {
        p_rows, ...scopeParams(sess),
      });
      if (error) {
        const msg = String(error.message || "");
        if (msg.includes("out_of_scope")) return json({ ok: false, error: "forbidden_rows" }, 403);
        if (msg.includes("dup_dia_ban")) return json({ ok: false, error: "dup_dia_ban" }, 409);
        if (msg.includes("thieu_du_lieu")) return json({ ok: false, error: "thieu_du_lieu" }, 400);
        throw new Error(msg);
      }
      return json({ ok: true, stats: data });
    }

    if (action === "deleteDiaBan") {
      if (sess.r !== "admin") return json({ ok: false, error: "forbidden" }, 403);
      const ids = (payload.ids || []).map(Number).filter((n) => Number.isFinite(n));
      if (!ids.length) return json({ ok: false, error: "no_rows" }, 400);
      const { error } = await db.from("dm_dia_ban").delete().in("id", ids);
      if (error) throw new Error(error.message);
      // Xoá khai báo KHÔNG đụng tới dòng kế hoạch đã có (dữ liệu kế hoạch vẫn
      // thuộc PS cũ) → không cần trả rev.
      return json({ ok: true, deleted: ids.length });
    }

    if (action === "applyDiaBan") {
      if (sess.r !== "admin") return json({ ok: false, error: "forbidden" }, 403);
      const ids = (payload.ids || []).map(Number).filter((n) => Number.isFinite(n));
      if (!ids.length) return json({ ok: false, error: "no_rows" }, 400);
      // fromMonth rỗng/không gửi = áp dụng CẢ NĂM (kể cả tháng đã qua) — app phải
      // gửi tháng hiện tại nếu muốn giữ nguyên lịch sử khớp actual.
      const fromMonth = payload.fromMonth ? String(payload.fromMonth) : null;
      const { data, error } = await db.rpc("apply_dia_ban_to_plan", {
        p_ids: ids, p_from_month: fromMonth,
      });
      if (error) throw new Error(error.message);
      return json({ ok: true, stats: data, rev: await getRev(db) });
    }

    return json({ ok: false, error: "unknown_action" }, 400);
  } catch (err) {
    return json({ ok: false, error: String(err && err.message || err) }, 500);
  }
});