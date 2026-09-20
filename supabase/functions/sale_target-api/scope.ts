import type { SupabaseClient } from "https://esm.sh/@supabase/supabase-js@2.49.1";
import type { Session } from "../_shared/auth.ts";
import { DEMO_BU } from "./config.ts";

export const excludeDemo = (q: ReturnType<SupabaseClient["from"]>) =>
  q.or(`bu.is.null,bu.neq.${DEMO_BU}`);

// Chiều thứ 4 = shared.users.nhom_san_pham (single value, nullable).
// Áp SAU role logic để thu hẹp thêm (AND). Product_manager đã dùng `scope`
// làm list ngành hàng — nếu ai đó gán thêm `nhom_san_pham` riêng thì GIAO
// 2 tập; kết quả rỗng thì fallback về sentinel "__none__" (không thấy gì).
function narrowGroups(sess: Session, groups: string[]) {
  const nhom = String(sess.g || "").trim();
  if (!nhom) return groups;
  return groups.length ? groups.filter((g) => g === nhom) : [nhom];
}

export function applyScope(
  query: ReturnType<SupabaseClient["from"]>,
  sess: Session,
  payload: Record<string, unknown> = {},
) {
  const role = String(sess.r || "").toLowerCase();
  const nhom = String(sess.g || "").trim();
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
    const groups = narrowGroups(
      sess,
      String(sess.s || "").split(",").map((x) => x.trim()).filter(Boolean),
    );
    if (groups.length === 0) return q.eq("nhom_san_pham", "__none__");
    return groups.length > 1 ? q.in("nhom_san_pham", groups) : q.eq("nhom_san_pham", groups[0]);
  }
  if (role === "area_manager") q = q.eq("mien", sess.s);
  else if (role === "ps") q = q.eq("ps", sess.s);
  else if (role !== "admin" && role !== "manager") q = q.eq("ps", sess.s);

  if (nhom) q = q.eq("nhom_san_pham", nhom);
  return q;
}

export function scopeParams(sess: Session) {
  const role = String(sess.r || "").toLowerCase();
  const nhom = String(sess.g || "").trim();
  const nil = { p_bu: null, p_mien: null, p_ps: null, p_groups: null };
  if (role === "admin" || role === "manager") {
    return nhom ? { ...nil, p_groups: [nhom] } : nil;
  }
  if (role === "product_manager") {
    const groups = narrowGroups(
      sess,
      String(sess.s || "").split(",").map((x) => x.trim()).filter(Boolean),
    );
    return { ...nil, p_groups: groups.length ? groups : ["__none__"] };
  }
  const base = role === "area_manager"
    ? { ...nil, p_bu: sess.b, p_mien: sess.s }
    : { ...nil, p_bu: sess.b, p_ps: sess.s };
  return nhom ? { ...base, p_groups: [nhom] } : base;
}

export function readScopeParams(sess: Session, payload: Record<string, unknown> = {}) {
  const role = String(sess.r || "").toLowerCase();
  const p = scopeParams(sess);
  if ((role === "admin" || role === "manager") && payload && payload.bu) {
    return { ...p, p_bu: payload.bu as string };
  }
  return p;
}
