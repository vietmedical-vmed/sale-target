import React, { useState, useEffect, useMemo, useContext } from 'react';
import ReactDOM from 'react-dom';
import { Trash2 } from './icons.jsx';
import { fmtInt } from '../lib/format.js';
import { EditableCell } from './EditableCell.jsx';
import { Modal } from './Modal.jsx';

// ============ Ô nhập tháng thầu (áp cho cả nhóm SP) — định dạng bắt buộc yyyy-mm ============
export function GroupMonthField({ label, value, pending, locked, onCommit }) {
  const [draft, setDraft] = useState(value || '');
  const [err, setErr] = useState(false);
  useEffect(() => {
    setDraft(value || '');
  }, [value]);
  const commit = () => {
    const v = (draft || '').trim();
    if (v === (value || '')) {
      setErr(false);
      return;
    }
    if (v !== '' && !/^\d{4}-\d{2}$/.test(v)) {
      setErr(true);
      return;
    } // giữ định dạng yyyy-mm
    setErr(false);
    onCommit(v);
  };
  return (
    <div className="flex items-center gap-1.5">
      <span className="text-[10.5px] font-semibold text-blue-800 uppercase tracking-wide whitespace-nowrap">
        {label}
      </span>
      <input
        value={draft}
        onChange={(e) => setDraft(e.target.value)}
        onBlur={commit}
        disabled={locked}
        placeholder="yyyy-mm"
        className={`w-[92px] text-[12px] px-2 py-1 rounded-md border outline-none ${err ? 'border-red-400 bg-red-50 ring-1 ring-red-200' : pending ? 'border-amber-400 bg-amber-50 ring-1 ring-amber-200' : 'border-slate-200 bg-white focus:border-emerald-500 focus:ring-2 focus:ring-emerald-100'}`}
      />
      {err && (
        <span className="text-[10px] text-red-500 whitespace-nowrap">
          yyyy-mm
        </span>
      )}
    </div>
  );
}

// ============ ĐỢT THẦU & QUOTA (shared.dot_thau / shared.quota_thau) ============
// Quota đã tách khỏi sale_target: 1 nhóm SP có thể có NHIỀU đợt thầu bổ sung trong
// cùng năm, và quota gắn với từng MỨC GIÁ (mỗi mức giá là một gói thầu) chứ không
// gắn với sản phẩm. Dữ liệu đi qua context để khỏi xuyên prop qua 4 tầng component.
export const QuotaThauCtx = React.createContext(null);
export const grpKey = (fy, ps, custId, grp) =>
  [fy || '', ps || '', custId || '', grp || ''].join('||');
export const prodKey = (fy, ps, custId, grp, mset, prod) =>
  [fy || '', ps || '', custId || '', grp || '', mset || '', prod || ''].join(
    '||',
  );
const LOAI_LABEL = {
  cu: 'Thầu cũ',
  chinh: 'Thầu chính',
  bo_sung: 'Thầu bổ sung',
};
// Nhãn ngắn cho 1 đợt: thầu chính 1 đợt thì không cần số, nhiều đợt mới đánh số.
const dotLabel = (loai, dot, tong) =>
  loai === 'cu'
    ? LOAI_LABEL.cu
    : tong > 1
      ? `${LOAI_LABEL[loai]} ${dot}`
      : LOAI_LABEL[loai];

// Ô nhập tháng thầu của MỘT đợt. Bỏ trống là hợp lệ (đã biết có đợt, chưa rõ tháng).
export function DotMonthInput({ value, locked, onCommit }) {
  const [draft, setDraft] = useState(value || '');
  const [err, setErr] = useState(false);
  useEffect(() => {
    setDraft(value || '');
  }, [value]);
  const commit = () => {
    const v = (draft || '').trim();
    if (v === (value || '')) {
      setErr(false);
      return;
    }
    if (v !== '' && !/^\d{4}-\d{2}$/.test(v)) {
      setErr(true);
      return;
    }
    setErr(false);
    onCommit(v);
  };
  return (
    <input
      value={draft}
      onChange={(e) => setDraft(e.target.value)}
      onBlur={commit}
      onKeyDown={(e) => {
        if (e.key === 'Enter') e.target.blur();
      }}
      disabled={locked}
      placeholder="yyyy-mm"
      className={`w-[86px] text-[12px] px-2 py-1 rounded-md border outline-none ${err ? 'border-red-400 bg-red-50 ring-1 ring-red-200' : 'border-slate-200 bg-white focus:border-emerald-500 focus:ring-2 focus:ring-emerald-100'}`}
    />
  );
}

// Danh sách đợt thầu của 1 nhóm SP, thay cho 2 ô tháng cố định trước đây.
export function DotThauPanel({ fy, ps, custId, grp, locked }) {
  const ctx = useContext(QuotaThauCtx);
  const [busy, setBusy] = useState(false);
  if (!ctx) return null;
  const all = ctx.dotsByGroup.get(grpKey(fy, ps, custId, grp)) || [];
  const cua = (loai) =>
    all.filter((d) => d.loai === loai).sort((a, b) => a.dot - b.dot);
  const chinh = cua('chinh');
  const bs = cua('bo_sung');

  const run = async (fn) => {
    if (busy) return;
    setBusy(true);
    try {
      await fn();
    } finally {
      setBusy(false);
    }
  };
  const them = (loai) =>
    run(() => ctx.saveDot([{ fy, ps, custId, grp, loai, thang: '' }]));
  const doiThang = (loai, dot, thang) =>
    run(() => ctx.saveDot([{ fy, ps, custId, grp, loai, dot, thang }]));
  const xoa = (loai, dot, nhan) => {
    if (
      !confirm(
        `Xoá ${nhan}?\nQuota đã nhập cho đợt này cũng bị xoá. Không hoàn tác được.`,
      )
    )
      return;
    run(() => ctx.deleteDot({ fy, ps, custId, grp, loai, dot }));
  };

  const hang = (loai, list) => (
    <div className="flex items-center gap-2 flex-wrap">
      <span className="text-[10.5px] font-semibold text-blue-800 uppercase tracking-wide whitespace-nowrap">
        {LOAI_LABEL[loai]}
      </span>
      {list.length === 0 && (
        <span className="text-[11px] text-slate-400">chưa có đợt nào</span>
      )}
      {list.map((d) => (
        <span key={loai + d.dot} className="inline-flex items-center gap-1">
          {list.length > 1 && (
            <span className="text-[10px] text-slate-500 tabular-nums">{`#${d.dot}`}</span>
          )}
          <DotMonthInput
            value={d.thang}
            locked={locked || busy}
            onCommit={(v) => doiThang(loai, d.dot, v)}
          />
          {!locked && (
            <button
              onClick={() =>
                xoa(loai, d.dot, dotLabel(loai, d.dot, list.length))
              }
              title="Xoá đợt này"
              className="text-slate-300 hover:text-red-600"
            >
              <Trash2 size={12} />
            </button>
          )}
        </span>
      ))}
      {!locked && (
        <button
          onClick={() => them(loai)}
          disabled={busy}
          className="text-[11px] font-semibold px-1.5 py-0.5 rounded border border-blue-200 text-blue-700 bg-white hover:bg-blue-50 disabled:opacity-50"
        >
          + đợt
        </button>
      )}
    </div>
  );

  return (
    <div className="flex flex-col gap-1.5">
      {hang('chinh', chinh)}
      {hang('bo_sung', bs)}
    </div>
  );
}

// Modal nhập quota của 1 sản phẩm: hàng = mức giá (mỗi mức giá là 1 gói thầu),
// cột = thầu cũ + từng đợt thầu chính / bổ sung.
export function QuotaThauModal({
  fy,
  ps,
  custId,
  grp,
  mset,
  prod,
  prices,
  locked,
  onClose,
}) {
  const ctx = useContext(QuotaThauCtx);
  const dots = ctx
    ? ctx.dotsByGroup.get(grpKey(fy, ps, custId, grp)) || []
    : [];
  const rowsQ = ctx
    ? ctx.quotasByProduct.get(prodKey(fy, ps, custId, grp, mset, prod)) || []
    : [];
  // Cột: thầu cũ luôn có (không thuộc đợt nào), rồi tới từng đợt đã khai báo.
  const cols = useMemo(() => {
    const nChinh = dots.filter((d) => d.loai === 'chinh').length;
    const nBs = dots.filter((d) => d.loai === 'bo_sung').length;
    const ds = [...dots].sort((a, b) =>
      a.loai === b.loai ? a.dot - b.dot : a.loai === 'chinh' ? -1 : 1,
    );
    return [{ loai: 'cu', dot: 1, label: LOAI_LABEL.cu, thang: '' }].concat(
      ds.map((d) => ({
        loai: d.loai,
        dot: d.dot,
        thang: d.thang,
        label: dotLabel(d.loai, d.dot, d.loai === 'chinh' ? nChinh : nBs),
      })),
    );
  }, [dots]);
  // Mức giá: gộp giá đang có trên kế hoạch với giá đã từng nhập quota.
  const giaList = useMemo(() => {
    const s = new Set((prices || []).map((p) => Number(p) || 0));
    for (const q of rowsQ) s.add(Number(q.price) || 0);
    if (s.size === 0) s.add(0);
    return [...s].sort((a, b) => a - b);
  }, [prices, rowsQ]);
  const cell = (price, c) => {
    const f = rowsQ.find(
      (q) =>
        (Number(q.price) || 0) === price &&
        q.loai === c.loai &&
        q.dot === c.dot,
    );
    return f ? f.qty : '';
  };
  const [draft, setDraft] = useState({}); // 'price|loai|dot' -> chuỗi đang nhập
  const [busy, setBusy] = useState(false);
  const [err, setErr] = useState('');
  const key = (price, c) => `${price}|${c.loai}|${c.dot}`;
  const val = (price, c) => {
    const k = key(price, c);
    return k in draft
      ? draft[k]
      : cell(price, c) === ''
        ? ''
        : String(cell(price, c));
  };

  const luu = async () => {
    const rows = [];
    for (const price of giaList) {
      for (const c of cols) {
        const k = key(price, c);
        if (!(k in draft)) continue;
        const raw = String(draft[k]).trim();
        const qty = raw === '' ? 0 : Number(raw);
        if (!Number.isFinite(qty) || qty < 0) {
          setErr('Số lượng không hợp lệ: ' + raw);
          return;
        }
        if (qty === (Number(cell(price, c)) || 0)) continue;
        rows.push({
          fy,
          ps,
          custId,
          grp,
          mset,
          prod,
          price,
          loai: c.loai,
          dot: c.dot,
          qty,
        });
      }
    }
    if (!rows.length) {
      onClose();
      return;
    }
    setBusy(true);
    setErr('');
    try {
      await ctx.saveQuota(rows, { fy, ps, custId, grp, mset, prod });
      onClose();
    } catch (e) {
      setErr(e.message || 'Lưu không được');
    }
    setBusy(false);
  };

  // Modal được mở từ trong <tr> nên phải portal ra body, không thì có <div> nằm
  // trực tiếp trong <tr> — DOM sai chuẩn.
  return ReactDOM.createPortal(
    <Modal
      open
      onClose={onClose}
      width={860}
      title={`Quota thầu · ${prod}`}
      icon={<span className="text-[14px]">📦</span>}
    >
      <div className="px-4 py-3">
        <div className="text-[11.5px] text-slate-500 mb-2">
          Mỗi mức giá là một gói thầu riêng. Để trống hoặc nhập 0 để xoá quota
          của ô đó.
        </div>
        {cols.length === 1 && (
          <div className="text-[11.5px] text-amber-700 bg-amber-50 border border-amber-200 rounded-md px-2 py-1.5 mb-2">
            Nhóm SP này chưa khai báo đợt thầu nào. Thêm đợt ở phần đầu nhóm
            trước, rồi mới nhập được quota thầu chính và bổ sung.
          </div>
        )}
        <div className="overflow-x-auto">
          <table className="border-collapse text-[12px]">
            <thead>
              <tr>
                <th className="px-2 py-1.5 text-left font-semibold text-slate-600 border-b border-r border-slate-200 whitespace-nowrap">
                  Đơn giá
                </th>
                {cols.map((c) => (
                  <th
                    key={c.loai + c.dot}
                    className="px-2 py-1.5 text-right font-semibold text-slate-600 border-b border-r border-slate-200 whitespace-nowrap"
                  >
                    {c.label}
                    {c.thang ? (
                      <div className="text-[10px] font-normal text-slate-400">
                        {c.thang}
                      </div>
                    ) : null}
                  </th>
                ))}
                <th className="px-2 py-1.5 text-right font-semibold text-slate-600 border-b border-slate-200">
                  Tổng
                </th>
              </tr>
            </thead>
            <tbody>
              {giaList.map((price) => {
                let tong = 0;
                for (const c of cols) tong += Number(val(price, c)) || 0;
                return (
                  <tr key={price}>
                    <td className="px-2 py-1 tabular-nums text-slate-700 border-b border-r border-slate-100 whitespace-nowrap">
                      {fmtInt(price)}
                    </td>
                    {cols.map((c) => (
                      <td
                        key={c.loai + c.dot}
                        className="px-1 py-1 border-b border-r border-slate-100"
                      >
                        <input
                          value={val(price, c)}
                          disabled={locked || busy}
                          onChange={(e) =>
                            setDraft((d) => ({
                              ...d,
                              [key(price, c)]: e.target.value,
                            }))
                          }
                          className="w-[74px] text-[12px] text-right px-1.5 py-1 rounded border border-slate-200 tabular-nums outline-none focus:border-emerald-500 focus:ring-2 focus:ring-emerald-100 disabled:bg-slate-50"
                        />
                      </td>
                    ))}
                    <td className="px-2 py-1 text-right tabular-nums font-semibold text-slate-800 border-b border-slate-100">
                      {fmtInt(tong)}
                    </td>
                  </tr>
                );
              })}
            </tbody>
          </table>
        </div>
        {err && <div className="mt-2 text-[12px] text-red-600">{err}</div>}
        <div className="mt-3 flex items-center justify-end gap-2">
          <button
            onClick={onClose}
            className="px-3 py-1.5 text-[12px] rounded-md border border-slate-200 text-slate-600 hover:bg-slate-50"
          >
            Đóng
          </button>
          {!locked && (
            <button
              onClick={luu}
              disabled={busy}
              className="px-3 py-1.5 text-[12px] font-semibold rounded-md bg-emerald-600 text-white hover:bg-emerald-700 disabled:opacity-50"
            >
              {busy ? 'Đang lưu…' : 'Lưu quota'}
            </button>
          )}
        </div>
      </div>
    </Modal>,
    document.body,
  );
}

// Ô quota trên dòng sản phẩm. Có bảng quota mới thì bấm vào mở modal nhập theo
// mức giá và theo đợt; chưa có thì rơi về ô sửa tại chỗ như trước.
export function QuotaCell({
  value,
  pending,
  width,
  onOpen,
  fallbackLocked,
  onCommit,
}) {
  if (!onOpen) {
    return (
      <EditableCell
        value={value}
        pending={pending}
        locked={fallbackLocked}
        onCommit={onCommit}
        width={width}
        bg="bg-blue-50/20"
      />
    );
  }
  return (
    <td
      onClick={onOpen}
      title="Bấm để nhập quota theo mức giá và theo đợt thầu"
      className={`px-1.5 py-1.5 text-[12px] text-right tabular-nums border-r border-b border-slate-100 cursor-pointer hover:bg-emerald-50/60 ${pending ? 'bg-amber-50' : 'bg-blue-50/20'}`}
      style={{ width, minWidth: width }}
    >
      {value ? fmtInt(value) : '·'}
    </td>
  );
}
