import { createClient } from "https://esm.sh/@supabase/supabase-js@2.49.1";
import * as bcrypt from "https://deno.land/x/bcrypt@v0.4.1/mod.ts";
import { getAllowedOrigin, corsHeaders, json as _json } from "../_shared/cors.ts";
import { sha256Hex, signToken } from "../_shared/auth.ts";

const MAX_ATTEMPTS = 5;
const LOCKOUT_WINDOW_SEC = 15 * 60;
const TOKEN_TTL_SEC = 2 * 60 * 60;

Deno.serve(async (req) => {
  const _origin = getAllowedOrigin(req);
  const json = (body: unknown, status = 200) => _json(body, status, req);
  if (req.method === "OPTIONS") return new Response("ok", { headers: corsHeaders(_origin) });
  if (req.method !== "POST") return json({ ok: false, error: "method" }, 405);

  const secret = Deno.env.get("TOKEN_SECRET");
  if (!secret) return json({ ok: false, error: "config_error" }, 500);

  let body: Record<string, unknown>;
  try { body = await req.json(); } catch { return json({ ok: false, error: "bad_body" }, 400); }

  const { username, password, newPassword } = body;
  if (!username || !password) return json({ ok: false, error: "missing_credentials" }, 400);

  const db = createClient(
    Deno.env.get("SUPABASE_URL") ?? "",
    Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "",
  );

  const ip = req.headers.get("x-forwarded-for")?.split(",")[0]?.trim() || "";

  // --- Rate limit check ---
  const since = new Date(Date.now() - LOCKOUT_WINDOW_SEC * 1000).toISOString();
  const { count } = await db.schema("shared").from("login_attempts")
    .select("id", { count: "exact", head: true })
    .eq("username", username as string)
    .eq("success", false)
    .gte("attempted_at", since);

  if ((count ?? 0) >= MAX_ATTEMPTS) {
    return json({
      ok: false,
      error: "account_locked",
      message: `Tài khoản tạm khoá do đăng nhập sai ${MAX_ATTEMPTS} lần. Thử lại sau 15 phút.`,
    }, 429);
  }

  // --- Fetch user ---
  const { data: user, error } = await db
    .schema("shared").from("users")
    .select("username, password_hash, password_bcrypt, salt, role, scope, bu, mien, nhom_san_pham, ho_va_ten, active")
    .eq("username", username as string)
    .maybeSingle();

  // Locked accounts (active = false) get the same "invalid" answer as unknown users.
  if (error || !user || user.active === false) {
    await recordAttempt(db, username as string, false, ip);
    return json({ ok: false, error: "invalid" }, 401);
  }

  // --- Verify password ---
  // shared.users is used by several apps (order, kpi-review, contract, ccdc) that only know
  // password_hash/salt, so the legacy SHA-256 hash is the source of truth. password_bcrypt is a
  // cache that goes stale when another app changes password_hash/salt, so verify both.
  const verify = await verifyPassword(user, String(password));

  if (verify.staleBcrypt) {
    // bcrypt matches an old password but password_hash was changed elsewhere: drop the stale
    // bcrypt so the next login with the current password re-derives it.
    try {
      await db.schema("shared").from("users")
        .update({ password_bcrypt: null })
        .eq("username", user.username);
    } catch (_) { /* cleanup failure is non-fatal */ }
  }

  if (!verify.ok) {
    await recordAttempt(db, user.username, false, ip);
    return json({ ok: false, error: "invalid" }, 401);
  }

  // --- Successful login ---
  await recordAttempt(db, user.username, true, ip);

  // Transparent re-hash: SHA-256 → bcrypt (missing or out of date)
  if (verify.needsRehash) {
    try {
      const hashed = await bcrypt.hash(String(password));
      await db.schema("shared").from("users")
        .update({ password_bcrypt: hashed })
        .eq("username", user.username);
    } catch (_) { /* re-hash failure is non-fatal */ }
  }

  // --- Change password ---
  if (newPassword !== undefined && newPassword !== null && newPassword !== "") {
    if (String(newPassword).length < 6) {
      return json({ ok: false, error: "weak_password" }, 400);
    }
    if (String(newPassword) === String(password)) {
      return json({ ok: false, error: "same_password" }, 400);
    }
    // Keep the shared legacy scheme authoritative (password_hash is NOT NULL and the other apps
    // verify only sha256(salt + ":" + password)). Refresh bcrypt for this app and null
    // password_hash_v2 so order-login re-derives it from the new legacy hash.
    const newSalt = randomSaltHex();
    const newHash = await sha256Hex(newSalt + ":" + String(newPassword));
    const newBcrypt = await bcrypt.hash(String(newPassword));
    const { error: upErr } = await db
      .schema("shared").from("users")
      .update({ password_hash: newHash, salt: newSalt, password_bcrypt: newBcrypt, password_hash_v2: null })
      .eq("username", user.username);
    if (upErr) return json({ ok: false, error: "update_failed" }, 500);
    return json({ ok: true, changed: true });
  }

  // --- Issue token ---
  const exp = Math.floor(Date.now() / 1000) + TOKEN_TTL_SEC;
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
    expiresAt: exp,
  });
});

// Verify against both hashes (mirrors order-login's verifyPassword for password_hash_v2):
//  - bcrypt ok, legacy ok   → accept
//  - bcrypt ok, legacy fail → password_hash changed by another app; bcrypt is stale → reject
//  - bcrypt fail, legacy ok → bcrypt out of date → accept and refresh bcrypt
//  - no bcrypt              → legacy decides; refresh bcrypt on success
async function verifyPassword(
  user: { password_hash: string | null; password_bcrypt: string | null; salt: string | null },
  password: string,
): Promise<{ ok: boolean; needsRehash: boolean; staleBcrypt: boolean }> {
  const toHash = user.salt ? (user.salt + ":" + password) : password;
  const legacyOk = !!user.password_hash &&
    (await sha256Hex(toHash)).toLowerCase() === String(user.password_hash).toLowerCase();

  if (user.password_bcrypt) {
    let bcryptOk = false;
    try { bcryptOk = await bcrypt.compare(password, user.password_bcrypt); } catch (_) { /* malformed hash */ }
    if (bcryptOk && legacyOk) return { ok: true, needsRehash: false, staleBcrypt: false };
    if (bcryptOk && !legacyOk) return { ok: false, needsRehash: false, staleBcrypt: true };
    if (!bcryptOk && legacyOk) return { ok: true, needsRehash: true, staleBcrypt: false };
    return { ok: false, needsRehash: false, staleBcrypt: false };
  }
  return { ok: legacyOk, needsRehash: legacyOk, staleBcrypt: false };
}

function randomSaltHex(): string {
  return Array.from(crypto.getRandomValues(new Uint8Array(16)))
    .map((b) => b.toString(16).padStart(2, "0")).join("");
}

async function recordAttempt(
  db: ReturnType<typeof createClient>,
  username: string,
  success: boolean,
  ip: string,
) {
  try {
    await db.schema("shared").from("login_attempts")
      .insert({ username, success, ip: ip || null });
  } catch (_) { /* logging failure is non-fatal */ }
}
