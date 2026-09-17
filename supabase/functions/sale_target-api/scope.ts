import type { SupabaseClient } from "https://esm.sh/@supabase/supabase-js@2.49.1";
import type { Session } from "../_shared/auth.ts";
import { DEMO_BU } from "./config.ts";

export const excludeDemo = (q: ReturnType<SupabaseClient["from"]>) =>
  q.or(`bu.is.null,bu.neq.${DEMO_BU}`);

export function applyScope(
  query: ReturnType<SupabaseClient["from"]>,
  sess: Session,
  payload: Record<string, unknown> = {},
) {
  const role = String(sess.r || "").toLowerCase();
  let q = query;

  if (role === "admin" || role === "manager") {
    if (payload && payload.bu) q = q.eq("bu", payload.bu as string);
    else q = excludeDemo(q);
  } else if (role === "product_manager") {
    q = excludeDemo(q);
  } else {
    q = q.eq("bu", sess.b);
  }

  if (role === "admin" || role === "manager") return q;
  if (role === "product_manager") {
    const groups = String(sess.s || "").split(",").map((x) => x.trim()).filter(Boolean);
    if (groups.length === 0) return q.eq("nhom_san_pham", "__none__");
    return groups.length > 1 ? q.in("nhom_san_pham", groups) : q.eq("nhom_san_pham", groups[0]);
  }
  if (role === "area_manager") return q.eq("mien", sess.s);
  if (role === "ps") return q.eq("ps", sess.s);
  return q.eq("ps", sess.s);
}

export function scopeParams(sess: Session) {
  const role = String(sess.r || "").toLowerCase();
  const nil = { p_bu: null, p_mien: null, p_ps: null, p_groups: null };
  if (role === "admin" || role === "manager") return nil;
  if (role === "product_manager") {
    const groups = String(sess.s || "").split(",").map((x) => x.trim()).filter(Boolean);
    return { ...nil, p_groups: groups.length ? groups : ["__none__"] };
  }
  if (role === "area_manager") return { ...nil, p_bu: sess.b, p_mien: sess.s };
  return { ...nil, p_bu: sess.b, p_ps: sess.s };
}

export function readScopeParams(sess: Session, payload: Record<string, unknown> = {}) {
  const role = String(sess.r || "").toLowerCase();
  const p = scopeParams(sess);
  if ((role === "admin" || role === "manager") && payload && payload.bu) {
    return { ...p, p_bu: payload.bu as string };
  }
  return p;
}
