import React, { useState, useEffect, useMemo, useCallback } from 'react';
import { Filter } from './icons.jsx';
import {
  MONTHS, MONTH_LABELS, CURRENT_MONTH, OOP_CUST, isYtdMonth,
} from '../config/constants.js';
import { fmtInt } from '../lib/format.js';
import { inSel, planCustKeys, custInPlan, matchSearch } from '../lib/text.js';
import { useFitHeight, useSummaryScrollbar, useStickyRows } from '../hooks/useLayout.jsx';
import { exportProductSummary } from '../lib/excel.js';

const chCls = (v) =>
  v > 0 ? 'text-emerald-700' : v < 0 ? 'text-red-600' : 'text-slate-400';

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
  // Thu gọn/mở phần thực hiện theo tháng (mặc định thu gọn → chỉ còn Luỹ kế YTD).
  const [showMonths, setShowMonths] = useState(false);
  const boxRef = useFitHeight();
  useSummaryScrollbar(boxRef);
  useStickyRows(boxRef); // ghim hàng Sản phẩm / Miền khi cuộn

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
    // moKh[]  = SL KH update từng tháng (kế hoạch đã update, mọi tháng)
    // moAct[] = SL thực hiện từng tháng (chỉ có số ở tháng đã qua / tháng hiện tại)
    // thYtd = tổng thực hiện luỹ kế (đến hết tháng hiện tại)
    // khYtd = tổng KH update THÔ luỹ kế (đến hết tháng hiện tại) → dùng để tính % TH YTD
    const blank = () => ({
      moKh: MONTHS.map(() => 0),
      moAct: MONTHS.map(() => 0),
      moKhDauNam: MONTHS.map(() => 0),
      thYtd: 0,
      khYtd: 0,
      onHand: 0,
      upcoming: 0,
      quota: 0,
    });
    // Tính trên TOÀN BỘ rows (không phải `filtered`): bộ lọc có thể đang ẩn dòng kế
    // hoạch của KH đó, không vì thế mà coi họ là KH lạ.
    const planCusts = planCustKeys(rows);
    const prodMap = new Map();
    for (const r of filtered) {
      const i = MONTHS.indexOf(r.mo);
      if (i < 0) continue;
      const pKey = r.prod || '(Không rõ SP)';
      if (!prodMap.has(pKey))
        prodMap.set(pKey, { prod: pKey, grp: r.grp, regMap: new Map() });
      const p = prodMap.get(pKey);
      const rKey = r.region || '(Không rõ miền)';
      if (!p.regMap.has(rKey))
        p.regMap.set(rKey, { region: rKey, custMap: new Map(), ...blank() });
      const cell = p.regMap.get(rKey);
      const isPast = isYtdMonth(r.mo); // luỹ kế YTD gồm cả tháng hiện tại
      const act = Number(r.act) || 0;
      const dSlDauNam = Number(r.rev) || 0;
      const dSlRevUpd = Number(r.revUpd) || 0;
      const planUpd =
        r.revUpd !== undefined && r.revUpd !== '' && r.revUpd !== null
          ? Number(r.revUpd) || 0
          : Number(r.rev) || 0;
      const dQOld = Number(r.qOld) || 0;
      const qMainVal = Number(r.qMain) || 0;
      const qAddVal = Number(r.qAdd) || 0;
      const mainOnHand = r.mMain && r.mMain <= CURRENT_MONTH;
      const addOnHand = r.mAdd && r.mAdd <= CURRENT_MONTH;
      const dOnHand =
        dQOld + (mainOnHand ? qMainVal : 0) + (addOnHand ? qAddVal : 0);
      const dUpcoming = (mainOnHand ? 0 : qMainVal) + (addOnHand ? 0 : qAddVal);
      const dQuota = dOnHand + dUpcoming;
      const isOop = !!r._oop && !custInPlan(planCusts, r);
      const bump = (o) => {
        o.moKh[i] += planUpd;
        o.moAct[i] += act;
        o.moKhDauNam[i] += dSlDauNam;
        o.onHand += dOnHand;
        o.upcoming += dUpcoming;
        o.quota += dQuota;
        if (isPast) {
          o.thYtd += act;
          if (!isOop) o.khYtd += planUpd;
        }
      };
      bump(cell);
      const cKey = isOop ? OOP_CUST : r.cust || '—';
      if (!cell.custMap.has(cKey))
        cell.custMap.set(cKey, {
          cust: cKey,
          custId: isOop ? '' : r.custId,
          oop: isOop,
          subMap: new Map(),
          ...blank(),
        });
      const cc = cell.custMap.get(cKey);
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
    const fold = () => ({
      moKh: MONTHS.map(() => 0),
      moAct: MONTHS.map(() => 0),
      moKhDauNam: MONTHS.map(() => 0),
      thYtd: 0,
      khYtd: 0,
      onHand: 0,
      upcoming: 0,
      quota: 0,
    });
    const add = (a, c) => {
      for (let i = 0; i < 12; i++) {
        a.moKh[i] += c.moKh[i];
        a.moAct[i] += c.moAct[i];
      }
      a.thYtd += c.thYtd;
      a.khYtd += c.khYtd;
      a.onHand += c.onHand;
      a.upcoming += c.upcoming;
      a.quota += c.quota;
      for (let i = 0; i < 12; i++) a.moKhDauNam[i] += c.moKhDauNam[i];
      return a;
    };
    const sumMo = (mo) => mo.reduce((s, v) => s + v, 0);
    const prods = Array.from(prodMap.values()).map((p) => {
      const regs = Array.from(p.regMap.values()).map((rg) => {
        const custs = Array.from(rg.custMap.values()).map((cu) => {
          const subs = Array.from(cu.subMap.values());
          subs.sort((a, b) => b.thYtd - a.thYtd); // KH ngoài kế hoạch: xếp theo SL thực hiện
          return { ...cu, subs };
        });
        custs.sort((a, b) => sumMo(b.moKh) - sumMo(a.moKh));
        return {
          region: rg.region,
          custs,
          moKh: rg.moKh,
          moAct: rg.moAct,
          thYtd: rg.thYtd,
          khYtd: rg.khYtd,
          onHand: rg.onHand,
          upcoming: rg.upcoming,
          quota: rg.quota,
        };
      });
      regs.sort((a, b) => a.region.localeCompare(b.region, 'vi'));
      return { prod: p.prod, grp: p.grp, regs, ...regs.reduce(add, fold()) };
    });
    prods.sort((a, b) => {
      const aUnk = a.prod === '(Không rõ SP)' ? 1 : 0;
      const bUnk = b.prod === '(Không rõ SP)' ? 1 : 0;
      if (aUnk !== bUnk) return aUnk - bUnk;
      return a.prod.localeCompare(b.prod, 'vi');
    });
    return { prods, grand: prods.reduce(add, fold()) };
  }, [rows, psFilter, regionFilter, custFilter, groupFilter, search]);

  const toggle = (k) =>
    setOpen((prev) => {
      const n = new Set(prev);
      n.has(k) ? n.delete(k) : n.add(k);
      return n;
    });

  const curIdx = Math.max(0, MONTHS.indexOf(CURRENT_MONTH));
  // Tháng đã qua + tháng hiện tại mới có thực hiện → hiện đủ 3 cột con; tháng tương lai chỉ 1 cột KH update
  const hasAct = (i) => i <= curIdx;
  // Cột tháng hiển thị: mặc định chỉ tháng hiện tại; bấm "Chi tiết theo tháng" thì hiện cả 12.
  const monthIdxs = showMonths
    ? MONTHS.map((_, i) => i)
    : MONTHS.indexOf(CURRENT_MONTH) >= 0
      ? [curIdx]
      : [];
  const N_COLS =
    1 + monthIdxs.reduce((s, i) => s + (hasAct(i) ? 3 : 1), 0) + 6 + 5 + 3;

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
  // Nền xen kẽ theo block tháng để mắt không lạc giữa 3 cột con
  const moBg = (i) =>
    MONTHS[i] === CURRENT_MONTH
      ? 'bg-blue-50/50'
      : i % 2
        ? 'bg-slate-50/60'
        : '';

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
  // Nhóm Luỹ kế YTD: KH · TH · % TH YTD · tốc độ TH YTD · tốc độ KH YTD · CL tốc độ (chỉ cột cuối có border-r đóng nhóm).
  const ytdSubHead = [
    <th
      key="sytdk"
      className="px-2 py-1 text-right text-[9.5px] font-medium uppercase text-slate-500 border-b border-slate-200 bg-amber-50/40"
    >
      KH
    </th>,
    <th
      key="sytda"
      className="px-2 py-1 text-right text-[9.5px] font-medium uppercase text-orange-600 border-b border-slate-200 bg-amber-50/40"
    >
      TH
    </th>,
    <th
      key="sytdp"
      className="px-2 py-1 text-right text-[9.5px] font-medium uppercase text-slate-500 border-b border-slate-200 whitespace-nowrap bg-amber-50/40"
    >
      % TH YTD
    </th>,
    <th
      key="sytdtd"
      className="px-2 py-1 text-right text-[9.5px] font-medium uppercase text-slate-500 border-b border-slate-200 whitespace-nowrap bg-amber-50/40"
    >
      tốc độ TH YTD
    </th>,
    <th
      key="sytdkp"
      className="px-2 py-1 text-right text-[9.5px] font-medium uppercase text-slate-500 border-b border-slate-200 whitespace-nowrap bg-amber-50/40"
    >
      tốc độ KH YTD
    </th>,
    <th
      key="sytdcl"
      className="px-2 py-1 text-right text-[9.5px] font-medium uppercase text-slate-500 border-r border-b border-slate-200 whitespace-nowrap bg-amber-50/40"
    >
      CL tốc độ
    </th>,
  ];

  const moCells = (node, extra) => {
    const out = [];
    for (const i of monthIdxs) {
      const bg = moBg(i);
      const kh = node.moKh[i],
        act = node.moAct[i];
      if (!hasAct(i)) {
        out.push(
          <td
            key={'k' + i}
            className={`px-2 py-1.5 text-right text-[12px] tabular-nums border-r border-slate-100 ${bg} ${extra || ''}`}
          >
            {fmtInt(kh)}
          </td>,
        );
        continue;
      }
      out.push(
        <td
          key={'k' + i}
          className={`px-2 py-1.5 text-right text-[12px] tabular-nums ${bg} ${extra || ''}`}
        >
          {fmtInt(kh)}
        </td>,
      );
      out.push(
        <td
          key={'a' + i}
          className={`px-2 py-1.5 text-right text-[12px] tabular-nums text-orange-600 ${bg} ${extra || ''}`}
        >
          {fmtInt(act)}
        </td>,
      );
      out.push(
        <td
          key={'p' + i}
          className={`px-2 py-1.5 text-right text-[11.5px] tabular-nums border-r border-slate-200 ${pctCls(act, kh)} ${bg}`}
        >
          {pctTxt(act, kh)}
        </td>,
      );
    }
    return out;
  };

  // KH update cả năm (SL) = tháng đã qua lấy thực hiện, từ tháng hiện tại trở đi lấy SL update
  // → giống định nghĩa cột "KH update" ở màn PS, để % KH YTD nhất quán giữa 2 màn.
  const updAnnual = (node) =>
    node.moKh.reduce((s, v, i) => s + (i < curIdx ? node.moAct[i] : v), 0);
  // Luỹ kế YTD (đến hết tháng hiện tại): KH · TH · % TH YTD · tốc độ TH YTD · tốc độ KH YTD · CL tốc độ
  // % TH YTD = TH YTD / KH YTD ; tốc độ TH YTD = TH YTD / KH update cả năm ;
  // tốc độ KH YTD = KH YTD / KH update cả năm ; CL tốc độ = tốc độ TH YTD − tốc độ KH YTD (điểm %).
  const ytdCells = (node, extra) => {
    const totKh = updAnnual(node);
    const tdTh = totKh > 0 ? node.thYtd / totKh : null;
    const tdKh = totKh > 0 ? node.khYtd / totKh : null;
    const clVal =
      tdTh != null && tdKh != null ? Math.round((tdTh - tdKh) * 100) : null;
    return [
      <td
        key="yk"
        className={`px-3 py-1.5 text-right text-[12px] tabular-nums bg-amber-50/40 ${extra || ''}`}
      >
        {fmtInt(node.khYtd)}
      </td>,
      <td
        key="ya"
        className={`px-3 py-1.5 text-right text-[12px] tabular-nums text-orange-700 bg-amber-50/40 ${extra || ''}`}
      >
        {fmtInt(node.thYtd)}
      </td>,
      <td
        key="yp"
        className={`px-3 py-1.5 text-right text-[12px] tabular-nums font-semibold bg-amber-50/40 ${pctCls(node.thYtd, node.khYtd)}`}
      >
        {pctTxt(node.thYtd, node.khYtd)}
      </td>,
      <td
        key="ytd"
        className={`px-3 py-1.5 text-right text-[12px] tabular-nums text-slate-500 bg-amber-50/40`}
      >
        {pctTxt(node.thYtd, totKh)}
      </td>,
      <td
        key="ykp"
        className={`px-3 py-1.5 text-right text-[12px] tabular-nums text-slate-500 bg-amber-50/40`}
      >
        {pctTxt(node.khYtd, totKh)}
      </td>,
      <td
        key="ycl"
        className={`px-3 py-1.5 text-right text-[12px] tabular-nums font-semibold border-r border-slate-200 bg-amber-50/40 ${chCls(clVal || 0)}`}
      >
        {clVal == null ? '—' : (clVal > 0 ? '+' : '') + clVal + '%'}
      </td>,
    ];
  };

  const qBg = 'bg-indigo-50/40';
  const quotaCells = (node, extra) => {
    const khaDung = node.oop ? null : (node.onHand || 0) - node.thYtd;
    return [
      <td
        key="qoh"
        className={`px-3 py-1.5 text-right text-[12px] tabular-nums font-medium text-indigo-700 ${qBg} ${extra || ''}`}
      >
        {fmtInt(node.onHand)}
      </td>,
      <td
        key="qup"
        className={`px-3 py-1.5 text-right text-[12px] tabular-nums font-medium text-indigo-500 ${qBg} ${extra || ''}`}
      >
        {fmtInt(node.upcoming)}
      </td>,
      <td
        key="qtot"
        className={`px-3 py-1.5 text-right text-[12px] tabular-nums font-medium text-indigo-800 ${qBg} ${extra || ''}`}
      >
        {fmtInt(node.quota)}
      </td>,
      <td
        key="qth"
        className={`px-3 py-1.5 text-right text-[12px] tabular-nums font-medium text-orange-600 ${qBg} ${extra || ''}`}
      >
        {fmtInt(node.thYtd)}
      </td>,
      <td
        key="qkd"
        className={`px-3 py-1.5 text-right text-[12px] tabular-nums font-medium border-r border-slate-200 ${qBg} ${node.oop ? 'text-slate-300' : 'text-indigo-800'} ${extra || ''}`}
      >
        {khaDung == null ? '—' : fmtInt(khaDung)}
      </td>,
    ];
  };

  const sumArr = (a) => a.reduce((s, v) => s + v, 0);
  const tBg = 'bg-emerald-50/40';
  const targetCells = (node, extra) => {
    const slDauNam = sumArr(node.moKhDauNam);
    const slUpd = updAnnual(node);
    const ch = slUpd - slDauNam;
    return [
      <td
        key="tdn"
        className={`px-3 py-1.5 text-right text-[12px] tabular-nums font-medium ${tBg} ${extra || ''}`}
      >
        {fmtInt(slDauNam)}
      </td>,
      <td
        key="tup"
        className={`px-3 py-1.5 text-right text-[12px] tabular-nums font-medium text-blue-600 ${tBg} ${extra || ''}`}
      >
        {fmtInt(slUpd)}
      </td>,
      <td
        key="tch"
        className={`px-3 py-1.5 text-right text-[12px] tabular-nums font-semibold border-r border-slate-200 ${tBg} ${chCls(ch)}`}
      >
        {ch === 0 ? '—' : (ch > 0 ? '+' : '') + fmtInt(ch)}
      </td>,
    ];
  };

  // Cột nhãn dính trái khi cuộn ngang — nền phải đục, không dùng màu trong suốt
  const stickyLabel = (bg) =>
    `sticky left-0 z-10 border-r border-slate-200 ${bg}`;

  // Nút xuất Excel nằm trên thanh bộ lọc (do App vẽ) → đăng ký hàm xuất lên đó
  useEffect(() => {
    onExport(() => exportProductSummary(data));
    return () => onExport(null);
  }, [data, onExport]);

  return (
    <div className="px-6 pb-8">
      <div className="bg-white rounded-lg border border-slate-200 overflow-hidden">
        <div className="flex items-center justify-end gap-2 px-3 py-2 border-b border-slate-100 bg-slate-50/50">
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
                  style={{ minWidth: 220 }}
                >
                  Sản phẩm / Miền / KH
                </th>,
                ...moHead(),
                <th
                  colSpan={6}
                  className="px-3 py-1.5 text-center text-[11px] font-bold uppercase tracking-wide text-amber-800 border-r border-b border-slate-200 bg-amber-50/60"
                >
                  Luỹ kế YTD
                </th>,
                <th
                  colSpan={5}
                  className="px-3 py-1.5 text-center text-[11px] font-bold uppercase tracking-wide text-indigo-800 border-r border-b border-slate-200 bg-indigo-50/60"
                >
                  Quota
                </th>,
                <th
                  colSpan={3}
                  className="px-3 py-1.5 text-center text-[11px] font-bold uppercase tracking-wide text-emerald-800 border-r border-b border-slate-200 bg-emerald-50/60"
                >
                  Target
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
                <th
                  key="qoh"
                  className="px-2 py-1 text-right text-[9.5px] font-medium uppercase text-indigo-600 border-b border-slate-200 bg-indigo-50/40 whitespace-nowrap"
                >
                  On hand
                </th>,
                <th
                  key="qup"
                  className="px-2 py-1 text-right text-[9.5px] font-medium uppercase text-indigo-600 border-b border-slate-200 bg-indigo-50/40 whitespace-nowrap"
                >
                  Upcoming
                </th>,
                <th
                  key="qtot"
                  className="px-2 py-1 text-right text-[9.5px] font-medium uppercase text-indigo-600 border-b border-slate-200 bg-indigo-50/40 whitespace-nowrap"
                >
                  Tổng
                </th>,
                <th
                  key="qth"
                  className="px-2 py-1 text-right text-[9.5px] font-medium uppercase text-orange-600 border-b border-slate-200 bg-indigo-50/40 whitespace-nowrap"
                >
                  TH YTD
                </th>,
                <th
                  key="qkd"
                  className="px-2 py-1 text-right text-[9.5px] font-medium uppercase text-indigo-600 border-r border-b border-slate-200 bg-indigo-50/40 whitespace-nowrap"
                >
                  Khả dụng
                </th>,
                <th
                  key="tdn"
                  className="px-2 py-1 text-right text-[9.5px] font-medium uppercase text-emerald-700 border-b border-slate-200 bg-emerald-50/40 whitespace-nowrap"
                >
                  KH đầu năm
                </th>,
                <th
                  key="tup"
                  className="px-2 py-1 text-right text-[9.5px] font-medium uppercase text-blue-600 border-b border-slate-200 bg-emerald-50/40 whitespace-nowrap"
                >
                  KH Update
                </th>,
                <th
                  key="tch"
                  className="px-2 py-1 text-right text-[9.5px] font-medium uppercase text-emerald-700 border-r border-b border-slate-200 bg-emerald-50/40 whitespace-nowrap"
                >
                  Chênh lệch
                </th>,
              )}
            </thead>
            <tbody>
              {data.prods.length === 0 ? (
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
                data.prods.map((p) => {
                  const isOpen = open.has(p.prod);
                  const out = [
                    React.createElement(
                      'tr',
                      {
                        key: p.prod,
                        'data-lv': 0,
                        className:
                          'bg-slate-50 cursor-pointer border-b border-slate-200',
                        onClick: () => toggle(p.prod),
                      },
                      <td
                        className={`px-4 py-2 text-[12.5px] font-semibold text-slate-800 ${stickyLabel('bg-slate-50')}`}
                      >
                        <span className="inline-block w-3 text-slate-400">
                          {isOpen ? '▾' : '▸'}
                        </span>{' '}
                        {p.prod}
                      </td>,
                      ...moCells(p, 'font-medium'),
                      ...ytdCells(p, 'font-semibold'),
                      ...quotaCells(p, 'font-semibold'),
                      ...targetCells(p, 'font-semibold'),
                    ),
                  ];
                  if (isOpen) {
                    for (const rg of p.regs) {
                      const rKey = p.prod + '||' + rg.region;
                      const rOpen = open.has(rKey);
                      const hasCust = rg.custs && rg.custs.length > 0;
                      out.push(
                        // bg đục (không phải /40) để lúc bị ghim không lộ dữ liệu chạy phía sau
                        React.createElement(
                          'tr',
                          {
                            key: rKey,
                            'data-lv': 1,
                            className:
                              'border-b border-slate-100 bg-slate-50' +
                              (hasCust ? ' cursor-pointer' : ''),
                            onClick: hasCust ? () => toggle(rKey) : undefined,
                          },
                          <td
                            className={`pl-10 pr-4 py-1.5 text-[12px] font-medium text-slate-700 ${stickyLabel('bg-slate-50')}`}
                          >
                            <span className="inline-block w-3 text-slate-400">
                              {hasCust ? (rOpen ? '▾' : '▸') : ''}
                            </span>{' '}
                            {rg.region}
                          </td>,
                          ...moCells(rg),
                          ...ytdCells(rg),
                          ...quotaCells(rg),
                          ...targetCells(rg),
                        ),
                      );
                      if (rOpen) {
                        // Nhóm "Ngoài kế hoạch" mở ra được để xem từng KH thật bên dưới
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
                            <td
                              className={`${pad} pr-4 py-1.5 text-[11.5px] text-slate-500 ${stickyLabel('bg-white')}`}
                            >
                              <span className="inline-block w-3 text-slate-400">
                                {kids ? (open.has(key) ? '▾' : '▸') : ''}
                              </span>
                              <span
                                className={
                                  'truncate' +
                                  (cu.cust === OOP_CUST
                                    ? ' text-amber-700 font-medium'
                                    : '')
                                }
                              >
                                {cu.cust}
                              </span>{' '}
                              {cu.cust === OOP_CUST ? (
                                <span className="text-[9.5px] px-1.5 py-0.5 rounded bg-amber-100 text-amber-700 font-medium whitespace-nowrap">
                                  Ngoài KH
                                </span>
                              ) : (
                                <span className="text-[10px] text-slate-400 font-mono">
                                  {cu.custId}
                                </span>
                              )}
                            </td>,
                            ...moCells(cu),
                            ...ytdCells(cu),
                            ...quotaCells(cu),
                            ...targetCells(cu),
                          );
                        for (const cu of rg.custs) {
                          const cKeyStr = rKey + '||' + cu.cust;
                          const subs = cu.subs || [];
                          out.push(
                            custRow(cu, cKeyStr, 'pl-16', subs.length > 0),
                          );
                          if (subs.length && open.has(cKeyStr)) {
                            for (const s of subs)
                              out.push(
                                custRow(
                                  s,
                                  cKeyStr + '||' + s.cust,
                                  'pl-24',
                                  false,
                                ),
                              );
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
                <td
                  className={`px-4 py-2.5 text-[12.5px] border-t-2 border-slate-900 sticky left-0 z-10 bg-slate-800`}
                >
                  TỔNG CỘNG
                </td>,
                ...monthIdxs.flatMap((i) => {
                  const kh = data.grand.moKh[i],
                    act = data.grand.moAct[i];
                  const cells = [
                    <td
                      key={'gk' + i}
                      className="px-2 py-2.5 text-right text-[12px] tabular-nums"
                    >
                      {fmtInt(kh)}
                    </td>,
                  ];
                  if (hasAct(i)) {
                    cells.push(
                      <td
                        key={'ga' + i}
                        className="px-2 py-2.5 text-right text-[12px] tabular-nums text-orange-200"
                      >
                        {fmtInt(act)}
                      </td>,
                    );
                    cells.push(
                      <td
                        key={'gp' + i}
                        className="px-2 py-2.5 text-right text-[11.5px] tabular-nums text-slate-300"
                      >
                        {pctTxt(act, kh)}
                      </td>,
                    );
                  }
                  return cells;
                }),
                <td className="px-3 py-2.5 text-right text-[12.5px] tabular-nums">
                  {fmtInt(data.grand.khYtd)}
                </td>,
                <td className="px-3 py-2.5 text-right text-[12.5px] tabular-nums text-orange-200">
                  {fmtInt(data.grand.thYtd)}
                </td>,
                <td className="px-3 py-2.5 text-right text-[12.5px] tabular-nums">
                  {pctTxt(data.grand.thYtd, data.grand.khYtd)}
                </td>,
                <td className="px-3 py-2.5 text-right text-[12.5px] tabular-nums text-slate-300">
                  {pctTxt(data.grand.thYtd, updAnnual(data.grand))}
                </td>,
                <td className="px-3 py-2.5 text-right text-[12.5px] tabular-nums text-slate-300">
                  {pctTxt(data.grand.khYtd, updAnnual(data.grand))}
                </td>,
                (() => {
                  const totKh = updAnnual(data.grand);
                  const tdTh = totKh > 0 ? data.grand.thYtd / totKh : null;
                  const tdKh = totKh > 0 ? data.grand.khYtd / totKh : null;
                  const clVal =
                    tdTh != null && tdKh != null
                      ? Math.round((tdTh - tdKh) * 100)
                      : null;
                  return (
                    <td className="px-3 py-2.5 text-right text-[12.5px] tabular-nums">
                      {clVal == null
                        ? '—'
                        : (clVal > 0 ? '+' : '') + clVal + '%'}
                    </td>
                  );
                })(),
                <td className="px-3 py-2.5 text-right text-[12.5px] tabular-nums">
                  {fmtInt(data.grand.onHand)}
                </td>,
                <td className="px-3 py-2.5 text-right text-[12.5px] tabular-nums">
                  {fmtInt(data.grand.upcoming)}
                </td>,
                <td className="px-3 py-2.5 text-right text-[12.5px] tabular-nums">
                  {fmtInt(data.grand.quota)}
                </td>,
                <td className="px-3 py-2.5 text-right text-[12.5px] tabular-nums text-orange-200">
                  {fmtInt(data.grand.thYtd)}
                </td>,
                <td className="px-3 py-2.5 text-right text-[12.5px] tabular-nums">
                  {fmtInt((data.grand.onHand || 0) - data.grand.thYtd)}
                </td>,
                (() => {
                  const dn = data.grand.moKhDauNam.reduce((s, v) => s + v, 0);
                  return (
                    <td className="px-3 py-2.5 text-right text-[12.5px] tabular-nums">
                      {fmtInt(dn)}
                    </td>
                  );
                })(),
                <td className="px-3 py-2.5 text-right text-[12.5px] tabular-nums text-blue-200">
                  {fmtInt(updAnnual(data.grand))}
                </td>,
                (() => {
                  const dn = data.grand.moKhDauNam.reduce((s, v) => s + v, 0);
                  const ch = updAnnual(data.grand) - dn;
                  return (
                    <td className="px-3 py-2.5 text-right text-[12.5px] tabular-nums">
                      {ch === 0 ? '—' : (ch > 0 ? '+' : '') + fmtInt(ch)}
                    </td>
                  );
                })(),
              )}
            </tbody>
          </table>
        </div>
      </div>
    </div>
  );
}
