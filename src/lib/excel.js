import { MONTHS, MONTH_LABELS, CURRENT_MONTH } from '../config/constants.js';

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
  const tr = (v) => (Number(v) || 0) / 1e6;
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
    moneyCols = [],
    intCols = [1];
  let c = 2;
  for (let i = 0; i < 12; i++) {
    if (hasAct(i)) {
      H1.push(MONTH_LABELS[i], '', '');
      H2.push('KH', 'TH', '% TH');
      merges.push({ s: { r: 0, c }, e: { r: 0, c: c + 2 } });
      cols.push({ wch: 10 }, { wch: 10 }, { wch: 7 });
      moneyCols.push(c, c + 1);
      pctCols.push(c + 2);
      c += 3;
    } else {
      H1.push(MONTH_LABELS[i]);
      H2.push('KH');
      cols.push({ wch: 10 });
      moneyCols.push(c);
      c += 1;
    }
  }
  H1.push('Luỹ kế YTD', '', '', '', '', '');
  H2.push('KH', 'TH', '% TH YTD', 'tốc độ TH YTD', 'tốc độ KH YTD', 'CL tốc độ');
  merges.push({ s: { r: 0, c }, e: { r: 0, c: c + 5 } });
  cols.push({ wch: 12 }, { wch: 12 }, { wch: 9 }, { wch: 13 }, { wch: 13 }, { wch: 9 });
  moneyCols.push(c, c + 1);
  pctCols.push(c + 2, c + 3, c + 4, c + 5);
  c += 6;
  H1.push('Quota', '', '', '', '');
  H2.push('On hand', 'Upcoming', 'Tổng quota', 'TH YTD', 'Khả dụng');
  merges.push({ s: { r: 0, c }, e: { r: 0, c: c + 4 } });
  cols.push({ wch: 14 }, { wch: 14 }, { wch: 14 }, { wch: 14 }, { wch: 16 });
  moneyCols.push(c, c + 1, c + 2, c + 3, c + 4);
  c += 5;
  H1.push('Target', '', '');
  H2.push('KH đầu năm', 'KH Update', 'Chênh lệch');
  merges.push({ s: { r: 0, c }, e: { r: 0, c: c + 2 } });
  cols.push({ wch: 12 }, { wch: 12 }, { wch: 12 });
  moneyCols.push(c, c + 1, c + 2);
  c += 3;
  const LAST_COL = c - 1;
  const aoa = [H1, H2];
  const levels = [null, null];
  const push = (level, label, d) => {
    const dt = Number(d.dt) || 0,
      ch = (Number(d.dtUpd) || 0) - dt;
    const khYtdDt = Number(d.khYtdDt) || 0,
      dtYtd = Number(d.dtYtd) || 0;
    const row = [
      '   '.repeat(level) + label,
      Number.isFinite(d.custCount) ? d.custCount : '',
    ];
    for (let i = 0; i < 12; i++) {
      const kh = d.moKhDt[i] || 0,
        act = d.moActDt[i] || 0;
      if (!hasAct(i)) {
        row.push(tr(kh));
        continue;
      }
      row.push(tr(kh), tr(act), kh > 0 ? act / kh : '');
    }
    const dtUpd = Number(d.dtUpd) || 0;
    const thP = khYtdDt > 0 ? dtYtd / khYtdDt : null;
    const tdTh = dtUpd > 0 ? dtYtd / dtUpd : null;
    const tdKh = dtUpd > 0 ? khYtdDt / dtUpd : null;
    const clP = tdTh != null && tdKh != null ? tdTh - tdKh : '';
    row.push(
      tr(khYtdDt), tr(dtYtd),
      thP == null ? '' : thP, tdTh == null ? '' : tdTh,
      tdKh == null ? '' : tdKh, clP,
    );
    const quotaRemain = d.quotaAvailDt == null ? '-' : tr((d.q14Dt || 0) - dtYtd);
    row.push(tr(d.q14Dt || 0), tr(d.qUpcomingDt || 0), tr(d.quotaFYDt || 0), tr(dtYtd), quotaRemain);
    row.push(tr(dt), tr(dtUpd), tr(ch));
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
        push(level + 2, (pp.mset ? pp.mset + ' · ' : '') + pp.prod, pp);
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
  const pctSet = new Set(pctCols),
    moneySet = new Set(moneyCols),
    intSet = new Set(intCols);
  for (let r = 2; r < aoa.length; r++) {
    for (let cc = 1; cc <= LAST_COL; cc++) {
      if (pctSet.has(cc)) _fmt(ws, r, cc, '0%');
      else if (moneySet.has(cc)) _fmt(ws, r, cc, '#,##0.###');
      else if (intSet.has(cc)) _fmt(ws, r, cc, '#,##0');
    }
  }
  const wb = XLSX.utils.book_new();
  XLSX.utils.book_append_sheet(wb, ws, 'Tong hop theo PS');
  XLSX.writeFile(wb, `TongHop_theo_PS_${_today()}.xlsx`);
}

export async function exportProductSummary(data) {
  const XLSX = await loadXLSX();
  const curIdx = Math.max(0, MONTHS.indexOf(CURRENT_MONTH));
  const hasAct = (i) => i <= curIdx;
  const H1 = ['Sản phẩm / Miền / KH'],
    H2 = [''];
  const merges = [{ s: { r: 0, c: 0 }, e: { r: 1, c: 0 } }];
  const cols = [{ wch: 34 }];
  const pctCols = [];
  let c = 1;
  for (let i = 0; i < 12; i++) {
    if (hasAct(i)) {
      H1.push(MONTH_LABELS[i], '', '');
      H2.push('KH update', 'Thực hiện', '% TH');
      merges.push({ s: { r: 0, c }, e: { r: 0, c: c + 2 } });
      cols.push({ wch: 9 }, { wch: 9 }, { wch: 7 });
      pctCols.push(c + 2);
      c += 3;
    } else {
      H1.push(MONTH_LABELS[i]);
      H2.push('KH update');
      cols.push({ wch: 9 });
      c += 1;
    }
  }
  H1.push('Luỹ kế YTD', '', '', '', '', '');
  H2.push('KH update', 'Thực hiện', '% TH YTD', 'tốc độ TH YTD', 'tốc độ KH YTD', 'CL tốc độ');
  merges.push({ s: { r: 0, c }, e: { r: 0, c: c + 5 } });
  cols.push({ wch: 11 }, { wch: 11 }, { wch: 9 }, { wch: 13 }, { wch: 13 }, { wch: 9 });
  pctCols.push(c + 2, c + 3, c + 4, c + 5);
  c += 6;
  H1.push('Quota (SL)', '', '', '', '');
  H2.push('On hand', 'Upcoming', 'Tổng', 'TH YTD', 'Khả dụng');
  merges.push({ s: { r: 0, c }, e: { r: 0, c: c + 4 } });
  cols.push({ wch: 11 }, { wch: 11 }, { wch: 11 }, { wch: 11 }, { wch: 13 });
  c += 5;
  H1.push('Group Target (SL)', '', '');
  H2.push('KH đầu năm', 'KH Update', 'Chênh lệch');
  merges.push({ s: { r: 0, c }, e: { r: 0, c: c + 2 } });
  cols.push({ wch: 13 }, { wch: 13 }, { wch: 13 });
  c += 3;
  const LAST_COL = c - 1;
  const aoa = [H1, H2];
  const levels = [null, null];
  const push = (level, label, d) => {
    const quota = Number(d.quota) || 0,
      thYtd = Number(d.thYtd) || 0,
      khYtd = Number(d.khYtd) || 0;
    const row = ['   '.repeat(level) + label];
    for (let i = 0; i < 12; i++) {
      const kh = Math.round(d.moKh[i] || 0);
      if (!hasAct(i)) {
        row.push(kh);
        continue;
      }
      const act = Math.round(d.moAct[i] || 0);
      row.push(kh, act, kh > 0 ? act / kh : '');
    }
    const totKh = d.moKh.reduce((s, v, i) => s + (i < curIdx ? d.moAct[i] || 0 : v), 0);
    const thP = khYtd > 0 ? thYtd / khYtd : null;
    const tdTh = totKh > 0 ? thYtd / totKh : null;
    const tdKh = totKh > 0 ? khYtd / totKh : null;
    const clP = tdTh != null && tdKh != null ? tdTh - tdKh : '';
    row.push(
      Math.round(khYtd), Math.round(thYtd),
      thP == null ? '' : thP, tdTh == null ? '' : tdTh,
      tdKh == null ? '' : tdKh, clP,
    );
    const onHand = Number(d.onHand) || 0,
      upcoming = Number(d.upcoming) || 0;
    row.push(
      Math.round(onHand), Math.round(upcoming), Math.round(quota),
      Math.round(thYtd), d.oop ? '-' : Math.round(onHand - thYtd),
    );
    const slDauNam = Math.round(d.slDauNam || 0);
    const slUpd = Math.round(totKh);
    row.push(slDauNam, slUpd, slUpd - slDauNam);
    aoa.push(row);
    levels.push(level);
  };
  for (const p of data.prods) {
    push(0, p.prod, p);
    for (const rg of p.regs) {
      push(1, rg.region, rg);
      for (const cu of rg.custs) {
        push(2, cu.cust + (cu.custId ? ` (${cu.custId})` : ''), cu);
        for (const s of cu.subs || [])
          push(3, s.cust + (s.custId ? ` (${s.custId})` : ''), s);
      }
    }
  }
  push(0, 'TỔNG CỘNG', data.grand);
  const ws = XLSX.utils.aoa_to_sheet(aoa);
  ws['!merges'] = merges;
  ws['!cols'] = cols;
  ws['!rows'] = levels.map((l) => (l == null ? {} : { level: l }));
  const pctSet = new Set(pctCols);
  for (let r = 2; r < aoa.length; r++) {
    for (let cc = 1; cc <= LAST_COL; cc++)
      _fmt(ws, r, cc, pctSet.has(cc) ? '0%' : '#,##0');
  }
  const wb = XLSX.utils.book_new();
  XLSX.utils.book_append_sheet(wb, ws, 'Tong hop theo SP');
  XLSX.writeFile(wb, `TongHop_theo_SP_${_today()}.xlsx`);
}
