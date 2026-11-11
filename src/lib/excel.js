import { MONTHS, MONTH_LABELS, CURRENT_MONTH, HIEN_HET_HIEU_LUC, NO_MSET, isYtdMonth } from '../config/constants.js';
import { quotaSanPham } from './quota.js';

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

// base: 'upd' = so thực hiện với KH update, 'dn' = so với Target đầu năm
export async function exportSummaryPS(data, base = 'upd') {
  const XLSX = await loadXLSX();
  const wb = XLSX.utils.book_new();
  _buildSumPSSheet(XLSX, wb, data, 'money', base);
  _buildSumPSSheet(XLSX, wb, data, 'qty', base);
  const suffix = base === 'dn' ? '_vs_Target' : '';
  XLSX.writeFile(wb, `TongHop_theo_PS${suffix}_${_today()}.xlsx`);
}

function _buildSumPSSheet(XLSX, wb, data, mode, base) {
  const isSL = mode === 'qty';
  const isDn = base === 'dn';
  const kh = isDn ? 'Target' : 'KH';
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
      H2.push(kh, 'TH', '% TH');
      merges.push({ s: { r: 0, c }, e: { r: 0, c: c + 2 } });
      cols.push({ wch: 10 }, { wch: 10 }, { wch: 7 });
      numCols.push(c, c + 1);
      pctCols.push(c + 2);
      c += 3;
    } else {
      H1.push(MONTH_LABELS[i]);
      H2.push(kh);
      cols.push({ wch: 10 });
      numCols.push(c);
      c += 1;
    }
  }
  H1.push('Luỹ kế YTD', '', '', '', '', '');
  H2.push(kh, 'TH', '% TH YTD', 'tốc độ TH YTD', `tốc độ ${kh} YTD`, 'CL tốc độ');
  merges.push({ s: { r: 0, c }, e: { r: 0, c: c + 5 } });
  cols.push({ wch: 12 }, { wch: 12 }, { wch: 9 }, { wch: 13 }, { wch: 13 }, { wch: 9 });
  numCols.push(c, c + 1);
  pctCols.push(c + 2, c + 3, c + 4, c + 5);
  c += 6;
  // Mốc KH update có thêm cột % DThu dự kiến / Target đầu năm ngay sau DThu dự kiến.
  if (isDn) {
    H1.push('Cả năm', '', '', '');
    H2.push(isSL ? 'SL đầu năm' : 'Target đầu năm', 'TH YTD', '% HT năm', 'Còn lại');
  } else {
    H1.push('Target', '', '', '', '');
    H2.push(
      isSL ? 'SL đầu năm' : 'Target đầu năm',
      isSL ? 'SL dự kiến' : 'DThu dự kiến',
      isSL ? '% Dự kiến / SL ĐN' : '% Dự kiến / Target',
      'Chênh lệch',
      'KH còn lại',
    );
  }
  merges.push({ s: { r: 0, c }, e: { r: 0, c: c + (isDn ? 3 : 4) } });
  if (isDn) {
    cols.push({ wch: 14 }, { wch: 14 }, { wch: 12 }, { wch: 12 });
    numCols.push(c, c + 1, c + 3);
    pctCols.push(c + 2);
    c += 4;
  } else {
    cols.push({ wch: 14 }, { wch: 14 }, { wch: 12 }, { wch: 12 }, { wch: 12 });
    numCols.push(c, c + 1, c + 3, c + 4);
    pctCols.push(c + 2);
    c += 5;
  }
  const qCols = HIEN_HET_HIEU_LUC
    ? ['On hand', 'Upcoming', 'Hết hiệu lực', 'Tổng quota', 'TH YTD', 'Khả dụng', 'KD định mức']
    : ['On hand', 'Upcoming', 'Tổng quota', 'TH YTD', 'Khả dụng', 'KD định mức'];
  H1.push('Quota', ...qCols.slice(1).map(() => ''));
  H2.push(...qCols);
  merges.push({ s: { r: 0, c }, e: { r: 0, c: c + qCols.length - 1 } });
  qCols.forEach((_, k) => { cols.push({ wch: k >= qCols.length - 2 ? 16 : 14 }); numCols.push(c + k); });
  c += qCols.length;
  const LAST_COL = c - 1;
  const aoa = [H1, H2];
  const levels = [null, null];
  const push = (level, label, d) => {
    const dtV = isSL ? (Number(d.slDauNam) || 0) : (Number(d.dt) || 0);
    // Mốc Target đầu năm: mẫu số tốc độ / KH theo tháng / KH YTD đều lấy theo target gốc
    const dtUpdV = isDn ? dtV : isSL ? (Number(d.slUpd) || 0) : (Number(d.dtUpd) || 0);
    const ch = dtUpdV - dtV;
    const khYtdV = isDn
      ? (isSL ? (Number(d.dnYtd) || 0) : (Number(d.dnYtdDt) || 0))
      : isSL ? (Number(d.khYtd) || 0) : (Number(d.khYtdDt) || 0);
    const dtYtdV = isSL ? (Number(d.ytd) || 0) : (Number(d.dtYtd) || 0);
    const moKh = isDn ? (isSL ? d.moDn : d.moDnDt) : isSL ? d.moKh : d.moKhDt;
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
    if (isDn) row.push(tr(dtV), tr(dtYtdV), dtV > 0 ? dtYtdV / dtV : '', tr(dtV - dtYtdV));
    else row.push(tr(dtV), tr(dtUpdV), dtV > 0 ? dtUpdV / dtV : '', tr(ch), tr(dtUpdV - dtYtdV));
    const q14V = isSL ? (d.q14 || 0) : (d.q14Dt || 0);
    const qUpV = isSL ? (d.qUpcoming || 0) : (d.qUpcomingDt || 0);
    const qHetV = isSL ? (d.qHet || 0) : (d.qHetDt || 0);
    const qFYV = isSL ? (d.quotaFY || 0) : (d.quotaFYDt || 0);
    const qAvail = isSL ? d.quotaAvail : d.quotaAvailDt;
    // TH YTD của nhóm Quota lấy như màn (mọi dòng thực hiện), để On hand − TH YTD = Khả dụng.
    const qYtdV = isSL ? (d.ytd || 0) : (d.dtYtd || 0);
    // Cùng số với màn: on hand − TH YTD, khả dụng âm của BV tư đã tính là 0.
    const quotaRemain = qAvail == null ? '-' : tr(qAvail);
    // Khả dụng định mức = quota 1.4 + phần quota chính / BS rơi vào năm tài chính.
    const qDmV = isSL ? (d.qDinhMuc || 0) : (d.qDinhMucDt || 0);
    row.push(tr(q14V), tr(qUpV), ...(HIEN_HET_HIEU_LUC ? [tr(qHetV)] : []), tr(qFYV), tr(qYtdV), quotaRemain, tr(qDmV));
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

// base: 'upd' = so thực hiện với KH update, 'dn' = so với Target đầu năm (giống màn PS)
export async function exportProductSummary(data, base = 'upd') {
  const XLSX = await loadXLSX();
  const wb = XLSX.utils.book_new();
  _buildProdSheet(XLSX, wb, data, 'money', base);
  _buildProdSheet(XLSX, wb, data, 'qty', base);
  const suffix = base === 'dn' ? '_vs_Target' : '';
  XLSX.writeFile(wb, `TongHop_theo_SP${suffix}_${_today()}.xlsx`);
}

function _buildProdSheet(XLSX, wb, data, mode, base) {
  const isSL = mode === 'qty';
  const isDn = base === 'dn';
  const kh = isDn ? 'Target' : 'KH update';
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
      H2.push(kh, 'Thực hiện', '% TH');
      merges.push({ s: { r: 0, c }, e: { r: 0, c: c + 2 } });
      cols.push({ wch: 10 }, { wch: 10 }, { wch: 7 });
      numCols.push(c, c + 1);
      pctCols.push(c + 2);
      c += 3;
    } else {
      H1.push(MONTH_LABELS[i]);
      H2.push(kh);
      cols.push({ wch: 10 });
      numCols.push(c);
      c += 1;
    }
  }
  H1.push('Luỹ kế YTD', '', '', '', '', '');
  H2.push(kh, 'Thực hiện', '% TH YTD', 'tốc độ TH YTD', `tốc độ ${isDn ? 'Target' : 'KH'} YTD`, 'CL tốc độ');
  merges.push({ s: { r: 0, c }, e: { r: 0, c: c + 5 } });
  cols.push({ wch: 12 }, { wch: 12 }, { wch: 9 }, { wch: 13 }, { wch: 13 }, { wch: 9 });
  numCols.push(c, c + 1);
  pctCols.push(c + 2, c + 3, c + 4, c + 5);
  c += 6;
  // Mốc KH update có thêm cột % DThu dự kiến / Target đầu năm ngay sau DThu dự kiến.
  if (isDn) {
    H1.push('Cả năm', '', '', '');
    H2.push(isSL ? 'SL đầu năm' : 'Target đầu năm', 'TH YTD', '% HT năm', 'Còn lại');
  } else {
    H1.push('Target', '', '', '', '');
    H2.push(
      isSL ? 'SL đầu năm' : 'Target đầu năm',
      isSL ? 'SL dự kiến' : 'DThu dự kiến',
      isSL ? '% Dự kiến / SL ĐN' : '% Dự kiến / Target',
      'Chênh lệch',
      'KH còn lại',
    );
  }
  merges.push({ s: { r: 0, c }, e: { r: 0, c: c + (isDn ? 3 : 4) } });
  if (isDn) {
    cols.push({ wch: 14 }, { wch: 14 }, { wch: 13 }, { wch: 13 });
    numCols.push(c, c + 1, c + 3);
    pctCols.push(c + 2);
    c += 4;
  } else {
    cols.push({ wch: 14 }, { wch: 14 }, { wch: 13 }, { wch: 13 }, { wch: 13 });
    numCols.push(c, c + 1, c + 3, c + 4);
    pctCols.push(c + 2);
    c += 5;
  }
  const qCols = HIEN_HET_HIEU_LUC
    ? ['On hand', 'Upcoming', 'Hết hiệu lực', 'Tổng', 'TH YTD', 'Khả dụng', 'KD định mức']
    : ['On hand', 'Upcoming', 'Tổng', 'TH YTD', 'Khả dụng', 'KD định mức'];
  H1.push('Quota', ...qCols.slice(1).map(() => ''));
  H2.push(...qCols);
  merges.push({ s: { r: 0, c }, e: { r: 0, c: c + qCols.length - 1 } });
  qCols.forEach((_, k) => { cols.push({ wch: k >= qCols.length - 2 ? 13 : 11 }); numCols.push(c + k); });
  c += qCols.length;
  const LAST_COL = c - 1;
  const aoa = [H1, H2];
  const levels = [null, null];
  const push = (level, label, d, price) => {
    const dtV = isSL ? (Number(d.slDauNam) || 0) : (Number(d.dt) || 0);
    // Mốc Target đầu năm: mẫu số tốc độ / KH theo tháng / KH YTD đều lấy theo target gốc
    const dtUpdV = isDn ? dtV : isSL ? (Number(d.slUpd) || 0) : (Number(d.dtUpd) || 0);
    const ch = dtUpdV - dtV;
    const khYtdV = isDn
      ? (isSL ? (Number(d.dnYtd) || 0) : (Number(d.dnYtdDt) || 0))
      : isSL ? (Number(d.khYtd) || 0) : (Number(d.khYtdDt) || 0);
    const thYtdV = isSL ? (Number(d.thYtd) || 0) : (Number(d.dtYtd) || 0);
    const moKh = isDn ? (isSL ? d.moKhDauNam : d.moKhDauNamDt) : isSL ? d.moKh : d.moKhDt;
    const moAct = isSL ? d.moAct : d.moActDt;
    const onHandV = isSL ? (Number(d.onHand) || 0) : (Number(d.onHandDt) || 0);
    const upcomingV = isSL ? (Number(d.upcoming) || 0) : (Number(d.upcomingDt) || 0);
    const hetV = isSL ? (Number(d.het) || 0) : (Number(d.hetDt) || 0);
    const quotaV = isSL ? (Number(d.quota) || 0) : (Number(d.quotaDt) || 0);
    // Khả dụng âm của BV tư đã tính là 0 (phần bù kdBu, giống màn).
    const kdBuV = isSL ? (Number(d.kdBu) || 0) : (Number(d.kdBuDt) || 0);
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
    if (isDn) row.push(tr(dtV), tr(thYtdV), dtV > 0 ? thYtdV / dtV : '', tr(dtV - thYtdV));
    else row.push(tr(dtV), tr(dtUpdV), dtV > 0 ? dtUpdV / dtV : '', tr(ch), tr(dtUpdV - thYtdV));
    row.push(
      tr(onHandV), tr(upcomingV), ...(HIEN_HET_HIEU_LUC ? [tr(hetV)] : []), tr(quotaV),
      tr(thYtdV), d.oop ? '-' : tr(onHandV - thYtdV + kdBuV),
      tr(isSL ? d.dinhMuc : d.dinhMucDt),
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

// So sánh DThu KH update giữa 2 kỳ chụp (tab So sánh KH update), chi tiết BU × miền × PS × KH × nhóm SP.
// Sheet 1: mỗi dòng BU × miền × PS × KH × nhóm, tổng 2 kỳ + chênh từng tháng. Sheet 2: dòng phẳng theo tháng.
// theo: cột tháng ở sheet tổng hợp là 'chenh' (B − A), 'a' (số kỳ gốc) hay 'b' (số bên so sánh).
// mocTH: tháng hiện tại lúc chụp của bên đang xuất (theo 'a'/'b'); tháng trước đó thêm cột KH upd.
export async function exportSoSanhKeHoach(rows, tenA, tenB, theo = 'chenh', mocTH = '') {
  const XLSX = await loadXLSX();
  const thang = MONTHS.filter((m) => rows.some((r) => r.mo === m));
  const laTH = (m) => theo !== 'chenh' && !!mocTH && m < mocTH;
  const nhom = new Map();
  for (const r of rows) {
    const k = [r.bu, r.region, r.ps, r.custId, r.grp].join('||');
    let g = nhom.get(k);
    if (!g) {
      g = { ...r, dtA: 0, dtB: 0, t: new Map(), kh: new Map() };
      nhom.set(k, g);
    }
    g.dtA += r.dtA;
    g.dtB += r.dtB;
    const v = theo === 'a' ? r.dtA : theo === 'b' ? r.dtB : r.dtB - r.dtA;
    g.t.set(r.mo, (g.t.get(r.mo) || 0) + v);
    g.kh.set(r.mo, (g.kh.get(r.mo) || 0) + (theo === 'a' ? r.khA || 0 : r.khB || 0));
  }
  const sx = (a, b) =>
    (a.bu || '').localeCompare(b.bu || '') ||
    (a.region || '').localeCompare(b.region || '') ||
    (a.ps || '').localeCompare(b.ps || '') ||
    (a.cust || '').localeCompare(b.cust || '') ||
    (a.grp || '').localeCompare(b.grp || '');
  const H1 = [
    'Năm TC', 'BU', 'Miền', 'PS', 'Mã KH', 'Khách hàng', 'Nhóm SP',
    `DThu ${tenA}`, `DThu ${tenB}`, 'Chênh', '% chênh',
    ...thang.flatMap((m) => {
      const ten = `${theo === 'a' ? tenA : theo === 'b' ? tenB : 'Chênh'} ${MONTH_LABELS[MONTHS.indexOf(m)]}`;
      return laTH(m) ? [`${ten} KH upd`, `${ten} TH`] : [ten];
    }),
  ];
  const aoa1 = [H1].concat(
    [...nhom.values()].sort(sx).map((g) => [
      g.fy, g.bu, g.region, g.ps, g.custId, g.cust, g.grp, g.dtA, g.dtB, g.dtB - g.dtA,
      g.dtA ? (g.dtB - g.dtA) / Math.abs(g.dtA) : '',
      ...thang.flatMap((m) => {
        const v = g.t.has(m) ? g.t.get(m) : '';
        return laTH(m) ? [g.t.has(m) ? g.kh.get(m) : '', v] : [v];
      }),
    ]),
  );
  const ws1 = XLSX.utils.aoa_to_sheet(aoa1);
  ws1['!cols'] = [6, 6, 8, 16, 9, 30, 22, 16, 16, 14, 8, ...thang.flatMap((m) => (laTH(m) ? [14, 12] : [12]))].map(
    (wch) => ({ wch }),
  );
  ws1['!autofilter'] = { ref: `A1:${_ec(aoa1.length - 1, H1.length - 1)}` };
  for (let r = 1; r < aoa1.length; r++) {
    for (let c = 7; c < H1.length; c++) _fmt(ws1, r, c, c === 10 ? '0.0%' : '#,##0');
  }

  const H2 = [
    'Năm TC', 'Tháng', 'BU', 'Miền', 'PS', 'Mã KH', 'Khách hàng', 'Nhóm SP', `DThu ${tenA}`, `DThu ${tenB}`, 'Chênh',
    `KH upd (SL × giá) ${tenA}`, `KH upd (SL × giá) ${tenB}`,
  ];
  const aoa2 = [H2].concat(
    [...rows]
      .sort((a, b) => sx(a, b) || (a.mo || '').localeCompare(b.mo || ''))
      .map((r) => [
        r.fy, r.mo, r.bu, r.region, r.ps, r.custId, r.cust, r.grp, r.dtA, r.dtB, r.dtB - r.dtA, r.khA || 0, r.khB || 0,
      ]),
  );
  const ws2 = XLSX.utils.aoa_to_sheet(aoa2);
  ws2['!cols'] = [6, 8, 6, 8, 16, 9, 30, 22, 16, 16, 14, 18, 18].map((wch) => ({ wch }));
  ws2['!autofilter'] = { ref: `A1:${_ec(aoa2.length - 1, H2.length - 1)}` };
  for (let r = 1; r < aoa2.length; r++) for (let c = 8; c <= 12; c++) _fmt(ws2, r, c, '#,##0');

  const wb = XLSX.utils.book_new();
  XLSX.utils.book_append_sheet(wb, ws1, 'BU-Miền-PS-KH-Nhóm');
  XLSX.utils.book_append_sheet(wb, ws2, 'Chi tiết tháng');
  XLSX.writeFile(wb, `SoSanh_KH_update_${_today()}.xlsx`);
}

// Tab Chi tiết kế hoạch: mỗi dòng = 1 sản phẩm (KH × nhóm SP × PS × SP × đơn giá) đúng như
// lưới trên màn hình, theo bộ lọc + tìm kiếm đang áp. Số liệu tính giống ProductGroupSection:
// SL update tháng đã qua (hoặc tháng hiện tại đã có thực hiện) = SL thực hiện.
// tree: cây KH của màn Chi tiết; quota: { dotsByGroup, quotasByProduct } từ QuotaThauCtx.
export async function exportChiTietKeHoach(tree, quota) {
  const XLSX = await loadXLSX();
  const qCols = HIEN_HET_HIEU_LUC
    ? ['Quota 1/4', 'Quota thầu chính', 'Quota thầu bổ sung', 'Quota hết hiệu lực', 'Tổng quota']
    : ['Quota 1/4', 'Quota thầu chính', 'Quota thầu bổ sung', 'Tổng quota'];
  const H = [
    'BU', 'Miền', 'PS', 'Mã KH', 'Khách hàng', 'Nhóm SP', 'Mã SP', 'Sản phẩm', 'Đơn giá',
    ...qCols, 'Tháng mở thầu', 'Hiệu lực thầu (tháng)', 'Quota on hand', 'SL TH YTD', 'Quota khả dụng',
    ...MONTH_LABELS.map((m) => `SL đầu năm ${m}`), 'Tổng SL đầu năm', 'DThu KH đầu năm',
    ...MONTH_LABELS.map((m) => `SL update ${m}`), 'Tổng SL update', 'DThu KH update', 'Chênh lệch DThu',
    'DThu TH YTD',
  ];
  const aoa = [H];
  for (const c of tree) {
    for (const g of c.groups) {
      for (const p of g.products) {
        const allRows = p.monthly.flatMap((cell) => cell.rows);
        const anchor = allRows[0] || null;
        const q = quota ? quotaSanPham(quota.dotsByGroup, quota.quotasByProduct, anchor, p.mset, p.product, CURRENT_MONTH) : null;
        let ytd = 0, dtBase = 0, dtUpd = 0, dtThYtd = 0, slDn = 0, slUpd = 0;
        const dn = [], upd = [];
        p.monthly.forEach((cell, i) => {
          const mo = MONTHS[i];
          const daTH = mo < CURRENT_MONTH || (mo === CURRENT_MONTH && cell.hasAct);
          const u = daTH ? cell.act : cell.hasUpd ? cell.revUpd : cell.rev;
          dn.push(cell.rev);
          upd.push(u);
          slDn += cell.rev;
          slUpd += u;
          if (isYtdMonth(mo)) ytd += cell.act;
          cell.rows.forEach((r) => {
            const pr = Number(r.price) || 0;
            const act = Number(r.act) || 0;
            const useAct = mo < CURRENT_MONTH || (mo === CURRENT_MONTH && act !== 0);
            dtBase += (Number(r.rev) || 0) * pr;
            const v = useAct
              ? act
              : r.revUpd !== undefined && r.revUpd !== '' && r.revUpd !== null
                ? Number(r.revUpd) || 0
                : Number(r.rev) || 0;
            dtUpd += v * pr;
            if (isYtdMonth(mo)) dtThYtd += Number(r.dtAct) || 0;
          });
        });
        const cu = q?.cu || 0, chinh = q?.chinh || 0, bs = q?.bo_sung || 0;
        const het = q && HIEN_HET_HIEU_LUC ? q.het : 0;
        // Nhiều đợt (thầu chính + bổ sung) thì nối bằng "; " theo cùng thứ tự ở 2 cột.
        const dotSp = q?.dots || [];
        const thangThau = dotSp.map((d) => d.thang || '?').join('; ');
        const hieuLuc =
          dotSp.length === 1 && Number(dotSp[0].thoiGian) > 0
            ? Number(dotSp[0].thoiGian)
            : dotSp.map((d) => (Number(d.thoiGian) > 0 ? Number(d.thoiGian) : '?')).join('; ');
        aoa.push([
          g.bu || '', c.region || '', g.ps || '', c.custId || '', c.customer || '', g.name || '',
          p.mset === NO_MSET ? '' : p.mset || '', p.product || '', p.pPrice || 0,
          cu, chinh, bs, ...(HIEN_HET_HIEU_LUC ? [het] : []), cu + chinh + bs - het,
          thangThau, hieuLuc,
          q?.onHand || 0, ytd, q?.hasQuota ? (q.onHand || 0) - ytd : '',
          ...dn, slDn, dtBase,
          ...upd, slUpd, dtUpd, dtUpd - dtBase,
          dtThYtd,
        ]);
      }
    }
  }
  const ws = XLSX.utils.aoa_to_sheet(aoa);
  ws['!cols'] = [
    6, 8, 16, 10, 34, 22, 16, 34, 13,
    ...qCols.map(() => 10), 13, 10, 11, 10, 11,
    ...MONTHS.map(() => 9), 11, 15,
    ...MONTHS.map(() => 9), 11, 15, 14,
    15,
  ].map((wch) => ({ wch }));
  ws['!autofilter'] = { ref: `A1:${_ec(aoa.length - 1, H.length - 1)}` };
  ws['!freeze'] = { xSplit: 0, ySplit: 1 };
  const cThang = H.indexOf('Tháng mở thầu');
  for (let r = 1; r < aoa.length; r++)
    for (let cc = 8; cc < H.length; cc++) if (cc !== cThang) _fmt(ws, r, cc, '#,##0');
  const wb = XLSX.utils.book_new();
  XLSX.utils.book_append_sheet(wb, ws, 'Chi tiết kế hoạch');
  XLSX.writeFile(wb, `ChiTiet_KeHoach_${_today()}.xlsx`);
}
