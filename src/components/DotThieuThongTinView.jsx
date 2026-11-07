import { useState, useMemo, useContext } from 'react';
import { Clock } from './icons.jsx';
import { CURRENT_MONTH, NO_MSET } from '../config/constants.js';
import { QuotaThauCtx, DotEditor, dotDuThongTin, QuotaThauModal } from './QuotaThau.jsx';
import { sanPhamAmQuota } from '../lib/quota.js';
import { deaccent, custLabel } from '../lib/text.js';
import { fmtInt } from '../lib/format.js';

const LOAI = { cu: 'Thầu cũ', chinh: 'Thầu chính', bo_sung: 'Thầu bổ sung' };
const khoaDot = (x) => [x.fy, x.ps, x.custId, x.grp, x.loai, x.dot].join('|');
const ty = (v) => (v / 1e9).toLocaleString('vi-VN', { maximumFractionDigits: 2 });

// Tab "Kiểm tra thông tin thầu":
//  1. Đợt chính thức còn thiếu tháng thầu / hiệu lực (dữ liệu cũ). Quota mới không nhập
//     được vào các đợt này cho tới khi điền đủ; điền ngay tại đây.
//  2. Sản phẩm trên Chi tiết kế hoạch có quota khả dụng âm → quota chưa điền / điền sai.
export function DotThieuThongTinView({ customers = [], rows = [], canEdit = false }) {
  const ctx = useContext(QuotaThauCtx);
  const [loi, setLoi] = useState('');
  const [search, setSearch] = useState('');
  const [suaQuota, setSuaQuota] = useState(null); // dòng SP đang mở popup quota
  const tenKh = useMemo(
    () => new Map(customers.map((c) => [String(c.custId), custLabel(c.custId, c.cust)])),
    [customers],
  );
  const q = deaccent(search.trim());
  // Giá trị thầu của đợt = Σ SL quota × đơn giá các sản phẩm trong đợt.
  const giaTri = useMemo(() => {
    const m = new Map();
    if (!ctx) return m;
    for (const qs of ctx.quotasByProduct.values())
      for (const x of qs) {
        const k = khoaDot(x);
        m.set(k, (m.get(k) || 0) + Number(x.qty || 0) * Number(x.price || 0));
      }
    return m;
  }, [ctx]);
  const list = useMemo(() => {
    if (!ctx) return [];
    const out = [];
    for (const ds of ctx.dotsByGroup.values())
      for (const d of ds) if (!dotDuThongTin(d)) out.push(d);
    return out
      .filter((d) => !q || [d.ps, d.custId, tenKh.get(String(d.custId)), d.grp].some((v) => deaccent(v || '').includes(q)))
      .sort((a, b) => (a.ps + a.custId + a.grp + a.loai + a.dot).localeCompare(b.ps + b.custId + b.grp + b.loai + b.dot));
  }, [ctx, q, tenKh]);
  const spAm = useMemo(
    () => (ctx ? sanPhamAmQuota(rows, ctx.dotsByGroup, ctx.quotasByProduct, CURRENT_MONTH) : []),
    [ctx, rows],
  );
  const spList = useMemo(
    () =>
      spAm
        .filter(
          (s) =>
            !q ||
            [s.ps, s.custId, s.cust, s.grp, s.prod, s.mset === NO_MSET ? '' : s.mset].some((v) =>
              deaccent(v || '').includes(q),
            ),
        )
        .sort(
          (a, b) =>
            a.ps.localeCompare(b.ps) ||
            (a.cust || '').localeCompare(b.cust || '', 'vi') ||
            a.grp.localeCompare(b.grp) ||
            a.prod.localeCompare(b.prod) ||
            a.price - b.price,
        ),
    [spAm, q],
  );
  if (!ctx) return null;
  const luu = async (d, thang, thoiGian) => {
    setLoi('');
    try {
      await ctx.saveDot([{ fy: d.fy, ps: d.ps, custId: d.custId, grp: d.grp, loai: d.loai, dot: d.dot, thang, thoiGian }]);
    } catch (e) {
      setLoi(`${d.ps} · ${d.custId} · ${d.grp}: ${e.message}`);
    }
  };
  const th = 'px-3 py-2 font-semibold text-slate-600';
  return (
    <div className="p-6 space-y-6">
      <div className="flex items-center justify-between flex-wrap gap-3">
        <div className="flex items-center gap-3">
          <Clock size={20} className="text-emerald-600" />
          <h2 className="text-lg font-bold text-slate-800">Kiểm tra thông tin thầu</h2>
        </div>
        <input
          value={search}
          onChange={(e) => setSearch(e.target.value)}
          placeholder="Lọc PS, KH, nhóm, sản phẩm…"
          className="px-3 py-1.5 text-[13px] border border-slate-200 rounded-md w-64 outline-none focus:border-emerald-500 focus:ring-2 focus:ring-emerald-100"
        />
      </div>

      <section className="space-y-3">
        <div className="flex items-baseline gap-3 flex-wrap">
          <h3 className="text-[14px] font-bold text-slate-700">Đợt thầu thiếu tháng thầu / hiệu lực</h3>
          <span className="text-[12px] text-slate-400">
            {list.length} đợt · {ty(list.reduce((s, d) => s + (giaTri.get(khoaDot(d)) || 0), 0))} tỷ
          </span>
        </div>
        <p className="text-[12px] text-slate-500 max-w-4xl">
          Quota của các đợt này đang tính Upcoming và không nhập thêm được. Điền tháng thầu (yyyy-mm) và hiệu lực (số tháng) — lưu khi đủ cả hai.
        </p>
        {loi && <div className="text-[12px] text-red-600">{loi}</div>}
        <div className="bg-white rounded-lg border border-slate-200 overflow-x-auto">
          <table className="w-full text-[12px]">
            <thead>
              <tr className="bg-slate-50 border-b border-slate-200">
                <th className={`${th} text-left`}>PS</th>
                <th className={`${th} text-left`}>Khách hàng</th>
                <th className={`${th} text-left`}>Nhóm SP</th>
                <th className={`${th} text-left`}>Loại</th>
                <th className={`${th} text-left`}>Tháng thầu · hiệu lực</th>
                <th className={`${th} text-right`}>Giá trị thầu</th>
              </tr>
            </thead>
            <tbody>
              {list.length === 0 ? (
                <tr><td colSpan={6} className="px-3 py-6 text-center text-slate-400">Mọi đợt đã đủ tháng thầu và hiệu lực</td></tr>
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
      </section>

      <section className="space-y-3">
        <div className="flex items-baseline gap-3 flex-wrap">
          <h3 className="text-[14px] font-bold text-slate-700">Sản phẩm có quota khả dụng âm</h3>
          <span className="text-[12px] text-slate-400">
            {spList.length} sản phẩm · thiếu {ty(spList.reduce((s, x) => s + x.thieuDt, 0))} tỷ
          </span>
        </div>
        <p className="text-[12px] text-slate-500 max-w-4xl">
          Sản phẩm trên Chi tiết kế hoạch có Quota khả dụng = Quota on hand − SL TH YTD &lt; 0, tức quota thầu chưa điền hoặc điền chưa đúng
          (sai mức giá, thiếu đợt, đợt chưa tới tháng thầu). Bấm "Sửa quota" để điền lại.
        </p>
        <div className="bg-white rounded-lg border border-slate-200 overflow-x-auto">
          <table className="w-full text-[12px]">
            <thead>
              <tr className="bg-slate-50 border-b border-slate-200">
                <th className={`${th} text-left`}>PS</th>
                <th className={`${th} text-left`}>Khách hàng</th>
                <th className={`${th} text-left`}>Nhóm SP</th>
                <th className={`${th} text-left`}>Sản phẩm</th>
                <th className={`${th} text-right`}>Đơn giá</th>
                <th className={`${th} text-right`}>Quota on hand</th>
                <th className={`${th} text-right`}>SL TH YTD</th>
                <th className={`${th} text-right`}>Quota khả dụng</th>
                <th className={`${th} text-left`}>Gợi ý</th>
                <th className={th} />
              </tr>
            </thead>
            <tbody>
              {spList.length === 0 ? (
                <tr><td colSpan={10} className="px-3 py-6 text-center text-slate-400">Không có sản phẩm nào âm quota khả dụng</td></tr>
              ) : (
                spList.map((s) => (
                  <tr key={s.key} className="border-b border-slate-100">
                    <td className="px-3 py-1.5 text-slate-700 whitespace-nowrap">{s.ps}</td>
                    <td className="px-3 py-1.5">
                      <div className="text-slate-800">{tenKh.get(String(s.custId)) || s.cust}</div>
                      <div className="text-[10px] text-slate-400">{s.custId}</div>
                    </td>
                    <td className="px-3 py-1.5 text-slate-600">{s.grp}</td>
                    <td className="px-3 py-1.5">
                      <div className="text-slate-800">{s.prod}</div>
                      {s.mset !== NO_MSET && <div className="text-[10px] text-slate-400">{s.mset}</div>}
                    </td>
                    <td className="px-3 py-1.5 text-right tabular-nums text-slate-700">{fmtInt(s.price)}</td>
                    <td className="px-3 py-1.5 text-right tabular-nums text-slate-700">{fmtInt(s.onHand)}</td>
                    <td className="px-3 py-1.5 text-right tabular-nums text-slate-700">{fmtInt(s.ytd)}</td>
                    <td className="px-3 py-1.5 text-right tabular-nums font-semibold text-red-600">{fmtInt(s.khaDung)}</td>
                    <td className="px-3 py-1.5 text-slate-500 max-w-[320px]">{s.lyDo}</td>
                    <td className="px-3 py-1.5 text-right whitespace-nowrap">
                      <button
                        className="px-2 py-1 text-[11px] font-semibold rounded border border-blue-200 text-blue-700 bg-white hover:bg-blue-50"
                        onClick={() => setSuaQuota(s)}
                      >
                        {canEdit ? 'Sửa quota' : 'Xem quota'}
                      </button>
                    </td>
                  </tr>
                ))
              )}
            </tbody>
          </table>
        </div>
      </section>

      {suaQuota && (
        <QuotaThauModal
          fy={suaQuota.fy}
          ps={suaQuota.ps}
          custId={suaQuota.custId}
          grp={suaQuota.grpName}
          items={suaQuota.items}
          focus={{ mset: suaQuota.mset, prod: suaQuota.prod, price: suaQuota.price }}
          locked={!canEdit}
          onClose={() => setSuaQuota(null)}
        />
      )}
    </div>
  );
}
