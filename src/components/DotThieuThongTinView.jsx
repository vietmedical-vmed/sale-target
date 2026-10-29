import { useState, useMemo, useContext } from 'react';
import { Clock } from './icons.jsx';
import { CURRENT_MONTH } from '../config/constants.js';
import { QuotaThauCtx, DotEditor, dotDuThongTin } from './QuotaThau.jsx';
import { deaccent, custLabel } from '../lib/text.js';
import { fmtInt } from '../lib/format.js';

const LOAI = { cu: 'Thầu cũ', chinh: 'Thầu chính', bo_sung: 'Thầu bổ sung' };
const khoaDot = (x) => [x.fy, x.ps, x.custId, x.grp, x.loai, x.dot].join('|');

// Đợt chính thức còn thiếu tháng thầu / hiệu lực (dữ liệu cũ). Quota mới không nhập
// được vào các đợt này cho tới khi điền đủ; điền ngay tại đây.
export function DotThieuThongTinView({ customers = [] }) {
  const ctx = useContext(QuotaThauCtx);
  const [loi, setLoi] = useState('');
  const [search, setSearch] = useState('');
  const tenKh = useMemo(
    () => new Map(customers.map((c) => [String(c.custId), custLabel(c.custId, c.cust)])),
    [customers],
  );
  // Giá trị thầu của đợt = Σ SL quota × đơn giá các sản phẩm trong đợt.
  const giaTri = useMemo(() => {
    const m = new Map();
    if (!ctx) return m;
    for (const qs of ctx.quotasByProduct.values())
      for (const q of qs) {
        const k = khoaDot(q);
        m.set(k, (m.get(k) || 0) + Number(q.qty || 0) * Number(q.price || 0));
      }
    return m;
  }, [ctx]);
  const list = useMemo(() => {
    if (!ctx) return [];
    const out = [];
    for (const ds of ctx.dotsByGroup.values())
      for (const d of ds) if (!dotDuThongTin(d)) out.push(d);
    const q = deaccent(search.trim());
    return out
      .filter((d) => !q || [d.ps, d.custId, tenKh.get(String(d.custId)), d.grp].some((v) => deaccent(v || '').includes(q)))
      .sort((a, b) => (a.ps + a.custId + a.grp + a.loai + a.dot).localeCompare(b.ps + b.custId + b.grp + b.loai + b.dot));
  }, [ctx, search, tenKh]);
  if (!ctx) return null;
  const luu = async (d, thang, thoiGian) => {
    setLoi('');
    try {
      await ctx.saveDot([{ fy: d.fy, ps: d.ps, custId: d.custId, grp: d.grp, loai: d.loai, dot: d.dot, thang, thoiGian }]);
    } catch (e) {
      setLoi(`${d.ps} · ${d.custId} · ${d.grp}: ${e.message}`);
    }
  };
  return (
    <div className="p-6 space-y-4">
      <div className="flex items-center justify-between flex-wrap gap-3">
        <div className="flex items-center gap-3">
          <Clock size={20} className="text-emerald-600" />
          <h2 className="text-lg font-bold text-slate-800">Đợt thiếu tháng thầu / hiệu lực</h2>
          <span className="text-[12px] text-slate-400">
            {list.length} đợt · {(list.reduce((s, d) => s + (giaTri.get(khoaDot(d)) || 0), 0) / 1e9).toLocaleString('vi-VN', { maximumFractionDigits: 2 })} tỷ
          </span>
        </div>
        <input
          value={search}
          onChange={(e) => setSearch(e.target.value)}
          placeholder="Lọc PS, KH, nhóm…"
          className="px-3 py-1.5 text-[13px] border border-slate-200 rounded-md w-56 outline-none focus:border-emerald-500 focus:ring-2 focus:ring-emerald-100"
        />
      </div>
      <p className="text-[12px] text-slate-500 max-w-4xl">
        Quota của các đợt này đang tính Upcoming và không nhập thêm được. Điền tháng thầu (yyyy-mm) và hiệu lực (số tháng) — lưu khi đủ cả hai.
      </p>
      {loi && <div className="text-[12px] text-red-600">{loi}</div>}
      <div className="bg-white rounded-lg border border-slate-200 overflow-x-auto">
        <table className="w-full text-[12px]">
          <thead>
            <tr className="bg-slate-50 border-b border-slate-200">
              <th className="px-3 py-2 text-left font-semibold text-slate-600">PS</th>
              <th className="px-3 py-2 text-left font-semibold text-slate-600">Khách hàng</th>
              <th className="px-3 py-2 text-left font-semibold text-slate-600">Nhóm SP</th>
              <th className="px-3 py-2 text-left font-semibold text-slate-600">Loại</th>
              <th className="px-3 py-2 text-left font-semibold text-slate-600">Tháng thầu · hiệu lực</th>
              <th className="px-3 py-2 text-right font-semibold text-slate-600">Giá trị thầu</th>
            </tr>
          </thead>
          <tbody>
            {list.length === 0 ? (
              <tr><td colSpan={6}className="px-3 py-6 text-center text-slate-400">Mọi đợt đã đủ tháng thầu và hiệu lực</td></tr>
            ) : (
              list.map((d) => (
                <tr key={khoaDot(d)} className="border-b border-slate-100">
                  <td className="px-3 py-1.5 text-slate-700 whitespace-nowrap">{d.ps}</td>
                  <td className="px-3 py-1.5">
                    <div className="text-slate-800">{tenKh.get(String(d.custId)) || d.custId}</div>
                    <div className="text-[10px] text-slate-400">{d.custId}</div>
                  </td>
                  <td className="px-3 py-1.5 text-slate-600">{d.grp}</td>
                  <td className="px-3 py-1.5 text-slate-600 whitespace-nowrap">{LOAI[d.loai] || d.loai} · đợt {d.dot}</td>
                  <td className="px-3 py-1.5">
                    <DotEditor
                      thang={d.thang}
                      thoiGian={d.thoiGian}
                      curMonth={CURRENT_MONTH}
                      onSave={(thang, thoiGian) => luu(d, thang, thoiGian)}
                    />
                  </td>
                  <td className="px-3 py-1.5 text-right tabular-nums text-slate-700">{fmtInt(giaTri.get(khoaDot(d)) || 0)}</td>
                </tr>
              ))
            )}
          </tbody>
        </table>
      </div>
    </div>
  );
}
