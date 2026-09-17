import { TOK_KEY } from '../config/constants.js';

const SUPABASE_URL = 'https://nrfxymnfmjhbsgpipvkb.supabase.co';
const SUPABASE_ANON_KEY =
  'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6Im5yZnh5bW5mbWpoYnNncGlwdmtiIiwicm9sZSI6ImFub24iLCJpYXQiOjE3ODI4ODk2OTQsImV4cCI6MjA5ODQ2NTY5NH0.cN-jTdPOLWKd9kNa1nNMENzHcY0_BftyYgPEbuVTWeo';
const FN_LOGIN = SUPABASE_URL + '/functions/v1/sale_target-login';
const FN_API = SUPABASE_URL + '/functions/v1/sale_target-api';

export async function api(action, payload = {}) {
  const token = sessionStorage.getItem(TOK_KEY) || '';
  const isLogin = action === 'login';
  const url = isLogin ? FN_LOGIN : FN_API;
  const bodyObj = isLogin ? payload : { action, token, payload };
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
    if (err === 'unauthorized') sessionStorage.removeItem(TOK_KEY);
    throw new Error(err);
  }
  if (!data) throw new Error('Máy chủ trả về dữ liệu rỗng');
  return data;
}
