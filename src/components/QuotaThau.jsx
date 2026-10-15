import React, { useState, useEffect, useMemo, useContext } from 'react';
import ReactDOM from 'react-dom';
import { Trash2 } from './icons.jsx';
import { fmtInt } from '../lib/format.js';
import { Modal } from './Modal.jsx';
import { CURRENT_MONTH, HIEN_HET_HIEU_LUC } from '../config/constants.js';
import { hetHanDot, trangThaiDot } from '../lib/quota.js';

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

const THANG_RE = /^\d{4}-\d{2}$/;
const hieuLucHopLe = (v) => {
  const n = Number(v);
  return Number.isInteger(n) && n >= 1 && n <= 120;
};
// Đợt đủ thông tin = có tháng thầu + hiệu lực (số tháng). Thiếu thì không nhập quota được.
export const dotDuThongTin = (d) => !!d && THANG_RE.test(d.thang || '') && hieuLucHopLe(d.thoiGian);

// Ô tháng + hiệu lực của MỘT đợt (hoặc đợt đang thêm). Chỉ lưu khi cả hai hợp lệ;
// thiếu ô nào thì viền đỏ và chưa gửi lên.
export function DotEditor({ thang, thoiGian, locked, onSave, autoFocus, curMonth }) {
  const [m, setM] = useState(thang || '');
  const [hl, setHl] = useState(thoiGian == null || thoiGian === '' ? '' : String(Number(thoiGian)));
  useEffect(() => {
    setM(thang || '');
  }, [thang]);
  useEffect(() => {
    setHl(thoiGian == null || thoiGian === '' ? '' : String(Number(thoiGian)));
  }, [thoiGian]);
  const mOk = THANG_RE.test(m.trim());
  const hlOk = hieuLucHopLe(hl);
  const thu = () => {
    const mv = m.trim();
    if (!THANG_RE.test(mv) || !hieuLucHopLe(hl)) return;
    if (mv === (thang || '') && Number(hl) === Number(thoiGian)) return;
    onSave(mv, Number(hl));
  };
  const het = hetHanDot(m.trim(), hl);
  const tt = mOk && hlOk ? trangThaiDot(m.trim(), hl, curMonth) : null;
  const o = (ok) =>
    `text-[12px] px-2 py-1 rounded-md border outline-none ${ok ? 'border-slate-200 bg-white focus:border-emerald-500 focus:ring-2 focus:ring-emerald-100' : 'border-red-400 bg-red-50'}`;
  const keyDown = (e) => {
    if (e.key === 'Enter') e.target.blur();
  };
  const nhan = 'text-[10.5px] text-slate-500 whitespace-nowrap';
  return (
    <span className="inline-flex items-center gap-1">
      <span className={nhan}>Tháng thầu</span>
      <input
        value={m}
        onChange={(e) => setM(e.target.value)}
        onBlur={thu}
        onKeyDown={keyDown}
        disabled={locked}
        autoFocus={autoFocus}
        placeholder="yyyy-mm"
        title="Tháng bắt đầu áp dụng thầu, dạng năm-tháng, ví dụ 2026-07 (bắt buộc)"
        className={`w-[80px] ${o(mOk)}`}
      />
      <span className={`${nhan} ml-1`}>Hiệu lực</span>
      <input
        value={hl}
        onChange={(e) => setHl(e.target.value.replace(/[^0-9]/g, ''))}
        onBlur={thu}
        onKeyDown={keyDown}
        disabled={locked}
        placeholder="vd 24"
        title="Số tháng hiệu lực của thầu, ví dụ 12, 18, 24 (bắt buộc). Hết hạn = tháng thầu + 3 tháng + hiệu lực − 1"
        className={`w-[46px] text-right ${o(hlOk)}`}
      />
      <span className={nhan}>tháng</span>
      {het && (
        <span
          className={`text-[10.5px] whitespace-nowrap ${HIEN_HET_HIEU_LUC && tt === 'het' ? 'text-red-600 font-semibold' : 'text-slate-400'}`}
          title="Tháng cuối còn hiệu lực = tháng thầu + 3 tháng + số tháng hiệu lực − 1"
        >
          {HIEN_HET_HIEU_LUC && tt === 'het' ? `(đã hết hiệu lực từ sau ${het})` : `(hiệu lực đến hết ${het})`}
        </span>
      )}
    </span>
  );
}

// Danh sách đợt thầu của 1 nhóm SP, thay cho 2 ô tháng cố định trước đây.
// Mỗi đợt bắt buộc có tháng thầu + hiệu lực (số tháng).
export function DotThauPanel({ fy, ps, custId, grp, locked }) {
  const ctx = useContext(QuotaThauCtx);
  const [busy, setBusy] = useState(false);
  const [err, setErr] = useState('');
  const [dangThem, setDangThem] = useState(null); // loai đang thêm đợt
  if (!ctx) return null;
  const all = ctx.dotsByGroup.get(grpKey(fy, ps, custId, grp)) || [];
  const cua = (loai) =>
    all.filter((d) => d.loai === loai).sort((a, b) => a.dot - b.dot);
  const chinh = cua('chinh');
  const bs = cua('bo_sung');

  const run = async (fn) => {
    if (busy) return false;
    setBusy(true);
    setErr('');
    try {
      await fn();
      return true;
    } catch (e) {
      setErr(e.message || 'Lưu đợt thầu không được');
      return false;
    } finally {
      setBusy(false);
    }
  };
  const them = async (loai, thang, thoiGian) => {
    const ok = await run(() => ctx.saveDot([{ fy, ps, custId, grp, loai, thang, thoiGian }]));
    if (ok) setDangThem(null);
  };
  const sua = (loai, dot, thang, thoiGian) =>
    run(() => ctx.saveDot([{ fy, ps, custId, grp, loai, dot, thang, thoiGian }]));
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
      {list.length === 0 && dangThem !== loai && (
        <span className="text-[11px] text-slate-400">chưa có đợt nào</span>
      )}
      {list.map((d) => (
        <span key={loai + d.dot} className="inline-flex items-center gap-1">
          {list.length > 1 && (
            <span className="text-[10px] text-slate-500 tabular-nums">{`#${d.dot}`}</span>
          )}
          <DotEditor
            thang={d.thang}
            thoiGian={d.thoiGian}
            locked={locked || busy}
            curMonth={CURRENT_MONTH}
            onSave={(t, h) => sua(loai, d.dot, t, h)}
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
      {!locked && dangThem === loai && (
        <span className="inline-flex items-center gap-1 px-1 py-0.5 rounded-md bg-blue-50 border border-blue-200">
          <span className="text-[10px] text-blue-700">Đợt mới</span>
          <DotEditor
            thang=""
            thoiGian=""
            locked={busy}
            autoFocus
            curMonth={CURRENT_MONTH}
            onSave={(t, h) => them(loai, t, h)}
          />
          <button
            onClick={() => setDangThem(null)}
            className="text-[11px] text-slate-500 hover:text-slate-700 px-1"
            title="Huỷ thêm đợt"
          >
            ✕
          </button>
        </span>
      )}
      {!locked && dangThem !== loai && (
        <button
          onClick={() => {
            setErr('');
            setDangThem(loai);
          }}
          disabled={busy}
          title="Thêm đợt: nhập tháng thầu và hiệu lực (số tháng)"
          className="text-[11px] font-semibold px-1.5 py-0.5 rounded border border-blue-200 text-blue-700 bg-white hover:bg-blue-50 disabled:opacity-50"
        >
          + đợt
        </button>
      )}
    </div>
  );

  const soThieu = all.filter((d) => !dotDuThongTin(d)).length;
  return (
    <div className="flex flex-col gap-1.5">
      {hang('chinh', chinh)}
      {hang('bo_sung', bs)}
      {soThieu > 0 && (
        <span className="text-[11px] text-red-600">
          {soThieu} đợt chưa đủ tháng thầu / hiệu lực — chưa nhập được quota cho đợt đó.
        </span>
      )}
      {err && <span className="text-[11px] text-red-600">{err}</span>}
    </div>
  );
}

// Modal nhập quota cho CẢ NHÓM SP: hàng = từng sản phẩm x mức giá (mỗi mức giá
// là một gói thầu riêng), cột = thầu cũ + từng đợt thầu chính / bổ sung.
// Bấm vào ô quota của sản phẩm nào thì mở đúng modal này, dòng của sản phẩm đó
// được tô sáng — nhập cho cả nhóm trong một lần, lưu một lần.
export function QuotaThauModal({
  fy,
  ps,
  custId,
  grp,
  items,
  focus,
  locked,
  onClose,
}) {
  const ctx = useContext(QuotaThauCtx);
  const dots = ctx
    ? ctx.dotsByGroup.get(grpKey(fy, ps, custId, grp)) || []
    : [];
  // Cột: thầu cũ luôn có (không thuộc đợt nào), rồi tới từng đợt đã khai báo.
  const cols = useMemo(() => {
    const nChinh = dots.filter((d) => d.loai === 'chinh').length;
    const nBs = dots.filter((d) => d.loai === 'bo_sung').length;
    const ds = [...dots].sort((a, b) =>
      a.loai === b.loai ? a.dot - b.dot : a.loai === 'chinh' ? -1 : 1,
    );
    return [{ loai: 'cu', dot: 1, label: LOAI_LABEL.cu, thang: '', du: true }].concat(
      ds.map((d) => ({
        loai: d.loai,
        dot: d.dot,
        thang: d.thang,
        thoiGian: d.thoiGian,
        du: dotDuThongTin(d),
        het: hetHanDot(d.thang, d.thoiGian),
        trangThai: dotDuThongTin(d) ? trangThaiDot(d.thang, d.thoiGian, CURRENT_MONTH) : 'up',
        label: dotLabel(d.loai, d.dot, d.loai === 'chinh' ? nChinh : nBs),
      })),
    );
  }, [dots]);

  // Một dòng = 1 sản phẩm ở 1 mức giá. Ngoài các mức giá đang có trên kế hoạch,
  // thêm mức giá chỉ còn tồn tại bên quota để số đã nhập không bị giấu mất.
  const lines = useMemo(() => {
    const out = [];
    const seen = new Set();
    const push = (mset, prod, price, tuKeHoach) => {
      const k = `${mset}||${prod}||${price}`;
      if (seen.has(k)) return;
      seen.add(k);
      out.push({ mset, prod, price, tuKeHoach });
    };
    for (const it of items || []) {
      push(it.mset || '', it.prod || '', Number(it.price) || 0, true);
    }
    for (const it of items || []) {
      const qs = ctx
        ? ctx.quotasByProduct.get(
            prodKey(fy, ps, custId, grp, it.mset, it.prod),
          ) || []
        : [];
      for (const q of qs)
        push(it.mset || '', it.prod || '', Number(q.price) || 0, false);
    }
    return out;
  }, [items, ctx, fy, ps, custId, grp]);

  const quotaCua = (mset, prod) =>
    (ctx
      ? ctx.quotasByProduct.get(prodKey(fy, ps, custId, grp, mset, prod))
      : null) || [];
  const cell = (line, c) => {
    const f = quotaCua(line.mset, line.prod).find(
      (q) =>
        (Number(q.price) || 0) === line.price &&
        q.loai === c.loai &&
        q.dot === c.dot,
    );
    return f ? f.qty : '';
  };
  const [draft, setDraft] = useState({}); // 'mset||prod||price|loai|dot' -> chuỗi đang nhập
  const [busy, setBusy] = useState(false);
  const [err, setErr] = useState('');
  const key = (line, c) =>
    `${line.mset}||${line.prod}||${line.price}|${c.loai}|${c.dot}`;
  const val = (line, c) => {
    const k = key(line, c);
    return k in draft
      ? draft[k]
      : cell(line, c) === ''
        ? ''
        : String(cell(line, c));
  };
  const laDongDangXem = (line) =>
    !!focus &&
    (focus.mset || '') === line.mset &&
    (focus.prod || '') === line.prod &&
    (Number(focus.price) || 0) === line.price;

  // Mọi ô của bảng, tra ngược từ khoá draft -> khỏi phải tách chuỗi khi lưu.
  const oTheoKhoa = useMemo(() => {
    const m = new Map();
    for (const line of lines)
      for (const c of cols) m.set(key(line, c), { line, c });
    return m;
  }, [lines, cols]);
  const doiGiaTri = (k) => {
    const o = oTheoKhoa.get(k);
    if (!o) return null;
    const raw = String(draft[k]).trim();
    const qty = raw === '' ? 0 : Number(raw);
    if (!Number.isFinite(qty) || qty < 0) return { loi: raw, o };
    if (qty === (Number(cell(o.line, o.c)) || 0)) return null;
    return { qty, o };
  };
  const soODaSua = Object.keys(draft).filter((k) => doiGiaTri(k)).length;

  const luu = async () => {
    const rows = [];
    for (const k of Object.keys(draft)) {
      const d = doiGiaTri(k);
      if (!d) continue;
      if (d.loi !== undefined) {
        setErr(`Số lượng không hợp lệ ở "${d.o.line.prod}": ${d.loi}`);
        return;
      }
      if (!d.o.c.du && d.qty > 0) {
        setErr(`${d.o.c.label} chưa có tháng thầu / hiệu lực — điền ở mục Đợt thầu của nhóm trước khi nhập quota.`);
        return;
      }
      rows.push({
        fy,
        ps,
        custId,
        grp,
        mset: d.o.line.mset,
        prod: d.o.line.prod,
        price: d.o.line.price,
        loai: d.o.c.loai,
        dot: d.o.c.dot,
        qty: d.qty,
      });
    }
    if (!rows.length) {
      onClose();
      return;
    }
    setBusy(true);
    setErr('');
    try {
      await ctx.saveQuota(rows, { fy, ps, custId, grp });
      onClose();
    } catch (e) {
      setErr(e.message || 'Lưu không được');
    }
    setBusy(false);
  };

  // Modal được mở từ trong bảng nên portal ra body cho khỏi bị khung cuộn cắt.
  return ReactDOM.createPortal(
    <Modal
      open
      onClose={onClose}
      width={1000}
      title={`Quota thầu · ${grp}`}
      icon={<span className="text-[14px]">📦</span>}
    >
      <div className="px-4 py-3">
        <div className="text-[11.5px] text-slate-500 mb-2">
          Nhập cho mọi sản phẩm của nhóm trong một lần. Mỗi mức giá là một gói
          thầu riêng. Để trống hoặc nhập 0 để xoá quota của ô đó.
        </div>
        {cols.length === 1 && (
          <div className="text-[11.5px] text-amber-700 bg-amber-50 border border-amber-200 rounded-md px-2 py-1.5 mb-2">
            Nhóm SP này chưa khai báo đợt thầu nào. Thêm đợt ở phần đầu nhóm
            trước, rồi mới nhập được quota thầu chính và bổ sung.
          </div>
        )}
        <div className="overflow-auto max-h-[60vh]">
          <table className="border-collapse text-[12px]">
            <thead className="sticky top-0 z-[1]">
              <tr className="bg-white">
                <th className="px-2 py-1.5 text-left font-semibold text-slate-600 border-b border-r border-slate-200 whitespace-nowrap bg-white">
                  Sản phẩm
                </th>
                <th className="px-2 py-1.5 text-right font-semibold text-slate-600 border-b border-r border-slate-200 whitespace-nowrap bg-white">
                  Đơn giá
                </th>
                {cols.map((c) => (
                  <th
                    key={c.loai + c.dot}
                    className="px-2 py-1.5 text-right font-semibold text-slate-600 border-b border-r border-slate-200 whitespace-nowrap bg-white"
                  >
                    {c.label}
                    {c.loai !== 'cu' && (
                      <div
                        className={`text-[10px] font-normal ${!c.du ? 'text-red-600' : HIEN_HET_HIEU_LUC && c.trangThai === 'het' ? 'text-red-500' : 'text-slate-400'}`}
                        title={c.du ? `Tháng thầu ${c.thang}, hiệu lực ${c.thoiGian} tháng, hết hạn ${c.het}` : 'Đợt chưa đủ tháng thầu / hiệu lực'}
                      >
                        {!c.du
                          ? 'thiếu tháng thầu / hiệu lực'
                          : `Từ ${c.thang} · hiệu lực ${Number(c.thoiGian)} tháng${HIEN_HET_HIEU_LUC && c.trangThai === 'het' ? ' · hết HL' : ''}`}
                      </div>
                    )}
                  </th>
                ))}
                <th className="px-2 py-1.5 text-right font-semibold text-slate-600 border-b border-slate-200 bg-white">
                  Tổng
                </th>
              </tr>
            </thead>
            <tbody>
              {lines.map((line, i) => {
                let tong = 0;
                for (const c of cols) tong += Number(val(line, c)) || 0;
                const dangXem = laDongDangXem(line);
                const doiSp = i === 0 || lines[i - 1].prod !== line.prod;
                return (
                  <tr
                    key={key(line, { loai: '_', dot: 0 })}
                    ref={
                      dangXem
                        ? (el) =>
                            el &&
                            el.scrollIntoView({
                              block: 'nearest',
                            })
                        : undefined
                    }
                    className={dangXem ? 'bg-emerald-50/70' : undefined}
                  >
                    <td
                      className={`px-2 py-1 text-slate-700 border-b border-r border-slate-100 max-w-[240px] ${doiSp ? '' : 'text-slate-400'}`}
                      title={`${line.mset ? line.mset + ' · ' : ''}${line.prod}`}
                    >
                      <div className="truncate">{doiSp ? line.prod : '↳'}</div>
                      {doiSp && line.mset && line.mset !== line.prod && (
                        <div className="truncate text-[10px] text-slate-400">
                          {line.mset}
                        </div>
                      )}
                    </td>
                    <td className="px-2 py-1 text-right tabular-nums text-slate-700 border-b border-r border-slate-100 whitespace-nowrap">
                      {fmtInt(line.price)}
                      {!line.tuKeHoach && (
                        <span
                          className="ml-1 text-[10px] text-amber-600"
                          title="Mức giá này không còn trên kế hoạch, chỉ còn số quota đã nhập trước đó"
                        >
                          ⚠
                        </span>
                      )}
                    </td>
                    {cols.map((c) => (
                      <td
                        key={c.loai + c.dot}
                        className="px-1 py-1 border-b border-r border-slate-100"
                      >
                        <input
                          value={val(line, c)}
                          disabled={locked || busy || (!c.du && cell(line, c) === '')}
                          title={!c.du ? 'Đợt chưa đủ tháng thầu / hiệu lực: chỉ xoá hoặc đưa về 0 được' : undefined}
                          onChange={(e) =>
                            setDraft((d) => ({
                              ...d,
                              [key(line, c)]: e.target.value,
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
          <span className="mr-auto text-[11.5px] text-slate-500">
            {lines.length} dòng
            {soODaSua > 0 ? ` · ${soODaSua} ô đã sửa` : ''}
          </span>
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
export function QuotaCell({ value, pending, width, onOpen }) {
  // Quota chỉ nhập qua modal theo mức giá × đợt (shared.quota_thau). Không có
  // onOpen (chưa nạp xong ngữ cảnh quota) thì chỉ hiện số.
  if (!onOpen) {
    return (
      <td
        className="px-1.5 py-1.5 text-[12px] text-right tabular-nums text-slate-700 border-r border-b border-slate-100 bg-blue-50/20"
        style={{ width, minWidth: width }}
      >
        {value ? fmtInt(value) : '·'}
      </td>
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
