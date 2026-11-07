import { useState, useEffect, useCallback, useMemo, useRef } from 'react';
import {
  Clock, Settings, Download, Filter, RefreshCw, Loader2,
  ChevronDown, ChevronRight, User, Search,
} from './icons.jsx';
import { ROLE_LABELS, TEAMS, setDeadlineDay as setDeadlineDayGlobal } from '../config/constants.js';
import { api } from '../api/client.js';
import { loadXLSX } from '../lib/excel.js';
import {
  ACTION_GROUPS, DETAIL_KEY_LABELS, actionLabel, actionColor, colLabel,
  fmtGio, fmtNgay, fmtNgayGio, tieuDeNgay, khoangNgay, tomTatNhom,
} from '../lib/audit.js';
import { BangThayDoi } from './LichSu.jsx';

const LIMIT = 50;
const PRESETS = [
  ['today', 'Hôm nay'],
  ['7d', '7 ngày'],
  ['30d', '30 ngày'],
  ['month', 'Tháng này'],
  ['all', 'Tất cả'],
  ['custom', 'Tùy chọn'],
];

const teamLabel = (bu) => (TEAMS[bu] && TEAMS[bu].label) || (bu === 'all' ? 'Tất cả' : bu || '');
const loiMayChu = (e) => {
  const msg = String((e && e.message) || e);
  return msg === 'unknown_action'
    ? 'Máy chủ chưa có bản cập nhật lịch sử. Cần deploy lại edge function sale_target-api.'
    : msg;
};

function Avatar({ name }) {
  const w = String(name || '?').trim().split(/\s+/);
  const ch = (w[w.length - 1] || '?')[0].toUpperCase();
  return (
    <div className="w-7 h-7 shrink-0 rounded-full bg-emerald-100 text-emerald-800 text-[12px] font-bold flex items-center justify-center">
      {ch}
    </div>
  );
}

// ============ Chi tiết thao tác không phải updateCells ============
function GiaTriDetail({ v }) {
  if (v === null || v === undefined || v === '') return <span className="text-slate-300">—</span>;
  if (typeof v === 'boolean') return v ? 'Có' : 'Không';
  if (typeof v === 'number') return v.toLocaleString('en-US');
  if (typeof v === 'object') return <span className="text-slate-500">{JSON.stringify(v).slice(0, 120)}</span>;
  return String(v);
}

function ChiTietKhac({ logs }) {
  return (
    <div className="divide-y divide-slate-100">
      {logs.map((l) => {
        const d = l.details || {};
        const rows = Array.isArray(d.rows) ? d.rows : null;
        const scalars = Object.entries(d).filter(([k, v]) => k !== 'rows' && k !== 'ids' && (v === null || typeof v !== 'object' || (Array.isArray(v) && v.every((x) => typeof x !== 'object'))));
        const cols = rows ? [...new Set(rows.flatMap((r) => Object.keys(r || {})))] : [];
        return (
          <div key={l.id} className="px-4 py-2">
            <div className="text-[11px] text-slate-500 mb-1">
              <Clock size={11} className="inline mr-1 -mt-0.5 text-slate-400" />
              <span className="font-semibold text-slate-700">{fmtGio(l.created_at)}</span>
              {l.row_count ? ` · ${l.row_count.toLocaleString('en-US')} dòng` : ''}
            </div>
            {scalars.length > 0 && (
              <div className="flex flex-wrap gap-x-4 gap-y-0.5 text-[12px]">
                {scalars.map(([k, v]) => (
                  <span key={k}>
                    <span className="text-slate-400">{(DETAIL_KEY_LABELS[k] || k) + ': '}</span>
                    <span className="text-slate-700">{Array.isArray(v) ? v.join(', ') : <GiaTriDetail v={v} />}</span>
                  </span>
                ))}
              </div>
            )}
            {Array.isArray(d.ids) && !rows && (
              <div className="text-[11px] text-slate-400">{`${d.ids.length} mã bản ghi`}</div>
            )}
            {rows && rows.length > 0 && (
              <div className="overflow-x-auto mt-1">
                <table className="text-[11.5px] border-collapse">
                  <thead>
                    <tr className="text-[10.5px] uppercase tracking-wide text-slate-500 border-b border-slate-200">
                      {cols.map((c) => <th key={c} className="px-2 py-1 text-left font-semibold whitespace-nowrap">{DETAIL_KEY_LABELS[c] || colLabel(c)}</th>)}
                    </tr>
                  </thead>
                  <tbody>
                    {rows.slice(0, 200).map((r, i) => (
                      <tr key={i} className="border-b border-slate-100">
                        {cols.map((c) => <td key={c} className="px-2 py-0.5 whitespace-nowrap text-slate-700"><GiaTriDetail v={r[c]} /></td>)}
                      </tr>
                    ))}
                  </tbody>
                </table>
                {rows.length > 200 && <div className="text-[11px] text-slate-400 px-2 py-1">{`… và ${rows.length - 200} dòng nữa`}</div>}
              </div>
            )}
          </div>
        );
      })}
    </div>
  );
}

function ChiTietNhom({ g, cache, onLoad }) {
  const c = cache[g.key];
  useEffect(() => {
    if (!c) onLoad(g);
  }, [c, g, onLoad]);
  if (!c || c.loading)
    return (
      <div className="px-4 py-4 text-[12px] text-slate-400">
        <Loader2 size={14} className="inline animate-spin mr-2" />
        Đang tải chi tiết...
      </div>
    );
  if (c.error) return <div className="px-4 py-4 text-[12px] text-red-600">{c.error}</div>;
  if (g.action !== 'updateCells') return <ChiTietKhac logs={c.logs} />;
  const soChiTiet = c.logs.reduce((s, l) => s + ((l.details && l.details.so_dong_chi_tiet) || 0), 0);
  return (
    <div>
      <BangThayDoi items={c.thayDoi} />
      {soChiTiet < (g.tong_dong || 0) && (
        <div className="px-4 py-1.5 text-[11px] text-slate-500 bg-amber-50/50 border-t border-slate-100">
          {`Chỉ lưu chi tiết ${soChiTiet.toLocaleString('en-US')}/${Number(g.tong_dong).toLocaleString('en-US')} dòng (lượt sửa nhiều dòng trước 07/11/2026 chỉ lưu 50 dòng đầu).`}
        </div>
      )}
    </div>
  );
}

// ============ Dòng thời gian ============
function NhatKy() {
  const [preset, setPreset] = useState('7d');
  const [tuNgay, setTuNgay] = useState('');
  const [denNgay, setDenNgay] = useState('');
  const [filterUser, setFilterUser] = useState('');
  const [filterGroup, setFilterGroup] = useState('');
  const [filterBu, setFilterBu] = useState('');
  const [qInput, setQInput] = useState('');
  const [q, setQ] = useState('');
  const [page, setPage] = useState(1);
  const [data, setData] = useState({ groups: [], total: 0, tong_ban_ghi: 0, users: [] });
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState('');
  const [expanded, setExpanded] = useState(() => new Set());
  const [cache, setCache] = useState({});
  const [exporting, setExporting] = useState(false);
  const reqId = useRef(0);

  useEffect(() => {
    const t = setTimeout(() => setQ(qInput.trim()), 400);
    return () => clearTimeout(t);
  }, [qInput]);

  const filterPayload = useMemo(() => {
    const { from, to } = khoangNgay(preset, tuNgay, denNgay);
    const p = {};
    if (from) p.from = from;
    if (to) p.to = to;
    if (filterUser) p.username = filterUser;
    if (filterGroup) p.actions = ACTION_GROUPS[filterGroup].actions;
    if (filterBu) p.bu = filterBu;
    if (q) p.q = q;
    return p;
  }, [preset, tuNgay, denNgay, filterUser, filterGroup, filterBu, q]);

  const load = useCallback(async (p, fp) => {
    const id = ++reqId.current;
    setLoading(true);
    setError('');
    try {
      const r = await api('getAuditNhom', { ...fp, page: p, limit: LIMIT });
      if (id !== reqId.current) return;
      const groups = (r.groups || []).map((g) => ({ ...g, key: `${g.ngay}|${g.username}|${g.action}` }));
      setData({ groups, total: r.total || 0, tong_ban_ghi: r.tong_ban_ghi || 0, users: r.users || [] });
    } catch (e) {
      if (id !== reqId.current) return;
      setError(loiMayChu(e));
      setData((d) => ({ ...d, groups: [], total: 0, tong_ban_ghi: 0 }));
    } finally {
      if (id === reqId.current) setLoading(false);
    }
  }, []);

  useEffect(() => {
    setPage(1);
    setExpanded(new Set());
    load(1, filterPayload);
  }, [filterPayload, load]);

  const goPage = (p) => {
    setPage(p);
    setExpanded(new Set());
    load(p, filterPayload);
  };

  const loadChiTiet = useCallback(async (g) => {
    setCache((c) => ({ ...c, [g.key]: { loading: true } }));
    try {
      const r = await api('getAuditChiTiet', { logIds: g.log_ids });
      setCache((c) => ({ ...c, [g.key]: { thayDoi: r.thayDoi || [], logs: r.logs || [] } }));
    } catch (e) {
      setCache((c) => ({ ...c, [g.key]: { error: loiMayChu(e) } }));
    }
  }, []);

  const toggle = (key) =>
    setExpanded((s) => {
      const n = new Set(s);
      if (n.has(key)) n.delete(key);
      else n.add(key);
      return n;
    });

  // Gom các nhóm của trang theo ngày để hiện tiêu đề ngày.
  const theoNgay = useMemo(() => {
    const out = [];
    for (const g of data.groups) {
      const last = out[out.length - 1];
      if (!last || last.ngay !== g.ngay) out.push({ ngay: g.ngay, groups: [g] });
      else last.groups.push(g);
    }
    return out;
  }, [data.groups]);

  const exportExcel = async () => {
    setExporting(true);
    try {
      const all = [];
      for (let p = 1; p <= 50; p++) {
        const r = await api('getAuditNhom', { ...filterPayload, page: p, limit: 200 });
        all.push(...(r.groups || []));
        if (all.length >= (r.total || 0) || !(r.groups || []).length) break;
      }
      const XLSX = await loadXLSX();
      const header = ['Ngày', 'Từ giờ', 'Đến giờ', 'Username', 'Họ tên', 'Vai trò', 'Team', 'Thao tác', 'Số lượt', 'Tổng dòng', 'Nội dung'];
      const rows = all.map((g) => [
        fmtNgay(g.last_at), fmtGio(g.first_at), fmtGio(g.last_at), g.username, g.ho_ten || '',
        ROLE_LABELS[g.role] || g.role || '', teamLabel(g.bu), actionLabel(g.action),
        g.so_lan, g.tong_dong, tomTatNhom(g),
      ]);
      const ws = XLSX.utils.aoa_to_sheet([header, ...rows]);
      ws['!cols'] = [{ wch: 11 }, { wch: 7 }, { wch: 7 }, { wch: 16 }, { wch: 22 }, { wch: 14 }, { wch: 12 }, { wch: 20 }, { wch: 8 }, { wch: 9 }, { wch: 70 }];
      const wb = XLSX.utils.book_new();
      XLSX.utils.book_append_sheet(wb, ws, 'Lịch sử');
      XLSX.writeFile(wb, 'lich_su_cap_nhat.xlsx');
    } catch (e) {
      alert('Xuất Excel lỗi: ' + loiMayChu(e));
    } finally {
      setExporting(false);
    }
  };

  const totalPages = Math.max(1, Math.ceil(data.total / LIMIT));
  const sel = 'px-2 py-1.5 text-[12px] border border-slate-200 rounded-md outline-none bg-white';

  return (
    <div className="space-y-3">
      <div className="flex items-center gap-1 flex-wrap">
        {PRESETS.map(([k, label]) => (
          <button
            key={k}
            onClick={() => setPreset(k)}
            className={`px-2.5 py-1 text-[12px] rounded-full border ${preset === k ? 'bg-emerald-600 border-emerald-600 text-white' : 'bg-white border-slate-200 text-slate-600 hover:bg-slate-50'}`}
          >
            {label}
          </button>
        ))}
        {preset === 'custom' && (
          <span className="flex items-center gap-1 ml-1 text-[12px] text-slate-500">
            <input type="date" value={tuNgay} onChange={(e) => setTuNgay(e.target.value)} className={sel} />
            –
            <input type="date" value={denNgay} onChange={(e) => setDenNgay(e.target.value)} className={sel} />
          </span>
        )}
        <div className="flex-1" />
        <button
          onClick={exportExcel}
          disabled={exporting || !data.total}
          className="flex items-center gap-1.5 px-3 py-1.5 text-[12px] font-medium bg-emerald-600 hover:bg-emerald-700 disabled:opacity-50 text-white rounded-md"
        >
          {exporting ? <Loader2 size={13} className="animate-spin" /> : <Download size={13} />}
          Xuất Excel
        </button>
      </div>
      <div className="flex items-center gap-2 flex-wrap">
        <Filter size={13} className="text-slate-400" />
        <select value={filterUser} onChange={(e) => setFilterUser(e.target.value)} className={sel}>
          <option value="">Mọi người dùng</option>
          {data.users.map((u) => (
            <option key={u.username} value={u.username}>{u.ho_ten && u.ho_ten !== u.username ? `${u.ho_ten} (${u.username})` : u.username}</option>
          ))}
        </select>
        <select value={filterGroup} onChange={(e) => setFilterGroup(e.target.value)} className={sel}>
          <option value="">Mọi thao tác</option>
          {Object.entries(ACTION_GROUPS).map(([k, g]) => <option key={k} value={k}>{g.label}</option>)}
        </select>
        <select value={filterBu} onChange={(e) => setFilterBu(e.target.value)} className={sel}>
          <option value="">Mọi team</option>
          {Object.entries(TEAMS).map(([k, t]) => <option key={k} value={k}>{t.label}</option>)}
        </select>
        <div className="relative">
          <Search size={13} className="absolute left-2 top-1/2 -translate-y-1/2 text-slate-400" />
          <input
            value={qInput}
            onChange={(e) => setQInput(e.target.value)}
            placeholder="Tìm khách hàng, sản phẩm, PS..."
            className="pl-7 pr-2 py-1.5 text-[12px] border border-slate-200 rounded-md outline-none w-[240px] focus:border-emerald-400"
          />
        </div>
        <button onClick={() => load(page, filterPayload)} title="Tải lại" className="px-2 py-1.5 text-[12px] text-emerald-600 hover:text-emerald-800">
          <RefreshCw size={13} className={loading ? 'animate-spin' : ''} />
        </button>
        <span className="text-[12px] text-slate-400 ml-auto">
          {`${data.total.toLocaleString('en-US')} nhóm · ${data.tong_ban_ghi.toLocaleString('en-US')} lượt ghi`}
        </span>
      </div>

      {error && <div className="px-3 py-2 text-[12px] text-red-700 bg-red-50 border border-red-200 rounded-md">{error}</div>}

      <div className="bg-white rounded-lg border border-slate-200 overflow-hidden">
        {loading && !data.groups.length ? (
          <div className="px-3 py-10 text-center text-slate-400 text-[12px]">
            <Loader2 size={16} className="inline animate-spin mr-2" />
            Đang tải...
          </div>
        ) : !data.groups.length ? (
          <div className="px-3 py-10 text-center text-slate-400 text-[12px]">Không có thao tác nào trong khoảng đã chọn</div>
        ) : (
          theoNgay.map((d) => (
            <div key={d.ngay}>
              <div className="px-4 py-1.5 bg-slate-50 border-b border-slate-200 text-[11.5px] font-semibold text-slate-600 flex items-center gap-2">
                {tieuDeNgay(d.ngay)}
                <span className="font-normal text-slate-400">{`· ${d.groups.length} nhóm thao tác`}</span>
              </div>
              {d.groups.map((g) => {
                const open = expanded.has(g.key);
                return (
                  <div key={g.key} className="border-b border-slate-100 last:border-b-0">
                    <button
                      onClick={() => toggle(g.key)}
                      className={`w-full text-left px-4 py-2 flex items-start gap-3 hover:bg-slate-50 ${open ? 'bg-blue-50/40' : ''}`}
                    >
                      <span className="w-[86px] shrink-0 text-[12px] tabular-nums text-slate-500 pt-1">
                        {g.so_lan > 1 && fmtGio(g.first_at) !== fmtGio(g.last_at) ? `${fmtGio(g.first_at)}–${fmtGio(g.last_at)}` : fmtGio(g.last_at)}
                      </span>
                      <Avatar name={g.ho_ten || g.username} />
                      <div className="flex-1 min-w-0">
                        <div className="flex items-center gap-2 flex-wrap">
                          <span className="text-[12.5px] font-semibold text-slate-800">{g.ho_ten || g.username}</span>
                          <span className="text-[11px] text-slate-400">{[ROLE_LABELS[g.role] || g.role, teamLabel(g.bu)].filter(Boolean).join(' · ')}</span>
                          <span className={`inline-block px-2 py-0.5 rounded-full text-[10.5px] font-semibold ${actionColor(g.action)}`}>{actionLabel(g.action)}</span>
                          {g.so_lan > 1 && <span className="text-[11px] text-slate-500">{`${g.so_lan} lượt`}</span>}
                        </div>
                        <div className="text-[12px] text-slate-600 truncate mt-0.5" title={tomTatNhom(g)}>{tomTatNhom(g) || '—'}</div>
                      </div>
                      {open ? <ChevronDown size={14} className="text-slate-400 mt-1.5" /> : <ChevronRight size={14} className="text-slate-400 mt-1.5" />}
                    </button>
                    {open && (
                      <div className="ml-[126px] mr-4 mb-3 border border-slate-200 rounded-md overflow-hidden bg-white">
                        <ChiTietNhom g={g} cache={cache} onLoad={loadChiTiet} />
                      </div>
                    )}
                  </div>
                );
              })}
            </div>
          ))
        )}
      </div>
      {totalPages > 1 && (
        <div className="flex items-center justify-between">
          <span className="text-[12px] text-slate-500">{`Trang ${page}/${totalPages}`}</span>
          <div className="flex items-center gap-1">
            <button disabled={page <= 1 || loading} onClick={() => goPage(page - 1)} className="px-2.5 py-1 text-[12px] rounded border border-slate-200 disabled:opacity-40 hover:bg-slate-50">Trước</button>
            <button disabled={page >= totalPages || loading} onClick={() => goPage(page + 1)} className="px-2.5 py-1 text-[12px] rounded border border-slate-200 disabled:opacity-40 hover:bg-slate-50">Sau</button>
          </div>
        </div>
      )}
    </div>
  );
}

// ============ Tổng quan deadline ============
const thangHienTai = () => {
  const d = new Date();
  return `${d.getFullYear()}-${String(d.getMonth() + 1).padStart(2, '0')}`;
};

function TongQuanDeadline({ deadlineDay }) {
  const [thang, setThang] = useState(thangHienTai);
  const [bu, setBu] = useState('');
  const [data, setData] = useState(null);
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState('');

  useEffect(() => {
    let huy = false;
    setLoading(true);
    setError('');
    api('getAuditDeadline', { thang, ...(bu ? { bu } : {}) })
      .then((r) => { if (!huy) setData(r); })
      .catch((e) => { if (!huy) { setError(loiMayChu(e)); setData(null); } })
      .finally(() => { if (!huy) setLoading(false); });
    return () => { huy = true; };
  }, [thang, bu, deadlineDay]);

  // PS lên trước (chưa cập nhật đứng đầu), người ngoài danh sách PS (admin, quản lý) xuống cuối.
  const users = useMemo(() => {
    const list = [...((data && data.users) || [])];
    const hang = (u) => (u.role === 'ps' ? (u.so_lan === 0 ? 0 : 1) : 2);
    return list.sort((a, b) => hang(a) - hang(b) || String(a.bu).localeCompare(String(b.bu)) || String(a.ho_ten).localeCompare(String(b.ho_ten), 'vi'));
  }, [data]);
  const ps = users.filter((u) => u.role === 'ps');
  const daCapNhat = ps.filter((u) => u.so_lan > 0).length;
  const chua = ps.length - daCapNhat;
  const den = data && data.den ? new Date(new Date(data.den).getTime() - 1) : null;
  const sel = 'px-2 py-1.5 text-[12px] border border-slate-200 rounded-md outline-none bg-white';

  return (
    <div className="space-y-3">
      <div className="flex items-center gap-2 flex-wrap">
        <span className="text-[12px] text-slate-600">Kỳ tháng</span>
        <input type="month" value={thang} onChange={(e) => e.target.value && setThang(e.target.value)} className={sel} />
        <select value={bu} onChange={(e) => setBu(e.target.value)} className={sel}>
          <option value="">Mọi team</option>
          {Object.entries(TEAMS).map(([k, t]) => <option key={k} value={k}>{t.label}</option>)}
        </select>
        {data && data.tu && (
          <span className="text-[12px] text-slate-500">
            {`Tính lượt sửa SL KH update từ ${fmtNgay(data.tu)} đến hết ${fmtNgay(den)} (hạn chót ngày ${data.han})`}
          </span>
        )}
      </div>
      {error && <div className="px-3 py-2 text-[12px] text-red-700 bg-red-50 border border-red-200 rounded-md">{error}</div>}
      <div className="grid grid-cols-3 gap-3">
        <div className="bg-white rounded-lg border border-slate-200 p-4">
          <div className="text-[11px] uppercase tracking-wide text-slate-400 font-semibold">PS cần cập nhật</div>
          <div className="text-2xl font-bold text-slate-800 mt-1">{ps.length}</div>
        </div>
        <div className="bg-emerald-50 rounded-lg border border-emerald-200 p-4">
          <div className="text-[11px] uppercase tracking-wide text-emerald-600 font-semibold">Đã cập nhật trước hạn</div>
          <div className="text-2xl font-bold text-emerald-700 mt-1">{daCapNhat}</div>
        </div>
        <div className="bg-red-50 rounded-lg border border-red-200 p-4">
          <div className="text-[11px] uppercase tracking-wide text-red-600 font-semibold">Chưa cập nhật</div>
          <div className="text-2xl font-bold text-red-700 mt-1">{chua}</div>
        </div>
      </div>
      <div className="bg-white rounded-lg border border-slate-200 overflow-hidden">
        <table className="w-full text-[12px]">
          <thead>
            <tr className="bg-slate-50 border-b border-slate-200">
              <th className="px-3 py-2 text-left font-semibold text-slate-600">Người dùng</th>
              <th className="px-3 py-2 text-left font-semibold text-slate-600">Vai trò</th>
              <th className="px-3 py-2 text-left font-semibold text-slate-600">Team</th>
              <th className="px-3 py-2 text-right font-semibold text-slate-600">Số lượt sửa</th>
              <th className="px-3 py-2 text-right font-semibold text-slate-600">Số dòng</th>
              <th className="px-3 py-2 text-left font-semibold text-slate-600">Lần đầu</th>
              <th className="px-3 py-2 text-left font-semibold text-slate-600">Lần cuối</th>
              <th className="px-3 py-2 text-center font-semibold text-slate-600">Trạng thái</th>
            </tr>
          </thead>
          <tbody>
            {loading ? (
              <tr><td colSpan={8} className="px-3 py-8 text-center text-slate-400"><Loader2 size={16} className="inline animate-spin mr-2" />Đang tải...</td></tr>
            ) : !users.length ? (
              <tr><td colSpan={8} className="px-3 py-8 text-center text-slate-400">Chưa có dữ liệu</td></tr>
            ) : (
              users.map((u) => (
                <tr key={u.username} className={`border-b border-slate-100 ${u.role !== 'ps' ? 'text-slate-400 opacity-70' : u.so_lan === 0 ? 'bg-red-50/30' : ''}`}>
                  <td className="px-3 py-2">
                    <div className="font-medium text-slate-800">{u.ho_ten}</div>
                    {u.ho_ten !== u.username && <div className="text-[10px] text-slate-400">{u.username}</div>}
                  </td>
                  <td className="px-3 py-2 text-slate-600">{ROLE_LABELS[u.role] || u.role}</td>
                  <td className="px-3 py-2 text-slate-600">{teamLabel(u.bu)}</td>
                  <td className="px-3 py-2 text-right tabular-nums">{u.so_lan || <span className="text-slate-300">0</span>}</td>
                  <td className="px-3 py-2 text-right tabular-nums">{u.so_dong ? Number(u.so_dong).toLocaleString('en-US') : <span className="text-slate-300">0</span>}</td>
                  <td className="px-3 py-2 text-slate-600 whitespace-nowrap">{fmtNgayGio(u.lan_dau)}</td>
                  <td className="px-3 py-2 text-slate-600 whitespace-nowrap">{fmtNgayGio(u.lan_cuoi)}</td>
                  <td className="px-3 py-2 text-center">
                    {u.role !== 'ps' ? (
                      <span className="inline-block px-2 py-0.5 rounded-full text-[10px] font-semibold bg-slate-100 text-slate-600">Ngoài danh sách PS</span>
                    ) : u.so_lan > 0 ? (
                      <span className="inline-block px-2 py-0.5 rounded-full text-[10px] font-semibold bg-emerald-100 text-emerald-700">Đã cập nhật</span>
                    ) : (
                      <span className="inline-block px-2 py-0.5 rounded-full text-[10px] font-semibold bg-red-100 text-red-700">Chưa cập nhật</span>
                    )}
                  </td>
                </tr>
              ))
            )}
          </tbody>
        </table>
      </div>
      <div className="text-[11px] text-slate-400">
        Sau hạn chót, PS không sửa được SL KH update của tháng đó nữa, nên chỉ có hai trạng thái: đã cập nhật trong kỳ hoặc chưa cập nhật.
      </div>
    </div>
  );
}

export function AuditLogView({ auth }) {
  const [deadlineDay, setDeadlineDay] = useState(5);
  const [editingDeadline, setEditingDeadline] = useState(false);
  const [deadlineInput, setDeadlineInput] = useState('5');
  const [subTab, setSubTab] = useState('log');
  const isAdmin = auth.role === 'admin';

  useEffect(() => {
    api('getAppConfig')
      .then((r) => {
        const v = Number(r.config && r.config.deadline_day) || 5;
        setDeadlineDay(v);
        setDeadlineInput(String(v));
      })
      .catch(() => {});
  }, []);

  const saveDeadline = async () => {
    const v = Math.max(1, Math.min(28, Number(deadlineInput) || 5));
    try {
      await api('setAppConfig', { key: 'deadline_day', value: v });
      setDeadlineDayGlobal(v);
      setDeadlineDay(v);
      setDeadlineInput(String(v));
      setEditingDeadline(false);
    } catch (e) {
      alert('Lưu hạn chót lỗi: ' + loiMayChu(e));
    }
  };

  const subTabBtn = (key, label, Icon) => (
    <button
      onClick={() => setSubTab(key)}
      className={`flex items-center gap-1.5 px-3 py-1.5 text-[12px] font-medium rounded-md transition-colors ${subTab === key ? 'bg-emerald-100 text-emerald-800' : 'bg-white text-slate-600 hover:bg-slate-100'}`}
    >
      {Icon && <Icon size={13} />}
      {label}
    </button>
  );

  return (
    <div className="p-6 space-y-4">
      <div className="flex items-center justify-between gap-3 flex-wrap">
        <div className="flex items-center gap-3">
          <Clock size={20} className="text-emerald-600" />
          <h2 className="text-lg font-bold text-slate-800">Lịch sử cập nhật</h2>
        </div>
        <div className="flex items-center gap-1.5 px-3 py-1.5 bg-slate-50 rounded-md border border-slate-200">
          <Settings size={13} className="text-slate-400" />
          <span className="text-[12px] text-slate-600">Hạn chót cập nhật: ngày </span>
          {editingDeadline ? (
            <>
              <input type="number" min={1} max={28} value={deadlineInput} onChange={(e) => setDeadlineInput(e.target.value)} className="w-10 px-1 py-0.5 text-[12px] border border-emerald-300 rounded text-center outline-none" />
              <button onClick={saveDeadline} className="ml-1 text-emerald-600 hover:text-emerald-800 text-[12px] font-semibold">Lưu</button>
              <button onClick={() => { setEditingDeadline(false); setDeadlineInput(String(deadlineDay)); }} className="ml-1 text-slate-400 hover:text-slate-600 text-[12px]">Hủy</button>
            </>
          ) : (
            <>
              <span className="font-bold text-slate-800 text-[13px]">{deadlineDay}</span>
              <span className="text-[12px] text-slate-600"> hằng tháng</span>
              {isAdmin && (
                <button onClick={() => setEditingDeadline(true)} className="ml-1 text-emerald-500 hover:text-emerald-700 text-[11px] underline">Sửa</button>
              )}
            </>
          )}
        </div>
      </div>
      <div className="flex items-center gap-2">
        {subTabBtn('log', 'Dòng thời gian', Clock)}
        {subTabBtn('deadline', 'Tổng quan deadline', User)}
      </div>
      {subTab === 'deadline' ? <TongQuanDeadline deadlineDay={deadlineDay} /> : <NhatKy />}
    </div>
  );
}
