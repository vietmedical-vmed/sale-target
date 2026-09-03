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
// Lỗi từ các RPC địa bàn -> mã HTTP + nội dung cho app.
// Các lỗi CÓ CHI TIẾT (thiếu tháng nào, tháng nào không hợp lệ) trả nguyên văn
// message để người cấu hình biết phải sửa gì; loại còn lại trả khoá ngắn cho app dịch.
function diaBanErr(error) {
  const msg = String(error && error.message || "");
  if (msg.includes("out_of_scope")) return json({ ok: false, error: "forbidden_rows" }, 403);
  if (msg.includes("dup_dia_ban")) return json({ ok: false, error: "dup_dia_ban" }, 409);
  if (msg.includes("khoang_trong")) return json({ ok: false, error: msg }, 409);
  if (msg.includes("khong_ton_tai")) return json({ ok: false, error: "khong_ton_tai" }, 404);
  if (msg.includes("thang_khong_hop_le") || msg.includes("trung_ps")) {
    return json({ ok: false, error: msg }, 400);
  }
  if (msg.includes("thieu_du_lieu")) return json({ ok: false, error: "thieu_du_lieu" }, 400);
  return json({ ok: false, error: msg }, 500);
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
    n: payload.ho_ten ?? payload.n ?? payload.username ?? payload.u,
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
  act: "sl_thuc_hien", dt: "doanh_thu_kh_dau_nam", bu: "bu",
};
// Thứ tự field khi trả getData (app đọc theo fields[])
const FIELDS = ["fy","mo","region","ps","cust","custId","grp","prod","mset",
  "qOld","mMain","dMain","qMain","mAdd","qAdd","rev","revUpd","price","note","act","dt","bu"];
// Chỉ các cột này được phép sửa qua updateCells
const EDITABLE = new Set(["qOld","mMain","dMain","qMain","mAdd","qAdd","revUpd","note","price"]);
// Các cột nhận diện (bộ vật tư / sản phẩm) — CHỈ admin được sửa qua updateCells.
const ADMIN_EDITABLE = new Set(["mset","prod","rev","dt"]);

// Team dữ liệu DEMO/TRAINING — số của nó không phải số kinh doanh thật nên KHÔNG
// bao giờ được cộng chung với các team khác. Chỉ hiện khi nhìn đúng team đó:
// admin/manager chọn TEST trên TeamSwitcher, hoặc user có bu = TEST trong token.
const DEMO_BU = "test";
// Loại dòng demo ra khỏi truy vấn "xem nhiều team".
// Giữ lại dòng bu rỗng: bu null nghĩa là chưa gắn team, không phải dữ liệu demo
// (dùng .neq trần thì Postgres loại luôn cả null vì null <> 'test' ra null).
const excludeDemo = (q) => q.or(`bu.is.null,bu.neq.${DEMO_BU}`);

// Lọc dữ liệu theo quyền của user.
// - admin/manager: xem tất cả team (bu) TRỪ team demo; gửi payload.bu cụ thể → lọc theo team đó.
// - Các role khác: LUÔN khoá theo bu trong token (không được ghi đè bằng payload).
// - Sau đó lọc tiếp theo phạm vi hẹp hơn: area_manager theo Miền, ps theo PS.
function applyScope(query, sess, payload = {}) {
  const role = String(sess.r || "").toLowerCase(); // phòng DB trả role viết HOA ("ADMIN"/"PS"...)
  let q = query;

  // --- Khoá theo team (bu) ---
  if (role === "admin" || role === "manager") {
    if (payload && payload.bu) q = q.eq("bu", payload.bu); // admin/manager chọn xem 1 team cụ thể
    else q = excludeDemo(q); // "Tất cả team" = mọi team THẬT, không gộp dữ liệu demo
  } else if (role === "product_manager") {
    // PM quản theo NGÀNH HÀNG, xuyên suốt các team → KHÔNG khoá theo bu.
    // (Muốn giới hạn PM trong 1 team thì bỏ comment dòng dưới.)
    // q = q.eq("bu", sess.b);
    q = excludeDemo(q); // nhưng vẫn không lấy dữ liệu demo (PM không có TeamSwitcher để tách ra)
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
  const { data } = await db.schema("shared").from("sale_target")
    .select("updated_at").order("updated_at", { ascending: false }).limit(1);
  if (data && data[0] && data[0].updated_at) return Date.parse(data[0].updated_at);
  return 0;
}

async function writeAuditLog(db, sess, action, rowCount, details, thangKeHoach) {
  try {
    await db.schema("shared").from("audit_log").insert({
      username: sess.u,
      ho_ten: sess.n || sess.u,
      role: sess.r,
      bu: sess.b,
      action,
      row_count: rowCount,
      details: details || null,
      thang_ke_hoach: thangKeHoach || null,
    });
  } catch (_) { /* không để lỗi log làm gãy action chính */ }
}

// Suy team (bu) của một PS từ chính dữ liệu kế hoạch của họ.
// Dùng khi admin/manager tạo dữ liệu HỘ một PS (thêm SP, khai báo địa bàn): gắn bu
// của người tạo là gán sai team, dòng đó sẽ lọt vào báo cáo của team khác.
// 1 tên PS có dữ liệu ở nhiều team → KHÔNG đoán, ném lỗi để người dùng biết.
// Trả về `fallback` khi PS chưa có dòng kế hoạch nào.
// Danh mục PS (shared.dm_ps) — NGUỒN CHUẨN cho team/miền của một PS.
// Suy từ sale_target chỉ là phương án dự phòng: PS mới chưa có dòng kế hoạch nào
// thì không suy được gì, và PS xuất hiện ở nhiều team/miền thì không quyết được.
// bu_code = mã team khớp sale_target.bu ('chcs'…); dm_ps.bu là tên đầy đủ ('CH&CS').
async function psInfo(db, psName) {
  const key = String(psName || "").trim().toLowerCase();
  if (!key) return null;
  const { data, error } = await db.schema("shared").from("dm_ps")
    .select("ps, ten_ps, bu, bu_code, area, team, trang_thai").limit(500);
  if (error) return null; // dm_ps chưa có/chưa cấp quyền → rơi về cách suy cũ
  return (data || []).find((d) => String(d.ps || "").trim().toLowerCase() === key) || null;
}

async function buForPs(db, psName, fallback) {
  const info = await psInfo(db, psName);
  if (info && info.bu_code) return info.bu_code;
  const { data, error } = await db.schema("shared").from("sale_target")
    .select("bu").eq("ps", psName).not("bu", "is", null).limit(1000);
  if (error) throw new Error(error.message);
  const list = [...new Set((data || []).map((r) => r.bu).filter(Boolean))];
  if (list.length === 1) return list[0];
  if (list.length > 1) {
    throw new Error(
      `PS "${psName}" đang có dữ liệu ở ${list.length} team (${list.join(", ")}) ` +
      `và chưa có trong danh mục PS (dm_ps) — không xác định được team để gắn cho dòng mới`,
    );
  }
  return fallback;
}

// Suy MIỀN của một PS từ dữ liệu kế hoạch. Miền là thuộc tính của PS, không phải
// trường nhập tay ở màn cấu hình địa bàn → server tự quyết, không tin client.
// Trả null khi không xác định được (PS chưa có dòng kế hoạch, hoặc đang có mặt ở
// nhiều miền) — caller hiểu là "giữ nguyên miền đang lưu".
async function mienForPs(db, psName) {
  const info = await psInfo(db, psName);
  if (info && info.area) return info.area; // dm_ps.area = miền của PS
  const { data, error } = await db.schema("shared").from("sale_target")
    .select("mien").eq("ps", psName).not("mien", "is", null).limit(1000);
  if (error) throw new Error(error.message);
  const list = [...new Set((data || []).map((r) => r.mien).filter(Boolean))];
  return list.length === 1 ? list[0] : null;
}

// Đọc TẤT CẢ dòng (PostgREST giới hạn 1000/lần → phân trang).
// Tối ưu: đếm tổng số dòng trước, rồi TẢI CÁC TRANG SONG SONG (thay vì tuần tự)
// để giảm mạnh thời gian chờ khi dữ liệu lớn (vd ~20k dòng = 21 trang).
const PAGE = 1000;      // = max_rows của PostgREST (config.toml) → không được vượt
const CONCURRENCY = 6;  // số trang tải đồng thời

async function fetchAll(db, sess, payload) {
  const cols = FIELDS.map((f) => COL[f]).join(",") + ",id";

  // 1) Đếm số dòng trong phạm vi quyền của user (head:true → không kéo data).
  let countQ = db.schema("shared").from("sale_target").select("id", { count: "exact", head: true });
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
      let q = db.schema("shared").from("sale_target").select(cols)
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
// Giữ NGUYÊN khách hàng thật của dòng thực hiện: app gom tất cả vào 1 nhóm
// "Ngoài kế hoạch" (nhận biết qua mảng oopRows riêng), bên dưới tách theo từng KH.
const OOP_CUST = "Ngoài kế hoạch";

async function fetchOutOfPlan(db, sess, payload) {
  const out = [];
  for (let from = 0; ; from += PAGE) {
    let q = db.schema("app_sale").from("v_actual_ngoai_ke_hoach")
      .select("thang_ke_hoach,mien,ps,ma_khach_hang,khach_hang,bu,nhom_san_pham,bo_vat_tu,san_pham,sl_thuc_hien,don_gia,ly_do,ps_dia_ban")
      .range(from, from + PAGE - 1);
    q = applyScope(q, sess, payload); // cùng phân quyền như sale_target
    const { data, error } = await q;
    if (error) throw new Error(error.message);
    out.push(...(data || []));
    if (!data || data.length < PAGE) break;
  }
  // Trả 2 mảng SONG SONG: rows (chuẩn theo FIELDS) + meta (ngoài FIELDS).
  // ly_do/ps_dia_ban không nằm trong FIELDS — nhét vào FIELDS sẽ làm mọi chỗ đọc
  // theo index bị đẩy; app tự đọc oopMeta[i] theo đúng chỉ số i của oopRows.
  const rows = out.map((r) => {
    const o = {
      mo: r.thang_ke_hoach, region: r.mien, ps: r.ps,
      cust: r.khach_hang || OOP_CUST, custId: r.ma_khach_hang,
      grp: r.nhom_san_pham, prod: r.san_pham,
      mset: r.bo_vat_tu, act: r.sl_thuc_hien,
      price: r.don_gia, bu: r.bu,
    };
    return FIELDS.map((f) => (o[f] === null || o[f] === undefined ? "" : o[f]));
  });
  const meta = out.map((r) => ({
    ly_do: r.ly_do || "",
    ps_dia_ban: r.ps_dia_ban || "",
  }));
  return { rows, meta };
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
  // Ai được SỬA số liệu (updateCells / addProduct). PHẠM VI ghi của từng role do
  // scopeParams() quyết định, không phải cờ này: manager mọi team, area_manager
  // trong bu + miền của mình, ps trong PS của mình.
  // product_manager KHÔNG có trong danh sách: họ theo dõi ngành hàng xuyên team,
  // không sở hữu số của PS nào nên chỉ xem.
  // Xoá dòng và cấu hình địa bàn vẫn CHỈ admin (gác riêng ở từng action).
  const canEdit = ["admin", "ps", "manager", "area_manager"].includes(sess.r);

  try {
    if (action === "ping") {
      return json({ ok: true, role: sess.r, scope: sess.s, bu: sess.b, username: sess.u });
    }

    if (action === "getData") {
      // fetchAll / fetchOutOfPlan / getRev độc lập → chạy song song để tiết kiệm lượt chờ.
      // fetchOutOfPlan hỏng KHÔNG được làm sập getData (vd view chưa tạo) → nuốt lỗi, trả [].
      const [dbRows, oop, rev] = await Promise.all([
        fetchAll(db, sess, payload),
        fetchOutOfPlan(db, sess, payload).catch(() => ({ rows: [], meta: [] })),
        getRev(db),
      ]);
      const rows = dbRows.map((r) => FIELDS.map((f) => {
        const v = r[COL[f]];
        return v === null || v === undefined ? "" : v;
      }));
      const rowNums = dbRows.map((r) => r.id);
      return json({
        ok: true, fields: FIELDS, rows, rowNums,
        oopRows: oop.rows, oopMeta: oop.meta, rev,
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
        const { data, error } = await db.schema("shared").from("dm_bo_vat_tu_mapping")
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
        const { data, error } = await db.schema("shared").from("dm_khach_hang")
          .select("customer_id, customer_name, customer_alias")
          .order("customer_id", { ascending: true })
          .range(from, from + PAGE - 1);
        if (error) throw new Error(error.message);
        if (!data || data.length === 0) break;
        // cust = tên gốc (dùng làm khoá & lưu khi thêm SP); alias = tên hiển thị rút gọn.
        for (const c of data) out.push({ custId: c.customer_id ?? "", cust: c.customer_name ?? "", alias: String(c.customer_alias ?? "").trim() });
        if (data.length < PAGE) break;
      }
      const customers = out.filter((c) => c.cust || c.custId);
      return json({ ok: true, customers });
    }

    // Danh mục PS (shared.dm_ps) — nguồn của dropdown PS, miền và team.
    // Trước đây app suy PS/miền từ chính dữ liệu kế hoạch nên PS mới (chưa có dòng
    // nào) không xuất hiện ở đâu cả → không khai báo địa bàn trước cho họ được.
    // Phạm vi: ps chỉ thấy mình, area_manager thấy miền mình; admin/manager có thể
    // giới hạn theo team đang xem (payload.bu).
    if (action === "getPs") {
      const { data, error } = await db.schema("shared").from("dm_ps")
        .select("ps, ten_ps, bu, bu_code, area, team, trang_thai")
        .order("ps", { ascending: true }).limit(1000);
      if (error) throw new Error(error.message);
      let list = (data || []).map((d) => ({
        ps: d.ps ?? "", tenPs: d.ten_ps ?? "",
        bu: d.bu_code ?? "", buLabel: d.bu ?? "",
        mien: d.area ?? "", team: d.team ?? "",
        active: String(d.trang_thai || "").toLowerCase() !== "inactive",
      })).filter((p) => p.ps);
      const role = sess.r;
      if (role === "ps") list = list.filter((p) => p.ps === sess.s);
      else if (role === "area_manager") list = list.filter((p) => p.mien === sess.s);
      else if ((role === "admin" || role === "manager") && payload.bu) {
        list = list.filter((p) => p.bu === payload.bu);
      }
      return json({ ok: true, ps: list });
    }

    // Bổ sung / sửa danh mục PS (shared.dm_ps). Chỉ admin — vì thêm PS = mở
    // quyền cho một tên mới trong hệ thống. Dùng khi ly_do='ps_la' (hoá đơn có
    // ten_ps không nằm trong dm_ps → dịch không được, số rơi ngoài kế hoạch).
    // p_id null = thêm mới; có id = sửa tên rút gọn (không đổi ten_ps: cột đó
    // là khoá dịch với hoá đơn, đổi = mất khớp hàng loạt).
    if (action === "savePs") {
      if (sess.r !== "admin") return json({ ok: false, error: "forbidden" }, 403);
      const p = payload || {};
      const ten = String(p.tenPs || "").trim(); // tên đầy đủ trong hoá đơn (khoá dịch)
      const ps  = String(p.ps || "").trim();     // tên rút gọn (khớp sale_target.ps)
      if (!ten || !ps) return json({ ok: false, error: "thieu_du_lieu" }, 400);
      const bu_code = String(p.buCode || "").trim().toLowerCase();
      const known = new Set(["chcs", "cttm", "thnk", "test"]);
      if (bu_code && !known.has(bu_code)) {
        return json({ ok: false, error: `bu_code không hợp lệ: ${bu_code}` }, 400);
      }
      const row = {
        ten_ps: ten, ps, bu: p.bu || null, bu_code: bu_code || null,
        area: p.mien || null, team: p.team || null,
        trang_thai: p.active === false ? "Inactive" : "Active",
      };
      // upsert theo ten_ps: có rồi → cập nhật, chưa có → thêm mới. Không đổi
      // ten_ps để không mất khớp với hoá đơn cũ. Tên rút gọn 'ps' đổi được:
      // sau khi đổi, chạy lại map_hoadon để số về đúng dòng kế hoạch mới.
      const q = db.schema("shared").from("dm_ps");
      const { data: existed } = await q.select("ten_ps").eq("ten_ps", ten).limit(1);
      const { error } = existed && existed.length
        ? await q.update(row).eq("ten_ps", ten)
        : await q.insert(row);
      if (error) {
        const msg = String(error.message || "");
        if (msg.includes("duplicate") || msg.includes("unique"))
          return json({ ok: false, error: "dup_ps" }, 409);
        return json({ ok: false, error: msg }, 500);
      }
      return json({ ok: true });
    }

    // Chỉ tải dòng ngoài kế hoạch (không đụng sale_target ~20k dòng). Dùng sau
    // khi sửa hoá đơn: view hoa_don_actual/v_actual_ngoai_ke_hoach tự cập nhật,
    // chỉ cần lấy lại mảng OOP + meta.
    if (action === "getOop") {
      const oop = await fetchOutOfPlan(db, sess, payload).catch(() => ({ rows: [], meta: [] }));
      return json({ ok: true, oopRows: oop.rows, oopMeta: oop.meta, rev: await getRev(db) });
    }

    // Sửa PS hàng loạt trong hoá đơn theo PS địa bàn — chỉ admin. Dùng cho nút
    // "Sửa tất cả sai_ps" ở modal Đối chiếu ngoài kế hoạch: update tất cả tổ
    // hợp trong 1 lượt, map + refresh 1 lần cuối (thay vì gọi single 87 lần).
    if (action === "suaPsHoaDonBulk") {
      if (sess.r !== "admin") return json({ ok: false, error: "forbidden" }, 403);
      const rows = (payload && payload.rows) || [];
      if (!rows.length) return json({ ok: false, error: "no_rows" }, 400);
      const p_rows = rows.map((r) => ({
        thang:      String(r.thang || ""),
        ma_kh:      String(r.maKh || ""),
        bo_vat_tu:  String(r.boVatTu || ""),
        san_pham:   String(r.sanPham || ""),
        ps_cu:      String(r.psCu || ""),
        ps_moi:     String(r.psMoi || ""),
      })).filter((r) => r.thang && r.ma_kh && r.ps_moi);
      if (!p_rows.length) return json({ ok: false, error: "no_rows" }, 400);
      const { data, error } = await db.rpc("sua_ps_hoa_don_bulk", { p_rows });
      if (error) {
        const msg = String(error.message || "");
        if (msg.includes("thieu_du_lieu")) return json({ ok: false, error: msg }, 400);
        return json({ ok: false, error: msg }, 500);
      }
      return json({ ok: true, stats: data, rev: await getRev(db) });
    }

    // Sửa PS trong hoá đơn theo PS địa bàn — chỉ admin. Dùng cho action ở modal
    // Đối chiếu ngoài kế hoạch với ly_do='sai_ps'. Backend gọi RPC làm cả update
    // hoa_don_bovattu.ten_ps + map + refresh trong 1 transaction.
    if (action === "suaPsHoaDon") {
      if (sess.r !== "admin") return json({ ok: false, error: "forbidden" }, 403);
      const p = payload || {};
      if (!p.thang || !p.maKh || !p.psMoi) {
        return json({ ok: false, error: "thieu_du_lieu" }, 400);
      }
      const { data, error } = await db.rpc("sua_ps_hoa_don", {
        p_thang:     String(p.thang),
        p_ma_kh:     String(p.maKh),
        p_bo_vat_tu: String(p.boVatTu || ""),
        p_san_pham:  String(p.sanPham || ""),
        p_ps_cu:     String(p.psCu || ""),
        p_ps_moi:    String(p.psMoi),
      });
      if (error) {
        const msg = String(error.message || "");
        if (msg.includes("ps_khong_ton_tai")) return json({ ok: false, error: msg }, 404);
        if (msg.includes("thieu_du_lieu"))    return json({ ok: false, error: msg }, 400);
        return json({ ok: false, error: msg }, 500);
      }
      return json({ ok: true, stats: data, rev: await getRev(db) });
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
        const { error } = await db.rpc("update_sale_target_cells", {
          p_updates, ...scopeParams(sess),
        });
        if (error) {
          if (String(error.message || "").includes("out_of_scope")) {
            return json({ ok: false, error: "forbidden_rows" }, 403);
          }
          throw new Error(error.message);
        }
        const cols = new Set();
        for (const u of updates) if (EDITABLE.has(u.key) || ADMIN_EDITABLE.has(u.key)) cols.add(u.key);
        await writeAuditLog(db, sess, "updateCells", byRow.size, {
          columns: [...cols],
          ids: [...byRow.keys()].slice(0, 50),
        });
      }
      return json({ ok: true, rev: await getRev(db) });
    }

    if (action === "deleteProduct") {
      if (sess.r !== "admin") return json({ ok: false, error: "forbidden" }, 403);
      const ids = (payload.rows || []).map(Number).filter((n) => Number.isFinite(n));
      if (!ids.length) return json({ ok: false, error: "no_rows" }, 400);
      const { error } = await db.schema("shared").from("sale_target").delete().in("id", ids);
      if (error) throw new Error(error.message);
      await writeAuditLog(db, sess, "deleteProduct", ids.length, { ids: ids.slice(0, 50) });
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
        const { error } = await db.schema("shared").from("sale_target").delete().in("id", ids.slice(i, i + CHUNK));
        if (error) throw new Error(error.message);
      }
      await writeAuditLog(db, sess, "deleteCustomer", ids.length, { ids: ids.slice(0, 50) });
      return json({ ok: true, deleted: ids.length, rev: await getRev(db) });
    }

    if (action === "addProduct") {
      if (!canEdit) return json({ ok: false, error: "forbidden" }, 403);
      const s = payload;
      // Lấy fy (năm tài chính) từ 1 dòng có sẵn
      const { data: any1 } = await db.schema("shared").from("sale_target").select("nam_tai_chinh").limit(1);
      const fy = any1 && any1[0] ? any1[0].nam_tai_chinh : "FY26";
      const MONTHS = ["2026-04","2026-05","2026-06","2026-07","2026-08","2026-09",
        "2026-10","2026-11","2026-12","2027-01","2027-02","2027-03"];
      // PS chỉ được thêm sản phẩm cho CHÍNH MÌNH: không tin payload.ps (client
      // có thể gửi tên PS khác). Các role còn lại lấy PS đã chọn trên giao diện —
      // scope của admin/manager/area_manager không phải tên PS nên không thay thế
      // được (lấy sess.s sẽ ghi ps = "Quản lý" / "Miền Bắc" vào dữ liệu).
      const psName = sess.r === "ps" ? sess.s : String(s.ps || "").trim();
      if (!psName) return json({ ok: false, error: "Chưa chọn PS phụ trách" }, 400);
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
      // area_manager chỉ thêm được cho PS trong ĐÚNG team + miền của mình —
      // không tin danh sách PS phía client. PS chưa có dòng nào (miền suy ra null)
      // thì cho qua, dòng mới sẽ nằm trong miền của chính area_manager.
      if (sess.r === "area_manager") {
        const psMien = await mienForPs(db, psName);
        if (bu !== sess.b || (psMien && psMien !== sess.s)) {
          return json({
            ok: false,
            error: `PS "${psName}" không thuộc phạm vi của bạn (${sess.b} / ${sess.s})`,
          }, 403);
        }
      }
      // Miền của area_manager do server quyết, không lấy theo client gửi lên: gửi
      // miền khác là dòng mới rơi ra ngoài tầm nhìn của chính họ.
      // Popup "Thêm khách hàng" không còn ô Miền → client có thể gửi rỗng, suy từ PS.
      let mien = sess.r === "area_manager" ? sess.s : String(s.region || "").trim();
      if (!mien) mien = await mienForPs(db, psName);
      // Tháng thầu (không bắt buộc) — thuộc tính của NHÓM SP nên ghi lên cả 12 dòng,
      // giống commitGroupField ở client. Sai định dạng yyyy-mm thì bỏ qua, để null.
      const thangThau = (v) => {
        const t = String(v || "").trim();
        return /^\d{4}-\d{2}$/.test(t) ? t : null;
      };
      const rowsIns = MONTHS.map((mo) => ({
        nam_tai_chinh: fy, thang_ke_hoach: mo, mien, ps: psName,
        thang_thau_chinh: thangThau(s.mMain), thang_thau_bo_sung: thangThau(s.mAdd),
        khach_hang: s.cust, ma_khach_hang: s.custId, nhom_san_pham: s.grp,
        san_pham: s.prod, bo_vat_tu: s.mset, don_gia: price,
        bu,
        sl_ke_hoach_dau_nam: 0, sl_thuc_hien: 0,
      }));
      // Trả luôn 12 dòng vừa tạo (đúng thứ tự FIELDS) để app chèn thẳng vào state,
      // khỏi phải getData lại toàn bộ ~20k dòng sau mỗi lần thêm sản phẩm.
      const cols = FIELDS.map((f) => COL[f]).join(",") + ",id";
      const { data: ins, error } = await db.schema("shared").from("sale_target").insert(rowsIns).select(cols);
      if (error) throw new Error(error.message);
      const inserted = ins || [];
      await writeAuditLog(db, sess, "addProduct", inserted.length, {
        ps: psName, cust: s.cust, grp: s.grp, prod: s.prod, mset: s.mset, bu,
      });
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
        let q = db.schema("shared").from("dm_dia_ban")
          .select("id, bu, ma_khach_hang, khach_hang, nhom_san_pham, mien, ps, active, tu_thang, den_thang")
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
            tuThang: d.tu_thang ?? "", denThang: d.den_thang ?? "",
          });
        }
        if (data.length < PAGE) break;
      }
      return json({ ok: true, diaBan: out });
    }

    if (action === "saveDiaBan") {
      if (sess.r !== "admin" && sess.r !== "manager") return json({ ok: false, error: "forbidden" }, 403);
      const rows = payload.rows || [];
      if (!rows.length) return json({ ok: false, error: "no_rows" }, 400);
      // Miền của dòng sửa: nếu không suy được theo PS thì giữ nguyên giá trị đang lưu
      // (RPC ghi thẳng cột mien) → đọc trước 1 lượt cho các id được sửa.
      const ids = rows.map((r) => Number(r.id)).filter((n) => Number.isFinite(n));
      const oldMien = new Map();
      if (ids.length) {
        const { data, error } = await db.schema("shared").from("dm_dia_ban").select("id, mien").in("id", ids);
        if (error) throw new Error(error.message);
        for (const d of data || []) oldMien.set(d.id, d.mien ?? "");
      }
      // bu chỉ cần cho dòng THÊM MỚI (dòng sửa giữ nguyên bu trong DB). bu/miền đều
      // suy theo PS được chọn, cache theo tên PS để không hỏi lại DB cho từng dòng.
      const buCache = new Map();
      const mienCache = new Map();
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
        if (!mienCache.has(ps)) mienCache.set(ps, await mienForPs(db, ps));
        p_rows.push({
          id: Number.isFinite(id) ? id : null,
          bu,
          ma_khach_hang: r.custId ?? "",
          khach_hang: r.cust ?? "",
          nhom_san_pham: r.grp ?? "",
          // KHÔNG dùng r.mien: miền do server suy theo PS.
          mien: mienCache.get(ps) || oldMien.get(id) || "",
          ps,
          active: r.active !== false,
          // Khoảng hiệu lực: thêm mới không gửi thì RPC lấy đầu năm tài chính;
          // dòng sửa không gửi thì giữ nguyên khoảng đang có.
          tu_thang: r.tuThang ?? "",
          den_thang: r.denThang ?? "",
        });
      }
      const { data, error } = await db.rpc("upsert_dm_dia_ban", {
        p_rows, ...scopeParams(sess),
      });
      if (error) return diaBanErr(error);
      await writeAuditLog(db, sess, "saveDiaBan", p_rows.length, { count: p_rows.length });
      return json({ ok: true, stats: data });
    }

    // Chuyển địa bàn sang PS khác TỪ MỘT THÁNG: đóng bản cũ + mở bản mới.
    // Đây là đường dùng khi đổi người phụ trách giữa năm — tháng cũ giữ PS cũ.
    if (action === "chuyenDiaBan") {
      if (sess.r !== "admin" && sess.r !== "manager") return json({ ok: false, error: "forbidden" }, 403);
      const id = Number(payload.id);
      const psMoi = String(payload.ps || "").trim();
      const tuThang = String(payload.tuThang || "").trim();
      if (!Number.isFinite(id) || !psMoi || !tuThang) {
        return json({ ok: false, error: "thieu_du_lieu" }, 400);
      }
      const sc = scopeParams(sess);
      const { data, error } = await db.rpc("chuyen_dia_ban", {
        p_id: id,
        p_ps_moi: psMoi,
        p_mien: await mienForPs(db, psMoi), // miền theo PS mới, không tin client
        p_tu_thang: tuThang,
        p_bu: sc.p_bu,
        p_mien_scope: sc.p_mien,
        p_ps_scope: sc.p_ps,
        p_groups: sc.p_groups,
      });
      if (error) return diaBanErr(error);
      return json({ ok: true, stats: data });
    }

    // Dọn tổ hợp KH×ngành hàng có nhiều PS chồng lấn — theo bản đang hiệu lực
    // của tháng do app truyền lên (thường = CURRENT_MONTH). Chỉ admin.
    if (action === "dopChongLan") {
      if (sess.r !== "admin") return json({ ok: false, error: "forbidden" }, 403);
      const thang = String((payload && payload.thang) || "").trim();
      if (!/^\d{4}-\d{2}$/.test(thang)) {
        return json({ ok: false, error: "thang_khong_hop_le" }, 400);
      }
      const { data, error } = await db.rpc("dep_dia_ban_chong_lan", { p_thang: thang });
      if (error) {
        const msg = String(error.message || "");
        if (msg.includes("thang_khong_hop_le")) return json({ ok: false, error: msg }, 400);
        return json({ ok: false, error: msg }, 500);
      }
      return json({ ok: true, stats: data, rev: await getRev(db) });
    }

    if (action === "deleteDiaBan") {
      if (sess.r !== "admin" && sess.r !== "manager") return json({ ok: false, error: "forbidden" }, 403);
      const ids = (payload.ids || []).map(Number).filter((n) => Number.isFinite(n));
      if (!ids.length) return json({ ok: false, error: "no_rows" }, 400);
      // Qua RPC (không phải .delete() trực tiếp) để việc kiểm khoảng trống nằm
      // trong CÙNG giao dịch với lệnh xóa.
      const { data, error } = await db.rpc("delete_dm_dia_ban", {
        p_ids: ids, ...scopeParams(sess),
      });
      if (error) return diaBanErr(error);
      await writeAuditLog(db, sess, "deleteDiaBan", ids.length, { ids: ids.slice(0, 50) });
      return json({ ok: true, stats: data });
    }

    if (action === "applyDiaBan") {
      if (sess.r !== "admin" && sess.r !== "manager") return json({ ok: false, error: "forbidden" }, 403);
      const ids = (payload.ids || []).map(Number).filter((n) => Number.isFinite(n));
      if (!ids.length) return json({ ok: false, error: "no_rows" }, 400);
      // Không còn tham số tháng: mỗi bản khai báo chỉ ghi vào các tháng nó phủ.
      const { data, error } = await db.rpc("apply_dia_ban_to_plan", { p_ids: ids });
      if (error) throw new Error(error.message);
      return json({ ok: true, stats: data, rev: await getRev(db) });
    }

    // ---- LỊCH SỬ CẬP NHẬT & CẤU HÌNH ----
    if (action === "getAuditLog") {
      if (sess.r !== "admin" && sess.r !== "manager") return json({ ok: false, error: "forbidden" }, 403);
      const page = Math.max(1, Number(payload.page) || 1);
      const limit = Math.min(100, Math.max(1, Number(payload.limit) || 50));
      const from = (page - 1) * limit;
      let q = db.schema("shared").from("audit_log")
        .select("*", { count: "exact" })
        .order("created_at", { ascending: false })
        .range(from, from + limit - 1);
      if (payload.username) q = q.eq("username", payload.username);
      if (payload.action) q = q.eq("action", payload.action);
      if (payload.bu) q = q.eq("bu", payload.bu);
      if (payload.from) q = q.gte("created_at", payload.from);
      if (payload.to) q = q.lte("created_at", payload.to);
      const { data, error, count } = await q;
      if (error) throw new Error(error.message);
      return json({ ok: true, logs: data || [], total: count || 0, page, limit });
    }

    if (action === "getAppConfig") {
      if (sess.r !== "admin" && sess.r !== "manager") return json({ ok: false, error: "forbidden" }, 403);
      const { data, error } = await db.schema("shared").from("app_config").select("key, value");
      if (error) throw new Error(error.message);
      const cfg = {};
      for (const r of data || []) cfg[r.key] = r.value;
      return json({ ok: true, config: cfg });
    }

    if (action === "setAppConfig") {
      if (sess.r !== "admin") return json({ ok: false, error: "forbidden" }, 403);
      const key = String(payload.key || "").trim();
      if (!key) return json({ ok: false, error: "missing_key" }, 400);
      const { error } = await db.schema("shared").from("app_config")
        .upsert({ key, value: payload.value, updated_at: new Date().toISOString() }, { onConflict: "key" });
      if (error) throw new Error(error.message);
      await writeAuditLog(db, sess, "setAppConfig", 1, { key, value: payload.value });
      return json({ ok: true });
    }

    return json({ ok: false, error: "unknown_action" }, 400);
  } catch (err) {
    return json({ ok: false, error: String(err && err.message || err) }, 500);
  }
});