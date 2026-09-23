import type { SupabaseClient } from "https://esm.sh/@supabase/supabase-js@2.49.1";
import type { Session } from "../_shared/auth.ts";
import { DEMO_BU } from "./config.ts";

export const excludeDemo = (q: ReturnType<SupabaseClient["from"]>) =>
  q.or(`bu.is.null,bu.neq.${DEMO_BU}`);

// Chiều thứ 4 = shared.users.nhom_san_pham. Cột text, nhưng nhận danh sách
// nhóm ngăn cách bởi dấu phẩy (giống scope của product_manager) để 1 user
// có thể phụ trách nhiều nhóm mà không cần đổi schema sang text[].
// Áp SAU role logic để thu hẹp thêm (AND). Với PM (scope đã là list ngành),
// nếu ai đó gán thêm `nhom_san_pham` riêng thì GIAO 2 tập; rỗng → sentinel
// "__none__" (không thấy gì).
export function parseGroups(raw: unknown): string[] {
  return String(raw || "").split(",").map((x) => x.trim()).filter(Boolean);
}

function narrowGroups(sess: Session, groups: string[]) {
  const nhoms = parseGroups(sess.g);
  if (!nhoms.length) return groups;
  return groups.length ? groups.filter((g) => nhoms.includes(g)) : nhoms;
}

function eqOrIn(q: ReturnType<SupabaseClient["from"]>, col: string, list: string[]) {
  if (list.length === 0) return q.eq(col, "__none__");
  return list.length > 1 ? q.in(col, list) : q.eq(col, list[0]);
}

export function applyScope(
  query: ReturnType<SupabaseClient["from"]>,
  sess: Session,
  payload: Record<string, unknown> = {},
) {
  const role = String(sess.r || "").toLowerCase();
  const nhoms = parseGroups(sess.g);
  let q = query;

  if (role === "admin" || role === "manager") {
    if (payload && payload.bu) q = q.eq("bu", payload.bu as string);
    else q = excludeDemo(q);
  } else if (role === "product_manager") {
    q = excludeDemo(q);
  } else {
    q = q.eq("bu", sess.b);
  }

  if (role === "product_manager") {
    const groups = narrowGroups(sess, parseGroups(sess.s));
    return eqOrIn(q, "nhom_san_pham", groups);
  }
  if (role === "area_manager") q = q.eq("mien", sess.s);
  else if (role === "ps") q = q.eq("ps", sess.s);
  else if (role !== "admin" && role !== "manager") q = q.eq("ps", sess.s);

  if (nhoms.length) q = eqOrIn(q, "nhom_san_pham", nhoms);
  return q;
}

export function scopeParams(sess: Session) {
  const role = String(sess.r || "").toLowerCase();
  const nhoms = parseGroups(sess.g);
  const nil = { p_bu: null, p_mien: null, p_ps: null, p_groups: null };
  if (role === "admin" || role === "manager") {
    return nhoms.length ? { ...nil, p_groups: nhoms } : nil;
  }
  if (role === "product_manager") {
    const groups = narrowGroups(sess, parseGroups(sess.s));
    return { ...nil, p_groups: groups.length ? groups : ["__none__"] };
  }
  const base = role === "area_manager"
    ? { ...nil, p_bu: sess.b, p_mien: sess.s }
    : { ...nil, p_bu: sess.b, p_ps: sess.s };
  return nhoms.length ? { ...base, p_groups: nhoms } : base;
}

export function readScopeParams(sess: Session, payload: Record<string, unknown> = {}) {
  const role = String(sess.r || "").toLowerCase();
  const p = scopeParams(sess);
  if ((role === "admin" || role === "manager") && payload && payload.bu) {
    return { ...p, p_bu: payload.bu as string };
  }
  return p;
}
