import React, { useState, useEffect, useMemo, useCallback, Fragment } from 'react';
import { ChevronDown, ChevronRight, AlertCircle, Download, Loader2, Trash2 } from './icons.jsx';
import { MONTHS, MONTH_LABELS, TEAMS, MASK_MONEY } from '../config/constants.js';
import { fmtTy3, moneyTy3 } from '../lib/format.js';
import { useFitHeight, useSummaryScrollbar, useStickyRows } from '../hooks/useLayout.jsx';
import { deaccent } from '../lib/text.js';
import { exportSoSanhKeHoach } from '../lib/excel.js';
import { api } from '../api/client.js';

// Dòng từ RPC so_sanh_chot_ke_hoach (mảng gọn, chi tiết PS × KH × nhóm SP × tháng):
// [fy, thang, bu, mien, ps, maKh, tenKh, nhom, dtA, dtB, khA, khB]
// dt = DThu KH update như app (tháng đã có thực hiện lấy TH); kh = SL update × giá (luôn là KH).
const toRow = (a) => ({
  fy: a[0], mo: a[1], bu: a[2], region: a[3], ps: a[4], custId: a[5], cust: a[6], grp: a[7],
  dtA: Number(a[8]) || 0, dtB: Number(a[9]) || 0, khA: Number(a[10]) || 0, khB: Number(a[11]) || 0,
});

const HIEN_TAI = '__hien_tai__';

// Cây cố định: BU → Miền → PS → Khách hàng → Nhóm sản phẩm.
const CAP = [
  { label: 'BU', key: (r) => r.bu || '', ten: (r) => (TEAMS[r.bu] && TEAMS[r.bu].label) || r.bu || '(trống)' },
  { label: 'Miền', key: (r) => r.region || '', ten: (r) => r.region || '(trống)' },
  { label: 'PS', key: (r) => r.ps || '', ten: (r) => r.ps || '(trống)' },
  {
    label: 'Khách hàng', key: (r) => r.custId || r.cust || '',
    ten: (r) => r.cust || r.custId || '(trống)', phu: (r) => r.custId,
  },
  { label: 'Nhóm SP', key: (r) => r.grp || '', ten: (r) => r.grp || '(trống)' },
];
const CAP_PS = CAP.findIndex((c) => c.label === 'PS'); // mặc định mở tới cấp PS
const NUT_MO = ['BU', 'Miền', 'PS', 'KH', 'Nhóm SP'];

const kyLabel = (ky) => (ky ? `T${Number(ky.slice(5, 7))}/${ky.slice(0, 4)}` : '');
const thangVN = () =>
  new Intl.DateTimeFormat('en-CA', { timeZone: 'Asia/Ho_Chi_Minh', year: 'numeric', month: '2-digit' })
    .format(new Date())
    .slice(0, 7);
const fmtLuc = (s) =>
  s ? new Date(s).toLocaleString('vi-VN', { timeZone: 'Asia/Ho_Chi_Minh', dateStyle: 'short', timeStyle: 'short' }) : '';
// '2026-11-05 18:00' giờ VN.
const fmtLucIso = (s) =>
  s
    ? new Intl.DateTimeFormat('sv-SE', {
        timeZone: 'Asia/Ho_Chi_Minh', year: 'numeric', month: '2-digit', day: '2-digit',
        hour: '2-digit', minute: '2-digit',
      }).format(new Date(s))
    : '';
const dongChot = (k) =>
  `Chốt bản ghi ${k.ky} lúc: ${fmtLucIso(k.chot_luc)}, ` +
  (k.nguon === 'tu_dong' ? 'thực hiện tự động' : `thực hiện thủ công${k.nguoi ? ' bởi ' + k.nguoi : ''}`);
const coDoi = (g) => Math.round(g.dtB - g.dtA) !== 0;

// Gộp đệ quy theo CAP[cap..]; mỗi nút giữ tổng A/B, tổng theo tháng và nút con.
function dungCay(list, cap, chaKey) {
  const c = CAP[cap];
  const m = new Map();
  for (const r of list) {
    const k = chaKey + '|' + c.key(r);
    let g = m.get(k);
    if (!g) {
      g = { k, cap, ten: c.ten(r), phu: c.phu ? c.phu(r) : '', dtA: 0, dtB: 0, thang: new Map(), rows: [] };
      m.set(k, g);
    }
    g.dtA += r.dtA;
    g.dtB += r.dtB;
    const t = g.thang.get(r.mo) || { dtA: 0, dtB: 0, khA: 0, khB: 0 };
    t.dtA += r.dtA;
    t.dtB += r.dtB;
    t.khA += r.khA;
    t.khB += r.khB;
    g.thang.set(r.mo, t);
    g.rows.push(r);
  }
  const out = Array.from(m.values());
  for (const g of out) {
    g.chenh = g.dtB - g.dtA;
    g.con = cap + 1 < CAP.length ? dungCay(g.rows, cap + 1, g.k) : [];
  }
  return out.sort((a, b) => Math.abs(b.chenh) - Math.abs(a.chenh) || a.ten.localeCompare(b.ten));
}

// Định dạng và màu theo màn Tổng hợp theo PS (SummaryView): tiền dạng tỷ / tr, 0 hiện '—'.
const fmtCh = (v) =>
  MASK_MONEY ? '•••' : Math.round(v / 1e6) === 0 ? '—' : (v > 0 ? '+' : '') + fmtTy3(v);
const chCls = (v) => (Math.round(v / 1e6) === 0 ? 'text-slate-400' : v > 0 ? 'text-emerald-700' : 'text-red-600');
const pctChenh = (a, b) => {
  if (!a) return b ? 'mới' : '—';
  const p = ((b - a) / Math.abs(a)) * 100;
  return (p > 0 ? '+' : '') + p.toLocaleString('en-US', { maximumFractionDigits: 1 }) + '%';
};
const pctTxt = (th, kh) => (kh > 0 ? Math.round((th / kh) * 100) + '%' : '—');
const pctCls = (th, kh) =>
  !(kh > 0) ? 'text-slate-300' : Math.round((th / kh) * 100) >= 90 ? 'text-green-700' : 'text-red-600';

// Hàng theo cấp BU → Miền → PS → KH → Nhóm SP; Miền / PS / KH / Nhóm giống màn Tổng hợp theo PS.
const DONG = [
  { tr: 'bg-slate-200 hover:bg-slate-300/60 border-slate-300', td: 'bg-slate-200 text-[13px] font-bold text-slate-900', chev: 'text-slate-600', icon: 14 },
  { tr: 'bg-sky-50 hover:bg-sky-100 border-slate-200', td: 'bg-sky-50 text-[13px] font-bold text-sky-900', chev: 'text-sky-600', icon: 14 },
  { tr: 'bg-slate-50 hover:bg-slate-100 border-slate-200', td: 'bg-slate-50 text-[13px] font-semibold text-slate-800 whitespace-nowrap', chev: 'text-slate-500', icon: 14 },
  { tr: 'bg-white hover:bg-slate-50/60 border-slate-100', td: 'bg-white text-[12px] text-slate-600', chev: 'text-slate-400', icon: 12, sm: true },
  { tr: 'bg-slate-50 hover:bg-slate-100/60 border-slate-100', td: 'bg-slate-50 text-[12px] font-medium text-slate-700', chev: 'text-slate-400', icon: 12, sm: true },
];
const TH_NHOM = 'font-semibold uppercase tracking-wide border-b border-slate-200';
const TH_CON = 'px-2 py-1 text-right text-[9.5px] font-medium uppercase border-b border-slate-200 whitespace-nowrap';

// So sánh DThu KH update giữa 2 bản chụp hằng tháng (hoặc bản chụp với dữ liệu hiện tại),
// chi tiết PS → khách hàng → nhóm sản phẩm. Bản chụp tự động lúc 23:59 ngày hạn chót
// sale điền (deadline_day); admin chụp tay được.
export function SoSanhKeHoachView({ viewBu, isAdmin = false, curMonth = '' }) {
  const [kys, setKys] = useState([]);
  const [kyA, setKyA] = useState('');
  const [kyB, setKyB] = useState(HIEN_TAI);
  const [data, setData] = useState([]);
  const [dangTai, setDangTai] = useState(false);
  const [dangChup, setDangChup] = useState(false);
  const [loi, setLoi] = useState('');
  const [baoXong, setBaoXong] = useState('');
  const [thang, setThang] = useState('');
  const [search, setSearch] = useState('');
  const [chiThayDoi, setChiThayDoi] = useState(false);
  // Cột theo tháng: 'an' ẩn, 'chenh' B − A, 'a' số kỳ gốc, 'b' số bên so sánh.
  const [cheDoThang, setCheDoThang] = useState('chenh');
  const theoThang = cheDoThang !== 'an';
  const [loaiAdmin, setLoaiAdmin] = useState(true);
  const [loaiThucHien, setLoaiThucHien] = useState(true);
  const [mo, setMo] = useState(() => new Set());

  const taiKy = useCallback(async () => {
    const r = await api('getChotKy');
    const list = r.rows || [];
    setKys(list);
    return list;
  }, []);

  useEffect(() => {
    taiKy()
      .then((list) => setKyA((cur) => cur || (list[0] && list[0].ky) || ''))
      .catch((e) => setLoi(e.message));
  }, [taiKy]);

  useEffect(() => {
    if (!kyA) {
      setData([]);
      return;
    }
    let huy = false;
    setDangTai(true);
    setLoi('');
    api('soSanhChot', { a: kyA, b: kyB === HIEN_TAI ? null : kyB, loaiAdmin, loaiThucHien })
      .then((r) => !huy && setData((r.rows || []).map(toRow)))
      .catch((e) => !huy && setLoi(e.message))
      .finally(() => !huy && setDangTai(false));
    return () => {
      huy = true;
    };
  }, [kyA, kyB, loaiAdmin, loaiThucHien]);

  const chupNgay = async () => {
    const ky = thangVN();
    const daCo = kys.some((k) => k.ky === ky);
    if (
      !confirm(
        daCo
          ? `Kỳ ${kyLabel(ky)} đã có bản chụp. Ghi đè bằng dữ liệu kế hoạch hiện tại?`
          : `Chụp kế hoạch update hiện tại vào kỳ ${kyLabel(ky)}?`,
      )
    )
      return;
    setDangChup(true);
    setLoi('');
    setBaoXong('');
    try {
      const r = await api('chotKeHoach', { ky, ghiDe: daCo });
      await taiKy();
      setBaoXong(`Đã chụp kỳ ${kyLabel(ky)}: ${Number(r.so_dong).toLocaleString('vi-VN')} dòng.`);
      if (!kyA) setKyA(ky);
    } catch (e) {
      setLoi(e.message);
    }
    setDangChup(false);
  };

  const xoaKy = async (ky) => {
    if (!confirm(`Xoá bản chụp kỳ ${kyLabel(ky)}? Không khôi phục được.`)) return;
    setLoi('');
    setBaoXong('');
    try {
      await api('xoaChotKy', { ky });
      const list = await taiKy();
      if (kyA === ky) setKyA((list[0] && list[0].ky) || '');
      if (kyB === ky) setKyB(HIEN_TAI);
      setBaoXong(`Đã xoá bản chụp kỳ ${kyLabel(ky)}.`);
    } catch (e) {
      setLoi(e.message);
    }
  };

  const loc = useMemo(() => {
    const q = deaccent(search.trim());
    const tu = thangVN();
    return data.filter(
      (r) =>
        (viewBu === 'test' ? r.bu === 'test' : r.bu !== 'test' && (!viewBu || r.bu === viewBu)) &&
        (!thang || (thang === 'con_lai' ? r.mo >= tu : r.mo === thang)) &&
        (!q || [r.grp, r.cust, r.custId, r.ps].some((v) => deaccent(v || '').includes(q))),
    );
  }, [data, viewBu, thang, search]);

  const cay = useMemo(() => dungCay(loc, 0, ''), [loc]);

  const tong = useMemo(() => {
    const t = { dtA: 0, dtB: 0, thang: new Map() };
    for (const r of loc) {
      t.dtA += r.dtA;
      t.dtB += r.dtB;
      const x = t.thang.get(r.mo) || { dtA: 0, dtB: 0, khA: 0, khB: 0 };
      x.dtA += r.dtA;
      x.dtB += r.dtB;
      x.khA += r.khA;
      x.khB += r.khB;
      t.thang.set(r.mo, x);
    }
    return t;
  }, [loc]);
  const boxRef = useFitHeight();
  useSummaryScrollbar(boxRef);
  useStickyRows(boxRef); // ghim hàng BU / Miền / PS / KH khi cuộn, như màn Tổng hợp

  const thangCo = useMemo(() => MONTHS.filter((m) => data.some((r) => r.mo === m)), [data]);
  const thangCot = useMemo(
    () => thangCo.filter((m) => !thang || (thang === 'con_lai' ? m >= thangVN() : m === thang)),
    [thangCo, thang],
  );

  const bat = (k) =>
    setMo((s) => {
      const n = new Set(s);
      if (n.has(k)) n.delete(k);
      else n.add(k);
      return n;
    });
  const moHet = (capToiDa) => {
    const n = new Set();
    const duyet = (ds) =>
      ds.forEach((g) => {
        if (g.cap < capToiDa) {
          n.add(g.k);
          duyet(g.con);
        }
      });
    duyet(cay);
    setMo(n);
  };
  // Mỗi lần tải dữ liệu so sánh mới (đổi kỳ): mở sẵn mọi BU, Miền để thấy tới cấp PS.
  useEffect(() => {
    moHet(CAP_PS);
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [data]);

  const infoA = kys.find((k) => k.ky === kyA);
  const infoB = kyB === HIEN_TAI ? null : kys.find((k) => k.ky === kyB);
  const tenA = kyA ? `Chốt ${kyLabel(kyA)}` : '—';
  const tenB = kyB === HIEN_TAI ? 'Hiện tại' : `Chốt ${kyLabel(kyB)}`;
  // Tháng hiện tại lúc chụp của bên đang xem: tháng trước đó DThu lấy theo thực hiện.
  const mocTH =
    cheDoThang === 'a'
      ? (infoA && infoA.thang_hien_tai) || ''
      : cheDoThang === 'b'
        ? (infoB ? infoB.thang_hien_tai : curMonth) || ''
        : '';
  const laTH = (m) => !!mocTH && m < mocTH;
  // Tháng TH (xem số A/B) tách 3 cột KH upd · TH · % như màn Tổng hợp.
  const tach = (m) => theoThang && cheDoThang !== 'chenh' && laTH(m);
  const soCot = 5 + (theoThang ? thangCot.length + 2 * thangCot.filter(tach).length : 0);
  // Tô màu tháng theo mốc: đã qua (teal) · tháng hiện tại (xanh đậm) · tương lai (xanh nhạt).
  const mocMau = mocTH || curMonth;
  const mauTH = (m) =>
    m < mocMau ? 'bg-teal-50/60 text-teal-700' : m === mocMau ? 'bg-blue-100/60 text-blue-700' : 'bg-blue-50/40 text-blue-600';
  const nenO = (m) => (m === mocMau ? 'bg-blue-50/50' : MONTHS.indexOf(m) % 2 ? 'bg-slate-50/60' : '');

  const xuat = () =>
    exportSoSanhKeHoach(
      loc.filter((r) => !chiThayDoi || coDoi(r)),
      tenA,
      tenB,
      cheDoThang === 'an' ? 'chenh' : cheDoThang,
      mocTH,
    );

  // Các ô số của 1 hàng: Cả năm (A · B · Chênh · %) rồi theo tháng.
  const oSo = (g, sm, dark) => {
    const p = sm ? 'py-1.5 text-[12px]' : dark ? 'py-2.5 text-[12.5px]' : 'py-2 text-[13px]';
    const base = dark ? 'text-white' : sm ? 'text-slate-600' : 'text-slate-700';
    const green = dark ? 'text-green-300' : sm ? 'text-green-600' : 'text-green-700';
    const blue = dark ? 'text-blue-200' : sm ? 'text-blue-600' : 'text-blue-700';
    const chMau = (v) =>
      dark ? (Math.round(v / 1e6) === 0 ? 'text-slate-400' : v > 0 ? 'text-emerald-300' : 'text-red-300') : chCls(v);
    const tbg = dark ? '' : 'bg-emerald-50/30';
    const ch = g.dtB - g.dtA;
    const o = [
      <td key="a" className={`px-3 ${p} text-right tabular-nums font-medium ${base} ${tbg}`}>{moneyTy3(g.dtA)}</td>,
      <td key="b" className={`px-3 ${p} text-right tabular-nums font-medium ${blue} ${tbg}`}>{moneyTy3(g.dtB)}</td>,
      <td key="c" className={`px-3 ${p} text-right tabular-nums font-semibold ${chMau(ch)} ${tbg}`}>{fmtCh(ch)}</td>,
      <td key="p" className={`px-3 ${p} text-right tabular-nums font-semibold border-r border-slate-200 ${chMau(ch)} ${tbg}`}>
        {pctChenh(g.dtA, g.dtB)}
      </td>,
    ];
    if (!theoThang) return o;
    for (const m of thangCot) {
      const t = g.thang.get(m) || { dtA: 0, dtB: 0, khA: 0, khB: 0 };
      const bg = dark ? '' : nenO(m);
      const tip = `${tenA}: ${fmtTy3(t.dtA)} → ${tenB}: ${fmtTy3(t.dtB)}`;
      if (cheDoThang === 'chenh') {
        const v = t.dtB - t.dtA;
        o.push(
          <td key={m} title={tip} className={`px-2 ${p} text-right tabular-nums border-r border-slate-100 ${chMau(v)} ${bg}`}>
            {fmtCh(v)}
          </td>,
        );
        continue;
      }
      const so = cheDoThang === 'a' ? t.dtA : t.dtB;
      if (!tach(m)) {
        o.push(
          <td key={m} title={tip} className={`px-2 ${p} text-right tabular-nums border-r border-slate-100 ${base} ${bg}`}>
            {moneyTy3(so)}
          </td>,
        );
        continue;
      }
      const kh = cheDoThang === 'a' ? t.khA : t.khB;
      o.push(
        <td key={m + 'k'} title="KH update = SL update × đơn giá" className={`px-2 ${p} text-right tabular-nums ${base} ${bg}`}>
          {moneyTy3(kh)}
        </td>,
        <td key={m + 't'} title={tip} className={`px-2 ${p} text-right tabular-nums ${green} ${bg}`}>
          {moneyTy3(so)}
        </td>,
        <td key={m + 'p'} className={`px-2 ${p} text-right tabular-nums border-r border-slate-200 ${dark ? 'text-slate-300' : pctCls(so, kh)} ${bg}`}>
          {pctTxt(so, kh)}
        </td>,
      );
    }
    return o;
  };

  const dongCay = (ds) =>
    ds
      .filter((g) => !chiThayDoi || coDoi(g))
      .map((g) => {
        const open = mo.has(g.k);
        const coCon = g.con.length > 0;
        const d = DONG[g.cap];
        return (
          <Fragment key={g.k}>
            <tr
              data-lv={g.cap}
              className={`${d.tr} border-b ${coCon ? 'cursor-pointer' : ''}`}
              onClick={coCon ? () => bat(g.k) : undefined}
              title={coCon ? `Xem theo ${CAP[g.cap + 1].label}` : undefined}
            >
              <td
                className={`px-3 ${d.sm ? 'py-1.5' : 'py-2'} border-r border-slate-100 sticky left-0 z-10 ${d.td}`}
                style={{ paddingLeft: 12 + g.cap * 10 }}
              >
                <span className="inline-flex items-center gap-1">
                  {coCon ? (
                    open ? (
                      <ChevronDown size={d.icon} className={`${d.chev} shrink-0`} />
                    ) : (
                      <ChevronRight size={d.icon} className={`${d.chev} shrink-0`} />
                    )
                  ) : (
                    <span className="shrink-0" style={{ width: d.icon, display: 'inline-block' }} />
                  )}
                  <span className="truncate">{g.ten}</span>
                  {g.phu && <span className="ml-1 text-[10px] font-normal text-slate-400 font-mono">{g.phu}</span>}
                </span>
              </td>
              {oSo(g, d.sm, false)}
            </tr>
            {open && dongCay(g.con)}
          </Fragment>
        );
      });

  return (
    <div className="p-6 space-y-4">
      <div className="flex items-center justify-between flex-wrap gap-3">
        <div className="flex items-baseline gap-3 flex-wrap">
          <h2 className="text-lg font-bold text-slate-800">So sánh kế hoạch update giữa các kỳ</h2>
          {kyA && (
            <span className="text-[12px] text-slate-500 tabular-nums">
              {tenA}: {moneyTy3(tong.dtA)} · {tenB}: {moneyTy3(tong.dtB)} · chênh{' '}
              <span className={chCls(tong.dtB - tong.dtA)}>
                {fmtCh(tong.dtB - tong.dtA)} ({pctChenh(tong.dtA, tong.dtB)})
              </span>
            </span>
          )}
        </div>
        <div className="flex items-center gap-2 flex-wrap">
          {isAdmin && (
            <button
              onClick={chupNgay}
              disabled={dangChup}
              className="px-3 py-1.5 text-[12px] font-semibold rounded-md bg-blue-600 text-white hover:bg-blue-700 disabled:bg-slate-200 disabled:text-slate-400"
            >
              {dangChup ? 'Đang chụp…' : `Chụp ngay (${kyLabel(thangVN())})`}
            </button>
          )}
          <button
            onClick={xuat}
            disabled={!loc.length}
            className="flex items-center gap-1 px-3 py-1.5 text-[12px] border border-slate-200 rounded-md text-slate-700 hover:bg-slate-50 disabled:text-slate-300"
          >
            <Download size={13} /> Excel
          </button>
        </div>
      </div>

      <div className="flex items-center gap-2 flex-wrap text-[13px]">
        <label className="flex items-center gap-1 text-[12px] text-slate-500">
          Kỳ gốc
          <select
            value={kyA}
            onChange={(e) => setKyA(e.target.value)}
            className="px-2 py-1.5 text-[13px] border border-slate-200 rounded-md bg-white"
          >
            {!kys.length && <option value="">Chưa có bản chụp</option>}
            {kys.map((k) => (
              <option key={k.ky} value={k.ky}>
                Chốt {kyLabel(k.ky)}
              </option>
            ))}
          </select>
        </label>
        <span className="text-slate-400">so với</span>
        <select
          value={kyB}
          onChange={(e) => setKyB(e.target.value)}
          className="px-2 py-1.5 text-[13px] border border-slate-200 rounded-md bg-white"
        >
          <option value={HIEN_TAI}>Hiện tại (chưa chốt)</option>
          {kys
            .filter((k) => k.ky !== kyA)
            .map((k) => (
              <option key={k.ky} value={k.ky}>
                Chốt {kyLabel(k.ky)}
              </option>
            ))}
        </select>
        <span className="w-px h-5 bg-slate-200 mx-1" />
        <select
          value={thang}
          onChange={(e) => setThang(e.target.value)}
          className="px-2 py-1.5 text-[13px] border border-slate-200 rounded-md bg-white"
        >
          <option value="">Cả năm</option>
          <option value="con_lai">Từ {MONTH_LABELS[MONTHS.indexOf(thangVN())] || 'tháng này'} trở đi</option>
          {thangCo.map((m) => (
            <option key={m} value={m}>
              {MONTH_LABELS[MONTHS.indexOf(m)]}
            </option>
          ))}
        </select>
        <input
          value={search}
          onChange={(e) => setSearch(e.target.value)}
          placeholder="Lọc PS, KH, nhóm SP…"
          className="px-3 py-1.5 text-[13px] border border-slate-200 rounded-md w-52 outline-none focus:border-blue-500 focus:ring-2 focus:ring-blue-100"
        />
        <label className="flex items-center gap-1 text-[12px] text-slate-600">
          <input type="checkbox" checked={chiThayDoi} onChange={(e) => setChiThayDoi(e.target.checked)} />
          Chỉ dòng có thay đổi
        </label>
        <div className="flex items-center gap-1 text-[12px] text-slate-500">
          Theo tháng
          <div className="inline-flex rounded-md border border-slate-200 overflow-hidden">
            {[
              ['an', 'Ẩn'],
              ['chenh', 'Chênh'],
              ['a', tenA],
              ['b', tenB],
            ].map(([v, t]) => (
              <button
                key={v}
                onClick={() => setCheDoThang(v)}
                disabled={(v === 'a' || v === 'b') && !kyA}
                className={`px-2 py-1 text-[11px] border-l border-slate-200 first:border-l-0 whitespace-nowrap ${
                  cheDoThang === v ? 'bg-blue-600 text-white' : 'bg-white text-slate-600 hover:bg-slate-50'
                }`}
              >
                {t}
              </button>
            ))}
          </div>
        </div>
        {isAdmin && (
          <label
            className="flex items-center gap-1 text-[12px] text-slate-600"
            title="Khi admin sửa đơn giá, bản chụp nhận giá mới để phần chênh chỉ còn thay đổi của sale. Bỏ tick để so theo số gốc lúc chụp."
          >
            <input type="checkbox" checked={loaiAdmin} onChange={(e) => setLoaiAdmin(e.target.checked)} />
            Loại điều chỉnh giá của admin
          </label>
        )}
        {isAdmin && (
          <label
            className="flex items-center gap-1 text-[12px] text-slate-600"
            title="Dòng × tháng mà cả 2 bên đều lấy thực hiện thì cùng nhận thực hiện mới nhất, nên đồng bộ thực hiện lại không sinh chênh. Bản ghi vẫn giữ KH update như lúc chụp. Bỏ tick để xem số thô."
          >
            <input type="checkbox" checked={loaiThucHien} onChange={(e) => setLoaiThucHien(e.target.checked)} />
            Loại chênh do đồng bộ thực hiện
          </label>
        )}
        <span className="w-px h-5 bg-slate-200 mx-1" />
        <span className="text-[12px] text-slate-500">Mở:</span>
        {NUT_MO.map((t, i) => (
          <button
            key={t}
            onClick={() => (i === 0 ? setMo(new Set()) : moHet(i))}
            className="px-2 py-1 text-[11px] border border-slate-200 rounded text-slate-600 hover:bg-slate-100"
          >
            {t}
          </button>
        ))}
      </div>

      <div className="text-[12px] text-slate-500 max-w-4xl space-y-0.5">
        <div>Bản ghi tự động lúc 23:59 ngày hạn chót sale điền KH mỗi tháng.</div>
        {infoA && <div>{dongChot(infoA)}</div>}
        {infoB && <div>{dongChot(infoB)}</div>}
      </div>

      {loi && (
        <div className="text-[12px] text-red-600 flex items-center gap-1.5">
          <AlertCircle size={13} /> {loi}
        </div>
      )}
      {baoXong && <div className="text-[12px] text-emerald-700">{baoXong}</div>}

      <div className="bg-white rounded-lg border border-slate-200 overflow-hidden">
        <div ref={boxRef} className="overflow-auto summary-scroll">
          <table className="w-full border-collapse sticky-head">
            <thead>
              <tr className="bg-slate-100">
                <th
                  rowSpan={2}
                  className={`px-4 py-2 text-left text-[11px] ${TH_NHOM} border-r text-slate-600 align-bottom sticky left-0 z-[11] bg-slate-100`}
                  style={{ minWidth: 240 }}
                >
                  BU / Miền / PS / Khách hàng / Nhóm SP
                </th>
                <th
                  colSpan={4}
                  className="px-3 py-1.5 text-center text-[11px] font-bold uppercase tracking-wide text-emerald-800 border-r border-b border-slate-200 bg-emerald-50/60"
                >
                  Cả năm
                </th>
                {theoThang &&
                  thangCot.map((m) => (
                    <th
                      key={m}
                      colSpan={tach(m) ? 3 : undefined}
                      rowSpan={tach(m) ? undefined : 2}
                      title={
                        m < mocMau
                          ? 'Tháng trước tháng hiện tại lúc chụp: DThu lấy theo thực hiện'
                          : m === mocMau
                            ? 'Tháng hiện tại lúc chụp'
                            : undefined
                      }
                      className={`px-2 py-1.5 text-[10px] ${TH_NHOM} border-r align-bottom ${tach(m) ? 'text-center' : 'text-right'} ${mauTH(m)}`}
                    >
                      {MONTH_LABELS[MONTHS.indexOf(m)]}
                    </th>
                  ))}
              </tr>
              <tr className="bg-slate-100">
                <th className={`${TH_CON} text-slate-500 bg-emerald-50/40`}>{tenA}</th>
                <th className={`${TH_CON} text-blue-600 bg-emerald-50/40`}>{tenB}</th>
                <th className={`${TH_CON} text-emerald-700 bg-emerald-50/40`}>Chênh</th>
                <th className={`${TH_CON} text-slate-500 border-r bg-emerald-50/40`}>%</th>
                {theoThang &&
                  thangCot.filter(tach).map((m) => (
                    <Fragment key={m}>
                      <th className={`${TH_CON} text-slate-500`} title="KH update = SL update (trống thì SL đầu năm) × đơn giá">
                        KH upd
                      </th>
                      <th className={`${TH_CON} text-green-600`} title="DThu thực hiện">
                        TH
                      </th>
                      <th className={`${TH_CON} text-slate-500 border-r`} title="TH / KH update">
                        %
                      </th>
                    </Fragment>
                  ))}
              </tr>
            </thead>
            <tbody>
              {!kys.length && !loi ? (
                <tr>
                  <td colSpan={soCot} className="px-4 py-8 text-center text-[13px] text-slate-500">
                    Chưa có bản chụp nào.{' '}
                    {isAdmin ? 'Bấm “Chụp ngay” để chụp kế hoạch update hiện tại, hoặc chờ' : 'Chờ'} bản chụp tự
                    động ngày hạn chót.
                  </td>
                </tr>
              ) : dangTai ? (
                <tr>
                  <td colSpan={soCot} className="px-3 py-6 text-center text-[12px] text-slate-400">
                    <Loader2 size={14} className="inline animate-spin mr-1" /> Đang tải…
                  </td>
                </tr>
              ) : cay.filter((g) => !chiThayDoi || coDoi(g)).length === 0 ? (
                <tr>
                  <td colSpan={soCot} className="px-3 py-6 text-center text-[12px] text-slate-400">
                    Không có thay đổi theo bộ lọc hiện tại
                  </td>
                </tr>
              ) : (
                <>
                  {dongCay(cay)}
                  <tr className="bg-slate-800 text-white font-semibold">
                    <td className="px-3 py-2.5 text-[12.5px] border-t-2 border-slate-900 sticky left-0 z-10 bg-slate-800">
                      TỔNG CỘNG
                    </td>
                    {oSo(tong, false, true)}
                  </tr>
                </>
              )}
            </tbody>
          </table>
        </div>
      </div>
      <p className="text-[11px] text-slate-400 -mt-2">
        Đơn vị: tỷ / triệu VNĐ. Cả năm = DThu KH update (tháng đã qua lấy thực hiện). Chênh = {tenB} − {tenA}.
        {theoThang && cheDoThang !== 'chenh' && ' Tháng đã qua: KH upd = SL update × đơn giá, TH = thực hiện, % = TH / KH upd.'}
      </p>

      {kys.length > 0 && (
        <div className="text-[11px] text-slate-500">
          <div className="font-semibold text-slate-600 mb-1">Các bản chụp</div>
          <div className="flex flex-wrap gap-2">
            {kys.map((k) => (
              <span key={k.ky} className="inline-flex items-center gap-1.5 px-2 py-1 border border-slate-200 rounded bg-white">
                <span className="text-slate-700 font-medium">{kyLabel(k.ky)}</span>
                <span className="tabular-nums">{Number(k.so_dong || 0).toLocaleString('vi-VN')} dòng</span>
                <span className="text-slate-400">
                  {fmtLuc(k.chot_luc)} · {k.nguon === 'tu_dong' ? 'tự động' : 'tay'}
                </span>
                {isAdmin && (
                  <button
                    onClick={() => xoaKy(k.ky)}
                    className="text-slate-300 hover:text-red-600"
                    title="Xoá bản chụp"
                  >
                    <Trash2 size={12} />
                  </button>
                )}
              </span>
            ))}
          </div>
        </div>
      )}
    </div>
  );
}
