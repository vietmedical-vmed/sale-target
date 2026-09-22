import React, { useState, useEffect, useMemo, useCallback } from 'react';
import { ChevronDown, ChevronRight, Filter } from './icons.jsx';
import {
  MONTHS, MONTH_LABELS, CURRENT_MONTH, OOP_CUST, MASK_MONEY,
  getCurIdx, isYtdMonth,
} from '../config/constants.js';
import { fmtTy3, moneyTy3 } from '../lib/format.js';
import { inSel, planCustKeys, custInPlan, matchSearch } from '../lib/text.js';
import { useFitHeight, useSummaryScrollbar, useStickyRows } from '../hooks/useLayout.jsx';
import { exportSummaryPS } from '../lib/excel.js';
import { GiaiTrinhModal, _openGiaiTrinh, setOpenGiaiTrinh } from './GiaiTrinhModal.jsx';

export function SummaryView({
  rows,
  psFilter,
  regionFilter,
  custFilter,
  groupFilter,
  search,
  onExport,
  auth,
}) {
  const [noteInfo, setNoteInfo] = useState(null);
  useEffect(() => {
    setOpenGiaiTrinh(setNoteInfo);
    return () => {
      setOpenGiaiTrinh(null);
    };
  }, []);
  const boxRef = useFitHeight();
  useSummaryScrollbar(boxRef);
  useStickyRows(boxRef); // ghim hàng Miền / PS / Khách hàng / Nhóm SP khi cuộn
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
    // Tính trên TOÀN BỘ rows (không phải `filtered`): bộ lọc có thể đang ẩn dòng kế
    // hoạch của KH đó, không vì thế mà coi họ là KH lạ.
    const planCusts = planCustKeys(rows);
    const regMap = new Map();
    for (const r of filtered) {
      // Bỏ dòng ngoài 12 tháng của năm tài chính. Dòng kế hoạch luôn nằm trong FY,
      // chỉ dòng THỰC HIỆN NGOÀI KẾ HOẠCH mới có tháng của năm trước — mà
      // isYtdMonth('2025-07') vẫn ra true nên nếu không chặn thì doanh số năm ngoái
      // bị cộng vào Thực hiện YTD/DThu của FY này. Màn Tổng hợp theo SP đã chặn sẵn.
      if (MONTHS.indexOf(r.mo) < 0) continue;
      const rKey = r.region || '(Không rõ miền)';
      if (!regMap.has(rKey))
        regMap.set(rKey, {
          region: rKey,
          psMap: new Map(),
        });
      const reg = regMap.get(rKey);
      const psKey = r.ps || '(Không rõ PS)';
      if (!reg.psMap.has(psKey))
        reg.psMap.set(psKey, {
          ps: psKey,
          custMap: new Map(),
        });
      const ps = reg.psMap.get(psKey);
      // Dòng ngoài kế hoạch gom hết vào 1 nhóm "Ngoài kế hoạch";
      // KH thật của dòng thực hiện nằm ở cấp con ngay dưới nhóm này.
      // Chỉ KH LẠ (không có dòng kế hoạch nào) mới vào nhóm "Ngoài kế hoạch";
      // KH đã có kế hoạch thì dòng thực hiện nhập thẳng vào chính KH đó, rồi rơi
      // xuống đúng nhóm SP / sản phẩm ở dưới như một dòng bình thường.
      const isOop = !!r._oop && !custInPlan(planCusts, r);
      const cKey = isOop ? OOP_CUST : r.cust || '—';
      const newCust = (name, id) => ({
        cust: name,
        custId: id,
        oop: isOop, // ngoài kế hoạch → không có quota, không tính khả dụng còn lại
        dt: 0,
        dtYtd: 0,
        dtUpd: 0,
        quotaFY: 0,
        quotaFYDt: 0,
        q14: 0,
        q14Dt: 0,
        qUpcomingDt: 0,
        ytd: 0,
        khLeft: 0,
        khLeftDt: 0,
        moKhDt: MONTHS.map(() => 0), // DThu KH update từng tháng
        moActDt: MONTHS.map(() => 0), // DThu thực hiện từng tháng
        khYtdDt: 0, // DThu KH update luỹ kế YTD (để tính % TH YTD)
        prods: new Set(),
        subMap: new Map(), // chỉ nhóm "Ngoài kế hoạch" dùng: KH thật → { grpMap }
        grpMap: new Map(), // Nhóm SP → { prodMap: Sản phẩm }
      });
      if (!ps.custMap.has(cKey))
        ps.custMap.set(cKey, newCust(cKey, isOop ? '' : r.custId));
      const c = ps.custMap.get(cKey);
      const price = Number(r.price) || 0; // đơn giá TỪNG DÒNG
      const dtActVal = Number(r.dtAct) || 0;
      const mi = MONTHS.indexOf(r.mo); // vị trí tháng (−1 nếu ngoài 12 tháng)
      const isPast =
        (r.mo || '') < CURRENT_MONTH ||
        ((r.mo || '') === CURRENT_MONTH && (Number(r.act) || 0) !== 0);
      const inYtd = isYtdMonth(r.mo); // luỹ kế YTD gồm cả tháng hiện tại
      const actQty = Number(r.act) || 0;
      const updQty = isPast
        ? actQty
        : r.revUpd !== undefined && r.revUpd !== '' && r.revUpd !== null
          ? Number(r.revUpd) || 0
          : Number(r.rev) || 0;
      // KH update THÔ theo tháng (KHÔNG ép tháng đã qua = thực hiện) → giống màn SP, để % TH có nghĩa
      const planUpd =
        r.revUpd !== undefined && r.revUpd !== '' && r.revUpd !== null
          ? Number(r.revUpd) || 0
          : Number(r.rev) || 0;
      // Delta của DÒNG này — dùng chung cho cả 3 cấp: KH → Nhóm SP → Sản phẩm
      const dSl = Number(r.rev) || 0;
      const dDt = dSl * price;
      const dDtUpd = updQty * price;
      const dQOld = Number(r.qOld) || 0;
      const qMainVal = Number(r.qMain) || 0;
      const qAddVal = Number(r.qAdd) || 0;
      const mainOnHand = r.mMain && r.mMain <= CURRENT_MONTH;
      const addOnHand = r.mAdd && r.mAdd <= CURRENT_MONTH;
      const dQ14 =
        dQOld + (mainOnHand ? qMainVal : 0) + (addOnHand ? qAddVal : 0);
      const dQUpcoming =
        (mainOnHand ? 0 : qMainVal) + (addOnHand ? 0 : qAddVal);
      const dQuota = dQ14 + dQUpcoming;
      const dQuotaDt = dQuota * price;
      const dQ14Dt = dQ14 * price;
      const dQUpcomingDt = dQUpcoming * price;
      const dYtd = inYtd ? actQty : 0;
      const dDtYtd = inYtd ? dtActVal : 0;
      const dKhLeft = inYtd ? 0 : updQty; // KH còn lại YTD = KH update các tháng SAU tháng hiện tại
      const dKhLeftDt = dKhLeft * price;
      const dMoKh = planUpd * price; // DThu KH update của tháng này
      const dMoAct = dtActVal; // DThu thực hiện của tháng này
      const dKhYtdDt = isOop ? 0 : inYtd ? dMoKh : 0; // DThu KH update luỹ kế YTD (bỏ OOP khỏi mẫu)
      const bump = (o) => {
        o.dt += dDt;
        o.dtUpd += dDtUpd;
        o.quotaFY += dQuota;
        o.quotaFYDt += dQuotaDt;
        o.q14 += dQ14;
        o.q14Dt += dQ14Dt;
        o.qUpcomingDt += dQUpcomingDt;
        o.ytd += dYtd;
        o.khLeft += dKhLeft;
        o.khLeftDt += dKhLeftDt;
        o.dtYtd += dDtYtd;
        if (mi >= 0) {
          o.moKhDt[mi] += dMoKh;
          o.moActDt[mi] += dMoAct;
        }
        o.khYtdDt += dKhYtdDt;
      };
      const prodKey = `${r.grp}||${r.mset}||${r.prod}`;
      bump(c);
      c.prods.add(prodKey);
      // --- Cấp Khách hàng thật (chỉ dưới nhóm "Ngoài kế hoạch") ---
      // Nhóm SP / Sản phẩm treo dưới KH thật, không treo thẳng vào nhóm "Ngoài kế hoạch".
      let host = c;
      if (isOop && r.cust && r.cust !== OOP_CUST) {
        if (!c.subMap.has(r.cust))
          c.subMap.set(r.cust, newCust(r.cust, r.custId));
        host = c.subMap.get(r.cust);
        bump(host);
        host.prods.add(prodKey);
      }
      // --- Cấp Nhóm sản phẩm ---
      const gKey = r.grp || '(Không rõ nhóm)';
      if (!host.grpMap.has(gKey))
        host.grpMap.set(gKey, {
          grp: gKey,
          dt: 0,
          dtYtd: 0,
          dtUpd: 0,
          quotaFY: 0,
          quotaFYDt: 0,
          q14: 0,
          q14Dt: 0,
          qUpcomingDt: 0,
          ytd: 0,
          khLeft: 0,
          khLeftDt: 0,
          moKhDt: MONTHS.map(() => 0),
          moActDt: MONTHS.map(() => 0),
          khYtdDt: 0,
          prodMap: new Map(),
        });
      const gNode = host.grpMap.get(gKey);
      bump(gNode);
      // --- Cấp Sản phẩm (trong 1 nhóm, phân biệt theo bộ vật tư + sản phẩm) ---
      const pKey = `${r.mset}||${r.prod}`;
      if (!gNode.prodMap.has(pKey))
        gNode.prodMap.set(pKey, {
          prod: r.prod || '—',
          mset: r.mset || '',
          dt: 0,
          dtYtd: 0,
          dtUpd: 0,
          quotaFY: 0,
          quotaFYDt: 0,
          q14: 0,
          q14Dt: 0,
          qUpcomingDt: 0,
          ytd: 0,
          khLeft: 0,
          khLeftDt: 0,
          moKhDt: MONTHS.map(() => 0),
          moActDt: MONTHS.map(() => 0),
          khYtdDt: 0,
        });
      bump(gNode.prodMap.get(pKey));
    }
    const fold = () => ({
      dt: 0,
      dtYtd: 0,
      dtUpd: 0,
      quotaFY: 0,
      quotaFYDt: 0,
      q14: 0,
      q14Dt: 0,
      qUpcomingDt: 0,
      ytd: 0,
      khLeft: 0,
      khLeftDt: 0,
      moKhDt: MONTHS.map(() => 0),
      moActDt: MONTHS.map(() => 0),
      khYtdDt: 0,
      prodCount: 0,
      custCount: 0,
    });
    const add = (a, c) => {
      a.dt += c.dt;
      a.dtYtd += c.dtYtd;
      a.dtUpd += c.dtUpd;
      a.quotaFY += c.quotaFY;
      a.quotaFYDt += c.quotaFYDt;
      a.q14 += c.q14;
      a.q14Dt += c.q14Dt;
      a.qUpcomingDt += c.qUpcomingDt;
      a.ytd += c.ytd;
      a.khLeft += c.khLeft;
      a.khLeftDt += c.khLeftDt;
      for (let i = 0; i < 12; i++) {
        a.moKhDt[i] += c.moKhDt[i];
        a.moActDt[i] += c.moActDt[i];
      }
      a.khYtdDt += c.khYtdDt;
      a.prodCount += c.prodCount;
      return a;
    };
    // Thứ tự PS/KH: có DThu KH update xếp trước (giảm dần theo KH update); không có thì
    // xếp sau (giảm dần theo DThu thực hiện YTD); "Ngoài kế hoạch" luôn xuống cuối.
    const orderByUpd = (a, b) => {
      const oa = a.cust === OOP_CUST ? 1 : 0,
        ob = b.cust === OOP_CUST ? 1 : 0;
      if (oa !== ob) return oa - ob;
      const ha = (a.dtUpd || 0) > 0 ? 0 : 1,
        hb = (b.dtUpd || 0) > 0 ? 0 : 1;
      if (ha !== hb) return ha - hb;
      return ha === 0
        ? (b.dtUpd || 0) - (a.dtUpd || 0)
        : (b.dtYtd || 0) - (a.dtYtd || 0);
    };
    const regions = Array.from(regMap.values()).map((reg) => {
      const psList = Array.from(reg.psMap.values()).map((ps) => {
        // Đệ quy: nhóm "Ngoài kế hoạch" có thêm 1 cấp KH thật (subs) trước khi tới Nhóm SP
        const buildCust = (c) => {
          // KH ngoài kế hoạch: quotaAvail = null → hiển thị "—" (không tính, không để âm)
          const avail = (o) => (c.oop ? null : o.q14 - o.ytd);
          const availDt = (o) =>
            c.oop ? null : o.q14Dt - o.dtYtd;
          // Nhóm SP dưới KH, và Sản phẩm dưới Nhóm SP
          const grps = Array.from(c.grpMap.values()).map((gp) => {
            const prods = Array.from(gp.prodMap.values()).map((pp) => ({
              ...pp,
              quotaAvail: avail(pp),
              quotaAvailDt: availDt(pp),
            }));
            prods.sort((a, b) => b.dt - a.dt);
            return {
              ...gp,
              _ps: ps.ps,
              _custId: c.custId || '',
              prods,
              prodCount: prods.length,
              quotaAvail: avail(gp),
              quotaAvailDt: availDt(gp),
            };
          });
          grps.sort((a, b) => b.dt - a.dt);
          const subs = Array.from(c.subMap.values()).map(buildCust);
          subs.sort((a, b) => b.ytd - a.ytd); // KH ngoài kế hoạch: xếp theo SL thực hiện
          return {
            ...c,
            grps,
            subs,
            prodCount: c.prods.size,
            quotaAvail: avail(c),
            quotaAvailDt: availDt(c),
          };
        };
        const custs = Array.from(ps.custMap.values()).map(buildCust);
        custs.sort(orderByUpd);
        const tot = custs.reduce(add, fold());
        tot.custCount = custs.length;
        return {
          ps: ps.ps,
          custs,
          ...tot,
          quotaAvail: tot.q14 - tot.ytd,
          quotaAvailDt: tot.q14Dt - tot.dtYtd,
        };
      });
      psList.sort(orderByUpd);
      const tot = psList.reduce((a, p) => {
        add(a, p);
        a.custCount += p.custCount;
        return a;
      }, fold());
      return {
        region: reg.region,
        psList,
        ...tot,
        quotaAvail: tot.q14 - tot.ytd,
        quotaAvailDt: tot.q14Dt - tot.dtYtd,
      };
    });
    regions.sort((a, b) => b.dt - a.dt);
    const grand = regions.reduce((a, rg) => {
      add(a, rg);
      a.custCount += rg.custCount;
      return a;
    }, fold());
    grand.quotaAvail = grand.q14 - grand.ytd;
    grand.quotaAvailDt = grand.q14Dt - grand.dtYtd;
    return {
      regions,
      grand,
    };
  }, [rows, psFilter, regionFilter, custFilter, groupFilter, search]);
  const g = data.grand;
  // Thu gọn/mở phần thực hiện theo tháng (mặc định thu gọn → chỉ còn Luỹ kế YTD).
  const [showMonths, setShowMonths] = useState(false);
  SUM_SHOW_MONTHS = showMonths; // set trước khi render header/rows (chúng đọc biến module này)
  // Nút xuất Excel nằm trên thanh bộ lọc (do App vẽ) → đăng ký hàm xuất lên đó
  useEffect(() => {
    onExport(() => exportSummaryPS(data));
    return () => onExport(null);
  }, [data, onExport]);
  return (
    <React.Fragment>
      <GiaiTrinhModal
        info={noteInfo}
        onClose={() => setNoteInfo(null)}
        auth={auth}
      />
      <div className="px-6 pb-8">
        <div className="bg-white rounded-lg border border-slate-200 overflow-hidden">
          <div className="flex items-center justify-end gap-2 px-3 py-2 border-b border-slate-100 bg-slate-50/50">
            <button
              onClick={() => setShowMonths((s) => !s)}
              title={
                showMonths
                  ? 'Thu gọn, chỉ hiện tháng hiện tại + Luỹ kế YTD'
                  : 'Hiện chi tiết doanh thu theo từng tháng'
              }
              className="inline-flex items-center gap-1.5 px-3 py-1.5 text-[12px] font-medium rounded-md border border-slate-200 bg-white text-slate-600 hover:bg-slate-50"
            >
              {showMonths ? '▾ Thu gọn theo tháng' : '▸ Chi tiết theo tháng'}
            </button>
          </div>
          <div ref={boxRef} className="overflow-auto summary-scroll">
            <table className="w-full border-collapse sticky-head">
              <thead>
                <SummaryHead />
              </thead>
              <tbody>
                {data.regions.map((rg) => (
                  <SummaryRegionRow key={rg.region} reg={rg} />
                ))}
                <tr className="bg-slate-800 text-white font-semibold">
                  <td className="px-3 py-2.5 text-[12.5px] border-t-2 border-slate-900 sticky left-0 z-10 bg-slate-800">
                    TỔNG CỘNG
                  </td>
                  <StatCells d={g} dark />
                  <td className="px-4 py-2.5" />
                </tr>
              </tbody>
            </table>
          </div>
        </div>
        <p className="text-[11px] text-slate-400 mt-2">
          Cột theo tháng & Luỹ kế YTD = doanh thu (SL × đơn giá): KH = DThu KH
          update, TH = DThu thực hiện, % = TH / KH. Mặc định chỉ hiện tháng hiện
          tại + Luỹ kế YTD; nút "Chi tiết theo tháng" hiện đủ 12 tháng. Ở Luỹ kế
          YTD: % TH YTD = TH YTD / KH YTD; tốc độ TH YTD = TH YTD / KH update cả
          năm; tốc độ KH YTD = KH YTD / KH update cả năm (tiến độ kế hoạch); CL
          tốc độ = tốc độ TH YTD − tốc độ KH YTD (dương = thực hiện nhanh hơn
          tiến độ kế hoạch). ≥1 tỷ hiện theo tỷ (1 số lẻ), nhỏ hơn hiện theo
          triệu. Luỹ kế YTD tính ĐẾN HẾT tháng hiện tại. Quota: On hand = (quota
          thầu cũ + quota chính đã tới tháng + quota BS đã tới tháng) × đơn giá;
          Upcoming = (quota chính + BS chưa tới tháng hoặc chưa điền tháng) ×
          đơn giá; Tổng quota = On hand + Upcoming; Khả dụng = Tổng quota − TH
          YTD. Target: KH đầu năm = DThu kế hoạch đầu năm; KH Update = DThu
          update cả năm; Chênh lệch = KH Update − KH đầu năm.
        </p>
      </div>
    </React.Fragment>
  );
}
const chCls = (v) =>
  v > 0 ? 'text-emerald-700' : v < 0 ? 'text-red-600' : 'text-slate-400';
// % Thực hiện YTD = DThu thực hiện YTD / DThu KH update cả năm
const pctYtd = (th, kh) => (kh > 0 ? ((th / kh) * 100).toFixed(1) + '%' : '—');

// ===== Cột theo tháng (doanh thu) cho màn Tổng hợp theo PS — giống bố cục màn SP =====
const getSumCurIdx = () => Math.max(0, getCurIdx());
const moHasAct = (i) => i <= getSumCurIdx(); // tháng đã qua/hiện tại mới có TH → 3 cột con; tháng sau chỉ 1 cột KH
const moBgSum = (i) =>
  MONTHS[i] === CURRENT_MONTH ? 'bg-blue-50/50' : i % 2 ? 'bg-slate-50/60' : '';
const pctTxtSum = (th, kh) =>
  kh > 0 ? Math.round((th / kh) * 100) + '%' : '—';
const pctClsSum = (th, kh) => {
  if (!(kh > 0)) return 'text-slate-300';
  const r = th / kh;
  return r >= 1
    ? 'text-green-700'
    : r >= 0.8
      ? 'text-amber-600'
      : 'text-red-600';
};
// Nút "chi tiết theo tháng": khi false chỉ hiện THÁNG HIỆN TẠI + Luỹ kế YTD; khi true hiện đủ 12 tháng.
// SummaryView set biến này trước khi render con (giống cơ chế MASK_MONEY).
let SUM_SHOW_MONTHS = false;
// Các cột tháng hiển thị: mặc định chỉ tháng hiện tại; bấm "Chi tiết theo tháng" thì hiện cả 12.
const sumMonthIdxs = () =>
  SUM_SHOW_MONTHS
    ? MONTHS.map((_, i) => i)
    : getCurIdx() >= 0
      ? [getCurIdx()]
      : [];

// Header 2 tầng cho màn Tổng hợp theo PS.
function SummaryHead() {
  const base =
    'font-semibold uppercase tracking-wide border-b border-slate-200';
  const monthThOf = (i) => {
    const m = MONTH_LABELS[i];
    const tone =
      MONTHS[i] < CURRENT_MONTH
        ? 'bg-teal-50/60 text-teal-700'
        : MONTHS[i] === CURRENT_MONTH
          ? 'bg-blue-100/60 text-blue-700'
          : 'bg-blue-50/40 text-blue-600';
    return (
      <th
        key={'mh' + i}
        colSpan={moHasAct(i) ? 3 : undefined}
        rowSpan={moHasAct(i) ? undefined : 2}
        className={`px-2 py-1.5 text-[10px] ${base} border-r align-bottom ${moHasAct(i) ? 'text-center' : 'text-right'} ${tone}`}
      >
        {m}
      </th>
    );
  };
  const sub = (key, tone, pctLabel = '%') => [
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
      className={`px-2 py-1 text-right text-[9.5px] font-medium uppercase text-slate-500 border-r border-b border-slate-200 whitespace-nowrap ${tone}`}
    >
      {pctLabel}
    </th>,
  ];
  // Nhóm Luỹ kế YTD: KH · TH · % TH YTD · tốc độ TH YTD · tốc độ KH YTD · CL tốc độ (chỉ cột cuối có border-r đóng nhóm).
  const ybg = 'bg-amber-50/40';
  const ytdSub = [
    <th
      key="ytk"
      className={`px-2 py-1 text-right text-[9.5px] font-medium uppercase text-slate-500 border-b border-slate-200 ${ybg}`}
    >
      KH
    </th>,
    <th
      key="yta"
      className={`px-2 py-1 text-right text-[9.5px] font-medium uppercase text-orange-600 border-b border-slate-200 ${ybg}`}
    >
      TH
    </th>,
    <th
      key="ytp"
      className={`px-2 py-1 text-right text-[9.5px] font-medium uppercase text-slate-500 border-b border-slate-200 whitespace-nowrap ${ybg}`}
    >
      % TH YTD
    </th>,
    <th
      key="yttd"
      className={`px-2 py-1 text-right text-[9.5px] font-medium uppercase text-slate-500 border-b border-slate-200 whitespace-nowrap ${ybg}`}
    >
      tốc độ TH YTD
    </th>,
    <th
      key="ytkp"
      className={`px-2 py-1 text-right text-[9.5px] font-medium uppercase text-slate-500 border-b border-slate-200 whitespace-nowrap ${ybg}`}
    >
      tốc độ KH YTD
    </th>,
    <th
      key="ytcl"
      className={`px-2 py-1 text-right text-[9.5px] font-medium uppercase text-slate-500 border-r border-b border-slate-200 whitespace-nowrap ${ybg}`}
    >
      CL tốc độ
    </th>,
  ];
  return (
    <React.Fragment>
      {React.createElement(
        'tr',
        { className: 'bg-slate-100' },
        <th
          rowSpan={2}
          className={`px-4 py-2 text-left text-[11px] ${base} border-r text-slate-600 align-bottom sticky left-0 z-[11] bg-slate-100`}
          style={{ minWidth: 200 }}
        >
          Miền / PS / Khách hàng
        </th>,
        ...sumMonthIdxs().map(monthThOf),
        <th
          colSpan={6}
          className="px-3 py-1.5 text-center text-[11px] font-bold uppercase tracking-wide text-amber-800 border-r border-b border-slate-200 bg-amber-50/60"
        >
          Luỹ kế YTD
        </th>,
        <th
          colSpan={5}
          className="px-3 py-1.5 text-center text-[11px] font-bold uppercase tracking-wide text-teal-800 border-r border-b border-slate-200 bg-teal-50/60"
        >
          Quota
        </th>,
        <th
          colSpan={3}
          className="px-3 py-1.5 text-center text-[11px] font-bold uppercase tracking-wide text-emerald-800 border-r border-b border-slate-200 bg-emerald-50/60"
        >
          Target
        </th>,
        <th
          rowSpan={2}
          className={`px-2 py-2 text-center text-[11px] ${base} text-amber-700 align-bottom`}
          style={{ width: 90 }}
        >
          Giải trình
        </th>,
      )}
      {React.createElement(
        'tr',
        { className: 'bg-slate-100' },
        ...sumMonthIdxs().flatMap((i) =>
          moHasAct(i)
            ? sub('s' + i, MONTHS[i] === CURRENT_MONTH ? 'bg-blue-50/40' : '')
            : [],
        ),
        ...ytdSub,
        <th
          key="qq14"
          className={`px-2 py-1 text-right text-[9.5px] font-medium uppercase text-teal-700 border-b border-slate-200 bg-teal-50/40 whitespace-nowrap`}
        >
          On hand
        </th>,
        <th
          key="qqup"
          className={`px-2 py-1 text-right text-[9.5px] font-medium uppercase text-teal-700 border-b border-slate-200 bg-teal-50/40 whitespace-nowrap`}
        >
          Upcoming
        </th>,
        <th
          key="qqfy"
          className={`px-2 py-1 text-right text-[9.5px] font-medium uppercase text-teal-700 border-b border-slate-200 bg-teal-50/40 whitespace-nowrap`}
        >
          Tổng quota
        </th>,
        <th
          key="qqth"
          className={`px-2 py-1 text-right text-[9.5px] font-medium uppercase text-orange-600 border-b border-slate-200 bg-teal-50/40 whitespace-nowrap`}
        >
          TH YTD
        </th>,
        <th
          key="qqav"
          className={`px-2 py-1 text-right text-[9.5px] font-medium uppercase text-teal-700 border-r border-b border-slate-200 bg-teal-50/40 whitespace-nowrap`}
        >
          Khả dụng
        </th>,
        <th
          key="tdt"
          className={`px-2 py-1 text-right text-[9.5px] font-medium uppercase text-emerald-700 border-b border-slate-200 bg-emerald-50/40 whitespace-nowrap`}
        >
          KH đầu năm
        </th>,
        <th
          key="tdu"
          className={`px-2 py-1 text-right text-[9.5px] font-medium uppercase text-blue-600 border-b border-slate-200 bg-emerald-50/40 whitespace-nowrap`}
        >
          KH Update
        </th>,
        <th
          key="tch"
          className={`px-2 py-1 text-right text-[9.5px] font-medium uppercase text-emerald-700 border-r border-b border-slate-200 bg-emerald-50/40 whitespace-nowrap`}
        >
          Chênh lệch
        </th>,
      )}
    </React.Fragment>
  );
}

// Các ô số: [tháng] → Luỹ kế YTD → Quota (On hand · Upcoming · Tổng · TH YTD · Khả dụng) → Target (KH đầu năm · KH Update · CL).
function StatCells({ d, size, dark }) {
  const p =
    size === 'sm'
      ? 'py-1.5 text-[12px]'
      : dark
        ? 'py-2.5 text-[12.5px]'
        : 'py-2 text-[13px]';
  const base = dark
    ? 'text-white'
    : size === 'sm'
      ? 'text-slate-600'
      : 'text-slate-700';
  const orange = dark
    ? 'text-orange-200'
    : size === 'sm'
      ? 'text-orange-600'
      : 'text-orange-700';
  const blue = dark
    ? 'text-blue-200'
    : size === 'sm'
      ? 'text-blue-600'
      : 'text-blue-700';
  const cells = [];
  // --- Cột theo tháng (mặc định chỉ tháng hiện tại, "chi tiết theo tháng" hiện đủ 12) ---
  for (const i of sumMonthIdxs()) {
    const bg = dark ? '' : moBgSum(i);
    const kh = d.moKhDt[i],
      act = d.moActDt[i];
    if (!moHasAct(i)) {
      cells.push(
        <td
          key={'k' + i}
          className={`px-2 ${p} text-right tabular-nums border-r border-slate-100 ${base} ${bg}`}
        >
          {moneyTy3(kh)}
        </td>,
      );
      continue;
    }
    cells.push(
      <td
        key={'k' + i}
        className={`px-2 ${p} text-right tabular-nums ${base} ${bg}`}
      >
        {moneyTy3(kh)}
      </td>,
    );
    cells.push(
      <td
        key={'a' + i}
        className={`px-2 ${p} text-right tabular-nums ${orange} ${bg}`}
      >
        {moneyTy3(act)}
      </td>,
    );
    cells.push(
      <td
        key={'pc' + i}
        className={`px-2 ${p} text-right tabular-nums border-r border-slate-200 ${dark ? 'text-slate-300' : pctClsSum(act, kh)} ${bg}`}
      >
        {pctTxtSum(act, kh)}
      </td>,
    );
  }
  // --- Luỹ kế YTD (doanh thu): KH · TH · % TH YTD · % KH YTD · CL tốc độ ---
  const ybg = dark ? '' : 'bg-amber-50/40';
  // % TH YTD = TH YTD / KH YTD ; tốc độ TH YTD = TH YTD / KH update cả năm ;
  // tốc độ KH YTD = KH YTD / KH update cả năm ; CL tốc độ = tốc độ TH YTD − tốc độ KH YTD (điểm %).
  const tdTh = d.dtUpd > 0 ? d.dtYtd / d.dtUpd : null;
  const tdKh = d.dtUpd > 0 ? d.khYtdDt / d.dtUpd : null;
  const clVal =
    tdTh != null && tdKh != null ? Math.round((tdTh - tdKh) * 100) : null;
  const clCol = dark ? 'text-slate-300' : chCls(clVal || 0);
  cells.push(
    <td
      key="yk"
      className={`px-3 ${p} text-right tabular-nums font-medium ${base} ${ybg}`}
    >
      {moneyTy3(d.khYtdDt)}
    </td>,
  );
  cells.push(
    <td
      key="ya"
      className={`px-3 ${p} text-right tabular-nums font-medium ${orange} ${ybg}`}
    >
      {moneyTy3(d.dtYtd)}
    </td>,
  );
  cells.push(
    <td
      key="yp"
      className={`px-3 ${p} text-right tabular-nums font-semibold ${dark ? 'text-slate-300' : pctClsSum(d.dtYtd, d.khYtdDt)} ${ybg}`}
    >
      {pctTxtSum(d.dtYtd, d.khYtdDt)}
    </td>,
  );
  cells.push(
    <td
      key="ytd"
      className={`px-3 ${p} text-right tabular-nums font-medium ${dark ? 'text-slate-300' : 'text-slate-500'} ${ybg}`}
    >
      {pctTxtSum(d.dtYtd, d.dtUpd)}
    </td>,
  );
  cells.push(
    <td
      key="ykp"
      className={`px-3 ${p} text-right tabular-nums font-medium ${dark ? 'text-slate-300' : 'text-slate-500'} ${ybg}`}
    >
      {pctTxtSum(d.khYtdDt, d.dtUpd)}
    </td>,
  );
  cells.push(
    <td
      key="ycl"
      className={`px-3 ${p} text-right tabular-nums font-semibold border-r border-slate-200 ${clCol} ${ybg}`}
    >
      {clVal == null ? '—' : (clVal > 0 ? '+' : '') + clVal + '%'}
    </td>,
  );
  // --- Quota group: On hand · Upcoming · Tổng quota · TH YTD · Khả dụng ---
  const qbg = dark ? '' : 'bg-teal-50/30';
  const quotaRemain =
    d.quotaAvailDt == null ? null : (d.q14Dt || 0) - (d.dtYtd || 0);
  cells.push(
    <td
      key="q14"
      className={`px-3 ${p} text-right tabular-nums font-medium ${base} ${qbg}`}
    >
      {moneyTy3(d.q14Dt)}
    </td>,
  );
  cells.push(
    <td
      key="qup"
      className={`px-3 ${p} text-right tabular-nums font-medium ${base} ${qbg}`}
    >
      {moneyTy3(d.qUpcomingDt)}
    </td>,
  );
  cells.push(
    <td
      key="q"
      className={`px-3 ${p} text-right tabular-nums font-medium ${base} ${qbg}`}
    >
      {moneyTy3(d.quotaFYDt)}
    </td>,
  );
  cells.push(
    <td
      key="qth"
      className={`px-3 ${p} text-right tabular-nums font-medium ${orange} ${qbg}`}
    >
      {moneyTy3(d.dtYtd)}
    </td>,
  );
  cells.push(
    <td
      key="qav"
      className={`px-3 ${p} text-right tabular-nums font-medium border-r border-slate-200 ${quotaRemain == null ? (dark ? 'text-slate-500' : 'text-slate-300') : base} ${qbg}`}
    >
      {quotaRemain == null ? '—' : moneyTy3(quotaRemain)}
    </td>,
  );
  // --- Target group: KH đầu năm · KH Update · Chênh lệch ---
  const tbg = dark ? '' : 'bg-emerald-50/30';
  const ch = (d.dtUpd || 0) - (d.dt || 0);
  const chCol = dark
    ? ch > 0
      ? 'text-emerald-300'
      : ch < 0
        ? 'text-red-300'
        : ''
    : chCls(ch);
  cells.push(
    <td
      key="dt"
      className={`px-3 ${p} text-right tabular-nums font-medium ${base} ${tbg}`}
    >
      {moneyTy3(d.dt)}
    </td>,
  );
  cells.push(
    <td
      key="du"
      className={`px-3 ${p} text-right tabular-nums font-medium ${blue} ${tbg}`}
    >
      {moneyTy3(d.dtUpd)}
    </td>,
  );
  cells.push(
    <td
      key="ch"
      className={`px-3 ${p} text-right tabular-nums font-semibold border-r border-slate-100 ${chCol} ${tbg}`}
    >
      {ch === 0 ? '—' : MASK_MONEY ? '•••' : (ch > 0 ? '+' : '') + fmtTy3(ch)}
    </td>,
  );
  return React.createElement(React.Fragment, null, ...cells);
}
function SummaryRegionRow({ reg }) {
  const [open, setOpen] = useState(true);
  return (
    <React.Fragment>
      <tr
        data-lv={0}
        className="bg-sky-50 hover:bg-sky-100 cursor-pointer border-b border-slate-200"
        onClick={() => setOpen(!open)}
      >
        <td className="px-3 py-2 text-[13px] font-bold text-sky-900 border-r border-slate-100 sticky left-0 z-10 bg-sky-50">
          <span className="inline-flex items-center gap-1.5">
            {open ? (
              <ChevronDown size={14} className="text-sky-600" />
            ) : (
              <ChevronRight size={14} className="text-sky-600" />
            )}
            {reg.region}
          </span>
        </td>
        <StatCells d={reg} />
        <td className="border-b border-slate-100" />
      </tr>
      {open && reg.psList.map((ps) => <SummaryPSRow key={ps.ps} ps={ps} />)}
    </React.Fragment>
  );
}
function SummaryPSRow({ ps }) {
  const [open, setOpen] = useState(false);
  return (
    <React.Fragment>
      <tr
        data-lv={1}
        className="bg-slate-50 hover:bg-slate-100 cursor-pointer border-b border-slate-200"
        onClick={() => setOpen(!open)}
      >
        <td className="px-3 py-2 text-[13px] font-semibold text-slate-800 border-r border-slate-100 whitespace-nowrap sticky left-0 z-10 bg-slate-50">
          <span className="inline-flex items-center gap-1.5">
            {open ? (
              <ChevronDown size={14} className="text-slate-500" />
            ) : (
              <ChevronRight size={14} className="text-slate-500" />
            )}
            {ps.ps}
          </span>
        </td>
        <StatCells d={ps} />
        <td className="border-b border-slate-100" />
      </tr>
      {open && ps.custs.map((c) => <SummaryCustRow key={c.cust} cust={c} />)}
    </React.Fragment>
  );
}
// Cấp Khách hàng — mở ra để xem Nhóm sản phẩm bên dưới.
// Riêng nhóm "Ngoài kế hoạch": con là các KH thật (depth+1), rồi mới tới Nhóm SP.
function SummaryCustRow({ cust: c, depth = 0 }) {
  const [open, setOpen] = useState(false);
  const subs = c.subs || [];
  const grps = c.grps || [];
  const hasKids = subs.length > 0 || grps.length > 0;
  return (
    <React.Fragment>
      <tr
        data-lv={2}
        className={
          (c.oop ? 'bg-amber-50/40' : 'bg-white') +
          ' hover:bg-slate-50/60 border-b border-slate-100' +
          (hasKids ? ' cursor-pointer' : '')
        }
        onClick={hasKids ? () => setOpen(!open) : undefined}
      >
        <td
          className={
            'px-3 py-1.5 text-[12px] text-slate-600 border-r border-slate-100 sticky left-0 z-10 ' +
            (c.oop ? 'bg-amber-50/40' : 'bg-white')
          }
        >
          <span className="inline-flex items-center gap-1">
            {hasKids ? (
              open ? (
                <ChevronDown size={12} className="text-slate-400" />
              ) : (
                <ChevronRight size={12} className="text-slate-400" />
              )
            ) : (
              <span style={{ width: 12, display: 'inline-block' }} />
            )}
            <span
              className={
                'truncate' +
                (c.cust === OOP_CUST ? ' text-amber-700 font-medium' : '')
              }
            >
              {c.cust}
            </span>{' '}
            {c.cust === OOP_CUST ? (
              <span className="text-[9.5px] px-1.5 py-0.5 rounded bg-amber-100 text-amber-700 font-medium whitespace-nowrap">
                Ngoài KH
              </span>
            ) : (
              <span className="text-[10px] text-slate-400 font-mono">
                {c.custId}
              </span>
            )}
          </span>
        </td>
        <StatCells d={c} size="sm" />
        <td className="border-b border-slate-100" />
      </tr>
      {open &&
        (subs.length
          ? subs.map((s) => (
              <SummaryCustRow key={s.cust} cust={s} depth={depth + 1} />
            ))
          : grps.map((gp) => (
              <SummaryGroupRow key={gp.grp} grp={gp} depth={depth} />
            )))}
    </React.Fragment>
  );
}
// Cấp Nhóm sản phẩm — có thể mở ra để xem từng Sản phẩm bên dưới.
function SummaryGroupRow({ grp: g, depth = 0 }) {
  const [open, setOpen] = useState(false);
  const hasKids = g.prods && g.prods.length > 0;
  return (
    <React.Fragment>
      <tr
        data-lv={3}
        className={
          'bg-slate-50 hover:bg-slate-100/60 border-b border-slate-100' +
          (hasKids ? ' cursor-pointer' : '')
        }
        onClick={hasKids ? () => setOpen(!open) : undefined}
      >
        <td className="px-3 py-1.5 text-[12px] text-slate-700 border-r border-slate-100 sticky left-0 z-10 bg-slate-50">
          <span className="inline-flex items-center gap-1">
            {hasKids ? (
              open ? (
                <ChevronDown size={12} className="text-slate-400" />
              ) : (
                <ChevronRight size={12} className="text-slate-400" />
              )
            ) : (
              <span style={{ width: 12, display: 'inline-block' }} />
            )}
            <span className="truncate font-medium">{g.grp}</span>
          </span>
        </td>
        <StatCells d={g} size="sm" />
        <td className="px-1 py-1.5 text-center border-b border-slate-100">
          <button
            className="inline-flex items-center gap-0.5 px-1.5 py-0.5 text-[11px] font-medium rounded border border-amber-200 text-amber-700 bg-white hover:bg-amber-50 whitespace-nowrap"
            onClick={(e) => {
              e.stopPropagation();
              _openGiaiTrinh &&
                _openGiaiTrinh({ ps: g._ps, custId: g._custId, grp: g.grp });
            }}
          >
            📝
          </button>
        </td>
      </tr>
      {open &&
        g.prods.map((p, i) => (
          <tr
            key={p.mset + '||' + p.prod + '||' + i}
            className="hover:bg-slate-50/40 border-b border-slate-100"
          >
            <td className="px-3 py-1.5 text-[11.5px] text-slate-500 border-r border-slate-100 sticky left-0 z-10 bg-white">
              <div className="break-words">{p.prod}</div>
            </td>
            <StatCells d={p} size="sm" />
            <td className="border-b border-slate-100" />
          </tr>
        ))}
    </React.Fragment>
  );
}
