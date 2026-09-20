import { TOK_KEY } from '../config/constants.js';

const SUPABASE_URL = 'https://nrfxymnfmjhbsgpipvkb.supabase.co';
const SUPABASE_ANON_KEY =
  'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6Im5yZnh5bW5mbWpoYnNncGlwdmtiIiwicm9sZSI6ImFub24iLCJpYXQiOjE3ODI4ODk2OTQsImV4cCI6MjA5ODQ2NTY5NH0.cN-jTdPOLWKd9kNa1nNMENzHcY0_BftyYgPEbuVTWeo';
const FN_LOGIN = SUPABASE_URL + '/functions/v1/sale_target-login';
const FN_API = SUPABASE_URL + '/functions/v1/sale_target-api';

const EXP_KEY = TOK_KEY + '_exp';
const REFRESH_MARGIN_SEC = 10 * 60;

let _onSessionExpired = null;

export function onSessionExpired(cb) {
  _onSessionExpired = cb;
}

export function getTokenExpiry() {
  const v = sessionStorage.getItem(EXP_KEY);
  return v ? Number(v) : 0;
}

export function setTokenData(token, expiresAt) {
  sessionStorage.setItem(TOK_KEY, token);
  if (expiresAt) sessionStorage.setItem(EXP_KEY, String(expiresAt));
}

function clearTokenData() {
  sessionStorage.removeItem(TOK_KEY);
  sessionStorage.removeItem(EXP_KEY);
}

async function tryRefresh() {
  const token = sessionStorage.getItem(TOK_KEY);
  if (!token) return false;
  try {
    const res = await fetch(FN_API, {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        apikey: SUPABASE_ANON_KEY,
        Authorization: 'Bearer ' + SUPABASE_ANON_KEY,
      },
      body: JSON.stringify({ action: 'refreshToken', token, payload: {} }),
    });
    const data = await res.json();
    if (data && data.ok && data.token) {
      setTokenData(data.token, data.expiresAt);
      return true;
    }
  } catch {
    /* refresh failed — will trigger re-login */
  }
  return false;
}

export async function api(action, payload = {}) {
  const token = sessionStorage.getItem(TOK_KEY) || '';
  const isLogin = action === 'login';
  const url = isLogin ? FN_LOGIN : FN_API;

  if (!isLogin && token) {
    const exp = getTokenExpiry();
    const now = Math.floor(Date.now() / 1000);
    if (exp && exp - now < REFRESH_MARGIN_SEC && exp - now > 0) {
      await tryRefresh();
    }
  }

  const currentToken = sessionStorage.getItem(TOK_KEY) || token;
  const bodyObj = isLogin ? payload : { action, token: currentToken, payload };
  let res;
  try {
    res = await fetch(url, {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        apikey: SUPABASE_ANON_KEY,
        Authorization: 'Bearer ' + SUPABASE_ANON_KEY,
      },
      body: JSON.stringify(bodyObj),
    });
  } catch (e) {
    throw new Error('Không kết nối được máy chủ: ' + ((e && e.message) || e), { cause: e });
  }
  let data = null;
  try {
    data = await res.json();
  } catch {
    /* body rỗng / không phải JSON */
  }
  if (!res.ok || (data && data.ok === false)) {
    const err = (data && data.error) || 'HTTP ' + res.status;
    if (err === 'unauthorized' || err === 'expired') {
      const refreshed = await tryRefresh();
      if (!refreshed) {
        clearTokenData();
        if (_onSessionExpired) _onSessionExpired();
      }
    }
    if (err === 'account_locked') {
      throw new Error(data.message || 'Tài khoản tạm khoá');
    }
    throw new Error(err);
  }
  if (!data) throw new Error('Máy chủ trả về dữ liệu rỗng');
  if (isLogin && data.token) {
    setTokenData(data.token, data.expiresAt);
  }
  return data;
}
