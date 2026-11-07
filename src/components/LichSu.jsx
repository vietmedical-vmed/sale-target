// Bảng thay đổi (cũ → mới) dùng chung cho tab Lịch sử cập nhật và lịch sử một sản phẩm.
import { useEffect, useMemo, useState } from 'react';
import { Clock, Loader2 } from './icons.jsx';
import { Modal } from './Modal.jsx';
import { api } from '../api/client.js';
import { colLabel, fmtGiaTri, chenhLech, fmtKhoangThang, fmtNgayGio, fmtGio, gopThang } from '../lib/audit.js';

const BUOC = 300;

function ChenhCell({ v }) {
  if (v === null || v === 0) return <span className="text-slate-300">—</span>;
  const up = v > 0;
  return (
    <span className={`font-semibold ${up ? 'text-emerald-700' : 'text-red-600'}`}>
      {(up ? '+' : '−') + Math.abs(v).toLocaleString('en-US', { maximumFractionDigits: 2 })}
    </span>
  );
}

// items: thay đổi đã trải phẳng từ RPC audit_thay_doi (mỗi phần tử = 1 ô dòng × cột).
// Gom theo lượt lưu (log_id); mỗi lượt có dòng tiêu đề giờ + người sửa.
export function BangThayDoi({ items, showKhachHang = true, showSanPham = true, showNguoi = false, showNgay = false }) {
  const [hien, setHien] = useState(BUOC);
  const luot = useMemo(() => {
    const out = [];
    let cur = null;
    for (const it of items.slice(0, hien)) {
      if (!cur || cur.log_id !== it.log_id) {
        cur = { log_id: it.log_id, at: it.at, ho_ten: it.ho_ten || it.username, rows: [] };
        out.push(cur);
      }
      cur.rows.push(it);
    }
    for (const l of out) {
      l.soO = l.rows.length;
      l.rows = gopThang(l.rows);
    }
    return out;
  }, [items, hien]);

  if (!items.length) return <div className="px-4 py-6 text-center text-[12px] text-slate-400">Không có thay đổi nào được ghi chi tiết</div>;

  const soCot = 4 + (showKhachHang ? 1 : 0) + (showSanPham ? 1 : 0);
  return (
    <div>
      <table className="w-full text-[12px] border-collapse">
        <thead>
          <tr className="text-[10.5px] uppercase tracking-wide text-slate-500 border-b border-slate-200">
            {showKhachHang && <th className="px-3 py-1.5 text-left font-semibold">Khách hàng</th>}
            {showSanPham && <th className="px-3 py-1.5 text-left font-semibold">Sản phẩm</th>}
            <th className="px-3 py-1.5 text-left font-semibold w-[120px]">Tháng</th>
            <th className="px-3 py-1.5 text-left font-semibold w-[120px]">Cột</th>
            <th className="px-3 py-1.5 text-right font-semibold w-[150px]">Cũ → Mới</th>
            <th className="px-3 py-1.5 text-right font-semibold w-[80px]">Chênh</th>
          </tr>
        </thead>
        <tbody>
          {luot.map((l) => (
            <LuotRows key={l.log_id} l={l} soCot={soCot} showKhachHang={showKhachHang} showSanPham={showSanPham} showNguoi={showNguoi} showNgay={showNgay} />
          ))}
        </tbody>
      </table>
      {items.length > hien && (
        <div className="px-3 py-2 text-center">
          <button onClick={() => setHien((h) => h + BUOC)} className="text-[12px] text-emerald-700 hover:underline">
            {`Hiện thêm (${(items.length - hien).toLocaleString('en-US')} thay đổi nữa)`}
          </button>
        </div>
      )}
    </div>
  );
}

function LuotRows({ l, soCot, showKhachHang, showSanPham, showNguoi, showNgay }) {
  return (
    <>
      <tr className="bg-slate-50/80">
        <td colSpan={soCot} className="px-3 py-1 text-[11px] text-slate-500 border-b border-slate-100">
          <Clock size={11} className="inline mr-1 -mt-0.5 text-slate-400" />
          <span className="font-semibold text-slate-700">{showNgay ? fmtNgayGio(l.at) : fmtGio(l.at)}</span>
          {showNguoi && <span>{' · ' + l.ho_ten}</span>}
          <span className="text-slate-400">{' · ' + l.soO + ' ô thay đổi'}</span>
        </td>
      </tr>
      {l.rows.map((r, i) => {
        const prev = i > 0 ? l.rows[i - 1] : null;
        const lapKh = prev && prev.kh === r.kh;
        const lapSp = lapKh && prev.sp === r.sp && prev.bo === r.bo;
        const d = chenhLech(r.cot, r.cu, r.moi);
        return (
          <tr key={i} className="border-b border-slate-100 hover:bg-blue-50/30">
            {showKhachHang && (
              <td className={`px-3 py-1 max-w-[260px] truncate ${lapKh ? 'text-slate-300' : 'text-slate-700'}`} title={(r.kh || '') + (r.ps ? ' — PS ' + r.ps : '')}>
                {r.kh || '—'}
              </td>
            )}
            {showSanPham && (
              <td className={`px-3 py-1 max-w-[260px] truncate ${lapSp ? 'text-slate-300' : 'text-slate-700'}`} title={[r.nhom, r.bo, r.sp].filter(Boolean).join(' › ')}>
                {r.sp || r.bo || '—'}
                {r.bo && r.sp && r.bo !== r.sp && !lapSp && <span className="ml-1 text-[10.5px] text-slate-400">{r.bo}</span>}
              </td>
            )}
            <td className="px-3 py-1 text-slate-600 whitespace-nowrap" title={r.thangs.length > 1 ? `${r.thangs.length} tháng` : undefined}>
              {fmtKhoangThang(r.thangs)}
              {r.thangs.length > 2 && <span className="ml-1 text-[10.5px] text-slate-400">{`(${r.thangs.length})`}</span>}
            </td>
            <td className="px-3 py-1 text-slate-600 whitespace-nowrap">{colLabel(r.cot)}</td>
            <td className="px-3 py-1 text-right tabular-nums whitespace-nowrap">
              <span className="text-slate-400">{fmtGiaTri(r.cot, r.cu)}</span>
              <span className="mx-1 text-slate-300">→</span>
              <span className="font-semibold text-slate-800">{fmtGiaTri(r.cot, r.moi)}</span>
            </td>
            <td className="px-3 py-1 text-right tabular-nums whitespace-nowrap"><ChenhCell v={d} /></td>
          </tr>
        );
      })}
    </>
  );
}

// Lịch sử một sản phẩm của một khách hàng (mọi tháng) — mở từ tab Chi tiết.
export function LichSuSanPhamModal({ info, onClose }) {
  const [state, setState] = useState({ loading: true, error: '', thayDoi: [], thieu: [] });
  useEffect(() => {
    if (!info) return undefined;
    let huy = false;
    setState({ loading: true, error: '', thayDoi: [], thieu: [] });
    api('getLichSuSanPham', { ids: info.ids })
      .then((r) => {
        if (!huy) setState({ loading: false, error: '', thayDoi: r.thay_doi || [], thieu: r.thieu_chi_tiet || [] });
      })
      .catch((e) => {
        if (huy) return;
        const msg = String(e.message || e);
        setState({
          loading: false,
          error: msg === 'unknown_action' ? 'Máy chủ chưa có bản cập nhật lịch sử. Báo quản trị deploy sale_target-api.' : msg,
          thayDoi: [],
          thieu: [],
        });
      });
    return () => {
      huy = true;
    };
  }, [info]);

  if (!info) return null;
  const soLuot = new Set(state.thayDoi.map((x) => x.log_id)).size;
  // Sản phẩm có nhiều dòng (nhiều mức giá / đổi tên) thì hiện thêm cột sản phẩm để phân biệt.
  const nhieuSp = new Set(state.thayDoi.map((x) => `${x.bo}|${x.sp}`)).size > 1;
  return (
    <Modal
      open
      onClose={onClose}
      width={820}
      icon={<Clock size={16} className="text-emerald-600" />}
      title={'Lịch sử sửa · ' + info.product}
    >
      <div className="px-4 py-2 text-[12px] text-slate-500 border-b border-slate-100">
        {info.cust && <span className="font-medium text-slate-700">{info.cust}</span>}
        {info.mset && info.mset !== info.product && <span>{' · Bộ ' + info.mset}</span>}
        {!state.loading && !state.error && <span>{` · ${soLuot} lượt sửa`}</span>}
      </div>
      <div className="max-h-[60vh] overflow-y-auto">
        {state.loading ? (
          <div className="px-4 py-8 text-center text-[12px] text-slate-400">
            <Loader2 size={14} className="inline animate-spin mr-2" />
            Đang tải...
          </div>
        ) : state.error ? (
          <div className="px-4 py-6 text-center text-[12px] text-red-600">{state.error}</div>
        ) : (
          <>
            <BangThayDoi items={state.thayDoi} showKhachHang={false} showSanPham={nhieuSp} showNguoi showNgay />
            {state.thieu.length > 0 && (
              <div className="px-4 py-2 text-[11px] text-slate-500 border-t border-slate-100 bg-amber-50/50">
                {`Còn ${state.thieu.length} lượt sửa cũ không lưu chi tiết (lượt sửa nhiều dòng trước 07/11/2026): `}
                {state.thieu.slice(0, 5).map((t) => `${fmtNgayGio(t.at)} ${t.ho_ten || t.username}`).join('; ')}
                {state.thieu.length > 5 ? '…' : ''}
              </div>
            )}
          </>
        )}
      </div>
    </Modal>
  );
}
