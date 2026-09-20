import { createClient } from "https://esm.sh/@supabase/supabase-js@2.49.1";
import { cors, json } from "../_shared/cors.ts";
import { sha256Hex, signToken } from "../_shared/auth.ts";

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: cors });
  if (req.method !== "POST") return json({ ok: false, error: "method" }, 405);

  const secret = Deno.env.get("TOKEN_SECRET");
  if (!secret) return json({ ok: false, error: "TOKEN_SECRET chua duoc set" }, 500);

  let body;
  try { body = await req.json(); } catch { return json({ ok: false, error: "bad_body" }, 400); }

  const { username, password, newPassword } = body;
  if (!username || !password) return json({ ok: false, error: "missing_credentials" }, 400);

  const admin = createClient(
    Deno.env.get("SUPABASE_URL") ?? "",
    Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "",
  );

  const { data: user, error } = await admin
    .schema("shared").from("users")
    .select("username, password_hash, salt, role, scope, bu, mien, nhom_san_pham, ho_va_ten")
    .eq("username", username)
    .maybeSingle();

  if (error || !user) return json({ ok: false, error: "invalid" }, 401);

  const toHash = user.salt ? (user.salt + ":" + password) : password;
  const inputHash = await sha256Hex(toHash);
  if (inputHash.toLowerCase() !== String(user.password_hash).toLowerCase()) {
    return json({ ok: false, error: "invalid" }, 401);
  }

  if (newPassword !== undefined && newPassword !== null && newPassword !== "") {
    if (String(newPassword).length < 6) {
      return json({ ok: false, error: "weak_password" }, 400);
    }
    if (String(newPassword) === String(password)) {
      return json({ ok: false, error: "same_password" }, 400);
    }
    const newHash = await sha256Hex(user.salt ? (user.salt + ":" + String(newPassword)) : String(newPassword));
    const { error: upErr } = await admin
      .schema("shared").from("users")
      .update({ password_hash: newHash })
      .eq("username", user.username);
    if (upErr) return json({ ok: false, error: "update_failed" }, 500);
    return json({ ok: true, changed: true });
  }

  const exp = Math.floor(Date.now() / 1000) + 8 * 60 * 60;
  const token = await signToken(
    {
      username: user.username,
      ho_ten: user.ho_va_ten || user.username,
      role: String(user.role || "").toLowerCase(),
      mien: user.mien || "MB",
      bu: user.bu ?? "",
      scope: user.scope ?? "",
      nhom_san_pham: user.nhom_san_pham ?? "",
      exp,
    },
    secret,
  );

  return json({
    ok: true,
    token,
    username: user.username,
    role: user.role,
    scope: user.scope,
    bu: user.bu,
    nhom_san_pham: user.nhom_san_pham,
  });
});
