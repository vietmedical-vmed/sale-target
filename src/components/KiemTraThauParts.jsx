import { useState, useEffect, useMemo, Fragment } from 'react';
import { ChevronDown, ChevronRight, Loader2, AlertCircle, Trash2, Pencil } from './icons.jsx';
import { Modal } from './Modal.jsx';
import { api } from '../api/client.js';
import { fmtInt, moneyTy3 } from '../lib/format.js';
import { TRANG_THAI, trangThaiCua, LOAI_DOT } from '../lib/kiemTraThau.js';
import { CURRENT_MONTH } from '../config/constants.js';

// ---------- ô trạng thái xử lý của 1 việc ----------
export function XuLyPill({ rec, onClick }) {
  const tt = trangThaiCua(rec);
  const meta = TRANG_THAI[tt];
  const tip = [
    rec && rec.nguoi_phu_trach ? 'Phụ trách: ' + rec.nguoi_phu_trach : '',
    rec && rec.ghi_chu ? 'Ghi chú: ' + rec.ghi_chu : '',
    rec && rec.cap_nhat_boi
      ? `Cập nhật: ${rec.cap_nhat_boi} · ${new Date(rec.cap_nhat_luc).toLocaleString('vi-VN')}`
      : '',
  ]
    .filter(Boolean)
    .join('\n');
  return (
    <button
      type="button"
      onClick={onClick}
      title={(tip ? tip + '\n' : '') + 'Bấm để cập nhật'}
      className={`inline-flex items-center gap-1 max-w-[180px] px-2 py-0.5 rounded text-[11px] font-medium hover:ring-2 hover:ring-slate-200 ${meta.cls}`}
    >
      <span className="truncate">
        {meta.label}
        {tt === 'dang_xu_ly' && rec.nguoi_phu_trach ? ' · ' + rec.nguoi_phu_trach : ''}
      </span>
      {rec && rec.ghi_chu && tt !== 'chua' && <Pencil size={10} className="shrink-0 opacity-60" />}
    </button>
  );
}

// ---------- popup cập nhật xử lý (1 hoặc nhiều việc) ----------
// items: [{buoc, key, bu, ps, moTa}]; recs: Map khoaXuLy → bản ghi hiện tại.
export function XuLyModal({ items, rec, psOptions, onSave, onClose }) {
  const mot = items.length === 1;
  const [tt, setTt] = useState(mot ? trangThaiCua(rec) : 'dang_xu_ly');
  const [nguoi, setNguoi] = useState((mot && rec && rec.nguoi_phu_trach) || (mot ? items[0].ps || '' : ''));
  const [ghiChu, setGhiChu] = useState((mot && rec && rec.ghi_chu) || '');
  const [busy, setBusy] = useState(false);
  const [loi, setLoi] = useState('');
  const luu = async () => {
    if (tt === 'bo_qua' && !ghiChu.trim()) {
      setLoi('Bỏ qua cần ghi lý do, ví dụ "BV tư không ký HĐ".');
      return;
    }
    setBusy(true);
    setLoi('');
    try {
      await onSave({ trangThai: tt === 'chua' ? null : tt, nguoiPhuTrach: nguoi.trim(), ghiChu: ghiChu.trim() });
      onClose();
    } catch (e) {
      setLoi(e.message);
      setBusy(false);
    }
  };
  return (
    <Modal
      open
      onClose={onClose}
      title={mot ? 'Cập nhật xử lý' : `Cập nhật xử lý ${items.length} việc`}
      width={520}
      footer={
        <div className="flex items-center justify-end gap-2 px-4 py-3 border-t border-slate-100">
          <button onClick={onClose} className="px-3 py-1.5 text-[13px] rounded-md border border-slate-200 hover:bg-slate-50">
            Huỷ
          </button>
          <button
            onClick={luu}
            disabled={busy}
            className="inline-flex items-center gap-1.5 px-3 py-1.5 text-[13px] font-medium rounded-md bg-emerald-600 text-white hover:bg-emerald-700 disabled:opacity-60"
          >
            {busy && <Loader2 size={14} className="animate-spin" />}
            Lưu
          </button>
        </div>
      }
    >
      <div className="p-4 space-y-3 text-[13px]">
        {mot ? (
          <div className="text-[12px] text-slate-500">{items[0].moTa}</div>
        ) : (
          <div className="text-[12px] text-slate-500 max-h-24 overflow-y-auto">
            {items.slice(0, 8).map((x) => (
              <div key={x.key} className="truncate">
                {x.moTa}
              </div>
            ))}
            {items.length > 8 && <div>… và {items.length - 8} việc khác</div>}
          </div>
        )}
        <div className="flex gap-2 flex-wrap">
          {['chua', 'dang_xu_ly', 'bo_qua'].map((k) => (
            <button
              key={k}
              type="button"
              onClick={() => setTt(k)}
              className={`px-2.5 py-1 rounded-md text-[12px] border ${tt === k ? 'border-emerald-500 ring-2 ring-emerald-100 text-emerald-800 bg-emerald-50' : 'border-slate-200 text-slate-600 hover:bg-slate-50'}`}
            >
              {TRANG_THAI[k].label}
            </button>
          ))}
        </div>
        {tt !== 'chua' && (
          <label className="block">
            <span className="text-[12px] text-slate-500">Người phụ trách</span>
            <input
              list="kt-ps-list"
              value={nguoi}
              onChange={(e) => setNguoi(e.target.value)}
              placeholder={mot ? items[0].ps || 'Tên PS' : 'Để trống: mỗi việc giao cho PS của việc đó'}
              className="mt-1 w-full px-2.5 py-1.5 border border-slate-200 rounded-md outline-none focus:border-emerald-500 focus:ring-2 focus:ring-emerald-100"
            />
            <datalist id="kt-ps-list">
              {psOptions.map((p) => (
                <option key={p} value={p} />
              ))}
            </datalist>
          </label>
        )}
        {tt !== 'chua' && (
          <label className="block">
            <span className="text-[12px] text-slate-500">
              Ghi chú{tt === 'bo_qua' ? ' (bắt buộc: lý do bỏ qua)' : ''}
            </span>
            <textarea
              value={ghiChu}
              onChange={(e) => {
                setGhiChu(e.target.value);
                setLoi('');
              }}
              rows={3}
              placeholder={tt === 'bo_qua' ? 'BV tư không ký HĐ' : 'Đã hỏi ngành hàng, chờ HĐ tháng 12'}
              className="mt-1 w-full px-2.5 py-1.5 border border-slate-200 rounded-md outline-none focus:border-emerald-500 focus:ring-2 focus:ring-emerald-100"
            />
          </label>
        )}
        {tt === 'chua' && (
          <div className="text-[12px] text-slate-500">Xoá trạng thái, việc trở về danh sách chưa xử lý.</div>
        )}
        {loi && <div className="text-[12px] text-red-600">{loi}</div>}
      </div>
    </Modal>
  );
}

// ---------- bảng gom nhóm ----------
// groups: [{key, label, items, giaTri}]; cols: [{label, cls}]; renderRow(item) → <tr>.
const MAX_DONG = 200;
export function BangNhom({ groups, cols, renderRow, selected, onToggleAll, emptyText, fmtGiaTri = moneyTy3 }) {
  const tong = groups.reduce((s, g) => s + g.items.length, 0);
  const [mo, setMo] = useState(() => new Set());
  const [them, setThem] = useState({});
  const moHet = tong <= 60;
  const sigNhom = groups.map((g) => g.key).join('|');
  useEffect(() => {
    setMo(new Set());
    setThem({});
  }, [sigNhom]);
  const isOpen = (k) => (moHet ? !mo.has(k) : mo.has(k));
  const toggle = (k) =>
    setMo((p) => {
      const s = new Set(p);
      s.has(k) ? s.delete(k) : s.add(k);
      return s;
    });
  const phang = groups.length === 1 && groups[0].key === '';
  const allKeys = groups.flatMap((g) => g.items.map((x) => x.key));
  const allSel = allKeys.length > 0 && allKeys.every((k) => selected.has(k));
  const th = 'px-3 py-2 font-semibold text-slate-600 whitespace-nowrap';
  return (
    <div className="bg-white rounded-lg border border-slate-200 overflow-x-auto">
      <table className="w-full text-[12px]">
        <thead>
          <tr className="bg-slate-50 border-b border-slate-200">
            <th className="px-3 py-2 w-8">
              <input
                type="checkbox"
                checked={allSel}
                onChange={() => onToggleAll(allKeys, !allSel)}
                title="Chọn tất cả việc đang lọc"
              />
            </th>
            {cols.map((c, i) => (
              <th key={i} className={`${th} ${c.cls || 'text-left'}`}>
                {c.label}
              </th>
            ))}
          </tr>
        </thead>
        <tbody>
          {tong === 0 ? (
            <tr>
              <td colSpan={cols.length + 1} className="px-3 py-8 text-center text-slate-400">
                {emptyText}
              </td>
            </tr>
          ) : (
            groups.map((g) => {
              const open = phang || isOpen(g.key);
              const lim = them[g.key] || MAX_DONG;
              const gKeys = g.items.map((x) => x.key);
              const gSel = gKeys.every((k) => selected.has(k));
              return (
                <Fragment key={g.key}>
                  {!phang && (
                    <tr className="bg-slate-50/70 border-b border-slate-200">
                      <td className="px-3 py-1.5">
                        <input
                          type="checkbox"
                          checked={gSel}
                          onChange={() => onToggleAll(gKeys, !gSel)}
                          title="Chọn cả nhóm"
                        />
                      </td>
                      <td colSpan={cols.length} className="px-2 py-1.5">
                        <button
                          type="button"
                          onClick={() => toggle(g.key)}
                          className="flex items-center gap-1.5 text-left w-full"
                        >
                          {open ? <ChevronDown size={14} /> : <ChevronRight size={14} />}
                          <span className="font-semibold text-slate-700">{g.label}</span>
                          <span className="text-slate-400 tabular-nums">
                            · {fmtInt(g.items.length)} việc
                            {g.giaTri ? ' · ' + fmtGiaTri(g.giaTri) : ''}
                          </span>
                        </button>
                      </td>
                    </tr>
                  )}
                  {open && g.items.slice(0, lim).map(renderRow)}
                  {open && g.items.length > lim && (
                    <tr className="border-b border-slate-100">
                      <td colSpan={cols.length + 1} className="px-3 py-1.5 text-center">
                        <button
                          type="button"
                          onClick={() => setThem((p) => ({ ...p, [g.key]: lim + MAX_DONG }))}
                          className="text-[12px] text-blue-600 hover:underline"
                        >
                          Hiện thêm {fmtInt(Math.min(MAX_DONG, g.items.length - lim))} / còn{' '}
                          {fmtInt(g.items.length - lim)} việc
                        </button>
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
  );
}

// ---------- chi tiết 1 khoá KH × SP: dòng quota, dòng HĐ, liên kết ----------
const TT_QUOTA = { cu: 'Quota 1.4', on: 'On hand', up: 'Upcoming', het: 'Hết HL' };
const CUA_SO_HD = { truoc: 'Ký trước năm TC', trong: 'Ký trong năm' };
const KQ_CLS = {
  'Chỉ có quota': 'bg-amber-50 text-amber-800',
  'Chỉ có HĐ': 'bg-amber-50 text-amber-800',
  'Quota > HĐ': 'bg-red-50 text-red-700',
  'HĐ > quota': 'bg-red-50 text-red-700',
  'HĐ đã bán hết trước 1/4': 'bg-red-50 text-red-700',
};
export const KqPill = ({ kq }) => (
  <span className={`inline-block px-1.5 py-0.5 rounded text-[11px] font-medium whitespace-nowrap ${KQ_CLS[kq] || 'bg-slate-100 text-slate-600'}`}>
    {kq}
  </span>
);

// Cửa sổ của dòng quota: 1.4 ứng với HĐ ký trước năm TC ('truoc'), chính / BS ứng với HĐ ký
// trong năm ('trong'). Gắn khác cửa sổ = dấu hiệu quota bị phân loại nhầm.
const khacCuaSo = (ttQuota, cuaSoHd) =>
  (ttQuota === 'cu' && cuaSoHd === 'trong') || (ttQuota !== 'cu' && cuaSoHd === 'truoc');
// Hiệu lực theo HĐ = số tháng tính cả tháng ký lẫn tháng hết hạn, để tháng hết hiệu lực
// (tháng thầu + HL − 1) trùng tháng hết hạn HĐ (migration 20261125110000).
const soThang = (tu, den) => {
  if (!tu || !den) return null;
  const [y1, m1] = tu.split('-').map(Number);
  const [y2, m2] = den.split('-').map(Number);
  const n = y2 * 12 + m2 - (y1 * 12 + m1) + 1;
  return n >= 1 && n <= 120 ? n : null;
};

// Mã dưới tên SP / hàng hoá, cùng định dạng cho dòng quota và dòng HĐ để dễ so: mã chung
// (danh mục HĐ) + mã SP (danh mục kế hoạch). Mã nào không tra được trong danh mục thì '—'.
function HaiMa({ maChung, maSp }) {
  return (
    <div className="text-[10.5px] text-slate-400 whitespace-nowrap">
      <span title="Mã chung (dm_vat_tu / dm_bo_vat_tu)">MC: {maChung || '—'}</span>
      <span className="mx-1">·</span>
      <span title="Mã sản phẩm / mã bộ">Mã SP: {maSp || '—'}</span>
    </div>
  );
}

export function ChiTietKhoaModal({ viec, hdRows, isAdmin, canEdit, onClose, onDaDoi, onSuaQuota, dotsOf, onQuotaDoi }) {
  const r = viec.row;
  const [data, setData] = useState(null);
  const [loi, setLoi] = useState('');
  const [busy, setBusy] = useState(false);
  const [chonQ, setChonQ] = useState(null);
  const [chonH, setChonH] = useState(null);
  const [sl, setSl] = useState('');
  // khung chuyển quota theo HĐ ký trong năm (1.4 → chính / BS, upcoming → đợt on hand)
  const [cv, setCv] = useState({ sl: '', slDich: '', dot: '', loai: 'chinh', thang: '', hl: '' });
  const tai = () => {
    setLoi('');
    api('ktChiTietKhoa', { kh: r.kh, khoa: r.khoa })
      .then(setData)
      .catch((e) => setLoi(e.message));
  };
  useEffect(tai, [r.kh, r.khoa]);
  const quota = useMemo(() => data?.quota || [], [data]);
  const hopDong = useMemo(() => data?.hopDong || [], [data]);
  const lienKet = useMemo(() => data?.lienKet || [], [data]);
  const daLkQ = useMemo(() => {
    const m = new Map();
    for (const l of lienKet) m.set(l.quotaId, (m.get(l.quotaId) || 0) + Number(l.slQuota || 0));
    return m;
  }, [lienKet]);
  const daLkH = useMemo(() => {
    const m = new Map();
    for (const l of lienKet) m.set(l.itemId, (m.get(l.itemId) || 0) + Number(l.slHd || 0));
    return m;
  }, [lienKet]);
  // Ứng viên ghép mã: khoá cùng KH, cùng cửa sổ, kết quả ngược chiều (chỉ có HĐ ↔ chỉ có quota).
  const ungVien = useMemo(() => {
    const kq = viec.kq;
    if (kq !== 'Chỉ có quota' && kq !== 'Chỉ có HĐ') return [];
    const nguoc = kq === 'Chỉ có quota' ? 'Chỉ có HĐ' : 'Chỉ có quota';
    const nhom = String(r.nhom || '').split(',').map((x) => x.trim());
    return hdRows
      .filter((x) => x.kh === r.kh && x.khoa !== r.khoa && (viec.cuaSo === 'fy' ? x.kqFy : x.kq14) === nguoc)
      .map((x) => ({ ...x, cungNhom: String(x.nhom || '').split(',').some((g) => nhom.includes(g.trim())) }))
      .sort((a, b) => Number(b.cungNhom) - Number(a.cungNhom) || String(a.tenSp).localeCompare(String(b.tenSp), 'vi'))
      .slice(0, 30);
  }, [hdRows, r, viec]);
  const lienKetLech = (l) => {
    const hh = hopDong.find((x) => x.itemId === l.itemId);
    return !!hh && ((l.cuaSo === 'quota_1_4' && hh.cuaSo === 'trong') || (l.cuaSo === 'trong_nam' && hh.cuaSo === 'truoc'));
  };
  const qChon = quota.find((q) => q.quotaId === chonQ) || null;
  const hChon = hopDong.find((h) => h.itemId === chonH) || null;
  const lechCuaSo = !!(qChon && hChon && khacCuaSo(qChon.tt, hChon.cuaSo));
  // Quota upcoming (đợt chưa tới tháng thầu / thiếu thông tin) mà HĐ đã ký trong năm.
  const upDaKy = !!(qChon && hChon && qChon.tt === 'up' && hChon.cuaSo === 'trong');
  const coTheChuyen = !!(
    canEdit && qChon && hChon && (qChon.tt === 'cu' || qChon.tt === 'up') && hChon.cuaSo === 'trong' && !qChon.bung
  );
  // Đợt đích có sẵn: cùng PS × KH × nhóm, loại đang chọn, đủ tháng + HL và đã tới tháng thầu.
  const dotCoSan = useMemo(() => {
    if (!qChon || !dotsOf) return [];
    return dotsOf(qChon.ps, r.kh, qChon.nhom).filter(
      (d) => d.loai === cv.loai && /^\d{4}-\d{2}$/.test(d.thang || '') && Number(d.thoiGian) > 0 && d.thang <= CURRENT_MONTH,
    );
  }, [qChon, dotsOf, r.kh, cv.loai]);
  useEffect(() => {
    if (!qChon || !hChon) return;
    const thang = (hChon.ngayKy || '').slice(0, 7);
    const lay = Math.min(Number(qChon.soLuong) || 0, Number(hChon.soLuong) || 0) || '';
    setCv({
      sl: String(lay),
      // 1.4 → chính (R1): giữ tổng quota. Upcoming → on hand (V4): SL đợt mới theo HĐ.
      slDich: String(qChon.tt === 'up' ? Number(hChon.soLuong) || lay : lay),
      dot: '',
      loai: qChon.tt === 'up' && (qChon.loai === 'chinh' || qChon.loai === 'bo_sung') ? qChon.loai : 'chinh',
      thang,
      hl: String(soThang(thang, (hChon.thoiHan || '').slice(0, 7)) || ''),
    });
  }, [qChon, hChon]);
  const run = async (fn) => {
    setBusy(true);
    setLoi('');
    try {
      await fn();
    } catch (e) {
      setLoi(e.message);
    } finally {
      setBusy(false);
    }
  };
  const ganTay = () =>
    run(async () => {
      const v = Number(String(sl).replace(',', '.'));
      if (!chonQ || !chonH || !(v > 0)) throw new Error('Chọn 1 dòng quota, 1 dòng HĐ và nhập SL > 0.');
      if (
        upDaKy &&
        !confirm(
          'Quota này đang upcoming nhưng HĐ đã ký trong năm. Liên kết tay KHÔNG đổi quota sang on hand, khoá vẫn báo lệch. ' +
            'Nên dùng "Chuyển sang đợt on hand" ở trên.\n\nVẫn gắn tay?',
        )
      )
        return;
      if (
        lechCuaSo &&
        !confirm(
          `Dòng quota là ${qChon.tt === 'cu' ? 'Quota 1.4' : 'thầu chính / BS'} nhưng HĐ ${hChon.cuaSo === 'trong' ? 'ký trong năm' : 'ký trước năm TC'}: gắn khác cửa sổ.\n\n` +
            'Liên kết tay KHÔNG đổi kết quả đối chiếu hay loại quota, khoá vẫn báo lệch.' +
            (qChon.tt === 'cu' && hChon.cuaSo === 'trong' ? ' Nên dùng "Chuyển sang thầu chính" ở trên.' : '') +
            '\n\nVẫn gắn tay?',
        )
      )
        return;
      await api('ktGanTay', { quotaId: chonQ, itemId: chonH, khoa: r.khoa, slHd: v });
      setChonQ(null);
      setChonH(null);
      setSl('');
      tai();
      onDaDoi && onDaDoi(false);
    });
  const chuyen = () =>
    run(async () => {
      const v = Number(String(cv.sl).replace(',', '.'));
      if (!(v > 0) || v > Number(qChon.soLuong)) throw new Error(`SL lấy từ quota nguồn phải từ 1 đến ${fmtInt(qChon.soLuong)}.`);
      const vDich = Number(String(cv.slDich).replace(',', '.'));
      if (!(vDich > 0)) throw new Error('SL ở đợt đích phải > 0.');
      const dotMoi = cv.dot === '';
      if (dotMoi && (!/^\d{4}-\d{2}$/.test(cv.thang) || !(Number(cv.hl) >= 1 && Number(cv.hl) <= 120)))
        throw new Error('Đợt mới cần tháng thầu (yyyy-mm) và hiệu lực 1..120 tháng.');
      const dich = dotMoi
        ? `${LOAI_DOT[cv.loai]} đợt MỚI, tháng ${cv.thang}, hiệu lực ${cv.hl} tháng`
        : `${LOAI_DOT[cv.loai]} đợt ${cv.dot}`;
      if (
        !confirm(
          `Chuyển ${fmtInt(v)} quota ${qChon.tt === 'cu' ? '1.4' : 'upcoming (' + (LOAI_DOT[qChon.loai] || qChon.loai) + ' đợt ' + qChon.dot + ')'} "${qChon.sp}" (${qChon.ps}) sang ${dich}` +
            (vDich !== v ? `, ghi ${fmtInt(vDich)} ở đợt đích (tổng quota ${vDich > v ? 'tăng' : 'giảm'} ${fmtInt(Math.abs(vDich - v))})` : '') +
            `?\n\nTheo HĐ ${hChon.soHd} ký ${hChon.ngayKy}${hChon.thoiHan ? ', hạn ' + hChon.thoiHan : ''}. ` +
            'Quota thành on hand ngay (từ tháng thầu của đợt đích), kế hoạch không đổi. Hệ thống chạy lại gắn liên kết tự động.',
        )
      )
        return;
      const res = await api('ktChuyenTheoHd', {
        quotaId: qChon.quotaId,
        itemId: hChon.itemId,
        khoa: r.khoa,
        sl: v,
        slDich: vDich,
        loaiDich: cv.loai,
        dotDich: dotMoi ? null : Number(cv.dot),
        thang: dotMoi ? cv.thang : null,
        hieuLuc: dotMoi ? Number(cv.hl) : null,
      });
      if (onQuotaDoi) await onQuotaDoi(res.result);
      setChonQ(null);
      setChonH(null);
      tai();
      onDaDoi && onDaDoi(false);
    });
  const boGan = (id) =>
    run(async () => {
      if (!confirm('Bỏ liên kết tay này?')) return;
      await api('ktBoGanTay', { id });
      tai();
      onDaDoi && onDaDoi(false);
    });
  const ghepMa = (x) =>
    run(async () => {
      const laQuota = viec.kq === 'Chỉ có quota';
      const nguon = laQuota ? r : x;
      const dich = laQuota ? x : r;
      const maSp = String(nguon.maSp || '').split('|').map((s) => s.trim()).filter(Boolean);
      if (!maSp.length) throw new Error('Phía quota không có mã SP để ghép.');
      if (
        !confirm(
          `Ghép mã quota ${maSp.join(', ')} (${nguon.tenSp}) với khoá HĐ ${dich.khoa} (${dich.tenSp}), riêng KH ${r.kh}?\n\n` +
            'Chỉ ảnh hưởng đối chiếu / liên kết quota ↔ HĐ, không sửa danh mục, quota hay kế hoạch. Sau khi ghép hệ thống chạy lại gắn liên kết tự động.',
        )
      )
        return;
      await api('ktThemAlias', {
        kh: r.kh,
        maSp,
        khoaDen: dich.khoa,
        ghiChu: `${viec.cuaSoLabel}: ${maSp.join(', ')} ${nguon.tenSp} ↔ ${dich.tenSp}`,
      });
      onDaDoi && onDaDoi(true);
    });
  const th = 'px-2 py-1.5 font-semibold text-slate-600 text-left whitespace-nowrap';
  const td = 'px-2 py-1 whitespace-nowrap';
  const slTxt = (v) => (v == null ? '—' : fmtInt(v));
  return (
    <Modal open onClose={onClose} title={`${r.tenKh || r.kh} · ${r.tenSp || r.khoa}`} width={1100}>
      <div className="p-4 space-y-4 text-[12px] max-h-[75vh] overflow-y-auto">
        <div className="flex flex-wrap gap-x-6 gap-y-1 text-slate-600">
          <span>
            {viec.cuaSoLabel}: <KqPill kq={viec.kq} />
          </span>
          <span>
            Quota <b className="tabular-nums">{fmtInt(viec.slQ)}</b> · HĐ <b className="tabular-nums">{fmtInt(viec.slH)}</b>
          </span>
          <span>Khoá: {r.khoa}</span>
          <span>Mã quota: {r.maSp || '—'}</span>
          <span>
            PS quota: {r.psQ || '—'} · PS trên HĐ: {r.psH || '—'}
          </span>
        </div>
        <div className="text-slate-700">
          <b>Nguyên nhân:</b> {viec.nnChiTiet}
          {r.canhBao && <div className="text-amber-700 mt-0.5">Cảnh báo: {r.canhBao}</div>}
        </div>
        {loi && (
          <div className="flex items-center gap-1.5 text-red-600">
            <AlertCircle size={13} /> {loi}
          </div>
        )}
        {!data && !loi ? (
          <div className="flex items-center gap-2 text-slate-400">
            <Loader2 size={14} className="animate-spin" /> Đang tải dòng quota và hợp đồng…
          </div>
        ) : (
          data && (
            <>
              <section>
                <div className="flex items-center gap-3 mb-1">
                  <h4 className="font-semibold text-slate-700">Dòng quota ({quota.length})</h4>
                  {onSuaQuota && quota.length > 0 && (
                    <button
                      onClick={() => onSuaQuota(quota[0])}
                      className="px-2 py-0.5 text-[11px] font-semibold rounded border border-blue-200 text-blue-700 hover:bg-blue-50"
                    >
                      {canEdit ? 'Sửa quota' : 'Xem quota'}
                    </button>
                  )}
                </div>
                <div className="border border-slate-200 rounded overflow-x-auto">
                  <table className="w-full">
                    <thead className="bg-slate-50">
                      <tr>
                        {(isAdmin || canEdit) && <th className={th} />}
                        <th className={th}>PS</th>
                        <th className={th}>Loại · đợt</th>
                        <th className={th}>Tháng thầu</th>
                        <th className={th}>Trạng thái</th>
                        <th className={th}>Sản phẩm</th>
                        <th className={`${th} text-right`}>SL</th>
                        <th className={`${th} text-right`}>Đơn giá</th>
                        <th className={`${th} text-right`}>Đã liên kết</th>
                      </tr>
                    </thead>
                    <tbody>
                      {quota.length === 0 && (
                        <tr>
                          <td colSpan={9} className="px-2 py-3 text-center text-slate-400">
                            Không có quota cho khoá này
                          </td>
                        </tr>
                      )}
                      {quota.map((q) => (
                        <tr key={q.quotaId} className="border-t border-slate-100">
                          {(isAdmin || canEdit) && (
                            <td className={td}>
                              <input type="radio" name="kt-q" checked={chonQ === q.quotaId} onChange={() => setChonQ(q.quotaId)} />
                            </td>
                          )}
                          <td className={td}>{q.ps}</td>
                          <td className={td}>
                            {LOAI_DOT[q.loai] || q.loai}
                            {q.loai !== 'cu' ? ' · đợt ' + q.dot : ''}
                          </td>
                          <td className={td}>{q.thang || '—'}</td>
                          <td className={td}>{TT_QUOTA[q.tt] || q.tt}</td>
                          <td className="px-2 py-1">
                            <div>
                              {q.sp}
                              {q.bung && <span className="text-slate-400"> · bộ bung ×{fmtInt(q.dinhMuc)}</span>}
                            </div>
                            <HaiMa maChung={q.maChung} maSp={q.maSp} />
                          </td>
                          <td className={`${td} text-right tabular-nums`}>{slTxt(q.sl)}</td>
                          <td className={`${td} text-right tabular-nums`}>{fmtInt(q.donGia)}</td>
                          <td className={`${td} text-right tabular-nums`}>{slTxt(daLkQ.get(q.quotaId) || 0)}</td>
                        </tr>
                      ))}
                    </tbody>
                  </table>
                </div>
              </section>
              <section>
                <h4 className="font-semibold text-slate-700 mb-1">Dòng hợp đồng ({hopDong.length})</h4>
                <div className="border border-slate-200 rounded overflow-x-auto">
                  <table className="w-full">
                    <thead className="bg-slate-50">
                      <tr>
                        {(isAdmin || canEdit) && <th className={th} />}
                        <th className={th}>Số HĐ</th>
                        <th className={th}>Ngày ký</th>
                        <th className={th}>Hạn</th>
                        <th className={th}>Cửa sổ</th>
                        <th className={th}>Hàng hoá</th>
                        <th className={`${th} text-right`}>SL</th>
                        <th className={`${th} text-right`}>Còn lại đầu năm</th>
                        <th className={`${th} text-right`}>Đơn giá</th>
                        <th className={th}>PS</th>
                        <th className={`${th} text-right`}>Đã liên kết</th>
                      </tr>
                    </thead>
                    <tbody>
                      {hopDong.length === 0 && (
                        <tr>
                          <td colSpan={11} className="px-2 py-3 text-center text-slate-400">
                            Không có dòng HĐ cho khoá này
                          </td>
                        </tr>
                      )}
                      {hopDong.map((h) => (
                        <tr key={h.itemId} className="border-t border-slate-100">
                          {(isAdmin || canEdit) && (
                            <td className={td}>
                              <input
                                type="radio"
                                name="kt-h"
                                checked={chonH === h.itemId}
                                onChange={() => {
                                  setChonH(h.itemId);
                                  if (!sl) setSl(String(h.cuaSo === 'truoc' ? h.conLai ?? h.soLuong : h.soLuong));
                                }}
                              />
                            </td>
                          )}
                          <td className={td} title={h.maHd}>
                            {h.soHd}
                          </td>
                          <td className={td}>{h.ngayKy || '—'}</td>
                          <td className={td}>{h.thoiHan || '—'}</td>
                          <td className={td}>{CUA_SO_HD[h.cuaSo] || h.cuaSo}</td>
                          <td className="px-2 py-1">
                            <div>{h.ten}</div>
                            <HaiMa maChung={h.maChung} maSp={h.maSp} />
                          </td>
                          <td className={`${td} text-right tabular-nums`}>{slTxt(h.soLuong)}</td>
                          <td className={`${td} text-right tabular-nums`}>{h.cuaSo === 'truoc' ? slTxt(h.conLai) : '—'}</td>
                          <td className={`${td} text-right tabular-nums`}>{fmtInt(h.donGia)}</td>
                          <td className={td}>{h.ps}</td>
                          <td className={`${td} text-right tabular-nums`}>{slTxt(daLkH.get(h.itemId) || 0)}</td>
                        </tr>
                      ))}
                    </tbody>
                  </table>
                </div>
              </section>
              {lechCuaSo && (
                <div className="px-3 py-2 rounded border border-amber-300 bg-amber-50 text-amber-900">
                  <b>Khác cửa sổ:</b> dòng quota là {qChon.tt === 'cu' ? 'Quota 1.4' : 'thầu chính / BS'} nhưng HĐ{' '}
                  {hChon.cuaSo === 'trong' ? 'ký trong năm' : 'ký trước năm TC'}. Gắn tay chỉ ghi liên kết, không đổi kết
                  quả đối chiếu hay loại quota.
                  {qChon.tt === 'cu' && hChon.cuaSo === 'trong' && ' Đúng ra quota phải là thầu chính / bổ sung theo HĐ này.'}
                </div>
              )}
              {upDaKy && (
                <div className="px-3 py-2 rounded border border-amber-300 bg-amber-50 text-amber-900">
                  <b>Upcoming đã ký HĐ:</b> quota thuộc {LOAI_DOT[qChon.loai] || qChon.loai} đợt {qChon.dot}
                  {qChon.thang ? ` (tháng thầu ${qChon.thang})` : ' (đợt thiếu tháng / hiệu lực)'} nên còn tính upcoming, nhưng HĐ
                  đã ký {hChon.ngayKy}. Gắn tay không đổi quota sang on hand; nên tách SP này sang đợt on hand theo HĐ.
                </div>
              )}
              {coTheChuyen && (
                <div className="px-3 py-2.5 rounded border border-blue-200 bg-blue-50/50 space-y-2">
                  <div className="font-semibold text-slate-700">
                    {qChon.tt === 'cu'
                      ? `Chuyển quota 1.4 → thầu chính / bổ sung theo HĐ ${hChon.soHd}`
                      : `Tách quota upcoming → đợt on hand theo HĐ ${hChon.soHd}`}
                  </div>
                  <div className="flex items-center gap-2 flex-wrap">
                    <span className="text-slate-600">Lấy</span>
                    <input
                      value={cv.sl}
                      onChange={(e) => setCv((p) => ({ ...p, sl: e.target.value }))}
                      title="SL lấy khỏi dòng quota nguồn"
                      className="w-20 px-2 py-1 border border-slate-200 rounded text-right tabular-nums bg-white"
                    />
                    <span className="text-slate-400">/ {fmtInt(qChon.soLuong)}</span>
                    <span className="text-slate-600">→ ghi</span>
                    <input
                      value={cv.slDich}
                      onChange={(e) => setCv((p) => ({ ...p, slDich: e.target.value }))}
                      title="SL ghi vào đợt đích. Khác SL lấy = đổi tổng quota (vd SL theo HĐ)"
                      className="w-20 px-2 py-1 border border-slate-200 rounded text-right tabular-nums bg-white"
                    />
                    <select
                      value={cv.loai}
                      onChange={(e) => setCv((p) => ({ ...p, loai: e.target.value, dot: '' }))}
                      className="px-2 py-1 border border-slate-200 rounded bg-white"
                    >
                      <option value="chinh">Thầu chính</option>
                      <option value="bo_sung">Thầu bổ sung</option>
                    </select>
                    <select
                      value={cv.dot}
                      onChange={(e) => setCv((p) => ({ ...p, dot: e.target.value }))}
                      className="px-2 py-1 border border-slate-200 rounded bg-white"
                    >
                      <option value="">Đợt mới theo HĐ</option>
                      {dotCoSan.map((d) => (
                        <option key={d.dot} value={d.dot}>
                          Đợt {d.dot} · {d.thang} · {d.thoiGian} th
                        </option>
                      ))}
                    </select>
                    {cv.dot === '' && (
                      <>
                        <span className="text-slate-600">tháng thầu</span>
                        <input
                          value={cv.thang}
                          onChange={(e) => setCv((p) => ({ ...p, thang: e.target.value }))}
                          placeholder="yyyy-mm"
                          className="w-24 px-2 py-1 border border-slate-200 rounded bg-white"
                        />
                        <span className="text-slate-600">hiệu lực</span>
                        <input
                          value={cv.hl}
                          onChange={(e) => setCv((p) => ({ ...p, hl: e.target.value }))}
                          className="w-14 px-2 py-1 border border-slate-200 rounded text-right bg-white"
                        />
                        <span className="text-slate-600">tháng</span>
                      </>
                    )}
                    <button
                      onClick={chuyen}
                      disabled={busy}
                      className="inline-flex items-center gap-1 px-2.5 py-1 text-[12px] font-semibold rounded border border-blue-300 text-blue-700 bg-white hover:bg-blue-50 disabled:opacity-50"
                    >
                      {busy && <Loader2 size={12} className="animate-spin" />}
                      {qChon.tt === 'cu'
                        ? `Chuyển sang ${cv.loai === 'chinh' ? 'thầu chính' : 'thầu bổ sung'}`
                        : 'Chuyển sang đợt on hand'}
                    </button>
                  </div>
                  <div className="text-slate-500">
                    Mặc định theo quy tắc {qChon.tt === 'cu' ? 'R1 (giữ tổng quota)' : 'V4 (chỉ tách SP có HĐ, SL ở đợt mới theo HĐ)'}:
                    tháng thầu = tháng ký ({(hChon.ngayKy || '').slice(0, 7)}), hiệu lực = số tháng từ tháng ký tới tháng hết hạn
                    HĐ. Đợt có sẵn chỉ hiện đợt đủ thông tin và đã tới tháng thầu.
                    {Number(cv.slDich) !== Number(cv.sl) && Number(cv.sl) > 0 && Number(cv.slDich) > 0 && (
                      <b className="text-amber-700">
                        {' '}
                        Tổng quota sẽ {Number(cv.slDich) > Number(cv.sl) ? 'tăng' : 'giảm'}{' '}
                        {fmtInt(Math.abs(Number(cv.slDich) - Number(cv.sl)))}.
                      </b>
                    )}
                  </div>
                </div>
              )}
              {isAdmin && (
                <div className="flex items-center gap-2 flex-wrap">
                  <span className="text-slate-600">Gắn tay dòng quota ↔ dòng HĐ đã chọn, SL theo đơn vị HĐ:</span>
                  <input
                    value={sl}
                    onChange={(e) => setSl(e.target.value)}
                    className="w-24 px-2 py-1 border border-slate-200 rounded text-right tabular-nums"
                    placeholder="SL"
                  />
                  <button
                    onClick={ganTay}
                    disabled={busy || !chonQ || !chonH}
                    className="inline-flex items-center gap-1 px-2.5 py-1 text-[12px] font-medium rounded border border-emerald-300 text-emerald-700 hover:bg-emerald-50 disabled:opacity-50"
                  >
                    {busy && <Loader2 size={12} className="animate-spin" />}
                    Gắn tay
                  </button>
                  <span className="text-slate-400">Lần gắn tự động sau sẽ giữ liên kết tay, bỏ qua 2 dòng này.</span>
                </div>
              )}
              <section>
                <h4 className="font-semibold text-slate-700 mb-1">Liên kết hiện có ({lienKet.length})</h4>
                {lienKet.length === 0 ? (
                  <div className="text-slate-400">Chưa có liên kết.</div>
                ) : (
                  <div className="border border-slate-200 rounded overflow-x-auto">
                    <table className="w-full">
                      <thead className="bg-slate-50">
                        <tr>
                          <th className={th}>Dòng quota</th>
                          <th className={th}>HĐ</th>
                          <th className={th}>Cửa sổ</th>
                          <th className={`${th} text-right`}>SL HĐ</th>
                          <th className={`${th} text-right`}>SL quota</th>
                          <th className={th}>Cách gắn</th>
                          <th className={th} />
                        </tr>
                      </thead>
                      <tbody>
                        {lienKet.map((l) => (
                          <tr key={l.id} className="border-t border-slate-100">
                            <td className={td}>#{l.quotaId}</td>
                            <td className={td}>{l.maHd}</td>
                            <td className={td}>
                              {l.cuaSo === 'quota_1_4' ? 'Quota 1.4' : 'Trong năm'}
                              {lienKetLech(l) && (
                                <span
                                  className="ml-1.5 px-1.5 py-0.5 rounded bg-amber-50 text-amber-800 text-[10px] font-medium"
                                  title="Cửa sổ của liên kết khác cửa sổ của dòng HĐ"
                                >
                                  khác cửa sổ
                                </span>
                              )}
                            </td>
                            <td className={`${td} text-right tabular-nums`}>{fmtInt(l.slHd)}</td>
                            <td className={`${td} text-right tabular-nums`}>{fmtInt(l.slQuota)}</td>
                            <td className={td}>
                              {l.cachGan === 'tay' ? `Tay · ${l.nguoi || ''}` : 'Tự động'}
                            </td>
                            <td className={td}>
                              {isAdmin && l.cachGan === 'tay' && (
                                <button onClick={() => boGan(l.id)} title="Bỏ liên kết tay" className="text-slate-400 hover:text-red-600">
                                  <Trash2 size={13} />
                                </button>
                              )}
                            </td>
                          </tr>
                        ))}
                      </tbody>
                    </table>
                  </div>
                )}
              </section>
              {ungVien.length > 0 && (
                <section>
                  <h4 className="font-semibold text-slate-700 mb-1">
                    Ghép mã: khoá {viec.kq === 'Chỉ có quota' ? '"chỉ có HĐ"' : '"chỉ có quota"'} cùng KH, cùng cửa sổ
                  </h4>
                  <div className="border border-slate-200 rounded overflow-x-auto">
                    <table className="w-full">
                      <thead className="bg-slate-50">
                        <tr>
                          <th className={th}>Sản phẩm</th>
                          <th className={th}>Khoá</th>
                          <th className={th}>Mã quota</th>
                          <th className={th}>Nhóm</th>
                          <th className={`${th} text-right`}>SL quota</th>
                          <th className={`${th} text-right`}>SL HĐ</th>
                          <th className={th} />
                        </tr>
                      </thead>
                      <tbody>
                        {ungVien.map((x) => {
                          const q = viec.cuaSo === 'fy' ? Number(x.qChinh || 0) + Number(x.qBs || 0) : x.q14;
                          const h = viec.cuaSo === 'fy' ? x.hFy : x.h14;
                          return (
                            <tr key={x.khoa} className={`border-t border-slate-100 ${x.cungNhom ? '' : 'text-slate-400'}`}>
                              <td className="px-2 py-1">{x.tenSp}</td>
                              <td className={td}>{x.khoa}</td>
                              <td className={td}>{x.maSp || '—'}</td>
                              <td className={td}>{x.nhom}</td>
                              <td className={`${td} text-right tabular-nums`}>{slTxt(q)}</td>
                              <td className={`${td} text-right tabular-nums`}>{slTxt(h)}</td>
                              <td className={td}>
                                {isAdmin && (
                                  <button
                                    onClick={() => ghepMa(x)}
                                    disabled={busy}
                                    className="px-2 py-0.5 text-[11px] font-semibold rounded border border-blue-200 text-blue-700 hover:bg-blue-50 disabled:opacity-50"
                                  >
                                    Ghép mã
                                  </button>
                                )}
                              </td>
                            </tr>
                          );
                        })}
                      </tbody>
                    </table>
                  </div>
                  {!isAdmin && <div className="text-slate-400 mt-1">Chỉ admin ghép mã được.</div>}
                </section>
              )}
            </>
          )
        )}
      </div>
    </Modal>
  );
}
