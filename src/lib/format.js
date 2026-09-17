import { MASK_MONEY } from '../config/constants.js';

export const fmtFull = (v) =>
  v == null || v === ''
    ? ''
    : typeof v === 'number'
      ? v.toLocaleString('en-US')
      : v;

export const fmtInt = (v) => {
  if (!v && v !== 0) return '—';
  if (v === 0) return '·';
  return Math.round(v).toLocaleString('en-US');
};

export const fmtM = (v) => {
  if (!v) return '—';
  const m = v / 1e6;
  if (Math.abs(m) >= 1000) return Math.round(m).toLocaleString('en-US');
  if (Math.abs(m) >= 100) return m.toFixed(0);
  if (Math.abs(m) >= 10) return m.toFixed(1);
  return m.toFixed(2);
};

export const fmtShort = (v) => {
  if (!v && v !== 0) return '—';
  const n = Math.abs(v);
  if (n >= 1e9) return (v / 1e9).toFixed(2) + 'tỷ';
  if (n >= 1e6) return (v / 1e6).toFixed(1) + 'tr';
  if (n >= 1e3) return (v / 1e3).toFixed(0) + 'k';
  return String(v);
};

export const parseNum = (s) => {
  if (s === '' || s == null) return 0;
  const n = Number(String(s).replace(/[^\d.-]/g, ''));
  return isNaN(n) ? 0 : n;
};

export const money = (v) => (MASK_MONEY ? '•••' : fmtM(v));
export const moneyShort = (v) => (MASK_MONEY ? '•••' : fmtShort(v));
export const moneyPrice = (v) =>
  MASK_MONEY
    ? '•••'
    : !v
      ? '—'
      : (v / 1e6).toLocaleString('en-US', {
          minimumFractionDigits: 3,
          maximumFractionDigits: 3,
        });

export const fmtTy3 = (v) => {
  const n = Math.abs(v);
  if (n >= 1e9)
    return (
      (v / 1e9).toLocaleString('en-US', {
        minimumFractionDigits: 1,
        maximumFractionDigits: 1,
      }) + 'tỷ'
    );
  return (
    (v / 1e6).toLocaleString('en-US', {
      maximumFractionDigits: 0,
    }) + 'tr'
  );
};

export const moneyTy3 = (v) => (MASK_MONEY ? '•••' : !v ? '—' : fmtTy3(v));
