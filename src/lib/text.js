import { ALIAS_MAP } from '../config/constants.js';

export const deaccent = (s) =>
  String(s == null ? '' : s)
    .toLowerCase()
    .normalize('NFD')
    .replace(/[̀-ͯ]/g, '')
    .replace(/đ/g, 'd');

export const isLooseSet = (name) =>
  deaccent(name).trim().startsWith('vat tu rieng le');

export const titleWord = (w) =>
  w ? w.charAt(0).toUpperCase() + w.slice(1).toLowerCase() : w;

export const fmtCust = (name) => {
  if (name == null) return name;
  const s = String(name).trim().replace(/\s+/g, ' ');
  if (!s) return s;
  let words = s.split(' ');
  let prefix = '';
  if (
    words.length >= 2 &&
    deaccent(words[0]) === 'benh' &&
    deaccent(words[1]) === 'vien'
  ) {
    prefix = 'BV ';
    words = words.slice(2);
  }
  return prefix + words.map(titleWord).join(' ');
};

export const custLabel = (custId, rawName) => {
  if (custId != null) {
    const a = ALIAS_MAP.get(String(custId));
    if (a) return a;
  }
  return fmtCust(rawName);
};

export const inSel = (sel, v) => !sel || sel.length === 0 || sel.includes(v);

const nk = (s) =>
  String(s == null ? '' : s)
    .trim()
    .toLowerCase();

export const planCustKeys = (rows) => {
  const s = new Set();
  for (const r of rows) {
    if (r._oop) continue;
    if (r.custId) s.add('#' + nk(r.custId));
    if (r.cust) s.add('@' + nk(r.cust));
  }
  return s;
};

export const custInPlan = (keys, r) =>
  (r.custId && keys.has('#' + nk(r.custId))) ||
  (r.cust && keys.has('@' + nk(r.cust)));

export const matchSearch = (r, q) =>
  !q ||
  (r.cust || '').toLowerCase().includes(q) ||
  (r.prod || '').toLowerCase().includes(q) ||
  (r.custId || '').toLowerCase().includes(q) ||
  (r.mset || '').toLowerCase().includes(q);
