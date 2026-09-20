import { createClient } from "https://esm.sh/@supabase/supabase-js@2.49.1";
import type { Session } from "../_shared/auth.ts";
import { json } from "../_shared/cors.ts";
import { COL, FIELDS, PAGE, CONCURRENCY } from "./config.ts";
import { applyScope, readScopeParams } from "./scope.ts";

export function diaBanErr(error: { message?: string }) {
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
  const nhom = String(sess.g || "").trim();
  let q = query;

  if (role === "admin" || role === "manager") {
    if (payload && payload.bu) q = q.eq("bu", payload.bu as string);
  } else if (role === "product_manager") {
    const raw = String(sess.s || "").split(",").map((x) => x.trim()).filter(Boolean);
    const groups = nhom ? (raw.length ? raw.filter((g) => g === nhom) : [nhom]) : raw;
    if (groups.length === 0) return q.eq("nhom_san_pham", "__none__");
    return groups.length > 1 ? q.in("nhom_san_pham", groups) : q.eq("nhom_san_pham", groups[0]);
  } else {
    q = q.eq("bu", sess.b);
    if (role === "area_manager") q = q.eq("mien", sess.s);
    else q = q.eq("ps", sess.s);
  }

  if (nhom && role !== "product_manager") q = q.eq("nhom_san_pham", nhom);
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
