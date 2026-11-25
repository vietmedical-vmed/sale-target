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

// ============ LIÊN KẾT QUOTA ↔ HỢP ĐỒNG (app_sale.quota_hop_dong) ============
// Tải lazy theo nhóm SP qua ctx.taiHopDongNhom (RPC get_quota_hop_dong_nhom). Chỉ tải
// khi nhóm có đợt đã liên kết HĐ (coHd): không có thì chắc chắn không có liên kết nào.
const lineKey = (mset, prod, price) => `${mset || ''}||${prod || ''}||${Number(price) || 0}`;
const ngan = (s, n = 18) => (!s ? '' : s.length > n ? s.slice(0, n - 1) + '…' : s);
const thangNam = (d) => (d && /^\d{4}-\d{2}/.test(d) ? `${d.slice(5, 7)}/${d.slice(0, 4)}` : '');
const soHd = (r) => r.so_hd || r.ma_hd || '';

export function useHopDongNhom(fy, ps, custId, grp, bat) {
  const ctx = useContext(QuotaThauCtx);
  const tai = ctx && ctx.taiHopDongNhom;
  const [st, setSt] = useState({ rows: null, err: '' });
  useEffect(() => {
    if (!tai || !bat) {
      setSt({ rows: null, err: '' });
      return undefined;
    }
    let huy = false;
    tai(fy, ps, custId, grp).then(
      (rows) => !huy && setSt({ rows, err: '' }),
      (e) => !huy && setSt({ rows: null, err: e.message || 'Không tải được hợp đồng' }),
    );
    return () => {
      huy = true;
    };
  }, [tai, bat, fy, ps, custId, grp]);
  return useMemo(() => ({ ...tomTatHopDong(st.rows), err: st.err }), [st]);
}

// Gom liên kết: theo dòng quota (SP × mức giá) và theo đợt.
function tomTatHopDong(rows) {
  const theoDong = new Map(); // lineKey -> [link]
  const theoO = new Map(); // lineKey|loai|dot -> { sl, hds: Set }
  const theoDot = new Map(); // loai|dot -> { hds: Map ma_hd -> {...}, dongs: Set lineKey }
  for (const r of rows || []) {
    const lk = lineKey(r.mset, r.prod, r.price);
    if (!theoDong.has(lk)) theoDong.set(lk, []);
    theoDong.get(lk).push(r);
    const ok = `${lk}|${r.loai}|${r.dot}`;
    const o = theoO.get(ok) || { sl: 0, hds: new Set() };
    o.sl += Number(r.sl_quota) || 0;
    o.hds.add(soHd(r));
    theoO.set(ok, o);
    const dk = `${r.loai}|${r.dot}`;
    const d = theoDot.get(dk) || { hds: new Map(), dongs: new Set() };
    d.dongs.add(lk);
    const h = d.hds.get(r.ma_hd) || {
      soHd: soHd(r),
      ngayKy: r.ngay_ky,
      thoiHan: r.thoi_han,
      giaTri: 0,
    };
    h.giaTri += (Number(r.sl_quota) || 0) * (Number(r.price) || 0);
    d.hds.set(r.ma_hd, h);
    theoDot.set(dk, d);
  }
  // HĐ chính của đợt = giá trị gắn lớn nhất, hoà thì HĐ ký sau (giống dien_dot_cu_tu_hop_dong).
  for (const d of theoDot.values()) {
    d.ds = [...d.hds.values()].sort(
      (a, b) => b.giaTri - a.giaTri || String(b.ngayKy || '').localeCompare(String(a.ngayKy || '')),
    );
  }
  return { co: !!rows, theoDong, theoO, theoDot };
}

// Nhãn HĐ của 1 đợt: "HĐ <số> · ký mm/yyyy · hết mm/yyyy · phủ a/b SP".
// soSp = số dòng (SP × mức giá) có quota > 0 trong đợt; undefined thì bỏ phần "phủ".
export function DotHopDongTag({ info, soSp, gon = false }) {
  if (!info || !info.ds || !info.ds.length) return null;
  const h = info.ds[0];
  const them = info.ds.length - 1;
  const phu = info.dongs.size;
  const title = info.ds
    .map((x) => `${x.soHd} · ký ${thangNam(x.ngayKy) || '?'} · hết ${thangNam(x.thoiHan) || '?'}`)
    .join('\n');
  const du = soSp == null || phu >= soSp;
  return (
    <span
      className={`inline-flex items-center gap-1 text-[10.5px] px-1.5 py-0.5 rounded border whitespace-nowrap ${du ? 'bg-emerald-50 border-emerald-200 text-emerald-800' : 'bg-amber-50 border-amber-200 text-amber-800'}`}
      title={`Hợp đồng đã gắn với quota của đợt:\n${title}`}
    >
      <span className="font-semibold">HĐ {ngan(h.soHd, gon ? 14 : 22)}</span>
      {them > 0 && <span>+{them}</span>}
      {!gon && h.ngayKy && <span>· ký {thangNam(h.ngayKy)}</span>}
      {!gon && h.thoiHan && <span>· hết {thangNam(h.thoiHan)}</span>}
      {soSp != null && soSp > 0 && (
        <span>
          · phủ {Math.min(phu, soSp)}/{soSp} SP
        </span>
      )}
    </span>
  );
}

// Ô tháng + hiệu lực của MỘT đợt (hoặc đợt đang thêm). Chỉ lưu khi cả hai hợp lệ;
// thiếu ô nào thì viền đỏ và chưa gửi lên.
export function DotEditor({ thang, thoiGian, locked, onSave, autoFocus, curMonth, coHd = false, hdTag = null }) {
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
  const het = hetHanDot(m.trim(), hl, coHd);
  const tt = mOk && hlOk ? trangThaiDot(m.trim(), hl, curMonth, undefined, coHd) : null;
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
        title={
          coHd
            ? 'Số tháng hiệu lực của thầu (bắt buộc). Đợt đã liên kết hợp đồng: hết hạn = tháng thầu + hiệu lực − 1'
            : 'Số tháng hiệu lực của thầu, ví dụ 12, 18, 24 (bắt buộc). Chưa liên kết hợp đồng: hết hạn = tháng thầu + 3 tháng + hiệu lực − 1'
        }
        className={`w-[46px] text-right ${o(hlOk)}`}
      />
      <span className={nhan}>tháng</span>
      {het && (
        <span
          className={`text-[10.5px] whitespace-nowrap ${HIEN_HET_HIEU_LUC && tt === 'het' ? 'text-red-600 font-semibold' : 'text-slate-400'}`}
          title={
            coHd
              ? 'Đã liên kết hợp đồng: tháng cuối còn hiệu lực = tháng thầu + số tháng hiệu lực − 1'
              : 'Chưa liên kết hợp đồng: tháng cuối còn hiệu lực = tháng thầu + 3 tháng + số tháng hiệu lực − 1'
          }
        >
          {HIEN_HET_HIEU_LUC && tt === 'het' ? `(đã hết hiệu lực từ sau ${het})` : `(hiệu lực đến hết ${het})`}
          {coHd && !hdTag && <span className="ml-1 text-emerald-700">· theo HĐ</span>}
        </span>
      )}
      {hdTag}
    </span>
  );
}

// Danh sách đợt thầu của 1 nhóm SP, thay cho 2 ô tháng cố định trước đây.
// Mỗi đợt bắt buộc có tháng thầu + hiệu lực (số tháng). Thêm đợt thì mở bảng nhập
// quota (onThemDot): đợt mới lưu cùng quota, không tạo đợt rỗng.
export function DotThauPanel({ fy, ps, custId, grp, locked, onThemDot }) {
  const ctx = useContext(QuotaThauCtx);
  const [busy, setBusy] = useState(false);
  const [err, setErr] = useState('');
  const all = (ctx && ctx.dotsByGroup.get(grpKey(fy, ps, custId, grp))) || [];
  const hd = useHopDongNhom(fy, ps, custId, grp, all.some((d) => d.coHd));
  if (!ctx) return null;
  // Số dòng (SP × mức giá) có quota > 0 của từng đợt, để ghi "phủ a/b SP".
  const soSpDot = new Map();
  for (const q of ctx.quotasByGroup?.get(grpKey(fy, ps, custId, grp)) || []) {
    if (!(Number(q.qty) > 0)) continue;
    const k = `${q.loai}|${q.dot}`;
    if (!soSpDot.has(k)) soSpDot.set(k, new Set());
    soSpDot.get(k).add(lineKey(q.mset, q.prod, q.price));
  }
  const tagDot = (loai, dot) => {
    const info = hd.theoDot.get(`${loai}|${dot}`);
    return info ? <DotHopDongTag info={info} soSp={soSpDot.get(`${loai}|${dot}`)?.size || 0} /> : null;
  };
  const cua = (loai) =>
    all.filter((d) => d.loai === loai).sort((a, b) => a.dot - b.dot);
  const chinh = cua('chinh');
  const bs = cua('bo_sung');
  // Thầu cũ: 1 đợt duy nhất, chỉ mang tháng thầu / hiệu lực (tự điền theo HĐ đã liên kết,
  // chưa có thì trống). Quota thầu cũ vẫn tính đủ vào on hand, không theo tháng / hiệu lực.
  const coQuotaCu = (ctx.cuByGroup?.get(grpKey(fy, ps, custId, grp)) || 0) > 0;
  const dotCu = cua('cu')[0] || null;

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
      {list.length === 0 && (
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
            coHd={!!d.coHd}
            hdTag={d.coHd ? tagDot(loai, d.dot) : null}
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
      {!locked && onThemDot && (
        <button
          onClick={() => {
            setErr('');
            onThemDot(loai);
          }}
          disabled={busy}
          title="Thêm đợt: mở bảng nhập quota, điền tháng thầu, hiệu lực và quota rồi lưu một lần"
          className="text-[11px] font-semibold px-1.5 py-0.5 rounded border border-blue-200 text-blue-700 bg-white hover:bg-blue-50 disabled:opacity-50"
        >
          + đợt
        </button>
      )}
    </div>
  );

  const hangCu = () => (
    <div className="flex items-center gap-2 flex-wrap">
      <span className="text-[10.5px] font-semibold text-blue-800 uppercase tracking-wide whitespace-nowrap">
        {LOAI_LABEL.cu}
      </span>
      {coQuotaCu || dotCu ? (
        <DotEditor
          thang={dotCu?.thang || ''}
          thoiGian={dotCu?.thoiGian ?? ''}
          coHd={!!dotCu?.coHd}
          hdTag={dotCu?.coHd ? tagDot('cu', 1) : null}
          locked={locked || busy || !coQuotaCu}
          curMonth={CURRENT_MONTH}
          onSave={(t, h) => sua('cu', 1, t, h)}
        />
      ) : (
        <span className="text-[11px] text-slate-400">chưa có quota thầu cũ</span>
      )}
      {coQuotaCu && !dotDuThongTin(dotCu) && (
        <span
          className="text-[11px] text-amber-700"
          title="Chưa khớp được hợp đồng ký trước năm tài chính cho nhóm này. Điền tay hoặc xử lý ở tab Kiểm tra thông tin thầu."
        >
          chưa khớp HĐ
        </span>
      )}
    </div>
  );

  const soThieu = all.filter((d) => d.loai !== 'cu' && !dotDuThongTin(d)).length;
  return (
    <div className="flex flex-col gap-1.5">
      {hangCu()}
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
  const coLienKet = dots.some((d) => d.coHd);
  const hd = useHopDongNhom(fy, ps, custId, grp, coLienKet);
  const [moRong, setMoRong] = useState(() => new Set()); // lineKey đang bung chi tiết HĐ
  const doiMoRong = (k) =>
    setMoRong((s) => {
      const n = new Set(s);
      if (n.has(k)) n.delete(k);
      else n.add(k);
      return n;
    });
  // Đợt đang thêm trong modal: chưa có trên DB, lưu cùng quota của nó khi bấm Lưu.
  // Số đợt chốt lúc thêm (max + 1) để khoá ô nhập không đổi khi bỏ đợt khác.
  const [moi, setMoi] = useState(() =>
    focus && focus.themDot
      ? [{ loai: focus.themDot, dot: dots.filter((d) => d.loai === focus.themDot).reduce((m, d) => Math.max(m, d.dot), 0) + 1, thang: '', thoiGian: '' }]
      : [],
  );
  // Cột: thầu cũ luôn có (không thuộc đợt nào), rồi tới từng đợt đã khai báo / đang thêm.
  const cols = useMemo(() => {
    // Đợt thầu cũ (chỉ mang tháng / hiệu lực) gắn vào cột thầu cũ cố định, không thành cột riêng.
    const cu = dots.find((d) => d.loai === 'cu');
    const ds = [...dots.filter((d) => d.loai !== 'cu'), ...moi.map((m) => ({ ...m, moi: true }))].sort((a, b) =>
      a.loai === b.loai ? a.dot - b.dot : a.loai === 'chinh' ? -1 : 1,
    );
    const nChinh = ds.filter((d) => d.loai === 'chinh').length;
    const nBs = ds.filter((d) => d.loai === 'bo_sung').length;
    return [
      {
        loai: 'cu',
        dot: 1,
        label: LOAI_LABEL.cu,
        thang: '',
        du: true,
        infoCu: dotDuThongTin(cu) ? `Từ ${cu.thang} · hiệu lực ${Number(cu.thoiGian)} tháng${cu.coHd ? ' · theo HĐ' : ''}` : '',
      },
    ].concat(
      ds.map((d) => ({
        loai: d.loai,
        dot: d.dot,
        moi: !!d.moi,
        thang: d.thang,
        thoiGian: d.thoiGian,
        du: dotDuThongTin(d),
        coHd: !!d.coHd,
        het: hetHanDot(d.thang, d.thoiGian, d.coHd),
        trangThai: dotDuThongTin(d) ? trangThaiDot(d.thang, d.thoiGian, CURRENT_MONTH, undefined, d.coHd) : 'up',
        label: dotLabel(d.loai, d.dot, d.loai === 'chinh' ? nChinh : nBs),
      })),
    );
  }, [dots, moi]);
  const themDot = (loai) =>
    setMoi((ms) => [
      ...ms,
      {
        loai,
        dot: [...dots, ...ms].filter((d) => d.loai === loai).reduce((m, d) => Math.max(m, d.dot), 0) + 1,
        thang: '',
        thoiGian: '',
      },
    ]);
  const suaDotMoi = (loai, dot, patch) =>
    setMoi((ms) => ms.map((m) => (m.loai === loai && m.dot === dot ? { ...m, ...patch } : m)));
  // Chỉ bỏ được đợt mới thêm sau cùng của mỗi loại, để số đợt không bị thủng.
  const boDotMoi = (loai, dot) => {
    setMoi((ms) => ms.filter((m) => !(m.loai === loai && m.dot === dot)));
    setDraft((d) => Object.fromEntries(Object.entries(d).filter(([k]) => !k.endsWith(`|${loai}|${dot}`))));
  };
  const laDotMoiCuoi = (c) =>
    c.moi && !moi.some((m) => m.loai === c.loai && m.dot > c.dot);

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
    focus.prod != null &&
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
    // Đợt mới phải đủ tháng thầu, hiệu lực và có giá trị thầu (ít nhất 1 quota > 0).
    const dotsMoi = [];
    for (const c of cols) {
      if (!c.moi) continue;
      if (!c.du) {
        setErr(`${c.label} (mới): điền tháng thầu (yyyy-mm) và hiệu lực (số tháng) ở đầu cột.`);
        return;
      }
      if (!rows.some((r) => r.loai === c.loai && r.dot === c.dot && r.qty > 0)) {
        setErr(`${c.label} (mới): nhập quota cho ít nhất một sản phẩm — đợt không có quota sẽ không được lưu.`);
        return;
      }
      dotsMoi.push({ fy, ps, custId, grp, loai: c.loai, dot: c.dot, thang: c.thang.trim(), thoiGian: Number(c.thoiGian) });
    }
    if (!rows.length) {
      onClose();
      return;
    }
    setBusy(true);
    setErr('');
    try {
      await ctx.saveQuota(rows, dotsMoi);
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
        <div className="flex items-start gap-2 mb-2">
          <div className="text-[11.5px] text-slate-500">
            Nhập cho mọi sản phẩm của nhóm trong một lần. Mỗi mức giá là một gói
            thầu riêng. Để trống hoặc nhập 0 để xoá quota của ô đó. Đợt mới phải
            có tháng thầu, hiệu lực và quota mới lưu được.
          </div>
          {!locked && (
            <div className="ml-auto flex items-center gap-1.5 shrink-0">
              {['chinh', 'bo_sung'].map((loai) => (
                <button
                  key={loai}
                  onClick={() => themDot(loai)}
                  disabled={busy}
                  className="text-[11px] font-semibold px-1.5 py-0.5 rounded border border-blue-200 text-blue-700 bg-white hover:bg-blue-50 disabled:opacity-50 whitespace-nowrap"
                >
                  + {LOAI_LABEL[loai]}
                </button>
              ))}
            </div>
          )}
        </div>
        {cols.length === 1 && (
          <div className="text-[11.5px] text-amber-700 bg-amber-50 border border-amber-200 rounded-md px-2 py-1.5 mb-2">
            Nhóm SP này chưa có đợt thầu nào. Bấm “+ {LOAI_LABEL.chinh}” để thêm
            đợt, điền tháng thầu, hiệu lực và quota rồi lưu.
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
                    {c.moi && (
                      <div className="mt-1 flex flex-col items-end gap-1 font-normal">
                        <span className="text-[10px] text-blue-700">
                          đợt mới
                          {laDotMoiCuoi(c) && (
                            <button
                              onClick={() => boDotMoi(c.loai, c.dot)}
                              className="ml-1 text-slate-400 hover:text-red-600"
                              title="Bỏ đợt mới này"
                            >
                              ✕
                            </button>
                          )}
                        </span>
                        <input
                          value={c.thang}
                          onChange={(e) => suaDotMoi(c.loai, c.dot, { thang: e.target.value })}
                          disabled={busy}
                          placeholder="yyyy-mm"
                          title="Tháng thầu, dạng năm-tháng, ví dụ 2026-07 (bắt buộc)"
                          className={`w-[74px] text-[11px] text-right px-1.5 py-0.5 rounded border outline-none ${THANG_RE.test(c.thang.trim()) ? 'border-slate-200' : 'border-red-400 bg-red-50'}`}
                        />
                        <span className="inline-flex items-center gap-1 text-[10px] text-slate-500">
                          <input
                            value={c.thoiGian}
                            onChange={(e) => suaDotMoi(c.loai, c.dot, { thoiGian: e.target.value.replace(/[^0-9]/g, '') })}
                            disabled={busy}
                            placeholder="HL"
                            title="Hiệu lực: số tháng, ví dụ 12, 18, 24 (bắt buộc)"
                            className={`w-[40px] text-[11px] text-right px-1.5 py-0.5 rounded border outline-none ${hieuLucHopLe(c.thoiGian) ? 'border-slate-200' : 'border-red-400 bg-red-50'}`}
                          />
                          tháng
                        </span>
                      </div>
                    )}
                    {c.infoCu && (
                      <div className="text-[10px] font-normal text-slate-400" title="Thông tin thầu cũ (theo HĐ ký trước năm tài chính)">
                        {c.infoCu}
                      </div>
                    )}
                    {!c.moi && hd.theoDot.get(`${c.loai}|${c.dot}`) && (
                      <div className="mt-0.5 font-normal">
                        <DotHopDongTag info={hd.theoDot.get(`${c.loai}|${c.dot}`)} gon />
                      </div>
                    )}
                    {c.loai !== 'cu' && !c.moi && (
                      <div
                        className={`text-[10px] font-normal ${!c.du ? 'text-red-600' : HIEN_HET_HIEU_LUC && c.trangThai === 'het' ? 'text-red-500' : 'text-slate-400'}`}
                        title={c.du ? `Tháng thầu ${c.thang}, hiệu lực ${c.thoiGian} tháng, hết hạn ${c.het}` : 'Đợt chưa đủ tháng thầu / hiệu lực'}
                      >
                        {!c.du
                          ? 'thiếu tháng thầu / hiệu lực'
                          : `Từ ${c.thang} · hiệu lực ${Number(c.thoiGian)} tháng${c.coHd ? ' · theo HĐ' : ''}${HIEN_HET_HIEU_LUC && c.trangThai === 'het' ? ' · hết HL' : ''}`}
                      </div>
                    )}
                  </th>
                ))}
                <th className="px-2 py-1.5 text-right font-semibold text-slate-600 border-b border-r border-slate-200 bg-white">
                  Tổng
                </th>
                {coLienKet && (
                  <th
                    className="px-2 py-1.5 text-left font-semibold text-slate-600 border-b border-slate-200 bg-white whitespace-nowrap"
                    title="Hợp đồng đã gắn với quota on hand của dòng. Bấm vào ô để xem từng dòng hợp đồng."
                  >
                    Hợp đồng
                    {!hd.co && !hd.err && <div className="text-[10px] font-normal text-slate-400">đang tải…</div>}
                    {hd.err && <div className="text-[10px] font-normal text-red-600">{hd.err}</div>}
                  </th>
                )}
              </tr>
            </thead>
            <tbody>
              {lines.map((line, i) => {
                let tong = 0;
                for (const c of cols) tong += Number(val(line, c)) || 0;
                const dangXem = laDongDangXem(line);
                const doiSp = i === 0 || lines[i - 1].prod !== line.prod;
                const lk = lineKey(line.mset, line.prod, line.price);
                const oHd = (c) => hd.theoO.get(`${lk}|${c.loai}|${c.dot}`);
                return (
                  <React.Fragment key={key(line, { loai: '_', dot: 0 })}>
                  <tr
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
                    {cols.map((c) => {
                      // Ô đã gắn HĐ: viền xanh nếu SL gắn đủ quota đã lưu, vàng nếu một phần.
                      const o = c.moi ? null : oHd(c);
                      const q = Number(cell(line, c)) || 0;
                      const vien = !o ? 'border-slate-200' : o.sl >= q - 1e-9 ? 'border-emerald-400 bg-emerald-50/40' : 'border-amber-400 bg-amber-50/40';
                      return (
                        <td
                          key={c.loai + c.dot}
                          className="px-1 py-1 border-b border-r border-slate-100"
                        >
                          <input
                            value={val(line, c)}
                            disabled={locked || busy || (!c.du && cell(line, c) === '')}
                            title={
                              c.moi && !c.du
                                ? 'Điền tháng thầu và hiệu lực ở đầu cột trước'
                                : !c.du
                                  ? 'Đợt chưa đủ tháng thầu / hiệu lực: chỉ xoá hoặc đưa về 0 được'
                                  : o
                                    ? `Đã gắn HĐ: ${[...o.hds].join(', ')} · SL gắn ${fmtInt(o.sl)}/${fmtInt(q)}`
                                    : undefined
                            }
                            onChange={(e) =>
                              setDraft((d) => ({
                                ...d,
                                [key(line, c)]: e.target.value,
                              }))
                            }
                            className={`w-[74px] text-[12px] text-right px-1.5 py-1 rounded border ${vien} tabular-nums outline-none focus:border-emerald-500 focus:ring-2 focus:ring-emerald-100 disabled:bg-slate-50`}
                          />
                        </td>
                      );
                    })}
                    <td className={`px-2 py-1 text-right tabular-nums font-semibold text-slate-800 border-b border-slate-100 ${coLienKet ? 'border-r' : ''}`}>
                      {fmtInt(tong)}
                    </td>
                    {coLienKet && (
                      <td className="px-2 py-1 border-b border-slate-100 whitespace-nowrap">
                        <ChipHopDong
                          hd={hd}
                          lk={lk}
                          cols={cols}
                          qtyCua={(c) => Number(cell(line, c)) || 0}
                          mo={moRong.has(lk)}
                          onClick={() => doiMoRong(lk)}
                        />
                      </td>
                    )}
                  </tr>
                  {coLienKet && moRong.has(lk) && (
                    <tr>
                      <td colSpan={cols.length + 4} className="px-3 py-2 bg-slate-50 border-b border-slate-200">
                        {/* Bảng quota cuộn ngang: giữ chi tiết HĐ bám mép trái khung cuộn. */}
                        <div className="sticky left-3 w-fit">
                          <ChiTietHopDong links={hd.theoDong.get(lk) || []} cols={cols} />
                        </div>
                      </td>
                    </tr>
                  )}
                  </React.Fragment>
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

// Chip HĐ của 1 dòng quota (SP × mức giá). Tỷ lệ phủ = SL đã gắn / SL quota của các ô
// on hand (thầu cũ + đợt đang hiệu lực) và các ô có liên kết. Đợt upcoming chưa có HĐ
// không kéo tỷ lệ xuống.
function ChipHopDong({ hd, lk, cols, qtyCua, mo, onClick }) {
  if (!hd.co) return <span className="text-[11px] text-slate-300">…</span>;
  const links = hd.theoDong.get(lk) || [];
  let qOn = 0;
  let qLk = 0;
  for (const c of cols) {
    if (c.moi) continue;
    const q = qtyCua(c);
    const o = hd.theoO.get(`${lk}|${c.loai}|${c.dot}`);
    if (!o && !(c.loai === 'cu' || c.trangThai === 'on')) continue;
    qOn += q;
    qLk += Math.min(o ? o.sl : 0, q);
  }
  if (!links.length) {
    return qOn > 0 ? (
      <span
        className="inline-flex items-center text-[11px] px-1.5 py-0.5 rounded border border-dashed border-slate-300 text-slate-400"
        title="Quota on hand của dòng này chưa gắn hợp đồng nào. Xử lý ở tab Kiểm tra thông tin thầu."
      >
        chưa có HĐ
      </span>
    ) : (
      <span className="text-[11px] text-slate-300" title="Chỉ có quota upcoming, chưa cần hợp đồng">
        —
      </span>
    );
  }
  const hds = [...new Set(links.map(soHd))];
  const tyLe = qOn > 0 ? qLk / qOn : 1;
  const du = tyLe >= 0.999;
  const lech = links.some((r) => (r.loai === 'cu') !== (r.cua_so === 'quota_1_4'));
  return (
    <button
      type="button"
      onClick={onClick}
      title={`${hds.join('\n')}\nĐã gắn ${fmtInt(qLk)}/${fmtInt(qOn)} quota on hand. Bấm để ${mo ? 'thu gọn' : 'xem từng dòng hợp đồng'}.`}
      className={`inline-flex items-center gap-1 text-[11px] px-1.5 py-0.5 rounded border ${du ? 'bg-emerald-50 border-emerald-200 text-emerald-800 hover:bg-emerald-100' : 'bg-amber-50 border-amber-200 text-amber-800 hover:bg-amber-100'}`}
    >
      <span className="font-semibold">{hds.length > 1 ? `${hds.length} HĐ` : ngan(hds[0])}</span>
      {!du && <span>· {Math.round(tyLe * 100)}%</span>}
      {lech && <span className="text-red-600" title="Có liên kết lệch cửa sổ (thầu cũ ↔ HĐ ký trong năm)">⚠</span>}
      <span className="text-slate-400">{mo ? '▴' : '▾'}</span>
    </button>
  );
}

// Bảng chi tiết dòng HĐ của 1 dòng quota: gộp theo đợt × HĐ × mã chung.
function ChiTietHopDong({ links, cols }) {
  const nhom = new Map();
  for (const r of links) {
    const k = `${r.loai}|${r.dot}|${r.ma_hd}|${r.ma_chung || ''}`;
    const g = nhom.get(k) || { ...r, slGan: 0, cach: new Set() };
    g.slGan += Number(r.sl_quota) || 0;
    g.cach.add(r.cach_gan);
    nhom.set(k, g);
  }
  const ds = [...nhom.values()];
  const nhanDot = (r) => cols.find((c) => c.loai === r.loai && c.dot === r.dot)?.label || r.loai;
  const th = 'px-2 py-1 text-left font-semibold text-slate-500 whitespace-nowrap';
  const td = 'px-2 py-1 border-t border-slate-200 whitespace-nowrap';
  return (
    <table className="text-[11px] border-collapse">
      <thead>
        <tr>
          <th className={th}>Đợt</th>
          <th className={th}>Số HĐ</th>
          <th className={th}>Ký</th>
          <th className={th}>Hết hạn</th>
          <th className={th}>Hàng hoá trên HĐ</th>
          <th className={`${th} text-right`}>SL gắn</th>
          <th className={`${th} text-right`}>SL dòng HĐ</th>
          <th className={`${th} text-right`}>Đã bán</th>
          <th className={`${th} text-right`}>Còn lại</th>
          <th className={`${th} text-right`}>Giá HĐ</th>
          <th className={th}>Nguồn</th>
        </tr>
      </thead>
      <tbody>
        {ds.map((r) => {
          const lech = (r.loai === 'cu') !== (r.cua_so === 'quota_1_4');
          const dong = r.sl_hd_dong == null ? null : Number(r.sl_hd_dong);
          const ban = Number(r.sl_da_ban) || 0;
          return (
            <tr key={`${r.loai}|${r.dot}|${r.ma_hd}|${r.ma_chung || ''}`}>
              <td className={td}>{nhanDot(r)}</td>
              <td className={`${td} font-semibold text-slate-700`} title={r.ma_hd}>
                {soHd(r)}
              </td>
              <td className={td}>{thangNam(r.ngay_ky)}</td>
              <td className={td}>{thangNam(r.thoi_han)}</td>
              <td className={`${td} max-w-[260px]`}>
                <div className="truncate" title={`${r.ma_chung || ''} · ${r.ten_hang_hoa || ''}`}>
                  <span className="text-slate-500">{r.ma_chung || '—'}</span>
                  {r.ten_hang_hoa ? ` · ${r.ten_hang_hoa}` : ''}
                </div>
              </td>
              <td className={`${td} text-right tabular-nums`}>{fmtInt(r.slGan)}</td>
              <td className={`${td} text-right tabular-nums`}>{dong == null ? '—' : fmtInt(dong)}</td>
              <td className={`${td} text-right tabular-nums`}>{fmtInt(ban)}</td>
              <td className={`${td} text-right tabular-nums`}>{dong == null ? '—' : fmtInt(dong - ban)}</td>
              <td className={`${td} text-right tabular-nums`}>{r.gia_hd == null ? '—' : fmtInt(Number(r.gia_hd))}</td>
              <td className={td}>
                {r.cach.has('tay') ? 'gắn tay' : 'tự động'}
                {lech && (
                  <span
                    className="ml-1 text-red-600"
                    title="Lệch cửa sổ: thầu cũ gắn HĐ ký trong năm, hoặc thầu chính / bổ sung gắn HĐ ký trước năm. Xử lý ở tab Kiểm tra thông tin thầu."
                  >
                    ⚠ lệch cửa sổ
                  </span>
                )}
              </td>
            </tr>
          );
        })}
      </tbody>
    </table>
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
