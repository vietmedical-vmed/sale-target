import { createClient } from "https://esm.sh/@supabase/supabase-js@2.49.1";
import type { Session } from "../_shared/auth.ts";
import { json } from "../_shared/cors.ts";
import { COL, FIELDS, PAGE, CONCURRENCY } from "./config.ts";
import { applyScope, readScopeParams, parseGroups, mienScope, scopeParams } from "./scope.ts";

export function diaBanErr(error: { message?: string }, req?: Request) {
  const msg = String(error && error.message || "");
  if (msg.includes("out_of_scope")) return json({ ok: false, error: "forbidden_rows" }, 403, req);
  if (msg.includes("dup_dia_ban")) return json({ ok: false, error: "dup_dia_ban" }, 409, req);
  if (msg.includes("khoang_trong")) return json({ ok: false, error: msg }, 409, req);
  if (msg.includes("khong_ton_tai")) return json({ ok: false, error: "khong_ton_tai" }, 404, req);
  if (msg.includes("thang_khong_hop_le") || msg.includes("trung_ps")) {
    return json({ ok: false, error: msg }, 400, req);
  }
  if (msg.includes("thieu_du_lieu")) return json({ ok: false, error: "thieu_du_lieu" }, 400, req);
  return json({ ok: false, error: msg }, 500, req);
}

// PS tự khai báo địa bàn: chỉ được THÊM bản mới cho CHÍNH MÌNH, và chỉ cho tổ hợp
// (KH × ngành hàng) chưa có PS khác — kể cả trong dm_dia_ban lẫn trên dòng kế hoạch.
// Lý do: upsert_dm_dia_ban tự apply_dia_ban_to_plan, ghi PS xuống MỌI dòng kế hoạch
// của tổ hợp; nếu PS khác đang có kế hoạch ở đó thì sẽ bị "cướp" dòng.
// Sửa/xoá/chuyển địa bàn vẫn chỉ admin/manager. Ghi đè ps/active trên `rows`.
// Trả { status, error } khi phải chặn, null khi hợp lệ.
export async function kiemTraPsThemDiaBan(
  db: ReturnType<typeof createClient>,
  sess: Session,
  rows: Record<string, unknown>[],
): Promise<{ status: number; error: string } | null> {
  const me = String(sess.s || "").trim();
  for (const r of rows) {
    if (r.id != null && r.id !== "") return { status: 403, error: "forbidden_rows" };
    const ps = String(r.ps || "").trim();
    if (ps && ps !== me) return { status: 403, error: "forbidden_rows" };
    r.ps = me;
    r.active = true;
  }
  let bu: string;
  try {
    bu = await buForPs(db, me, sess.b);
  } catch (e) {
    return { status: 409, error: String(e && (e as Error).message || e) };
  }
  const keyOf = (custId: unknown, cust: unknown) =>
    String(custId || "").trim() || String(cust || "").trim();
  const want = new Map<string, string>(); // custKey||grp -> nhãn hiển thị
  for (const r of rows) {
    const k = keyOf(r.custId, r.cust);
    const g = String(r.grp || "").trim();
    if (k && g) want.set(`${k}||${g}`, `${String(r.cust || k)} · ${g}`);
  }
  if (!want.size) return null; // thiếu dữ liệu → để upsert_dm_dia_ban báo thieu_du_lieu
  const keys = [...new Set([...want.keys()].map((x) => x.split("||")[0]))];
  const grps = [...new Set([...want.keys()].map((x) => x.split("||")[1]))];

  const conflict = new Map<string, Set<string>>(); // custKey||grp -> PS khác
  const add = (k: string, ps: unknown) => {
    if (!want.has(k)) return;
    let s = conflict.get(k);
    if (!s) conflict.set(k, s = new Set());
    s.add(String(ps));
  };

  const { data: dbs, error: e1 } = await db.schema("shared").from("dm_dia_ban")
    .select("cust_key, nhom_san_pham, ps")
    .eq("bu", bu).in("cust_key", keys).in("nhom_san_pham", grps).neq("ps", me);
  if (e1) throw new Error(e1.message);
  for (const d of dbs || []) add(`${d.cust_key}||${d.nhom_san_pham}`, d.ps);

  // Khớp dòng kế hoạch y như apply_dia_ban_to_plan: coalesce(nullif(ma_khach_hang,''), khach_hang).
  const ids = keys.filter((k) => rows.some((r) => String(r.custId || "").trim() === k));
  const names = keys.filter((k) => !ids.includes(k));
  const scan = async (col: "ma_khach_hang" | "khach_hang", vals: string[]) => {
    if (!vals.length) return;
    const { data, error } = await db.schema("shared").from("sale_target")
      .select("ma_khach_hang, khach_hang, nhom_san_pham, ps")
      .eq("bu", bu).in(col, vals).in("nhom_san_pham", grps).neq("ps", me)
      .limit(5000);
    if (error) throw new Error(error.message);
    for (const s of data || []) {
      const k = keyOf(s.ma_khach_hang, s.khach_hang);
      add(`${k}||${s.nhom_san_pham}`, s.ps);
    }
  };
  await scan("ma_khach_hang", ids);
  await scan("khach_hang", names);

  if (!conflict.size) return null;
  const list = [...conflict].map(([k, s]) => `${want.get(k)} (PS ${[...s].join(", ")})`);
  return {
    status: 409,
    error: `da_co_ps_khac: ${list.slice(0, 5).join("; ")}${list.length > 5 ? ` … và ${list.length - 5} tổ hợp khác` : ""}`,
  };
}

export function admin() {
  return createClient(
    Deno.env.get("SUPABASE_URL") ?? "",
    Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "",
  );
}

export async function getRev(
  db: ReturnType<typeof createClient>,
  sess: Session | null,
  payload?: Record<string, unknown>,
) {
  let q = db.schema("shared").from("sale_target").select("_rev");
  if (sess) q = applyScope(q, sess, payload);
  q = q.order("_rev", { ascending: false }).limit(1);
  const { data } = await q;
  const saleRev = data && data[0] ? Number(data[0]._rev) || 0 : 0;

  let tq = db.schema("shared").from("sale_target_tombstone").select("_rev")
    .order("_rev", { ascending: false }).limit(1);
  if (sess) tq = applyScopeTombstone(tq, sess, payload);
  const { data: tData } = await tq;
  const tombRev = tData && tData[0] ? Number(tData[0]._rev) || 0 : 0;

  return Math.max(saleRev, tombRev);
}

export function applyScopeTombstone(
  query: ReturnType<SupabaseClient["from"]>,
  sess: Session,
  payload: Record<string, unknown> = {},
) {
  const role = String(sess.r || "").toLowerCase();
  const nhoms = parseGroups(sess.g);
  let q = query;

  if (role === "admin" || role === "manager") {
    if (payload && payload.bu) q = q.eq("bu", payload.bu as string);
  } else if (role === "product_manager") {
    const raw = parseGroups(sess.s);
    const groups = nhoms.length
      ? (raw.length ? raw.filter((g) => nhoms.includes(g)) : nhoms)
      : raw;
    if (groups.length === 0) return q.eq("nhom_san_pham", "__none__");
    return groups.length > 1 ? q.in("nhom_san_pham", groups) : q.eq("nhom_san_pham", groups[0]);
  } else {
    q = q.eq("bu", sess.b);
    if (role === "area_manager") {
      const miens = mienScope(sess);
      q = miens.length > 1 ? q.in("mien", miens) : q.eq("mien", miens[0] ?? "__none__");
    }
    else q = q.eq("ps", sess.s);
  }

  if (nhoms.length && role !== "product_manager") {
    q = nhoms.length > 1 ? q.in("nhom_san_pham", nhoms) : q.eq("nhom_san_pham", nhoms[0]);
  }
  return q;
}

export async function writeAuditLog(
  db: ReturnType<typeof createClient>,
  sess: Session,
  action: string,
  rowCount: number,
  details?: Record<string, unknown> | null,
  thangKeHoach?: string | null,
) {
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

export async function psInfo(db: ReturnType<typeof createClient>, psName: string) {
  const key = String(psName || "").trim().toLowerCase();
  if (!key) return null;
  const { data, error } = await db.schema("shared").from("dm_ps")
    .select("ps, ten_ps, bu, bu_code, area, team, trang_thai").limit(500);
  if (error) return null;
  return (data || []).find((d: Record<string, unknown>) =>
    String(d.ps || "").trim().toLowerCase() === key
  ) || null;
}

export async function buForPs(
  db: ReturnType<typeof createClient>,
  psName: string,
  fallback: string,
) {
  const info = await psInfo(db, psName);
  if (info && info.bu_code) return info.bu_code;
  const { data, error } = await db.schema("shared").from("sale_target")
    .select("bu").eq("ps", psName).not("bu", "is", null).limit(1000);
  if (error) throw new Error(error.message);
  const list = [...new Set((data || []).map((r: Record<string, unknown>) => r.bu).filter(Boolean))];
  if (list.length === 1) return list[0] as string;
  if (list.length > 1) {
    throw new Error(
      `PS "${psName}" đang có dữ liệu ở ${list.length} team (${list.join(", ")}) ` +
      `và chưa có trong danh mục PS (dm_ps) — không xác định được team để gắn cho dòng mới`,
    );
  }
  return fallback;
}

// Đơn giá kế hoạch BU CTTM & CTUT lấy theo danh mục: dm_vat_tu.don_gia_thau_moi, giữ
// nguyên (không trừ VAT) — cùng cách khớp với migration 20261016150000:
//   1. tên SP; 2. mã SP (bỏ 'Chưa có'); 3. tên không phân biệt hoa thường;
// mỗi bước chỉ dùng khi ra đúng 1 giá. Tên trước mã vì mã M0013941xxxxx dùng chung
// cho Transend và Truselect. Trả hàm tra giá; không khớp → null (giữ giá cũ).
export const BU_GIA_DANH_MUC = "cttm";
export async function giaDanhMucCttm(db: ReturnType<typeof createClient>) {
  const theoTen = new Map<string, Set<number>>();
  const theoMa = new Map<string, Set<number>>();
  const theoTenThuong = new Map<string, Set<number>>();
  const add = (m: Map<string, Set<number>>, k: string, g: number) => {
    let s = m.get(k);
    if (!s) m.set(k, s = new Set());
    s.add(g);
  };
  for (let from = 0; ; from += PAGE) {
    const { data, error } = await db.schema("shared").from("dm_vat_tu")
      .select("id, san_pham, ma_san_pham, don_gia_thau_moi")
      .eq("bu_code", BU_GIA_DANH_MUC).gt("don_gia_thau_moi", 0)
      .order("id", { ascending: true })
      .range(from, from + PAGE - 1);
    if (error) throw new Error(error.message);
    for (const r of data || []) {
      const g = Number(r.don_gia_thau_moi);
      if (!Number.isFinite(g) || g <= 0) continue;
      if (r.san_pham != null) {
        add(theoTen, String(r.san_pham), g);
        add(theoTenThuong, String(r.san_pham).trim().toLowerCase(), g);
      }
      const ma = String(r.ma_san_pham ?? "").trim();
      if (ma && ma !== "Chưa có") add(theoMa, ma, g);
    }
    if (!data || data.length < PAGE) break;
  }
  const mot = (s: Set<number> | undefined) => (s && s.size === 1 ? [...s][0] : null);
  return (sanPham: unknown, maSanPham: unknown): number | null => {
    const ten = sanPham == null ? "" : String(sanPham);
    const ma = String(maSanPham ?? "").trim();
    return mot(theoTen.get(ten)) ??
      (ma && ma !== "Chưa có" ? mot(theoMa.get(ma)) : null) ??
      mot(theoTenThuong.get(ten.trim().toLowerCase()));
  };
}

export async function mienForPs(db: ReturnType<typeof createClient>, psName: string) {
  const info = await psInfo(db, psName);
  if (info && info.area) return info.area;
  const { data, error } = await db.schema("shared").from("sale_target")
    .select("mien").eq("ps", psName).not("mien", "is", null).limit(1000);
  if (error) throw new Error(error.message);
  const list = [...new Set((data || []).map((r: Record<string, unknown>) => r.mien).filter(Boolean))];
  return list.length === 1 ? list[0] as string : null;
}

export async function fetchAll(
  db: ReturnType<typeof createClient>,
  sess: Session,
  payload: Record<string, unknown>,
) {
  const cols = FIELDS.map((f) => COL[f]).join(",") + ",id,_rev";
  let countQ = db.schema("shared").from("sale_target").select("id", { count: "exact", head: true });
  countQ = applyScope(countQ, sess, payload);
  const { count, error: cErr } = await countQ;
  if (cErr) throw new Error(cErr.message);
  const total = count || 0;
  if (total === 0) return [];

  const pages = Math.ceil(total / PAGE);
  const out = new Array(total);
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
      for (let i = 0; i < (data as unknown[]).length; i++) out[from + i] = data[i];
    }
  }
  await Promise.all(
    Array.from({ length: Math.min(CONCURRENCY, pages) }, worker),
  );
  return out.filter(Boolean);
}

export async function fetchOopClassify(
  db: ReturnType<typeof createClient>,
  sess: Session,
  payload: Record<string, unknown> = {},
) {
  const scope = readScopeParams(sess, payload);
  const out: Record<string, unknown>[] = [];
  for (let from = 0; ; from += PAGE) {
    const { data, error } = await db.rpc("classify_oop_sale_target", scope)
      .range(from, from + PAGE - 1);
    if (error) break;
    out.push(...(data || []));
    if (!data || data.length < PAGE) break;
  }
  return new Map(out.map((c) => [c.target_id, c]));
}

export async function fetchQuotaThau(
  db: ReturnType<typeof createClient>,
  sess: Session,
  payload: Record<string, unknown> = {},
) {
  const params = {
    p_fy: payload && payload.fy ? payload.fy : null,
    ...readScopeParams(sess, payload),
  };
  const rows: Record<string, unknown>[] = [];
  for (let from = 0; ; from += PAGE) {
    const { data, error } = await db.rpc("get_quota_thau", params).range(from, from + PAGE - 1);
    if (error) throw new Error(error.message);
    if (!data || data.length === 0) break;
    for (const r of data) rows.push(r);
    if (data.length < PAGE) break;
  }
  const dots: Record<string, unknown>[] = [];
  const quotas: Record<string, unknown>[] = [];
  for (const r of rows) {
    if (r.kind === "dot") {
      dots.push({
        fy: r.fy, ps: r.ps, custId: r.cust_id ?? "", grp: r.grp ?? "",
        loai: r.loai, dot: r.dot,
        thang: r.thang ?? "", thoiGian: r.thoi_gian ?? "",
      });
    } else {
      quotas.push({
        fy: r.fy, ps: r.ps, custId: r.cust_id ?? "", grp: r.grp ?? "",
        mset: r.mset ?? "", prod: r.prod ?? "", price: r.price ?? 0,
        loai: r.loai, dot: r.dot, qty: r.qty ?? 0,
      });
    }
  }
  return { dots, quotas };
}

// Sau khi thêm SP vào kế hoạch: các tháng đã "Đồng bộ thực hiện" trước đó đang nằm ở
// dòng OOP (ngoai_ke_hoach=true) cùng khoá tháng+PS+KH+bộ VT+SP. Chuyển SL/DT thực hiện
// của chúng sang dòng kế hoạch vừa tạo rồi xoá dòng OOP — đúng như map_hoadon_to_sale_target
// sẽ làm ở lần đồng bộ sau (cùng khoá lower(btrim)), để không phải chờ đồng bộ lại và
// không bị đếm 2 lần. Lần đồng bộ sau tính lại toàn bộ nên lỗi giữa chừng tự lành.
// Trả về số dòng OOP đã hấp thụ; mảng `inserted` được cập nhật tại chỗ (sl/dt/_rev).
export async function absorbOop(
  db: ReturnType<typeof createClient>,
  inserted: Record<string, unknown>[],
  cols: string,
): Promise<number> {
  const n = (v: unknown) => String(v ?? "").trim().toLowerCase();
  const keyOf = (r: Record<string, unknown>) =>
    [r.thang_ke_hoach, n(r.ps), n(r.ma_khach_hang), n(r.bo_vat_tu), n(r.san_pham)].join("\0");
  const custIds = [...new Set(inserted.map((r) => String(r.ma_khach_hang ?? "").trim()).filter(Boolean))];
  if (!custIds.length) return 0;

  const oop: Record<string, unknown>[] = [];
  for (let i = 0; i < custIds.length; i += 100) {
    for (let from = 0; ; from += PAGE) {
      const { data, error } = await db.schema("shared").from("sale_target")
        .select("id, thang_ke_hoach, ps, ma_khach_hang, bo_vat_tu, san_pham, sl_thuc_hien, doanh_thu_thuc_hien")
        .eq("ngoai_ke_hoach", true)
        .in("ma_khach_hang", custIds.slice(i, i + 100))
        .order("id", { ascending: true })
        .range(from, from + PAGE - 1);
      if (error) throw new Error(error.message);
      oop.push(...(data || []));
      if (!data || data.length < PAGE) break;
    }
  }
  if (!oop.length) return 0;

  const agg = new Map<string, { sl: number; dt: number; ids: number[] }>();
  for (const r of oop) {
    const k = keyOf(r);
    const a = agg.get(k) || { sl: 0, dt: 0, ids: [] };
    a.sl += Number(r.sl_thuc_hien) || 0;
    a.dt += Number(r.doanh_thu_thuc_hien) || 0;
    a.ids.push(r.id as number);
    agg.set(k, a);
  }

  const absorbedIds: number[] = [];
  for (let i = 0; i < inserted.length; i++) {
    const k = keyOf(inserted[i]);
    const a = agg.get(k);
    if (!a) continue;
    agg.delete(k); // nhiều dòng cùng khoá (khác đơn giá) -> dồn vào dòng đầu như map
    const { data, error } = await db.schema("shared").from("sale_target")
      .update({ sl_thuc_hien: a.sl, doanh_thu_thuc_hien: a.dt, updated_at: new Date().toISOString() })
      .eq("id", inserted[i].id as number)
      .select(cols);
    if (error) throw new Error(error.message);
    if (data && data[0]) inserted[i] = data[0];
    absorbedIds.push(...a.ids);
  }
  for (let i = 0; i < absorbedIds.length; i += 500) {
    const { error } = await db.schema("shared").from("sale_target")
      .delete().in("id", absorbedIds.slice(i, i + 500));
    if (error) throw new Error(error.message);
  }
  return absorbedIds.length;
}

// Tháng thầu nhập lúc thêm sản phẩm → đợt thầu (shared.dot_thau) của nhóm SP.
// sale_target không còn lưu tháng thầu. Chỉ tạo đợt mới khi nhóm chưa có đợt cùng
// loại cùng tháng (số đợt do upsert_dot_thau tự đánh tiếp). Trả về số đợt đã tạo.
// Tháng thầu nhập thì bắt buộc kèm hiệu lực (số tháng nguyên 1–120). Trả câu lỗi, hoặc null.
export function kiemTraThangHieuLuc(items: Record<string, unknown>[]) {
  for (const it of items) {
    for (const [nhan, m, hl] of [["chính", it.mMain, it.hlMain], ["bổ sung", it.mAdd, it.hlAdd]] as const) {
      if (!String(m || "").trim()) continue;
      const n = Number(hl);
      if (!Number.isInteger(n) || n < 1 || n > 120) {
        return `Thầu ${nhan}: nhập tháng thầu thì phải nhập hiệu lực (số tháng, 1–120)`;
      }
    }
  }
  return null;
}

export async function taoDotTuThangThau(
  db: ReturnType<typeof createClient>,
  sess: Session,
  items: {
    fy: string; ps: string; custId: unknown; grp: unknown;
    mMain: unknown; mAdd: unknown; hlMain?: unknown; hlAdd?: unknown;
  }[],
) {
  const thang = (v: unknown) => {
    const t = String(v || "").trim();
    return /^\d{4}-\d{2}$/.test(t) ? t : null;
  };
  const can = new Map<string, Record<string, unknown>>();
  for (const it of items) {
    for (const [loai, v, hl] of [["chinh", it.mMain, it.hlMain], ["bo_sung", it.mAdd, it.hlAdd]] as const) {
      const t = thang(v);
      if (!t) continue;
      const row = {
        fy: it.fy, ps: it.ps, custId: String(it.custId || ""), grp: String(it.grp || ""), loai, thang: t,
        thoiGian: Number(hl) || null,
      };
      can.set([row.fy, row.ps, row.custId, row.grp, loai, t].join("||"), row);
    }
  }
  if (!can.size) return 0;
  const grps = [...new Set([...can.values()].map((r) => String(r.grp)))];
  const coSan = new Set<string>();
  for (let i = 0; i < grps.length; i += 50) {
    const { data, error } = await db.schema("shared").from("dot_thau")
      .select("nam_tai_chinh,ps,ma_khach_hang,nhom_san_pham,loai,thang_thau")
      .in("nhom_san_pham", grps.slice(i, i + 50));
    if (error) throw new Error(error.message);
    for (const d of data || []) {
      coSan.add([d.nam_tai_chinh, d.ps, d.ma_khach_hang, d.nhom_san_pham, d.loai, d.thang_thau].join("||"));
    }
  }
  const rows = [...can.entries()].filter(([k]) => !coSan.has(k)).map(([, r]) => r);
  if (!rows.length) return 0;
  const { data, error } = await db.rpc("upsert_dot_thau", {
    p_rows: rows, ...scopeParams(sess), p_actor: sess.u,
  });
  if (error) throw new Error(error.message);
  return Number(data) || rows.length;
}
