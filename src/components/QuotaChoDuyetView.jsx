import { useState, useEffect, useCallback, useMemo } from 'react';
import { Check, XIcon, Loader2, RefreshCw, Search, Package, AlertCircle } from './icons.jsx';
import { TEAMS } from '../config/constants.js';
import { api } from '../api/client.js';
import { fmtInt } from '../lib/format.js';
import { deaccent } from '../lib/text.js';

const LOAI = { cu: 'Thầu cũ', chinh: 'Thầu chính', bo_sung: 'Thầu bổ sung' };
const ty = (v) => (v / 1e9).toLocaleString('vi-VN', { maximumFractionDigits: 2 });

// Quota chuyển từ cột cũ sale_target mà app đang ẩn (nhóm đã khai đợt nhưng sản
// phẩm chưa có quota_thau). Nằm ở quota_thau trạng thái 'cho_duyet', không lên
// app cho tới khi admin duyệt; loại = xoá hẳn.
export function QuotaChoDuyetView({ onChanged }) {
  const [rows, setRows] = useState([]);
  const [dots, setDots] = useState([]);
  const [loading, setLoading] = useState(true);
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState('');
  const [notice, setNotice] = useState('');
  const [search, setSearch] = useState('');
  const [chon, setChon] = useState(() => new Set());

  const load = useCallback(async () => {
    setLoading(true);
    setError('');
    try {
      const r = await api('getQuotaChoDuyet');
      setRows(r.rows || []);
      setDots(r.dots || []);
      setChon(new Set());
    } catch (e) {
      setError('Không tải được quota chờ duyệt: ' + e.message);
    } finally {
      setLoading(false);
    }
  }, []);
  useEffect(() => { load(); }, [load]);

  const loc = useMemo(() => {
    const q = deaccent(search.trim());
    if (!q) return rows;
    return rows.filter((r) =>
      [r.ps, r.ma_khach_hang, r.khach_hang, r.nhom_san_pham, r.bo_vat_tu, r.san_pham]
        .some((v) => deaccent(v || '').includes(q)),
    );
  }, [rows, search]);

  const tongTien = (list) => list.reduce((s, r) => s + Number(r.so_luong) * Number(r.don_gia), 0);
  const tatCaDaChon = loc.length > 0 && loc.every((r) => chon.has(r.id));
  const doiChon = (id) =>
    setChon((s) => {
      const n = new Set(s);
      if (n.has(id)) n.delete(id);
      else n.add(id);
      return n;
    });
  const chonTatCa = () =>
    setChon((s) => {
      const n = new Set(s);
      if (tatCaDaChon) loc.forEach((r) => n.delete(r.id));
      else loc.forEach((r) => n.add(r.id));
      return n;
    });

  const xuLy = async (duyet) => {
    const ids = [...chon];
    if (!ids.length) return;
    const msg = duyet
      ? `Duyệt ${ids.length} dòng quota? Các dòng này sẽ hiện và được tính trên app.`
      : `Loại ${ids.length} dòng quota? Các dòng này sẽ bị xoá hẳn.`;
    if (!window.confirm(msg)) return;
    setBusy(true);
    setError('');
    try {
      const r = await api('duyetQuotaThau', { ids, duyet });
      setNotice(
        duyet
          ? `Đã duyệt ${r.quota || 0} dòng quota${r.dot ? `, ${r.dot} đợt thầu` : ''}.`
          : `Đã loại ${r.quota || 0} dòng quota${r.dot ? `, xoá ${r.dot} đợt chờ duyệt` : ''}.`,
      );
      await load();
      if (duyet) await onChanged?.();
    } catch (e) {
      setError((duyet ? 'Duyệt' : 'Loại') + ' thất bại: ' + e.message);
    } finally {
      setBusy(false);
    }
  };

  const daChon = rows.filter((r) => chon.has(r.id));

  const xuLyDot = async (ids, duyet) => {
    if (!ids.length) return;
    const msg = duyet
      ? `Duyệt ${ids.length} đợt thầu? Đợt sẽ hiện ở mục Đợt thầu của nhóm.`
      : `Loại ${ids.length} đợt thầu? Đợt sẽ bị xoá hẳn.`;
    if (!window.confirm(msg)) return;
    setBusy(true);
    setError('');
    try {
      const r = await api('duyetDotThau', { ids, duyet });
      setNotice(`${duyet ? 'Đã duyệt' : 'Đã loại'} ${r.dot || 0} đợt thầu.`);
      await load();
      if (duyet) await onChanged?.();
    } catch (e) {
      setError((duyet ? 'Duyệt' : 'Loại') + ' đợt thất bại: ' + e.message);
    } finally {
      setBusy(false);
    }
  };

  return (
    <div className="p-6 space-y-4">
      <div className="flex items-center justify-between flex-wrap gap-3">
        <div className="flex items-center gap-3">
          <Package size={20} className="text-emerald-600" />
          <h2 className="text-lg font-bold text-slate-800">Quota chờ duyệt</h2>
          <span className="text-[12px] text-slate-400">
            {rows.length} dòng · {ty(tongTien(rows))} tỷ
          </span>
        </div>
        <div className="flex items-center gap-2">
          <button
            onClick={() => xuLy(true)}
            disabled={busy || !chon.size}
            className="inline-flex items-center gap-1.5 px-3 py-1.5 text-[12px] font-medium bg-emerald-600 hover:bg-emerald-700 text-white rounded-md disabled:opacity-50"
          >
            {busy ? <Loader2 size={13} className="animate-spin" /> : <Check size={13} />}
            Duyệt{chon.size ? ` (${chon.size})` : ''}
          </button>
          <button
            onClick={() => xuLy(false)}
            disabled={busy || !chon.size}
            className="inline-flex items-center gap-1.5 px-3 py-1.5 text-[12px] font-medium text-red-700 bg-white border border-red-200 hover:bg-red-50 rounded-md disabled:opacity-50"
          >
            <XIcon size={13} />
            Loại{chon.size ? ` (${chon.size})` : ''}
          </button>
        </div>
      </div>
      <p className="text-[12px] text-slate-500 max-w-4xl">
        Quota chuyển từ cột cũ của kế hoạch, trước đây app đang ẩn vì nhóm SP đã khai đợt thầu nhưng
        sản phẩm chưa nhập quota theo đợt. Các dòng này chưa tính vào app. Duyệt để hiện và tính
        như quota bình thường; loại để xoá.
      </p>
      {notice && (
        <div className="px-3 py-2 bg-emerald-50 border border-emerald-200 rounded-md text-[12px] text-emerald-800">{notice}</div>
      )}
      {error && (
        <div className="px-3 py-2 bg-red-50 border border-red-200 rounded-md text-[12px] text-red-800 flex items-center gap-2">
          <AlertCircle size={14} /> {error}
        </div>
      )}
      <div className="flex items-center gap-2">
        <div className="relative">
          <Search size={14} className="absolute left-2.5 top-1/2 -translate-y-1/2 text-slate-400" />
          <input
            value={search}
            onChange={(e) => setSearch(e.target.value)}
            placeholder="Tìm PS, KH, nhóm, sản phẩm…"
            className="pl-8 pr-3 py-1.5 text-[13px] border border-slate-200 rounded-md w-72 outline-none focus:border-emerald-500 focus:ring-2 focus:ring-emerald-100"
          />
        </div>
        <button onClick={load} title="Tải lại" className="px-2 py-1.5 text-emerald-600 hover:text-emerald-800">
          <RefreshCw size={13} />
        </button>
        {chon.size > 0 && (
          <span className="text-[12px] text-slate-500">
            Đã chọn {chon.size} dòng · {ty(tongTien(daChon))} tỷ
          </span>
        )}
      </div>
      <div className="bg-white rounded-lg border border-slate-200 overflow-hidden">
        <div className="overflow-x-auto">
          <table className="w-full text-[12px]">
            <thead>
              <tr className="bg-slate-50 border-b border-slate-200">
                <th className="px-3 py-2 w-8">
                  <input type="checkbox" checked={tatCaDaChon} onChange={chonTatCa} disabled={!loc.length} />
                </th>
                <th className="px-3 py-2 text-left font-semibold text-slate-600">Team</th>
                <th className="px-3 py-2 text-left font-semibold text-slate-600">PS</th>
                <th className="px-3 py-2 text-left font-semibold text-slate-600">Khách hàng</th>
                <th className="px-3 py-2 text-left font-semibold text-slate-600">Nhóm SP</th>
                <th className="px-3 py-2 text-left font-semibold text-slate-600">Sản phẩm</th>
                <th className="px-3 py-2 text-right font-semibold text-slate-600">Đơn giá</th>
                <th className="px-3 py-2 text-left font-semibold text-slate-600">Loại</th>
                <th className="px-3 py-2 text-left font-semibold text-slate-600">Tháng thầu</th>
                <th className="px-3 py-2 text-right font-semibold text-slate-600">SL quota</th>
                <th className="px-3 py-2 text-right font-semibold text-slate-600">Thành tiền</th>
              </tr>
            </thead>
            <tbody>
              {loading ? (
                <tr><td colSpan={11} className="px-3 py-8 text-center text-slate-400"><Loader2 size={16} className="inline animate-spin mr-2" />Đang tải...</td></tr>
              ) : loc.length === 0 ? (
                <tr><td colSpan={11} className="px-3 py-8 text-center text-slate-400">Không có quota chờ duyệt</td></tr>
              ) : (
                loc.map((r) => (
                  <tr
                    key={r.id}
                    onClick={() => doiChon(r.id)}
                    className={'border-b border-slate-100 cursor-pointer ' + (chon.has(r.id) ? 'bg-emerald-50/60' : 'hover:bg-slate-50/50')}
                  >
                    <td className="px-3 py-2">
                      <input type="checkbox" checked={chon.has(r.id)} onChange={() => doiChon(r.id)} onClick={(e) => e.stopPropagation()} />
                    </td>
                    <td className="px-3 py-2 text-slate-600">{(TEAMS[r.bu] && TEAMS[r.bu].label) || r.bu || ''}</td>
                    <td className="px-3 py-2 text-slate-700 whitespace-nowrap">{r.ps}</td>
                    <td className="px-3 py-2">
                      <div className="text-slate-800">{r.khach_hang || r.ma_khach_hang}</div>
                      <div className="text-[10px] text-slate-400">{r.ma_khach_hang}</div>
                    </td>
                    <td className="px-3 py-2 text-slate-600">{r.nhom_san_pham}</td>
                    <td className="px-3 py-2">
                      <div className="text-slate-800">{r.san_pham}</div>
                      {r.bo_vat_tu && r.bo_vat_tu !== r.san_pham && (
                        <div className="text-[10px] text-slate-400">{r.bo_vat_tu}</div>
                      )}
                    </td>
                    <td className="px-3 py-2 text-right tabular-nums text-slate-700">{fmtInt(r.don_gia)}</td>
                    <td className="px-3 py-2 text-slate-600 whitespace-nowrap">
                      {LOAI[r.loai] || r.loai}
                      {r.loai !== 'cu' && <span className="text-slate-400"> · đợt {r.dot}</span>}
                    </td>
                    <td className="px-3 py-2 text-slate-600 whitespace-nowrap">
                      {r.loai === 'cu' ? '—' : r.thang_thau || <span className="text-amber-600">chưa có</span>}
                      {r.dot_cho_duyet && <span className="ml-1 text-[10px] text-amber-600">(đợt mới)</span>}
                    </td>
                    <td className="px-3 py-2 text-right tabular-nums font-medium text-slate-800">{fmtInt(r.so_luong)}</td>
                    <td className="px-3 py-2 text-right tabular-nums text-slate-700">{fmtInt(Number(r.so_luong) * Number(r.don_gia))}</td>
                  </tr>
                ))
              )}
            </tbody>
          </table>
        </div>
      </div>
      {dots.length > 0 && (
        <DotChoDuyet dots={dots} busy={busy} onXuLy={xuLyDot} />
      )}
    </div>
  );
}

// Đợt thầu chờ duyệt không gắn quota: chỉ có tháng (và thời gian) thầu chuyển từ
// cột cũ của kế hoạch, nhóm chưa có đợt cùng tháng.
function DotChoDuyet({ dots, busy, onXuLy }) {
  const [chon, setChon] = useState(() => new Set());
  useEffect(() => { setChon(new Set()); }, [dots]);
  const doi = (id) =>
    setChon((s) => {
      const n = new Set(s);
      if (n.has(id)) n.delete(id);
      else n.add(id);
      return n;
    });
  const tatCa = dots.length > 0 && dots.every((d) => chon.has(d.id));
  return (
    <div className="space-y-2">
      <div className="flex items-center justify-between flex-wrap gap-2 pt-2">
        <div>
          <h3 className="text-[14px] font-bold text-slate-800">Đợt thầu chờ duyệt (chưa có quota)</h3>
          <p className="text-[12px] text-slate-500">
            Tháng thầu ghi ở cột cũ của kế hoạch mà nhóm chưa có đợt cùng tháng. Duyệt để đợt hiện ở mục Đợt thầu của nhóm.
          </p>
        </div>
        <div className="flex items-center gap-2">
          <button
            onClick={() => onXuLy([...chon], true)}
            disabled={busy || !chon.size}
            className="inline-flex items-center gap-1.5 px-3 py-1.5 text-[12px] font-medium bg-emerald-600 hover:bg-emerald-700 text-white rounded-md disabled:opacity-50"
          >
            <Check size={13} />
            Duyệt đợt{chon.size ? ` (${chon.size})` : ''}
          </button>
          <button
            onClick={() => onXuLy([...chon], false)}
            disabled={busy || !chon.size}
            className="inline-flex items-center gap-1.5 px-3 py-1.5 text-[12px] font-medium text-red-700 bg-white border border-red-200 hover:bg-red-50 rounded-md disabled:opacity-50"
          >
            <XIcon size={13} />
            Loại đợt{chon.size ? ` (${chon.size})` : ''}
          </button>
        </div>
      </div>
      <div className="bg-white rounded-lg border border-slate-200 overflow-x-auto">
        <table className="w-full text-[12px]">
          <thead>
            <tr className="bg-slate-50 border-b border-slate-200">
              <th className="px-3 py-2 w-8">
                <input
                  type="checkbox"
                  checked={tatCa}
                  onChange={() => setChon(tatCa ? new Set() : new Set(dots.map((d) => d.id)))}
                />
              </th>
              <th className="px-3 py-2 text-left font-semibold text-slate-600">Team</th>
              <th className="px-3 py-2 text-left font-semibold text-slate-600">PS</th>
              <th className="px-3 py-2 text-left font-semibold text-slate-600">Mã KH</th>
              <th className="px-3 py-2 text-left font-semibold text-slate-600">Nhóm SP</th>
              <th className="px-3 py-2 text-left font-semibold text-slate-600">Loại</th>
              <th className="px-3 py-2 text-left font-semibold text-slate-600">Tháng thầu</th>
              <th className="px-3 py-2 text-right font-semibold text-slate-600">Thời gian</th>
            </tr>
          </thead>
          <tbody>
            {dots.map((d) => (
              <tr
                key={d.id}
                onClick={() => doi(d.id)}
                className={'border-b border-slate-100 cursor-pointer ' + (chon.has(d.id) ? 'bg-emerald-50/60' : 'hover:bg-slate-50/50')}
              >
                <td className="px-3 py-2">
                  <input type="checkbox" checked={chon.has(d.id)} onChange={() => doi(d.id)} onClick={(e) => e.stopPropagation()} />
                </td>
                <td className="px-3 py-2 text-slate-600">{(TEAMS[d.bu] && TEAMS[d.bu].label) || d.bu || ''}</td>
                <td className="px-3 py-2 text-slate-700 whitespace-nowrap">{d.ps}</td>
                <td className="px-3 py-2 text-slate-600">{d.ma_khach_hang}</td>
                <td className="px-3 py-2 text-slate-600">{d.nhom_san_pham}</td>
                <td className="px-3 py-2 text-slate-600 whitespace-nowrap">{LOAI[d.loai] || d.loai} · đợt {d.dot}</td>
                <td className="px-3 py-2 text-slate-700">{d.thang_thau}</td>
                <td className="px-3 py-2 text-right tabular-nums text-slate-700">{d.thoi_gian ?? ''}</td>
              </tr>
            ))}
          </tbody>
        </table>
      </div>
    </div>
  );
}
