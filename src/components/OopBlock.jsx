import React, { useState } from 'react';
import { ChevronDown, ChevronRight, Plus } from './icons.jsx';
import { LY_DO_LABEL, MASK_MONEY, MONTHS, MONTH_LABELS, OOP_CUST, NO_MSET } from '../config/constants.js';
import { fmtFull, moneyTy3 } from '../lib/format.js';

// ============ NGOÀI KẾ HOẠCH TRÊN MÀN CHI TIẾT ============
// Thực hiện (hoá đơn) không khớp dòng kế hoạch nào → gom theo KH × SP để hiện ngay
// dưới thẻ KH tương ứng (hoặc thẻ riêng nếu KH chưa có trong kế hoạch). Chỉ để xem:
// không sửa ô, không xoá. "Đưa vào KH" chỉ cho ly_do='thieu_dong_ke_hoach' — các lý
// do khác là lỗi cấu hình (địa bàn / PS / bộ vật tư), thêm dòng kế hoạch sẽ không hút
// được số thực hiện mà còn tạo dòng sai PS.

const tomTat = (key, base, items) => {
  let dt = 0,
    nThieu = 0;
  for (const it of items) {
    dt += it.dt;
    if (it.lyDo === 'thieu_dong_ke_hoach') nThieu++;
  }
  return { ...base, key, items, dt, nThieu };
};

// rows: oopRows đã lọc theo bộ lọc chung. Trả Map khoá KH (custId || tên hiển thị —
// trùng khoá thẻ ở màn Chi tiết) → { custId, cust, region, items, dt, nThieu }.
export function gomOopTheoKh(rows) {
  const byCust = new Map();
  for (const r of rows) {
    const idx = MONTHS.indexOf(r.mo);
    if (idx < 0) continue;
    const ck = r.custId || r.cust || OOP_CUST;
    let c = byCust.get(ck);
    if (!c) {
      c = {
        custId: r.custId || '',
        cust: r.cust || OOP_CUST,
        region: r.region || '',
        iMap: new Map(),
      };
      byCust.set(ck, c);
    }
    const price = Number(r.price) || 0;
    const ik = [r.grp || '', r.ps || '', r.mset || '', r.prod || '', price].join('||');
    let it = c.iMap.get(ik);
    if (!it) {
      it = {
        k: ik,
        grp: r.grp || '',
        ps: r.ps || '',
        bu: r.bu || '',
        mset: r.mset || '',
        prod: r.prod || '—',
        price,
        lyDo: r._lyDo || '',
        psDiaBan: r._psDiaBan || '',
        act: Array(12).fill(0),
        sl: 0,
        dt: 0,
        rows: [],
      };
      c.iMap.set(ik, it);
    }
    const a = Number(r.act) || 0;
    it.act[idx] += a;
    it.sl += a;
    it.dt += Number(r.dtAct) || 0;
    it.rows.push(r);
  }
  const out = new Map();
  for (const [ck, c] of byCust) {
    const items = Array.from(c.iMap.values()).sort((a, b) => b.dt - a.dt);
    out.set(ck, tomTat(ck, { custId: c.custId, cust: c.cust, region: c.region }, items));
  }
  return out;
}

// Chế độ chia theo team: thẻ KH ở team tk lấy SP ngoài KH của team đó. SP thuộc team
// mà KH không có thẻ nào (teamsCoThe) gắn vào thẻ ở team đầu tiên, khỏi bị rơi mất.
// Cache theo entry để cùng input trả cùng object (CustomerCard là React.memo).
const cacheTheoTeam = new WeakMap();
export function oopTheoTeam(e, tk, teamsCoThe) {
  const ck = tk + '|' + teamsCoThe.join(',');
  let m = cacheTheoTeam.get(e);
  if (!m) cacheTheoTeam.set(e, (m = new Map()));
  if (m.has(ck)) return m.get(ck);
  const items = e.items.filter(
    (it) => it.bu === tk || (!teamsCoThe.includes(it.bu) && tk === teamsCoThe[0]),
  );
  const out = items.length
    ? tomTat(e.key, { custId: e.custId, cust: e.cust, region: e.region }, items)
    : undefined;
  m.set(ck, out);
  return out;
}

const MAU_LY_DO = {
  red: 'bg-red-50 text-red-700 border-red-200',
  amber: 'bg-amber-50 text-amber-700 border-amber-200',
  orange: 'bg-orange-50 text-orange-700 border-orange-200',
  slate: 'bg-slate-50 text-slate-600 border-slate-200',
};

export function OopChip({ oop }) {
  return (
    <span
      title="Có thực hiện nhưng chưa có dòng kế hoạch tương ứng"
      className="flex-shrink-0 px-1.5 py-0.5 text-[10.5px] font-medium rounded border bg-amber-50 text-amber-700 border-amber-200 whitespace-nowrap"
    >
      +{oop.items.length} SP ngoài KH
    </span>
  );
}

// Bảng SP ngoài KH của 1 khách hàng. embedded = nằm trong thẻ KH có kế hoạch
// (có thanh tiêu đề gập/mở riêng); không embedded = thân của OopCustomerCard.
export function OopBlock({ oop, embedded, canAdd, isAdmin, busy, onAdd, onAddAll, onFix }) {
  const [open, setOpen] = useState(!embedded);
  const th =
    'px-2 py-1.5 text-[10px] font-semibold uppercase tracking-wide text-slate-500 border-b border-slate-200 whitespace-nowrap bg-white';
  const td = 'px-2 py-1.5 text-[12px] border-b border-slate-100 whitespace-nowrap';
  const addAll =
    canAdd && oop.nThieu > 1 ? (
      <button
        onClick={(e) => {
          e.stopPropagation();
          onAddAll(oop);
        }}
        disabled={busy}
        title={`Thêm cả ${oop.nThieu} SP "Thiếu SP trong KH" của khách hàng này vào kế hoạch (mỗi SP = 12 dòng)`}
        className="flex items-center gap-1 px-2 py-1 text-[11.5px] font-semibold rounded-md border border-amber-300 text-amber-800 bg-white hover:bg-amber-100 disabled:opacity-50"
      >
        <Plus size={13} />
        Đưa cả {oop.nThieu} SP vào KH
      </button>
    ) : null;
  const action = (it) => {
    if (it.lyDo === 'thieu_dong_ke_hoach')
      return canAdd ? (
        <button
          onClick={() => onAdd(it, oop)}
          title="Mở form Thêm sản phẩm với KH, PS, nhóm và sản phẩm điền sẵn. Thực hiện các tháng đã có sẽ chuyển vào dòng mới."
          className="px-1.5 py-0.5 text-[11px] font-medium text-blue-700 hover:bg-blue-100 rounded"
        >
          Đưa vào KH
        </button>
      ) : null;
    if (!it.lyDo) return null;
    return isAdmin ? (
      <button
        onClick={() => onFix(it.lyDo)}
        title="Mở bảng Đối chiếu ngoài kế hoạch, lọc sẵn theo lý do này"
        className="px-1.5 py-0.5 text-[11px] font-medium text-emerald-700 hover:bg-emerald-100 rounded"
      >
        Xử lý
      </button>
    ) : (
      <span
        title="Lỗi cấu hình (địa bàn / PS / bộ vật tư) — cần admin xử lý ở màn Cấu hình địa bàn"
        className="text-[11px] text-slate-400"
      >
        Chờ admin
      </span>
    );
  };
  return (
    <div className={embedded ? 'border-t border-amber-200' : ''}>
      {embedded && (
        <div
          role="button"
          onClick={() => setOpen((v) => !v)}
          className="flex items-center gap-3 px-4 py-2 bg-amber-50/70 hover:bg-amber-50 cursor-pointer"
        >
          {open ? (
            <ChevronDown size={15} className="text-amber-600" />
          ) : (
            <ChevronRight size={15} className="text-amber-600" />
          )}
          <span className="text-[12.5px] font-semibold text-amber-800">Ngoài kế hoạch</span>
          <span className="text-[12px] text-amber-700 tabular-nums">
            {oop.items.length} SP · DThu TH {moneyTy3(oop.dt)}
          </span>
          <div className="flex-1" />
          {addAll}
        </div>
      )}
      {!embedded && addAll && (
        <div className="flex justify-end px-4 py-2 bg-amber-50/50">{addAll}</div>
      )}
      {open && (
        <div className="overflow-x-auto">
          <table className="border-collapse min-w-full">
            <thead>
              <tr>
                <th className={th + ' text-left'}>Nhóm SP · PS</th>
                <th className={th + ' text-left'}>Bộ vật tư</th>
                <th className={th + ' text-left'}>Sản phẩm</th>
                <th className={th + ' text-right'}>Đơn giá</th>
                {MONTH_LABELS.map((m) => (
                  <th key={m} className={th + ' text-right'}>
                    {m}
                  </th>
                ))}
                <th className={th + ' text-right'}>Tổng SL</th>
                <th className={th + ' text-right'}>DThu TH</th>
                <th className={th + ' text-left'}>Lý do</th>
                <th className={th} />
              </tr>
            </thead>
            <tbody>
              {oop.items.map((it) => {
                const lb = LY_DO_LABEL[it.lyDo];
                return (
                  <tr key={it.k} className="hover:bg-amber-50/40">
                    <td className={td}>
                      <div className="text-slate-800">{it.grp || '—'}</div>
                      <div className="text-[10.5px] text-slate-400">{it.ps || '—'}</div>
                    </td>
                    <td className={td + ' text-slate-600'}>
                      {it.mset && it.mset !== NO_MSET ? it.mset : '—'}
                    </td>
                    <td className={td + ' text-slate-800 max-w-[260px] truncate'} title={it.prod}>
                      {it.prod}
                    </td>
                    <td className={td + ' text-right tabular-nums text-slate-600'}>
                      {!it.price ? '—' : MASK_MONEY ? '•••' : fmtFull(Math.round(it.price))}
                    </td>
                    {it.act.map((a, i) => (
                      <td key={i} className={td + ' text-right tabular-nums text-slate-700'}>
                        {a ? fmtFull(a) : ''}
                      </td>
                    ))}
                    <td className={td + ' text-right tabular-nums font-semibold text-slate-800'}>
                      {fmtFull(it.sl)}
                    </td>
                    <td className={td + ' text-right tabular-nums text-amber-800'}>
                      {moneyTy3(it.dt)}
                    </td>
                    <td className={td}>
                      {lb ? (
                        <span
                          title={lb.desc}
                          className={`px-1.5 py-0.5 text-[10.5px] font-medium rounded border ${MAU_LY_DO[lb.color] || MAU_LY_DO.slate}`}
                        >
                          {lb.short}
                        </span>
                      ) : (
                        <span className="text-slate-400">—</span>
                      )}
                    </td>
                    <td className={td + ' text-right'}>{action(it)}</td>
                  </tr>
                );
              })}
            </tbody>
          </table>
        </div>
      )}
    </div>
  );
}

// Thẻ cho KH có thực hiện nhưng KHÔNG có dòng kế hoạch nào (theo bộ lọc hiện tại).
export const OopCustomerCard = React.memo(function OopCustomerCard({
  oop,
  open,
  onToggle,
  ...rest
}) {
  return (
    <div className="bg-white rounded-lg border border-amber-200 mb-3 shadow-sm">
      <div className="flex items-stretch">
        <button onClick={onToggle} className="flex-1 min-w-0 flex items-stretch text-left">
          <div className="bg-amber-500 text-white px-3 py-3 flex flex-col items-center justify-center min-w-[88px]">
            <div className="text-[11px] opacity-90 font-mono">{oop.custId || '—'}</div>
          </div>
          <div className="flex-1 flex items-center gap-4 px-4 py-3 hover:bg-amber-50/50 min-w-0">
            {open ? (
              <ChevronDown size={16} className="text-slate-400 flex-shrink-0" />
            ) : (
              <ChevronRight size={16} className="text-slate-400 flex-shrink-0" />
            )}
            <h3 className="flex-1 min-w-0 text-[14px] font-semibold text-slate-900 truncate">
              {oop.cust}
            </h3>
            <div className="text-right flex-shrink-0">
              <div className="text-[10px] uppercase tracking-wide text-slate-400">
                DThu TH ngoài KH
              </div>
              <div className="text-[13px] font-semibold tabular-nums text-amber-800">
                {moneyTy3(oop.dt)}
              </div>
            </div>
            <div className="text-right flex-shrink-0 min-w-[48px]">
              <div className="text-[10px] uppercase tracking-wide text-slate-400">SP</div>
              <div className="text-[13px] font-semibold tabular-nums text-slate-700">
                {oop.items.length}
              </div>
            </div>
          </div>
        </button>
      </div>
      {open && (
        <div className="border-t border-amber-200">
          <OopBlock oop={oop} {...rest} />
        </div>
      )}
    </div>
  );
});
