import { MONTHS, MONTH_LABELS, CURRENT_MONTH, HIEN_HET_HIEU_LUC } from '../config/constants.js';

let _XLSX = null;
export async function loadXLSX() {
  if (!_XLSX) _XLSX = await import('xlsx');
  return _XLSX;
}
const _ec = (r, c) => _XLSX.utils.encode_cell({ r, c });
const _today = () => new Date().toISOString().slice(0, 10).replace(/-/g, '');
const _fmt = (ws, r, c, z) => {
  const cell = ws[_ec(r, c)];
  if (cell && cell.v !== '' && cell.v != null) cell.z = z;
};

export async function exportSummaryPS(data) {
  const XLSX = await loadXLSX();
  const wb = XLSX.utils.book_new();
  _buildSumPSSheet(XLSX, wb, data, 'money');
  _buildSumPSSheet(XLSX, wb, data, 'qty');
  XLSX.writeFile(wb, `TongHop_theo_PS_${_today()}.xlsx`);
}

function _buildSumPSSheet(XLSX, wb, data, mode) {
  const isSL = mode === 'qty';
  const tr = isSL ? (v) => Math.round(Number(v) || 0) : (v) => (Number(v) || 0) / 1e6;
  const curIdx = Math.max(0, MONTHS.indexOf(CURRENT_MONTH));
  const hasAct = (i) => i <= curIdx;
  const H1 = ['Miền / PS / Khách hàng', 'Số KH'],
    H2 = ['', ''];
  const merges = [
    { s: { r: 0, c: 0 }, e: { r: 1, c: 0 } },
    { s: { r: 0, c: 1 }, e: { r: 1, c: 1 } },
  ];
  const cols = [{ wch: 34 }, { wch: 7 }];
  const pctCols = [],
    numCols = [],
    moneyCols = [],
    intCols = [1];
  let c = 2;
  if (isSL) {
    H1.push('Đơn giá');
    H2.push('');
    merges.push({ s: { r: 0, c: 2 }, e: { r: 1, c: 2 } });
    cols.push({ wch: 14 });
    moneyCols.push(2);
    c = 3;
  }
  for (let i = 0; i < 12; i++) {
    if (hasAct(i)) {
      H1.push(MONTH_LABELS[i], '', '');
      H2.push('KH', 'TH', '% TH');
      merges.push({ s: { r: 0, c }, e: { r: 0, c: c + 2 } });
      cols.push({ wch: 10 }, { wch: 10 }, { wch: 7 });
      numCols.push(c, c + 1);
      pctCols.push(c + 2);
      c += 3;
    } else {
      H1.push(MONTH_LABELS[i]);
      H2.push('KH');
      cols.push({ wch: 10 });
      numCols.push(c);
      c += 1;
    }
  }
  H1.push('Luỹ kế YTD', '', '', '', '', '');
  H2.push('KH', 'TH', '% TH YTD', 'tốc độ TH YTD', 'tốc độ KH YTD', 'CL tốc độ');
  merges.push({ s: { r: 0, c }, e: { r: 0, c: c + 5 } });
  cols.push({ wch: 12 }, { wch: 12 }, { wch: 9 }, { wch: 13 }, { wch: 13 }, { wch: 9 });
  numCols.push(c, c + 1);
  pctCols.push(c + 2, c + 3, c + 4, c + 5);
  c += 6;
  H1.push('Target', '', '', '');
  H2.push(
    isSL ? 'SL đầu năm' : 'Target đầu năm',
    isSL ? 'SL dự kiến' : 'DThu dự kiến',
    'Chênh lệch', 'KH còn lại',
  );
  merges.push({ s: { r: 0, c }, e: { r: 0, c: c + 3 } });
  cols.push({ wch: 14 }, { wch: 14 }, { wch: 12 }, { wch: 12 });
  numCols.push(c, c + 1, c + 2, c + 3);
  c += 4;
  const qCols = HIEN_HET_HIEU_LUC
    ? ['On hand', 'Upcoming', 'Hết hiệu lực', 'Tổng quota', 'TH YTD', 'Khả dụng']
    : ['On hand', 'Upcoming', 'Tổng quota', 'TH YTD', 'Khả dụng'];
  H1.push('Quota', ...qCols.slice(1).map(() => ''));
  H2.push(...qCols);
  merges.push({ s: { r: 0, c }, e: { r: 0, c: c + qCols.length - 1 } });
  qCols.forEach((_, k) => { cols.push({ wch: k === qCols.length - 1 ? 16 : 14 }); numCols.push(c + k); });
  c += qCols.length;
  const LAST_COL = c - 1;
  const aoa = [H1, H2];
  const levels = [null, null];
  const push = (level, label, d) => {
    const dtV = isSL ? (Number(d.slDauNam) || 0) : (Number(d.dt) || 0);
    const dtUpdV = isSL ? (Number(d.slUpd) || 0) : (Number(d.dtUpd) || 0);
    const ch = dtUpdV - dtV;
    const khYtdV = isSL ? (Number(d.khYtd) || 0) : (Number(d.khYtdDt) || 0);
    const dtYtdV = isSL ? (Number(d.ytd) || 0) : (Number(d.dtYtd) || 0);
    const moKh = isSL ? d.moKh : d.moKhDt;
    const moAct = isSL ? d.moAct : d.moActDt;
    const row = [
      '   '.repeat(level) + label,
      Number.isFinite(d.custCount) ? d.custCount : '',
    ];
    if (isSL) row.push(d.price > 0 ? d.price : '');
    for (let i = 0; i < 12; i++) {
      const kh = moKh[i] || 0, act = moAct[i] || 0;
      if (!hasAct(i)) { row.push(tr(kh)); continue; }
      row.push(tr(kh), tr(act), kh > 0 ? act / kh : '');
    }
    const thP = khYtdV > 0 ? dtYtdV / khYtdV : null;
    const tdTh = dtUpdV > 0 ? dtYtdV / dtUpdV : null;
    const tdKh = dtUpdV > 0 ? khYtdV / dtUpdV : null;
    const clP = tdTh != null && tdKh != null ? tdTh - tdKh : '';
    row.push(
      tr(khYtdV), tr(dtYtdV),
      thP == null ? '' : thP, tdTh == null ? '' : tdTh,
      tdKh == null ? '' : tdKh, clP,
    );
    row.push(tr(dtV), tr(dtUpdV), tr(ch), tr(dtUpdV - dtYtdV));
    const q14V = isSL ? (d.q14 || 0) : (d.q14Dt || 0);
    const qUpV = isSL ? (d.qUpcoming || 0) : (d.qUpcomingDt || 0);
    const qHetV = isSL ? (d.qHet || 0) : (d.qHetDt || 0);
    const qFYV = isSL ? (d.quotaFY || 0) : (d.quotaFYDt || 0);
    const qAvail = isSL ? d.quotaAvail : d.quotaAvailDt;
    const quotaRemain = qAvail == null ? '-' : tr(q14V - dtYtdV);
    row.push(tr(q14V), tr(qUpV), ...(HIEN_HET_HIEU_LUC ? [tr(qHetV)] : []), tr(qFYV), tr(dtYtdV), quotaRemain);
    aoa.push(row);
    levels.push(level);
  };
  const pushCust = (level, c) => {
    const subs = c.subs || [];
    push(level, c.cust + (c.custId ? ` (${c.custId})` : ''), subs.length ? { ...c, custCount: subs.length } : c);
    for (const s of subs) pushCust(level + 1, s);
    for (const gp of c.grps) {
      push(level + 1, gp.grp, gp);
      for (const pp of gp.prods)
        push(level + 2, pp.prod, pp);
    }
  };
  for (const reg of data.regions) {
    push(0, reg.region, reg);
    for (const ps of reg.psList) {
      push(1, ps.ps, ps);
      for (const c of ps.custs) pushCust(2, c);
    }
  }
  push(0, 'TỔNG CỘNG', data.grand);
  const ws = XLSX.utils.aoa_to_sheet(aoa);
  ws['!merges'] = merges;
  ws['!cols'] = cols;
  ws['!rows'] = levels.map((l) => (l == null ? {} : { level: l }));
  const pctSet = new Set(pctCols), numSet = new Set(numCols), intSet = new Set(intCols), moneySet = new Set(moneyCols);
  const numFmt = isSL ? '#,##0' : '#,##0.###';
  for (let r = 2; r < aoa.length; r++) {
    for (let cc = 1; cc <= LAST_COL; cc++) {
      if (pctSet.has(cc)) _fmt(ws, r, cc, '0%');
      else if (moneySet.has(cc)) _fmt(ws, r, cc, '#,##0');
      else if (numSet.has(cc)) _fmt(ws, r, cc, numFmt);
      else if (intSet.has(cc)) _fmt(ws, r, cc, '#,##0');
    }
  }
  XLSX.utils.book_append_sheet(wb, ws, isSL ? 'Theo PS (SL)' : 'Theo PS (Tien)');
}

export async function exportProductSummary(data) {
  const XLSX = await loadXLSX();
  const wb = XLSX.utils.book_new();
  _buildProdSheet(XLSX, wb, data, 'money');
  _buildProdSheet(XLSX, wb, data, 'qty');
  XLSX.writeFile(wb, `TongHop_theo_SP_${_today()}.xlsx`);
}

function _buildProdSheet(XLSX, wb, data, mode) {
  const isSL = mode === 'qty';
  const tr = isSL ? (v) => Math.round(Number(v) || 0) : (v) => (Number(v) || 0) / 1e6;
  const curIdx = Math.max(0, MONTHS.indexOf(CURRENT_MONTH));
  const hasAct = (i) => i <= curIdx;
  const H1 = ['Miền / Nhóm SP / SP / KH'],
    H2 = [''];
  const merges = [{ s: { r: 0, c: 0 }, e: { r: 1, c: 0 } }];
  const cols = [{ wch: 38 }];
  const pctCols = [], numCols = [], moneyCols = [];
  let c = 1;
  if (isSL) {
    H1.push('Đơn giá');
    H2.push('');
    merges.push({ s: { r: 0, c: 1 }, e: { r: 1, c: 1 } });
    cols.push({ wch: 14 });
    moneyCols.push(1);
    c = 2;
  }
  for (let i = 0; i < 12; i++) {
    if (hasAct(i)) {
      H1.push(MONTH_LABELS[i], '', '');
      H2.push('KH update', 'Thực hiện', '% TH');
      merges.push({ s: { r: 0, c }, e: { r: 0, c: c + 2 } });
      cols.push({ wch: 10 }, { wch: 10 }, { wch: 7 });
      numCols.push(c, c + 1);
      pctCols.push(c + 2);
      c += 3;
    } else {
      H1.push(MONTH_LABELS[i]);
      H2.push('KH update');
      cols.push({ wch: 10 });
      numCols.push(c);
      c += 1;
    }
  }
  H1.push('Luỹ kế YTD', '', '', '', '', '');
  H2.push('KH update', 'Thực hiện', '% TH YTD', 'tốc độ TH YTD', 'tốc độ KH YTD', 'CL tốc độ');
  merges.push({ s: { r: 0, c }, e: { r: 0, c: c + 5 } });
  cols.push({ wch: 12 }, { wch: 12 }, { wch: 9 }, { wch: 13 }, { wch: 13 }, { wch: 9 });
  numCols.push(c, c + 1);
  pctCols.push(c + 2, c + 3, c + 4, c + 5);
  c += 6;
  H1.push('Target', '', '', '');
  H2.push(
    isSL ? 'SL đầu năm' : 'Target đầu năm',
    isSL ? 'SL dự kiến' : 'DThu dự kiến',
    'Chênh lệch', 'KH còn lại',
  );
  merges.push({ s: { r: 0, c }, e: { r: 0, c: c + 3 } });
  cols.push({ wch: 14 }, { wch: 14 }, { wch: 13 }, { wch: 13 });
  numCols.push(c, c + 1, c + 2, c + 3);
  c += 4;
  const qCols = HIEN_HET_HIEU_LUC
    ? ['On hand', 'Upcoming', 'Hết hiệu lực', 'Tổng', 'TH YTD', 'Khả dụng']
    : ['On hand', 'Upcoming', 'Tổng', 'TH YTD', 'Khả dụng'];
  H1.push('Quota', ...qCols.slice(1).map(() => ''));
  H2.push(...qCols);
  merges.push({ s: { r: 0, c }, e: { r: 0, c: c + qCols.length - 1 } });
  qCols.forEach((_, k) => { cols.push({ wch: k === qCols.length - 1 ? 13 : 11 }); numCols.push(c + k); });
  c += qCols.length;
  const LAST_COL = c - 1;
  const aoa = [H1, H2];
  const levels = [null, null];
  const push = (level, label, d, price) => {
    const dtV = isSL ? (Number(d.slDauNam) || 0) : (Number(d.dt) || 0);
    const dtUpdV = isSL ? (Number(d.slUpd) || 0) : (Number(d.dtUpd) || 0);
    const ch = dtUpdV - dtV;
    const khYtdV = isSL ? (Number(d.khYtd) || 0) : (Number(d.khYtdDt) || 0);
    const thYtdV = isSL ? (Number(d.thYtd) || 0) : (Number(d.dtYtd) || 0);
    const moKh = isSL ? d.moKh : d.moKhDt;
    const moAct = isSL ? d.moAct : d.moActDt;
    const onHandV = isSL ? (Number(d.onHand) || 0) : (Number(d.onHandDt) || 0);
    const upcomingV = isSL ? (Number(d.upcoming) || 0) : (Number(d.upcomingDt) || 0);
    const hetV = isSL ? (Number(d.het) || 0) : (Number(d.hetDt) || 0);
    const quotaV = isSL ? (Number(d.quota) || 0) : (Number(d.quotaDt) || 0);
    const row = ['   '.repeat(level) + label];
    if (isSL) row.push(price > 0 ? price : '');
    for (let i = 0; i < 12; i++) {
      const kh = moKh[i] || 0, act = moAct[i] || 0;
      if (!hasAct(i)) { row.push(tr(kh)); continue; }
      row.push(tr(kh), tr(act), kh > 0 ? act / kh : '');
    }
    const thP = khYtdV > 0 ? thYtdV / khYtdV : null;
    const tdTh = dtUpdV > 0 ? thYtdV / dtUpdV : null;
    const tdKh = dtUpdV > 0 ? khYtdV / dtUpdV : null;
    const clP = tdTh != null && tdKh != null ? tdTh - tdKh : '';
    row.push(
      tr(khYtdV), tr(thYtdV),
      thP == null ? '' : thP, tdTh == null ? '' : tdTh,
      tdKh == null ? '' : tdKh, clP,
    );
    row.push(tr(dtV), tr(dtUpdV), tr(ch), tr(dtUpdV - thYtdV));
    row.push(
      tr(onHandV), tr(upcomingV), ...(HIEN_HET_HIEU_LUC ? [tr(hetV)] : []), tr(quotaV),
      tr(thYtdV), d.oop ? '-' : tr(onHandV - thYtdV),
    );
    aoa.push(row);
    levels.push(level);
  };
  for (const reg of data.regs) {
    push(0, reg.region, reg, 0);
    for (const g of reg.grps) {
      push(1, g.grp, g, 0);
      for (const p of g.prods) {
        push(2, p.prod, p, p.price || 0);
        for (const cu of p.custs) {
          push(3, cu.cust + (cu.custId ? ` (${cu.custId})` : ''), cu, 0);
          for (const s of cu.subs || [])
            push(4, s.cust + (s.custId ? ` (${s.custId})` : ''), s, 0);
        }
      }
    }
  }
  push(0, 'TỔNG CỘNG', data.grand, 0);
  const ws = XLSX.utils.aoa_to_sheet(aoa);
  ws['!merges'] = merges;
  ws['!cols'] = cols;
  ws['!rows'] = levels.map((l) => (l == null ? {} : { level: l }));
  const pctSet = new Set(pctCols), numSet = new Set(numCols), moneySet = new Set(moneyCols);
  const numFmt = isSL ? '#,##0' : '#,##0.###';
  for (let r = 2; r < aoa.length; r++) {
    for (let cc = 1; cc <= LAST_COL; cc++) {
      if (pctSet.has(cc)) _fmt(ws, r, cc, '0%');
      else if (moneySet.has(cc)) _fmt(ws, r, cc, '#,##0');
      else if (numSet.has(cc)) _fmt(ws, r, cc, numFmt);
    }
  }
  XLSX.utils.book_append_sheet(wb, ws, isSL ? 'Theo SP (SL)' : 'Theo SP (Tien)');
}

// Quota thầu gộp 2 nguồn (view shared.v_quota_thau_xuat) — tạm chỉ admin.
export async function exportQuotaThau(rows) {
  const XLSX = await loadXLSX();
  const LOAI = { cu: 'Thầu cũ', chinh: 'Thầu chính', bo_sung: 'Thầu bổ sung' };
  const H = [
    'Năm TC', 'BU', 'Miền', 'PS', 'Mã KH', 'Khách hàng', 'Nhóm SP', 'Bộ vật tư',
    'Sản phẩm', 'Đơn giá', 'Loại thầu', 'Đợt', 'Tháng thầu', 'Hiệu lực (tháng)', 'Hết hạn', 'SL quota',
    'Thành tiền', 'Trạng thái', 'Nguồn', 'Cảnh báo',
  ];
  const num = (v) => (v === null || v === undefined || v === '' ? '' : Number(v));
  const aoa = [H].concat(
    rows.map((r) => [
      r.nam_tai_chinh, r.bu, r.mien, r.ps, r.ma_khach_hang, r.khach_hang,
      r.nhom_san_pham, r.bo_vat_tu, r.san_pham, num(r.don_gia),
      LOAI[r.loai] || r.loai, num(r.dot), r.thang_thau || '', num(r.hieu_luc), r.het_han || '', num(r.so_luong),
      num(r.thanh_tien), r.trang_thai, r.nguon, r.canh_bao || '',
    ]),
  );
  const ws = XLSX.utils.aoa_to_sheet(aoa);
  ws['!cols'] = [6, 6, 8, 16, 9, 30, 18, 18, 30, 13, 12, 5, 10, 9, 9, 10, 16, 12, 18, 30].map(
    (wch) => ({ wch }),
  );
  ws['!autofilter'] = { ref: `A1:${_ec(aoa.length - 1, H.length - 1)}` };
  ws['!freeze'] = { xSplit: 0, ySplit: 1 };
  for (let r = 1; r < aoa.length; r++) {
    _fmt(ws, r, 9, '#,##0');
    _fmt(ws, r, 15, '#,##0');
    _fmt(ws, r, 16, '#,##0');
  }
  const wb = XLSX.utils.book_new();
  XLSX.utils.book_append_sheet(wb, ws, 'Quota thầu');
  XLSX.writeFile(wb, `Quota_thau_${_today()}.xlsx`);
}
