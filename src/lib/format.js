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

// Đọc số người dùng gõ, chấp nhận cả kiểu en-US (app hiển thị "1,234.5") lẫn kiểu Việt
// ("1.234.567", "1,5"). Luật:
//   - có cả '.' và ',': dấu xuất hiện SAU CÙNG là dấu thập phân, dấu kia là phân nhóm;
//   - nhiều dấu cùng loại ("1,234,567" / "1.234.567"): phân nhóm;
//   - đúng một ',': "1,234" (3 chữ số sau) = phân nhóm như cách app hiển thị, còn lại
//     ("1,5", "12,75") = thập phân;
//   - đúng một '.': thập phân.
// Chuỗi có ký tự khác (chữ, nhiều dấu '-') → null, KHÔNG âm thầm thành 0.
export const parseNumStrict = (s) => {
  if (s == null) return 0;
  if (typeof s === 'number') return Number.isFinite(s) ? s : null;
  let t = String(s).replace(/\s/g, '');
  if (t === '') return 0;
  if (!/^-?[\d.,]+$/.test(t) || !/\d/.test(t)) return null;
  const dots = (t.match(/\./g) || []).length;
  const commas = (t.match(/,/g) || []).length;
  if (dots && commas) {
    const dec = t.lastIndexOf('.') > t.lastIndexOf(',') ? '.' : ',';
    const grp = dec === '.' ? ',' : '.';
    if (t.split(dec).length > 2) return null;
    t = t.split(grp).join('').replace(dec, '.');
  } else if (commas > 1) {
    t = t.replace(/,/g, '');
  } else if (dots > 1) {
    t = t.replace(/\./g, '');
  } else if (commas === 1) {
    t = /^-?\d{1,3},\d{3}$/.test(t) ? t.replace(',', '') : t.replace(',', '.');
  }
  const n = Number(t);
  return Number.isFinite(n) ? n : null;
};

export const parseNum = (s) => parseNumStrict(s) ?? 0;

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
