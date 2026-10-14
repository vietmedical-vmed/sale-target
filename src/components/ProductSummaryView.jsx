import React, { useState, useEffect, useMemo, useCallback } from 'react';
import { Filter } from './icons.jsx';
import {
  MONTHS, MONTH_LABELS, CURRENT_MONTH, OOP_CUST, MASK_MONEY, isYtdMonth, HIEN_HET_HIEU_LUC,
} from '../config/constants.js';
import { fmtInt, fmtTy3, moneyTy3, moneyPrice } from '../lib/format.js';
import { inSel, planCustKeys, custInPlan, matchSearch } from '../lib/text.js';
import { useFitHeight, useSummaryScrollbar, useStickyRows } from '../hooks/useLayout.jsx';
import { exportProductSummary } from '../lib/excel.js';

const chCls = (v) =>
  v > 0 ? 'text-emerald-700' : v < 0 ? 'text-red-600' : 'text-slate-400';

const fmtSL = (v) => (!v ? '—' : Math.round(v).toLocaleString('en-US'));

export function ProductSummaryView({
  rows,
  psFilter,
  regionFilter,
  custFilter,
  groupFilter,
  search,
  onExport,
}) {
  const [open, setOpen] = useState(() => new Set());
  const [showMonths, setShowMonths] = useState(false);
  const [viewMode, setViewMode] = useState('money');
  const boxRef = useFitHeight();
  useSummaryScrollbar(boxRef);
  useStickyRows(boxRef);

  const data = useMemo(() => {
    const q = (search || '').toLowerCase().trim();
    const filtered = rows.filter(
      (r) =>
        inSel(psFilter, r.ps) &&
        inSel(regionFilter, r.region) &&
        inSel(custFilter, r.cust) &&
        inSel(groupFilter, r.grp) &&
        matchSearch(r, q),
    );
    const planCusts = planCustKeys(rows);
    const curIdx = Math.max(0, MONTHS.indexOf(CURRENT_MONTH));
    const blank = () => ({
      moKh: MONTHS.map(() => 0),
      moAct: MONTHS.map(() => 0),
      moKhDt: MONTHS.map(() => 0),
      moActDt: MONTHS.map(() => 0),
      moKhDauNam: MONTHS.map(() => 0),
      moKhDauNamDt: MONTHS.map(() => 0),
      thYtd: 0,
      khYtd: 0,
      dtYtd: 0,
      khYtdDt: 0,
      onHand: 0,
      upcoming: 0,
      quota: 0,
      onHandDt: 0,
      upcomingDt: 0,
      quotaDt: 0,
      het: 0,
      hetDt: 0,
      slDauNam: 0,
      dt: 0,
      slUpd: 0,
      dtUpd: 0,
    });
    const regMap = new Map();
    for (const r of filtered) {
      const i = MONTHS.indexOf(r.mo);
      if (i < 0) continue;
      const price = Number(r.price) || 0;
      const dtActVal = Number(r.dtAct) || 0;
      const isPast = isYtdMonth(r.mo);
      const actQty = Number(r.act) || 0;
      const dSlDauNam = Number(r.rev) || 0;
      const planUpd =
        r.revUpd !== undefined && r.revUpd !== '' && r.revUpd !== null
          ? Number(r.revUpd) || 0
          : Number(r.rev) || 0;
      const updQty = (i < curIdx) ? actQty : planUpd;
      const dOnHand = Number(r._qOnHand) || 0;
      const dUpcoming = Number(r._qUp) || 0;
      const dQuota = dOnHand + dUpcoming;
      const dHet = Number(r._qHet) || 0; // hết hiệu lực: hiện riêng, không vào tổng
      const isOop = !!r._oop && !custInPlan(planCusts, r);
      const dMoKhDt = planUpd * price;
      const dMoActDt = dtActVal;

      const bump = (o) => {
        o.moKh[i] += planUpd;
        o.moAct[i] += actQty;
        o.moKhDt[i] += dMoKhDt;
        o.moActDt[i] += dMoActDt;
        o.moKhDauNam[i] += dSlDauNam;
        o.moKhDauNamDt[i] += dSlDauNam * price;
        o.onHand += dOnHand;
        o.upcoming += dUpcoming;
        o.quota += dQuota;
        o.onHandDt += dOnHand * price;
        o.upcomingDt += dUpcoming * price;
        o.quotaDt += dQuota * price;
        o.het += dHet;
        o.hetDt += dHet * price;
        o.slDauNam += dSlDauNam;
        o.dt += dSlDauNam * price;
        o.slUpd += updQty;
        o.dtUpd += (i < curIdx) ? dtActVal : updQty * price;
        if (isPast) {
          o.thYtd += actQty;
          o.dtYtd += dtActVal;
          if (!isOop) {
            o.khYtd += planUpd;
            o.khYtdDt += dMoKhDt;
          }
        }
      };

      // Region (top level)
      const rKey = r.region || '(Không rõ miền)';
      if (!regMap.has(rKey))
        regMap.set(rKey, { region: rKey, grpMap: new Map(), ...blank() });
      const regNode = regMap.get(rKey);

      // Group layer
      const gKey = r.grp || '(Không rõ nhóm SP)';
      if (!regNode.grpMap.has(gKey))
        regNode.grpMap.set(gKey, { grp: gKey, prodMap: new Map(), ...blank() });
      const gNode = regNode.grpMap.get(gKey);

      // Product layer
      const pKey = r.prod || '(Không rõ SP)';
      if (!gNode.prodMap.has(pKey))
        gNode.prodMap.set(pKey, { prod: pKey, mset: r.mset || '', price: 0, custMap: new Map(), ...blank() });
      const pNode = gNode.prodMap.get(pKey);
      if (!pNode.mset && r.mset) pNode.mset = r.mset;
      if (price > 0) {
        if (pNode.price === 0) pNode.price = price;
        else if (pNode.price > 0 && pNode.price !== price) pNode.price = -1;
      }

      bump(regNode);
      bump(gNode);
      bump(pNode);

      // Customer layer (under product)
      const cKey = isOop ? OOP_CUST : r.cust || '—';
      if (!pNode.custMap.has(cKey))
        pNode.custMap.set(cKey, {
          cust: cKey,
          custId: isOop ? '' : r.custId,
          oop: isOop,
          subMap: new Map(),
          ...blank(),
        });
      const cc = pNode.custMap.get(cKey);
      bump(cc);
      if (isOop && r.cust && r.cust !== OOP_CUST) {
        if (!cc.subMap.has(r.cust))
          cc.subMap.set(r.cust, {
            cust: r.cust,
            custId: r.custId,
            oop: true,
            subMap: new Map(),
            ...blank(),
          });
        bump(cc.subMap.get(r.cust));
      }
    }
    const fold = () => ({ ...blank() });
    const add = (a, c) => {
      for (let i = 0; i < 12; i++) {
        a.moKh[i] += c.moKh[i];
        a.moAct[i] += c.moAct[i];
        a.moKhDt[i] += c.moKhDt[i];
        a.moActDt[i] += c.moActDt[i];
        a.moKhDauNam[i] += c.moKhDauNam[i];
        a.moKhDauNamDt[i] += c.moKhDauNamDt[i];
      }
      a.thYtd += c.thYtd;
      a.khYtd += c.khYtd;
      a.dtYtd += c.dtYtd;
      a.khYtdDt += c.khYtdDt;
      a.onHand += c.onHand;
      a.upcoming += c.upcoming;
      a.quota += c.quota;
      a.onHandDt += c.onHandDt;
      a.upcomingDt += c.upcomingDt;
      a.quotaDt += c.quotaDt;
      a.het += c.het;
      a.hetDt += c.hetDt;
      a.slDauNam += c.slDauNam;
      a.dt += c.dt;
      a.slUpd += c.slUpd;
      a.dtUpd += c.dtUpd;
      return a;
    };
    const sumMo = (mo) => mo.reduce((s, v) => s + v, 0);
    const regs = Array.from(regMap.values()).map((reg) => {
      const grps = Array.from(reg.grpMap.values()).map((g) => {
        const prods = Array.from(g.prodMap.values()).map((p) => {
          const custs = Array.from(p.custMap.values()).map((cu) => {
            const subs = Array.from(cu.subMap.values());
            subs.sort((a, b) => b.thYtd - a.thYtd);
            return { ...cu, subs };
          });
          custs.sort((a, b) => sumMo(b.moKh) - sumMo(a.moKh));
          return { ...p, custs };
        });
        prods.sort((a, b) => {
          const aUnk = a.prod === '(Không rõ SP)' ? 1 : 0;
          const bUnk = b.prod === '(Không rõ SP)' ? 1 : 0;
          if (aUnk !== bUnk) return aUnk - bUnk;
          return a.prod.localeCompare(b.prod, 'vi');
        });
        return { ...g, prods };
      });
      grps.sort((a, b) => {
        const aUnk = a.grp.startsWith('(') ? 1 : 0;
        const bUnk = b.grp.startsWith('(') ? 1 : 0;
        if (aUnk !== bUnk) return aUnk - bUnk;
        return a.grp.localeCompare(b.grp, 'vi');
      });
      return { ...reg, grps };
    });
    regs.sort((a, b) => a.region.localeCompare(b.region, 'vi'));
    return { regs, grand: regs.reduce(add, fold()) };
  }, [rows, psFilter, regionFilter, custFilter, groupFilter, search]);

  const toggle = (k) =>
    setOpen((prev) => {
      const n = new Set(prev);
      n.has(k) ? n.delete(k) : n.add(k);
      return n;
    });

  const curIdx = Math.max(0, MONTHS.indexOf(CURRENT_MONTH));
  const hasAct = (i) => i <= curIdx;
  const monthIdxs = showMonths
    ? MONTHS.map((_, i) => i)
    : MONTHS.indexOf(CURRENT_MONTH) >= 0
      ? [curIdx]
      : [];
  const N_COLS =
    1 + monthIdxs.reduce((s, i) => s + (hasAct(i) ? 3 : 1), 0) + 6 + (HIEN_HET_HIEU_LUC ? 6 : 5) + 4;

  const pctTxt = (th, kh) => (kh > 0 ? Math.round((th / kh) * 100) + '%' : '—');
  const pctCls = (th, kh) => {
    if (!(kh > 0)) return 'text-slate-300';
    const r = th / kh;
    return r >= 1
      ? 'text-green-700'
      : r >= 0.8
        ? 'text-amber-600'
        : 'text-red-600';
  };
  const moBg = (i) =>
    MONTHS[i] === CURRENT_MONTH
      ? 'bg-blue-50/50'
      : i % 2
        ? 'bg-slate-50/60'
        : '';

  const isQty = viewMode === 'qty';
  const fmt = isQty ? fmtSL : moneyTy3;
  const fmtCh = isQty
    ? (v) => (!v ? '—' : (v > 0 ? '+' : '') + Math.round(v).toLocaleString('en-US'))
    : (v) => (!v ? '—' : MASK_MONEY ? '•••' : (v > 0 ? '+' : '') + fmtTy3(v));
  const pick = (node) => {
    const moKh = isQty ? node.moKh : node.moKhDt;
    const moAct = isQty ? node.moAct : node.moActDt;
    const khYtdV = isQty ? node.khYtd : node.khYtdDt;
    const thYtdV = isQty ? node.thYtd : node.dtYtd;
    const dtV = isQty ? node.slDauNam : node.dt;
    const dtUpdV = isQty ? node.slUpd : node.dtUpd;
    const onHandV = isQty ? node.onHand : node.onHandDt;
    const upcomingV = isQty ? node.upcoming : node.upcomingDt;
    const quotaV = isQty ? node.quota : node.quotaDt;
    const hetV = isQty ? node.het : node.hetDt;
    return { moKh, moAct, khYtdV, thYtdV, dtV, dtUpdV, onHandV, upcomingV, quotaV, hetV };
  };

  const moHead = () => {
    const out = [];
    monthIdxs.forEach((i) => {
      const m = MONTH_LABELS[i];
      const tone =
        MONTHS[i] < CURRENT_MONTH
          ? 'bg-teal-50/60 text-teal-700'
          : MONTHS[i] === CURRENT_MONTH
            ? 'bg-blue-100/60 text-blue-700'
            : 'bg-blue-50/40 text-blue-600';
      out.push(
        <th
          key={'mh' + i}
          colSpan={hasAct(i) ? 3 : undefined}
          rowSpan={hasAct(i) ? undefined : 2}
          className={`px-2 py-1.5 text-[10px] font-semibold uppercase border-r border-b border-slate-200 align-bottom ${hasAct(i) ? 'text-center' : 'text-right'} ${tone}`}
        >
          {m}
        </th>,
      );
    });
    return out;
  };
  const subHead = (key, tone) => [
    <th
      key={key + 'k'}
      className={`px-2 py-1 text-right text-[9.5px] font-medium uppercase text-slate-500 border-b border-slate-200 ${tone}`}
    >
      KH
    </th>,
    <th
      key={key + 'a'}
      className={`px-2 py-1 text-right text-[9.5px] font-medium uppercase text-orange-600 border-b border-slate-200 ${tone}`}
    >
      TH
    </th>,
    <th
      key={key + 'p'}
      className={`px-2 py-1 text-right text-[9.5px] font-medium uppercase text-slate-500 border-r border-b border-slate-200 ${tone}`}
    >
      %
    </th>,
  ];
  const ytdSubHead = [
    <th key="sytdk" className="px-2 py-1 text-right text-[9.5px] font-medium uppercase text-slate-500 border-b border-slate-200 bg-amber-50/40">KH</th>,
    <th key="sytda" className="px-2 py-1 text-right text-[9.5px] font-medium uppercase text-orange-600 border-b border-slate-200 bg-amber-50/40">TH</th>,
    <th key="sytdp" className="px-2 py-1 text-right text-[9.5px] font-medium uppercase text-slate-500 border-b border-slate-200 whitespace-nowrap bg-amber-50/40">% TH YTD</th>,
    <th key="sytdtd" className="px-2 py-1 text-right text-[9.5px] font-medium uppercase text-slate-500 border-b border-slate-200 whitespace-nowrap bg-amber-50/40">tốc độ TH YTD</th>,
    <th key="sytdkp" className="px-2 py-1 text-right text-[9.5px] font-medium uppercase text-slate-500 border-b border-slate-200 whitespace-nowrap bg-amber-50/40">tốc độ KH YTD</th>,
    <th key="sytdcl" className="px-2 py-1 text-right text-[9.5px] font-medium uppercase text-slate-500 border-r border-b border-slate-200 whitespace-nowrap bg-amber-50/40">CL tốc độ</th>,
  ];

  const moCells = (node, extra) => {
    const { moKh, moAct } = pick(node);
    const out = [];
    for (const i of monthIdxs) {
      const bg = moBg(i);
      const kh = moKh[i], act = moAct[i];
      if (!hasAct(i)) {
        out.push(
          <td key={'k' + i} className={`px-2 py-1.5 text-right text-[12px] tabular-nums border-r border-slate-100 ${bg} ${extra || ''}`}>
            {fmt(kh)}
          </td>,
        );
        continue;
      }
      out.push(
        <td key={'k' + i} className={`px-2 py-1.5 text-right text-[12px] tabular-nums ${bg} ${extra || ''}`}>{fmt(kh)}</td>,
      );
      out.push(
        <td key={'a' + i} className={`px-2 py-1.5 text-right text-[12px] tabular-nums text-orange-600 ${bg} ${extra || ''}`}>{fmt(act)}</td>,
      );
      out.push(
        <td key={'p' + i} className={`px-2 py-1.5 text-right text-[11.5px] tabular-nums border-r border-slate-200 ${pctCls(act, kh)} ${bg}`}>
          {pctTxt(act, kh)}
        </td>,
      );
    }
    return out;
  };

  const ytdCells = (node, extra) => {
    const { khYtdV, thYtdV, dtUpdV } = pick(node);
    const tdTh = dtUpdV > 0 ? thYtdV / dtUpdV : null;
    const tdKh = dtUpdV > 0 ? khYtdV / dtUpdV : null;
    const clVal = tdTh != null && tdKh != null ? Math.round((tdTh - tdKh) * 100) : null;
    return [
      <td key="yk" className={`px-3 py-1.5 text-right text-[12px] tabular-nums bg-amber-50/40 ${extra || ''}`}>{fmt(khYtdV)}</td>,
      <td key="ya" className={`px-3 py-1.5 text-right text-[12px] tabular-nums text-orange-700 bg-amber-50/40 ${extra || ''}`}>{fmt(thYtdV)}</td>,
      <td key="yp" className={`px-3 py-1.5 text-right text-[12px] tabular-nums font-semibold bg-amber-50/40 ${pctCls(thYtdV, khYtdV)}`}>{pctTxt(thYtdV, khYtdV)}</td>,
      <td key="ytd" className={`px-3 py-1.5 text-right text-[12px] tabular-nums text-slate-500 bg-amber-50/40`}>{pctTxt(thYtdV, dtUpdV)}</td>,
      <td key="ykp" className={`px-3 py-1.5 text-right text-[12px] tabular-nums text-slate-500 bg-amber-50/40`}>{pctTxt(khYtdV, dtUpdV)}</td>,
      <td key="ycl" className={`px-3 py-1.5 text-right text-[12px] tabular-nums font-semibold border-r border-slate-200 bg-amber-50/40 ${chCls(clVal || 0)}`}>
        {clVal == null ? '—' : (clVal > 0 ? '+' : '') + clVal + '%'}
      </td>,
    ];
  };

  const tBg = 'bg-emerald-50/40';
  const targetCells = (node, extra) => {
    const { dtV, dtUpdV, thYtdV } = pick(node);
    const ch = dtUpdV - dtV;
    return [
      <td key="tdn" className={`px-3 py-1.5 text-right text-[12px] tabular-nums font-medium ${tBg} ${extra || ''}`}>{fmt(dtV)}</td>,
      <td key="tup" className={`px-3 py-1.5 text-right text-[12px] tabular-nums font-medium text-blue-600 ${tBg} ${extra || ''}`}>{fmt(dtUpdV)}</td>,
      <td key="tch" className={`px-3 py-1.5 text-right text-[12px] tabular-nums font-semibold ${tBg} ${chCls(ch)}`}>{fmtCh(ch)}</td>,
      <td key="tkl" className={`px-3 py-1.5 text-right text-[12px] tabular-nums font-medium border-r border-slate-200 text-purple-600 ${tBg} ${extra || ''}`}>{fmt(dtUpdV - thYtdV)}</td>,
    ];
  };

  const qBg = 'bg-indigo-50/40';
  const quotaCells = (node, extra) => {
    const { onHandV, upcomingV, quotaV, thYtdV, hetV } = pick(node);
    const khaDung = node.oop ? null : onHandV - thYtdV;
    return [
      <td key="qoh" className={`px-3 py-1.5 text-right text-[12px] tabular-nums font-medium text-indigo-700 ${qBg} ${extra || ''}`}>{fmt(onHandV)}</td>,
      <td key="qup" className={`px-3 py-1.5 text-right text-[12px] tabular-nums font-medium text-indigo-500 ${qBg} ${extra || ''}`}>{fmt(upcomingV)}</td>,
      HIEN_HET_HIEU_LUC && <td key="qhet" className={`px-3 py-1.5 text-right text-[12px] tabular-nums font-medium text-red-500 ${qBg} ${extra || ''}`}>{fmt(hetV)}</td>,
      <td key="qtot" className={`px-3 py-1.5 text-right text-[12px] tabular-nums font-medium text-indigo-800 ${qBg} ${extra || ''}`}>{fmt(quotaV)}</td>,
      <td key="qth" className={`px-3 py-1.5 text-right text-[12px] tabular-nums font-medium text-orange-600 ${qBg} ${extra || ''}`}>{fmt(thYtdV)}</td>,
      <td key="qkd" className={`px-3 py-1.5 text-right text-[12px] tabular-nums font-medium border-r border-slate-200 ${qBg} ${node.oop ? 'text-slate-300' : 'text-indigo-800'} ${extra || ''}`}>
        {khaDung == null ? '—' : fmt(khaDung)}
      </td>,
    ];
  };

  const stickyLabel = (bg) =>
    `sticky left-0 z-10 border-r border-slate-200 ${bg}`;

  useEffect(() => {
    onExport(() => exportProductSummary(data));
    return () => onExport(null);
  }, [data, onExport]);

  const grandCells = (node, dark) => {
    const { moKh, moAct, khYtdV, thYtdV, dtV, dtUpdV, onHandV, upcomingV, quotaV, hetV } = pick(node);
    const cells = [];
    for (const i of monthIdxs) {
      const kh = moKh[i], act = moAct[i];
      cells.push(
        <td key={'gk' + i} className="px-2 py-2.5 text-right text-[12px] tabular-nums">{fmt(kh)}</td>,
      );
      if (hasAct(i)) {
        cells.push(
          <td key={'ga' + i} className="px-2 py-2.5 text-right text-[12px] tabular-nums text-orange-200">{fmt(act)}</td>,
        );
        cells.push(
          <td key={'gp' + i} className="px-2 py-2.5 text-right text-[11.5px] tabular-nums text-slate-300">{pctTxt(act, kh)}</td>,
        );
      }
    }
    const tdTh = dtUpdV > 0 ? thYtdV / dtUpdV : null;
    const tdKh = dtUpdV > 0 ? khYtdV / dtUpdV : null;
    const clVal = tdTh != null && tdKh != null ? Math.round((tdTh - tdKh) * 100) : null;
    cells.push(
      <td key="gyk" className="px-3 py-2.5 text-right text-[12.5px] tabular-nums">{fmt(khYtdV)}</td>,
      <td key="gya" className="px-3 py-2.5 text-right text-[12.5px] tabular-nums text-orange-200">{fmt(thYtdV)}</td>,
      <td key="gyp" className="px-3 py-2.5 text-right text-[12.5px] tabular-nums">{pctTxt(thYtdV, khYtdV)}</td>,
      <td key="gytd" className="px-3 py-2.5 text-right text-[12.5px] tabular-nums text-slate-300">{pctTxt(thYtdV, dtUpdV)}</td>,
      <td key="gykp" className="px-3 py-2.5 text-right text-[12.5px] tabular-nums text-slate-300">{pctTxt(khYtdV, dtUpdV)}</td>,
      <td key="gycl" className="px-3 py-2.5 text-right text-[12.5px] tabular-nums">
        {clVal == null ? '—' : (clVal > 0 ? '+' : '') + clVal + '%'}
      </td>,
    );
    const ch = dtUpdV - dtV;
    cells.push(
      <td key="gtdn" className="px-3 py-2.5 text-right text-[12.5px] tabular-nums">{fmt(dtV)}</td>,
      <td key="gtup" className="px-3 py-2.5 text-right text-[12.5px] tabular-nums text-blue-200">{fmt(dtUpdV)}</td>,
      <td key="gtch" className="px-3 py-2.5 text-right text-[12.5px] tabular-nums">{fmtCh(ch)}</td>,
      <td key="gtkl" className="px-3 py-2.5 text-right text-[12.5px] tabular-nums text-purple-200">{fmt(dtUpdV - thYtdV)}</td>,
    );
    cells.push(
      <td key="gqoh" className="px-3 py-2.5 text-right text-[12.5px] tabular-nums">{fmt(onHandV)}</td>,
      <td key="gqup" className="px-3 py-2.5 text-right text-[12.5px] tabular-nums">{fmt(upcomingV)}</td>,
      HIEN_HET_HIEU_LUC && <td key="gqhet" className="px-3 py-2.5 text-right text-[12.5px] tabular-nums text-red-200">{fmt(hetV)}</td>,
      <td key="gqtot" className="px-3 py-2.5 text-right text-[12.5px] tabular-nums">{fmt(quotaV)}</td>,
      <td key="gqth" className="px-3 py-2.5 text-right text-[12.5px] tabular-nums text-orange-200">{fmt(thYtdV)}</td>,
      <td key="gqkd" className="px-3 py-2.5 text-right text-[12.5px] tabular-nums">{fmt(onHandV - thYtdV)}</td>,
    );
    return cells;
  };

  return (
    <div className="px-6 pb-8">
      <div className="bg-white rounded-lg border border-slate-200 overflow-hidden">
        <div className="flex items-center justify-end gap-2 px-3 py-2 border-b border-slate-100 bg-slate-50/50">
          <button
            onClick={() => setViewMode((m) => (m === 'money' ? 'qty' : 'money'))}
            title={viewMode === 'money' ? 'Chuyển sang xem Số lượng' : 'Chuyển sang xem Doanh thu'}
            className="inline-flex items-center gap-1.5 px-3 py-1.5 text-[12px] font-medium rounded-md border border-slate-200 bg-white text-slate-600 hover:bg-slate-50"
          >
            {viewMode === 'money' ? '💰 Doanh thu' : '📦 Số lượng'}
          </button>
          <button
            onClick={() => setShowMonths((s) => !s)}
            title={
              showMonths
                ? 'Thu gọn, chỉ hiện tháng hiện tại + Luỹ kế YTD'
                : 'Hiện chi tiết theo từng tháng'
            }
            className="inline-flex items-center gap-1.5 px-3 py-1.5 text-[12px] font-medium rounded-md border border-slate-200 bg-white text-slate-600 hover:bg-slate-50"
          >
            {showMonths ? '▾ Thu gọn theo tháng' : '▸ Chi tiết theo tháng'}
          </button>
        </div>
        <div ref={boxRef} className="overflow-auto summary-scroll">
          <table className="w-full border-collapse sticky-head">
            <thead>
              {React.createElement(
                'tr',
                { className: 'bg-slate-100' },
                <th
                  rowSpan={2}
                  className={`px-4 py-2 text-left text-[11px] font-semibold uppercase tracking-wide text-slate-600 border-b align-bottom ${stickyLabel('bg-slate-100')}`}
                  style={{ minWidth: 240 }}
                >
                  Miền / Nhóm SP / SP / KH
                </th>,
                ...moHead(),
                <th
                  colSpan={6}
                  className="px-3 py-1.5 text-center text-[11px] font-bold uppercase tracking-wide text-amber-800 border-r border-b border-slate-200 bg-amber-50/60"
                >
                  Luỹ kế YTD
                </th>,
                <th
                  colSpan={4}
                  className="px-3 py-1.5 text-center text-[11px] font-bold uppercase tracking-wide text-emerald-800 border-r border-b border-slate-200 bg-emerald-50/60"
                >
                  Target
                </th>,
                <th
                  colSpan={HIEN_HET_HIEU_LUC ? 6 : 5}
                  className="px-3 py-1.5 text-center text-[11px] font-bold uppercase tracking-wide text-indigo-800 border-r border-b border-slate-200 bg-indigo-50/60"
                >
                  Quota
                </th>,
              )}
              {React.createElement(
                'tr',
                { className: 'bg-slate-100' },
                ...monthIdxs.flatMap((i) =>
                  hasAct(i)
                    ? subHead(
                        's' + i,
                        MONTHS[i] === CURRENT_MONTH ? 'bg-blue-50/40' : '',
                      )
                    : [],
                ),
                ...ytdSubHead,
                <th key="tdn" className="px-2 py-1 text-right text-[9.5px] font-medium uppercase text-emerald-700 border-b border-slate-200 bg-emerald-50/40 whitespace-nowrap">
                  {isQty ? 'SL đầu năm' : 'Target đầu năm'}
                </th>,
                <th key="tup" className="px-2 py-1 text-right text-[9.5px] font-medium uppercase text-blue-600 border-b border-slate-200 bg-emerald-50/40 whitespace-nowrap">
                  {isQty ? 'SL dự kiến' : 'DThu dự kiến'}
                </th>,
                <th key="tch" className="px-2 py-1 text-right text-[9.5px] font-medium uppercase text-emerald-700 border-b border-slate-200 bg-emerald-50/40 whitespace-nowrap">
                  Chênh lệch
                </th>,
                <th key="tkl" className="px-2 py-1 text-right text-[9.5px] font-medium uppercase text-purple-600 border-r border-b border-slate-200 bg-emerald-50/40 whitespace-nowrap">
                  KH còn lại
                </th>,
                <th key="qoh" className="px-2 py-1 text-right text-[9.5px] font-medium uppercase text-indigo-600 border-b border-slate-200 bg-indigo-50/40 whitespace-nowrap">On hand</th>,
                <th key="qup" className="px-2 py-1 text-right text-[9.5px] font-medium uppercase text-indigo-600 border-b border-slate-200 bg-indigo-50/40 whitespace-nowrap">Upcoming</th>,
                HIEN_HET_HIEU_LUC && <th key="qhet" title="Quota của đợt đã quá tháng hết hiệu lực (tháng thầu + hiệu lực − 1). Không tính vào Tổng / Khả dụng." className="px-2 py-1 text-right text-[9.5px] font-medium uppercase text-red-600 border-b border-slate-200 bg-indigo-50/40 whitespace-nowrap">Hết HL</th>,
                <th key="qtot" className="px-2 py-1 text-right text-[9.5px] font-medium uppercase text-indigo-600 border-b border-slate-200 bg-indigo-50/40 whitespace-nowrap">Tổng</th>,
                <th key="qth" className="px-2 py-1 text-right text-[9.5px] font-medium uppercase text-orange-600 border-b border-slate-200 bg-indigo-50/40 whitespace-nowrap">TH YTD</th>,
                <th key="qkd" className="px-2 py-1 text-right text-[9.5px] font-medium uppercase text-indigo-600 border-r border-b border-slate-200 bg-indigo-50/40 whitespace-nowrap">Khả dụng</th>,
              )}
            </thead>
            <tbody>
              {data.regs.length === 0 ? (
                <tr>
                  <td
                    colSpan={N_COLS}
                    className="px-4 py-12 text-center text-slate-400 text-sm"
                  >
                    {rows.length === 0
                      ? 'Sheet trống'
                      : 'Không có sản phẩm nào khớp bộ lọc'}
                  </td>
                </tr>
              ) : (
                data.regs.map((reg) => {
                  const regKey = 'r:' + reg.region;
                  const regOpen = open.has(regKey);
                  const out = [
                    React.createElement(
                      'tr',
                      {
                        key: regKey,
                        'data-lv': 0,
                        className: 'bg-slate-100 cursor-pointer border-b border-slate-300',
                        onClick: () => toggle(regKey),
                      },
                      <td className={`px-4 py-2 text-[12.5px] font-bold text-slate-800 ${stickyLabel('bg-slate-100')}`}>
                        <span className="inline-block w-3 text-slate-400">{regOpen ? '▾' : '▸'}</span>{' '}
                        {reg.region}
                      </td>,
                      ...moCells(reg, 'font-semibold'),
                      ...ytdCells(reg, 'font-semibold'),
                      ...targetCells(reg, 'font-semibold'),
                      ...quotaCells(reg, 'font-semibold'),
                    ),
                  ];
                  if (regOpen) {
                    for (const g of reg.grps) {
                      const gKey = regKey + '||' + g.grp;
                      const gOpen = open.has(gKey);
                      out.push(
                        React.createElement(
                          'tr',
                          {
                            key: gKey,
                            'data-lv': 1,
                            className: 'bg-slate-50 cursor-pointer border-b border-slate-200',
                            onClick: () => toggle(gKey),
                          },
                          <td className={`pl-8 pr-4 py-2 text-[12px] font-semibold text-slate-700 ${stickyLabel('bg-slate-50')}`}>
                            <span className="inline-block w-3 text-slate-400">{gOpen ? '▾' : '▸'}</span>{' '}
                            {g.grp}
                            <span className="ml-2 text-[10px] text-slate-400 font-normal">({g.prods.length} SP)</span>
                          </td>,
                          ...moCells(g, 'font-medium'),
                          ...ytdCells(g, 'font-semibold'),
                          ...targetCells(g, 'font-semibold'),
                          ...quotaCells(g, 'font-semibold'),
                        ),
                      );
                      if (gOpen) {
                        for (const p of g.prods) {
                          const pKey = gKey + '||' + p.prod;
                          const pOpen = open.has(pKey);
                          const hasCust = p.custs && p.custs.length > 0;
                          out.push(
                            React.createElement(
                              'tr',
                              {
                                key: pKey,
                                'data-lv': 2,
                                className:
                                  'border-b border-slate-100 bg-slate-50' +
                                  (hasCust ? ' cursor-pointer' : ''),
                                onClick: hasCust ? () => toggle(pKey) : undefined,
                              },
                              <td className={`pl-14 pr-4 py-1.5 text-[12px] font-medium text-slate-700 ${stickyLabel('bg-slate-50')}`}>
                                <span className="inline-block w-3 text-slate-400">
                                  {hasCust ? (pOpen ? '▾' : '▸') : ''}
                                </span>{' '}
                                {p.prod}
                                {isQty && p.price > 0 && (
                                  <span className="ml-2 text-[10px] text-slate-400 font-normal">
                                    ĐG: {moneyPrice(p.price)}tr
                                  </span>
                                )}
                              </td>,
                              ...moCells(p),
                              ...ytdCells(p),
                              ...targetCells(p),
                              ...quotaCells(p),
                            ),
                          );
                          if (pOpen) {
                            const custRow = (cu, key, pad, kids) =>
                              React.createElement(
                                'tr',
                                {
                                  key,
                                  className:
                                    'border-b border-slate-100' +
                                    (cu.oop ? ' bg-amber-50/40' : '') +
                                    (kids ? ' cursor-pointer' : ''),
                                  onClick: kids ? () => toggle(key) : undefined,
                                },
                                <td className={`${pad} pr-4 py-1.5 text-[11.5px] text-slate-500 ${stickyLabel('bg-white')}`}>
                                  <span className="inline-block w-3 text-slate-400">
                                    {kids ? (open.has(key) ? '▾' : '▸') : ''}
                                  </span>
                                  <span className={'truncate' + (cu.cust === OOP_CUST ? ' text-amber-700 font-medium' : '')}>
                                    {cu.cust}
                                  </span>{' '}
                                  {cu.cust === OOP_CUST ? (
                                    <span className="text-[9.5px] px-1.5 py-0.5 rounded bg-amber-100 text-amber-700 font-medium whitespace-nowrap">
                                      Ngoài KH
                                    </span>
                                  ) : (
                                    <span className="text-[10px] text-slate-400 font-mono">{cu.custId}</span>
                                  )}
                                </td>,
                                ...moCells(cu),
                                ...ytdCells(cu),
                                ...targetCells(cu),
                                ...quotaCells(cu),
                              );
                            for (const cu of p.custs) {
                              const cKeyStr = pKey + '||' + cu.cust;
                              const subs = cu.subs || [];
                              out.push(custRow(cu, cKeyStr, 'pl-20', subs.length > 0));
                              if (subs.length && open.has(cKeyStr)) {
                                for (const s of subs)
                                  out.push(custRow(s, cKeyStr + '||' + s.cust, 'pl-28', false));
                              }
                            }
                          }
                        }
                      }
                    }
                  }
                  return out;
                })
              )}
              {React.createElement(
                'tr',
                { className: 'bg-slate-800 text-white font-semibold' },
                <td className={`px-4 py-2.5 text-[12.5px] border-t-2 border-slate-900 sticky left-0 z-10 bg-slate-800`}>
                  TỔNG CỘNG
                </td>,
                ...grandCells(data.grand),
              )}
            </tbody>
          </table>
        </div>
      </div>
      <p className="text-[11px] text-slate-400 mt-2">
        {viewMode === 'money'
          ? 'Chế độ Doanh thu: tất cả giá trị = SL × đơn giá (triệu VNĐ). '
          : 'Chế độ Số lượng: tất cả giá trị = SL; đơn giá hiện ở dòng sản phẩm. '}
        KH = KH update, TH = thực hiện, % = TH / KH. Luỹ kế YTD tính đến hết
        tháng hiện tại.
      </p>
    </div>
  );
}
