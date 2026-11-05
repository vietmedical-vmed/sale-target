import React, { useState, useMemo, Fragment } from 'react';
import { ChevronDown, ChevronRight, AlertCircle } from './icons.jsx';
import { MONTHS, MONTH_LABELS } from '../config/constants.js';
import { deaccent } from '../lib/text.js';
import { fmtInt, parseNum } from '../lib/format.js';

const khoa = (r) =>
  [r.fy, r.ps, r.custId, r.grp, r.mset, r.prod, Number(r.price) || 0].join('||');

const spKey = (g) => `${g.grp || ''}||${g.mset || ''}||${g.prod || ''}`;

const fmtTr = (v) =>
  (v / 1e6).toLocaleString('vi-VN', { maximumFractionDigits: 1 });

// Đơn giá kế hoạch (sale_target.don_gia) so với đơn giá bình quân hoá đơn
// (Σ doanh thu thực hiện / Σ SL thực hiện) theo từng dòng KH × SP × PS × mức giá.
export function SoSanhGiaView({ rows, priceOf, onUpdatePrice }) {
  const [search, setSearch] = useState('');
  const [chieu, setChieu] = useState('');
  const [nguong, setNguong] = useState('1');
  const [mo, setMo] = useState(null);
  const [nhap, setNhap] = useState({});
  const [dangLuu, setDangLuu] = useState(null);
  const [loi, setLoi] = useState('');
  const [baoXong, setBaoXong] = useState('');

  const nhom = useMemo(() => {
    const m = new Map();
    for (const r of rows) {
      if (r.oop || r._oop) continue;
      const k = khoa(r);
      let g = m.get(k);
      if (!g) {
        g = {
          k,
          fy: r.fy,
          ps: r.ps,
          custId: r.custId,
          cust: r.cust,
          grp: r.grp,
          mset: r.mset,
          prod: r.prod,
          price: Number(r.price) || 0,
          ids: [],
          sl: 0,
          dt: 0,
          thang: new Map(),
        };
        m.set(k, g);
      }
      g.ids.push(r._row);
      const sl = Number(r.act) || 0;
      const dt = Number(r.dtAct) || 0;
      if (!sl && !dt) continue;
      g.sl += sl;
      g.dt += dt;
      const t = g.thang.get(r.mo) || { sl: 0, dt: 0 };
      t.sl += sl;
      t.dt += dt;
      g.thang.set(r.mo, t);
    }
    const out = [];
    for (const g of m.values()) {
      if (!g.sl || !g.price) continue;
      const giaHd = g.dt / g.sl;
      const chenh = giaHd - g.price;
      const giaDm =
        priceOf && priceOf.tuDanhMuc(g.grp, g.mset, g.prod)
          ? priceOf(g.grp, g.mset, g.prod)
          : null;
      out.push({
        ...g,
        giaHd,
        chenh,
        pct: (chenh / g.price) * 100,
        chenhDt: g.dt - g.sl * g.price,
        giaDm,
      });
    }
    return out;
  }, [rows, priceOf]);

  const list = useMemo(() => {
    const q = deaccent(search.trim());
    const n = Math.max(0, Number(nguong) || 0);
    const loc = nhom
      .filter((g) => Math.abs(g.pct) >= n && Math.abs(g.chenh) >= 1)
      .filter((g) => (chieu === 'up' ? g.chenh > 0 : chieu === 'down' ? g.chenh < 0 : true))
      .filter(
        (g) =>
          !q ||
          [g.prod, g.mset, g.grp, g.cust, g.custId, g.ps].some((v) =>
            deaccent(v || '').includes(q),
          ),
      );
    // Cùng sản phẩm đứng liền nhau; sản phẩm xếp theo dòng lệch lớn nhất của nó.
    const lonNhat = new Map();
    for (const g of loc) {
      const k = spKey(g);
      lonNhat.set(k, Math.max(lonNhat.get(k) || 0, Math.abs(g.chenhDt)));
    }
    return loc.sort(
      (a, b) =>
        lonNhat.get(spKey(b)) - lonNhat.get(spKey(a)) ||
        spKey(a).localeCompare(spKey(b)) ||
        Math.abs(b.chenhDt) - Math.abs(a.chenhDt),
    );
  }, [nhom, search, chieu, nguong]);

  const tong = useMemo(() => {
    let up = 0,
      down = 0,
      dt = 0;
    for (const g of list) {
      if (g.chenh > 0) up++;
      else down++;
      dt += g.chenhDt;
    }
    return { up, down, dt };
  }, [list]);

  const luu = async (g) => {
    const gia = parseNum(nhap[g.k]);
    if (!(gia > 0) || gia === g.price) return;
    if (
      !confirm(
        `Đổi đơn giá kế hoạch "${g.prod}" · ${g.custId} · ${g.ps}\n` +
          `${fmtInt(g.price)} → ${fmtInt(gia)} trên ${g.ids.length} dòng (mọi tháng).\n` +
          'Target đầu năm tính lại theo giá mới, quota thầu chuyển theo giá mới.',
      )
    )
      return;
    setLoi('');
    setBaoXong('');
    setDangLuu(g.k);
    try {
      await onUpdatePrice(g.ids, gia);
      setNhap((p) => {
        const c = { ...p };
        delete c[g.k];
        return c;
      });
      setBaoXong(`Đã đổi đơn giá "${g.prod}" · ${g.custId}: ${fmtInt(g.price)} → ${fmtInt(gia)}.`);
    } catch (e) {
      setLoi(`${g.prod} · ${g.custId}: ${e.message}`);
    }
    setDangLuu(null);
  };

  const dien = (g, v) => setNhap((p) => ({ ...p, [g.k]: String(Math.round(v)) }));

  return (
    <div className="p-6 space-y-4">
      <div className="flex items-center justify-between flex-wrap gap-3">
        <div className="flex items-baseline gap-3 flex-wrap">
          <h2 className="text-lg font-bold text-slate-800">So sánh đơn giá kế hoạch và hoá đơn</h2>
          <span className="text-[12px] text-slate-500 tabular-nums">
            {list.length} dòng ·{' '}
            <span className="text-emerald-700">{tong.up} HĐ cao hơn</span> ·{' '}
            <span className="text-red-600">{tong.down} HĐ thấp hơn</span> · chênh doanh thu{' '}
            <span className={tong.dt > 0 ? 'text-emerald-700' : tong.dt < 0 ? 'text-red-600' : ''}>
              {tong.dt > 0 ? '+' : ''}
              {fmtTr(tong.dt)} tr
            </span>
          </span>
        </div>
        <div className="flex items-center gap-2 flex-wrap">
          <input
            value={search}
            onChange={(e) => setSearch(e.target.value)}
            placeholder="Lọc SP, KH, PS, nhóm…"
            className="px-3 py-1.5 text-[13px] border border-slate-200 rounded-md w-56 outline-none focus:border-blue-500 focus:ring-2 focus:ring-blue-100"
          />
          <select
            value={chieu}
            onChange={(e) => setChieu(e.target.value)}
            className="px-2 py-1.5 text-[13px] border border-slate-200 rounded-md bg-white"
          >
            <option value="">Cả hai chiều</option>
            <option value="up">HĐ cao hơn KH</option>
            <option value="down">HĐ thấp hơn KH</option>
          </select>
          <label className="flex items-center gap-1 text-[12px] text-slate-500">
            Lệch từ
            <input
              value={nguong}
              onChange={(e) => setNguong(e.target.value.replace(/[^\d.]/g, ''))}
              className="w-12 px-2 py-1.5 text-[13px] border border-slate-200 rounded-md text-right tabular-nums"
            />
            %
          </label>
        </div>
      </div>
      <p className="text-[12px] text-slate-500 max-w-4xl">
        Giá HĐ = Σ doanh thu thực hiện / Σ SL thực hiện của dòng kế hoạch (mọi tháng có thực hiện). Giá DM =
        đơn giá thầu mới trong danh mục vật tư. Đổi giá áp cho mọi tháng của dòng KH × SP × PS ở mức giá đó;
        doanh thu thực hiện giữ nguyên số hoá đơn.
      </p>
      {loi && (
        <div className="text-[12px] text-red-600 flex items-center gap-1.5">
          <AlertCircle size={13} /> {loi}
        </div>
      )}
      {baoXong && <div className="text-[12px] text-emerald-700">{baoXong}</div>}
      <div className="bg-white rounded-lg border border-slate-200 overflow-x-auto">
        <table className="w-full text-[12px] tabular-nums">
          <thead>
            <tr className="bg-slate-50 border-b border-slate-200 text-slate-600">
              <th className="w-6" />
              <th className="px-3 py-2 text-left font-semibold">Sản phẩm</th>
              <th className="px-3 py-2 text-left font-semibold">Khách hàng</th>
              <th className="px-3 py-2 text-left font-semibold">PS</th>
              <th className="px-3 py-2 text-right font-semibold">Giá KH</th>
              <th className="px-3 py-2 text-right font-semibold">Giá DM</th>
              <th className="px-3 py-2 text-right font-semibold">Giá HĐ</th>
              <th className="px-3 py-2 text-right font-semibold">Lệch</th>
              <th className="px-3 py-2 text-right font-semibold">SL TH</th>
              <th className="px-3 py-2 text-right font-semibold">Chênh DT (tr)</th>
              <th className="px-3 py-2 text-left font-semibold">Đơn giá mới</th>
            </tr>
          </thead>
          <tbody>
            {list.length === 0 ? (
              <tr>
                <td colSpan={11} className="px-3 py-6 text-center text-slate-400">
                  Không có dòng nào lệch giá theo bộ lọc hiện tại
                </td>
              </tr>
            ) : (
              list.map((g, i) => {
                const open = mo === g.k;
                const dauSp = i > 0 && spKey(list[i - 1]) !== spKey(g);
                const mau = g.chenh > 0 ? 'text-emerald-700' : 'text-red-600';
                const dmLech = g.giaDm != null && Math.round(g.giaDm) !== Math.round(g.price);
                return (
                  <Fragment key={g.k}>
                    <tr
                      className={`border-b border-slate-100 hover:bg-slate-50/60 ${dauSp ? 'border-t-2 border-t-slate-300' : ''}`}
                    >
                      <td className="pl-2">
                        <button
                          onClick={() => setMo(open ? null : g.k)}
                          className="p-0.5 text-slate-400 hover:text-slate-700"
                          title="Xem theo tháng"
                        >
                          {open ? <ChevronDown size={14} /> : <ChevronRight size={14} />}
                        </button>
                      </td>
                      <td className="px-3 py-1.5">
                        <div className="text-slate-800">{g.prod}</div>
                        <div className="text-[10px] text-slate-400">
                          {g.grp}
                          {g.mset && g.mset !== g.prod ? ` · ${g.mset}` : ''}
                        </div>
                      </td>
                      <td className="px-3 py-1.5">
                        <div className="text-slate-800">{g.cust}</div>
                        <div className="text-[10px] text-slate-400">{g.custId}</div>
                      </td>
                      <td className="px-3 py-1.5 text-slate-600 whitespace-nowrap">{g.ps}</td>
                      <td className="px-3 py-1.5 text-right text-slate-800">{fmtInt(g.price)}</td>
                      <td
                        className={`px-3 py-1.5 text-right ${dmLech ? 'text-amber-700 font-medium' : 'text-slate-500'}`}
                        title={dmLech ? 'Giá kế hoạch khác giá danh mục' : undefined}
                      >
                        {g.giaDm != null ? fmtInt(g.giaDm) : '—'}
                      </td>
                      <td className={`px-3 py-1.5 text-right ${mau}`}>{fmtInt(g.giaHd)}</td>
                      <td className={`px-3 py-1.5 text-right whitespace-nowrap ${mau}`}>
                        {g.pct > 0 ? '+' : ''}
                        {g.pct.toLocaleString('vi-VN', { maximumFractionDigits: 1 })}%
                      </td>
                      <td className="px-3 py-1.5 text-right text-slate-700">{fmtInt(g.sl)}</td>
                      <td className={`px-3 py-1.5 text-right ${mau}`}>
                        {g.chenhDt > 0 ? '+' : ''}
                        {fmtTr(g.chenhDt)}
                      </td>
                      <td className="px-3 py-1.5">
                        <div className="flex items-center gap-1 whitespace-nowrap">
                          <input
                            id={`gia-moi-${g.k}`}
                            value={nhap[g.k] ?? ''}
                            onChange={(e) => setNhap((p) => ({ ...p, [g.k]: e.target.value }))}
                            onKeyDown={(e) => e.key === 'Enter' && luu(g)}
                            placeholder={fmtInt(g.price)}
                            className="w-28 px-2 py-1 text-[12px] border border-slate-200 rounded text-right outline-none focus:border-blue-500"
                          />
                          <button
                            onClick={() => dien(g, g.giaHd)}
                            className="px-1.5 py-1 text-[11px] border border-slate-200 rounded text-slate-600 hover:bg-slate-100"
                            title="Điền giá hoá đơn bình quân"
                          >
                            HĐ
                          </button>
                          {g.giaDm != null && (
                            <button
                              onClick={() => dien(g, g.giaDm)}
                              className="px-1.5 py-1 text-[11px] border border-slate-200 rounded text-slate-600 hover:bg-slate-100"
                              title="Điền giá danh mục"
                            >
                              DM
                            </button>
                          )}
                          <button
                            onClick={() => luu(g)}
                            disabled={
                              dangLuu === g.k ||
                              !(parseNum(nhap[g.k]) > 0) ||
                              parseNum(nhap[g.k]) === g.price
                            }
                            className="px-2 py-1 text-[11px] font-semibold rounded bg-blue-600 text-white hover:bg-blue-700 disabled:bg-slate-200 disabled:text-slate-400"
                          >
                            {dangLuu === g.k ? 'Đang lưu…' : 'Lưu'}
                          </button>
                        </div>
                      </td>
                    </tr>
                    {open && (
                      <tr className="border-b border-slate-100 bg-slate-50/60">
                        <td />
                        <td colSpan={10} className="px-3 py-2">
                          <div className="flex flex-wrap gap-x-5 gap-y-1 text-[11px] text-slate-600">
                            {MONTHS.filter((m) => g.thang.has(m)).map((m) => {
                              const t = g.thang.get(m);
                              const gia = t.sl ? t.dt / t.sl : null;
                              const lech = gia != null && Math.round(gia) !== Math.round(g.price);
                              return (
                                <span key={m}>
                                  <span className="text-slate-400">{MONTH_LABELS[MONTHS.indexOf(m)]}:</span>{' '}
                                  {fmtInt(t.sl)} × <span className={lech ? 'font-semibold text-slate-800' : ''}>{gia != null ? fmtInt(gia) : '—'}</span>
                                  {' '}= {fmtTr(t.dt)} tr
                                </span>
                              );
                            })}
                          </div>
                        </td>
                      </tr>
                    )}
                  </Fragment>
                );
              })
            )}
          </tbody>
        </table>
      </div>
    </div>
  );
}
