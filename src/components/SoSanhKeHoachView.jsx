import React, { useState, useEffect, useMemo, useCallback, Fragment } from 'react';
import { ChevronDown, ChevronRight, AlertCircle, Download, Loader2, Trash2 } from './icons.jsx';
import { MONTHS, MONTH_LABELS, TEAMS } from '../config/constants.js';
import { deaccent } from '../lib/text.js';
import { exportSoSanhKeHoach } from '../lib/excel.js';
import { api } from '../api/client.js';

// Dòng từ RPC so_sanh_chot_ke_hoach (mảng gọn, chi tiết PS × KH × nhóm SP × tháng):
// [fy, thang, bu, mien, ps, maKh, tenKh, nhom, dtA, dtB]
const toRow = (a) => ({
  fy: a[0], mo: a[1], bu: a[2], region: a[3], ps: a[4], custId: a[5], cust: a[6], grp: a[7],
  dtA: Number(a[8]) || 0, dtB: Number(a[9]) || 0,
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

const fmtTr = (v) => (v / 1e6).toLocaleString('vi-VN', { maximumFractionDigits: 1 });
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
    const t = g.thang.get(r.mo) || { dtA: 0, dtB: 0 };
    t.dtA += r.dtA;
    t.dtB += r.dtB;
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

const Chenh = ({ v, className = '' }) => (
  <span className={`${v > 0 ? 'text-emerald-700' : v < 0 ? 'text-red-600' : 'text-slate-300'} ${className}`}>
    {Math.round(v / 1e5) === 0 ? '·' : (v > 0 ? '+' : '') + fmtTr(v)}
  </span>
);

const Pct = ({ a, b }) => {
  if (!a) return <span className="text-slate-400">{b ? 'mới' : '—'}</span>;
  const p = ((b - a) / Math.abs(a)) * 100;
  return (
    <span className={p > 0 ? 'text-emerald-700' : p < 0 ? 'text-red-600' : 'text-slate-400'}>
      {p > 0 ? '+' : ''}
      {p.toLocaleString('vi-VN', { maximumFractionDigits: 1 })}%
    </span>
  );
};

const NEN_CAP = ['bg-slate-100/70', 'bg-slate-50', '', 'bg-slate-50/40', 'bg-slate-50/70'];
const CHU_CAP = [
  'text-[12px] font-bold text-slate-900',
  'text-[12px] font-semibold text-slate-800',
  'text-[12px] font-medium text-slate-800',
  'text-[12px] text-slate-700',
  'text-[11px] text-slate-600',
];

// So sánh DThu KH update giữa 2 bản chụp hằng tháng (hoặc bản chụp với dữ liệu hiện tại),
// chi tiết PS → khách hàng → nhóm sản phẩm. Bản chụp tự động lúc 23:59 ngày hạn chót
// sale điền (deadline_day); admin chụp tay được.
export function SoSanhKeHoachView({ viewBu, isAdmin = false }) {
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
  const [theoThang, setTheoThang] = useState(true);
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
    let a = 0,
      b = 0;
    for (const r of loc) {
      a += r.dtA;
      b += r.dtB;
    }
    return { a, b };
  }, [loc]);

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
  const soCot = 5 + (theoThang ? thangCot.length : 0);

  const xuat = () =>
    exportSoSanhKeHoach(
      loc.filter((r) => !chiThayDoi || coDoi(r)),
      tenA,
      tenB,
    );

  const dongCay = (ds) =>
    ds
      .filter((g) => !chiThayDoi || coDoi(g))
      .map((g) => {
        const open = mo.has(g.k);
        const coCon = g.con.length > 0;
        return (
          <Fragment key={g.k}>
            <tr className={`border-b border-slate-100 hover:bg-blue-50/40 ${NEN_CAP[g.cap]}`}>
              <td className="px-3 py-1.5" style={{ paddingLeft: 8 + g.cap * 20 }}>
                <div className="flex items-start gap-1">
                  {coCon ? (
                    <button
                      onClick={() => bat(g.k)}
                      className="p-0.5 text-slate-400 hover:text-slate-700 shrink-0"
                      title={`Xem theo ${CAP[g.cap + 1].label}`}
                    >
                      {open ? <ChevronDown size={14} /> : <ChevronRight size={14} />}
                    </button>
                  ) : (
                    <span className="w-[18px] shrink-0" />
                  )}
                  <div className={CHU_CAP[g.cap]}>
                    {g.ten}
                    {g.phu && <span className="ml-1.5 text-[10px] text-slate-400">{g.phu}</span>}
                  </div>
                </div>
              </td>
              <td className="px-3 py-1.5 text-right text-slate-600">{fmtTr(g.dtA)}</td>
              <td className="px-3 py-1.5 text-right text-slate-800">{fmtTr(g.dtB)}</td>
              <td className="px-3 py-1.5 text-right font-medium">
                <Chenh v={g.chenh} />
              </td>
              <td className="px-3 py-1.5 text-right">
                <Pct a={g.dtA} b={g.dtB} />
              </td>
              {theoThang &&
                thangCot.map((m) => {
                  const t = g.thang.get(m);
                  return (
                    <td
                      key={m}
                      className="px-2 py-1.5 text-right text-[11px] border-l border-slate-100"
                      title={t ? `${fmtTr(t.dtA)} → ${fmtTr(t.dtB)} tr` : undefined}
                    >
                      {t ? <Chenh v={t.dtB - t.dtA} /> : <span className="text-slate-200">·</span>}
                    </td>
                  );
                })}
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
              {tenA}: {fmtTr(tong.a)} tr · {tenB}: {fmtTr(tong.b)} tr · chênh{' '}
              <Chenh v={tong.b - tong.a} /> tr (<Pct a={tong.a} b={tong.b} />)
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
        <label className="flex items-center gap-1 text-[12px] text-slate-600">
          <input type="checkbox" checked={theoThang} onChange={(e) => setTheoThang(e.target.checked)} />
          Chênh theo tháng
        </label>
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

      {!kys.length && !loi ? (
        <div className="bg-white rounded-lg border border-slate-200 px-4 py-8 text-center text-[13px] text-slate-500">
          Chưa có bản chụp nào.{' '}
          {isAdmin ? 'Bấm “Chụp ngay” để chụp kế hoạch update hiện tại, hoặc chờ' : 'Chờ'} bản chụp tự động
          ngày hạn chót.
        </div>
      ) : (
        <div className="bg-white rounded-lg border border-slate-200 overflow-x-auto">
          <table className="w-full text-[12px] tabular-nums">
            <thead>
              <tr className="bg-slate-50 border-b border-slate-200 text-slate-600">
                <th className="px-3 py-2 text-left font-semibold">BU / Miền / PS / Khách hàng / Nhóm SP</th>
                <th className="px-3 py-2 text-right font-semibold whitespace-nowrap">{tenA} (tr)</th>
                <th className="px-3 py-2 text-right font-semibold whitespace-nowrap">{tenB} (tr)</th>
                <th className="px-3 py-2 text-right font-semibold whitespace-nowrap">Chênh (tr)</th>
                <th className="px-3 py-2 text-right font-semibold">%</th>
                {theoThang &&
                  thangCot.map((m) => (
                    <th key={m} className="px-2 py-2 text-right font-semibold border-l border-slate-200">
                      {MONTH_LABELS[MONTHS.indexOf(m)]}
                    </th>
                  ))}
              </tr>
            </thead>
            <tbody>
              {dangTai ? (
                <tr>
                  <td colSpan={soCot} className="px-3 py-6 text-center text-slate-400">
                    <Loader2 size={14} className="inline animate-spin mr-1" /> Đang tải…
                  </td>
                </tr>
              ) : cay.filter((g) => !chiThayDoi || coDoi(g)).length === 0 ? (
                <tr>
                  <td colSpan={soCot} className="px-3 py-6 text-center text-slate-400">
                    Không có thay đổi theo bộ lọc hiện tại
                  </td>
                </tr>
              ) : (
                dongCay(cay)
              )}
            </tbody>
          </table>
        </div>
      )}

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
