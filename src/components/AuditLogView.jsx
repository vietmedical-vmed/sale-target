import { useState, useEffect, useCallback, useMemo } from 'react';
import {
  Clock, Settings, Download, Filter, RefreshCw, Loader2,
  ChevronDown, User,
} from './icons.jsx';
import { ROLE_LABELS, TEAMS } from '../config/constants.js';
import { api } from '../api/client.js';
import { loadXLSX } from '../lib/excel.js';

const ACTION_LABELS = {
  updateCells: 'Cập nhật ô',
  addProduct: 'Thêm sản phẩm',
  deleteProduct: 'Xóa sản phẩm',
  deleteCustomer: 'Xóa khách hàng',
  saveDiaBan: 'Lưu địa bàn',
  deleteDiaBan: 'Xóa địa bàn',
  setAppConfig: 'Đổi cấu hình',
  saveGiaiTrinh: 'Giải trình',
  syncThucHien: 'Đồng bộ thực hiện',
};
const ACTION_COLORS = {
  updateCells: 'bg-blue-100 text-blue-700',
  addProduct: 'bg-emerald-100 text-emerald-700',
  deleteProduct: 'bg-red-100 text-red-700',
  deleteCustomer: 'bg-red-100 text-red-700',
  saveDiaBan: 'bg-violet-100 text-violet-700',
  deleteDiaBan: 'bg-red-100 text-red-700',
  setAppConfig: 'bg-amber-100 text-amber-700',
  saveGiaiTrinh: 'bg-amber-100 text-amber-700',
  syncThucHien: 'bg-blue-100 text-blue-700',
};
const DB_COL_LABELS = {
  quota_thau_cu_con_lai: 'Quota thầu cũ',
  thang_thau_chinh: 'Tháng thầu chính',
  thoi_gian_thau_chinh: 'TG thầu chính',
  quota_thau_chinh: 'Quota thầu chính',
  thang_thau_bo_sung: 'Tháng thầu BS',
  quota_bo_sung: 'Quota thầu bổ sung',
  sl_ke_hoach_dau_nam: 'SL KH đầu năm',
  sl_ke_hoach_update: 'SL KH update',
  don_gia: 'Đơn giá',
  sl_thuc_hien: 'SL thực hiện',
  doanh_thu_kh_dau_nam: 'Dthu KH đầu năm',
  bo_vat_tu: 'Bộ vật tư',
  san_pham: 'Sản phẩm',
};

function DeadlineDashboard({ data, deadlineDay, fmtTime }) {
  if (data.length === 0)
    return (
      <div className="bg-white rounded-lg border border-slate-200 px-4 py-12 text-center text-slate-400 text-[13px]">
        Chưa có dữ liệu
      </div>
    );
  const onTimeCount = data.filter((u) => u.late === 0 && u.count > 0).length;
  const lateCount = data.filter((u) => u.late > 0).length;
  return (
    <div className="space-y-4">
      <div className="grid grid-cols-3 gap-3">
        <div className="bg-white rounded-lg border border-slate-200 p-4">
          <div className="text-[11px] uppercase tracking-wide text-slate-400 font-semibold">Tổng người dùng</div>
          <div className="text-2xl font-bold text-slate-800 mt-1">{data.length}</div>
        </div>
        <div className="bg-emerald-50 rounded-lg border border-emerald-200 p-4">
          <div className="text-[11px] uppercase tracking-wide text-emerald-600 font-semibold">Đúng hạn</div>
          <div className="text-2xl font-bold text-emerald-700 mt-1">{onTimeCount}</div>
        </div>
        <div className="bg-red-50 rounded-lg border border-red-200 p-4">
          <div className="text-[11px] uppercase tracking-wide text-red-600 font-semibold">Có trễ hạn</div>
          <div className="text-2xl font-bold text-red-700 mt-1">{lateCount}</div>
        </div>
      </div>
      <div className="bg-white rounded-lg border border-slate-200 overflow-hidden">
        <table className="w-full text-[12px]">
          <thead>
            <tr className="bg-slate-50 border-b border-slate-200">
              <th className="px-3 py-2 text-left font-semibold text-slate-600">Người dùng</th>
              <th className="px-3 py-2 text-left font-semibold text-slate-600">Vai trò</th>
              <th className="px-3 py-2 text-left font-semibold text-slate-600">Team</th>
              <th className="px-3 py-2 text-right font-semibold text-slate-600">Tổng lượt</th>
              <th className="px-3 py-2 text-right font-semibold text-emerald-600">Đúng hạn</th>
              <th className="px-3 py-2 text-right font-semibold text-red-600">Trễ hạn</th>
              <th className="px-3 py-2 text-center font-semibold text-slate-600">Tỷ lệ đúng hạn</th>
              <th className="px-3 py-2 text-left font-semibold text-slate-600">Cập nhật cuối</th>
              <th className="px-3 py-2 text-center font-semibold text-slate-600">Trạng thái</th>
            </tr>
          </thead>
          <tbody>
            {data.map((u) => {
              const pct = u.count > 0 ? Math.round((u.onTime / u.count) * 100) : 0;
              const lastLate = new Date(u.lastAt).getDate() > deadlineDay;
              return (
                <tr key={u.username} className="border-b border-slate-100 hover:bg-slate-50/50">
                  <td className="px-3 py-2">
                    <div className="font-medium text-slate-800">{u.ho_ten}</div>
                    <div className="text-[10px] text-slate-400">{u.username}</div>
                  </td>
                  <td className="px-3 py-2 text-slate-600">{ROLE_LABELS[u.role] || u.role}</td>
                  <td className="px-3 py-2 text-slate-600">{(TEAMS[u.bu] && TEAMS[u.bu].label) || u.bu || ''}</td>
                  <td className="px-3 py-2 text-right tabular-nums font-medium">{u.count}</td>
                  <td className="px-3 py-2 text-right tabular-nums text-emerald-700">{u.onTime}</td>
                  <td className="px-3 py-2 text-right tabular-nums text-red-600">{u.late}</td>
                  <td className="px-3 py-2 text-center">
                    <div className="flex items-center gap-2 justify-center">
                      <div className="w-16 h-1.5 bg-slate-200 rounded-full overflow-hidden">
                        <div className={`h-full rounded-full ${pct >= 80 ? 'bg-emerald-500' : pct >= 50 ? 'bg-amber-500' : 'bg-red-500'}`} style={{ width: pct + '%' }} />
                      </div>
                      <span className={`text-[11px] font-semibold ${pct >= 80 ? 'text-emerald-700' : pct >= 50 ? 'text-amber-600' : 'text-red-600'}`}>{pct + '%'}</span>
                    </div>
                  </td>
                  <td className="px-3 py-2 text-slate-600 whitespace-nowrap">{fmtTime(u.lastAt)}</td>
                  <td className="px-3 py-2 text-center">
                    <span className={`inline-block px-2 py-0.5 rounded-full text-[10px] font-semibold ${lastLate ? 'bg-red-100 text-red-700' : 'bg-emerald-100 text-emerald-700'}`}>
                      {lastLate ? 'Lần cuối trễ' : 'Đúng hạn'}
                    </span>
                  </td>
                </tr>
              );
            })}
          </tbody>
        </table>
      </div>
    </div>
  );
}

export function AuditLogView({ auth, viewBu }) {
  const [logs, setLogs] = useState([]);
  const [total, setTotal] = useState(0);
  const [page, setPage] = useState(1);
  const [loading, setLoading] = useState(false);
  const [filterUser, setFilterUser] = useState('');
  const [filterAction, setFilterAction] = useState('');
  const [filterBu, setFilterBu] = useState('');
  const [config, setConfig] = useState({});
  const [deadlineDay, setDeadlineDay] = useState(5);
  const [editingDeadline, setEditingDeadline] = useState(false);
  const [deadlineInput, setDeadlineInput] = useState('5');
  const [subTab, setSubTab] = useState('log');
  const [expandedGroup, setExpandedGroup] = useState(null);
  const LIMIT = 50;
  const isAdmin = auth.role === 'admin';

  const loadConfig = useCallback(async () => {
    try {
      const r = await api('getAppConfig');
      if (r.config) {
        setConfig(r.config);
        setDeadlineDay(Number(r.config.deadline_day) || 5);
        setDeadlineInput(String(Number(r.config.deadline_day) || 5));
      }
    } catch (_) { /* ignore */ }
  }, []);

  const loadLogs = useCallback(
    async (p) => {
      setLoading(true);
      try {
        const payload = { page: p, limit: LIMIT };
        if (filterUser) payload.username = filterUser;
        if (filterAction) payload.action = filterAction;
        if (filterBu) payload.bu = filterBu;
        const r = await api('getAuditLog', payload);
        setLogs(r.logs || []);
        setTotal(r.total || 0);
      } catch (e) {
        setLogs([]);
      } finally {
        setLoading(false);
      }
    },
    [filterUser, filterAction, filterBu],
  );

  useEffect(() => { loadConfig(); }, []);
  useEffect(() => { setPage(1); loadLogs(1); }, [filterUser, filterAction, filterBu]);
  useEffect(() => { loadLogs(page); }, [page]);

  const totalPages = Math.max(1, Math.ceil(total / LIMIT));

  const isLate = (createdAt) => {
    const d = new Date(createdAt);
    return d.getDate() > deadlineDay;
  };

  const deadlineTag = (createdAt) => {
    const late = isLate(createdAt);
    return (
      <span className={`inline-block px-1.5 py-0.5 rounded text-[10px] font-semibold ${late ? 'bg-red-100 text-red-700' : 'bg-emerald-100 text-emerald-700'}`}>
        {late ? 'Trễ hạn' : 'Đúng hạn'}
      </span>
    );
  };

  const saveDeadline = async () => {
    const v = Math.max(1, Math.min(28, Number(deadlineInput) || 5));
    try {
      await api('setAppConfig', { key: 'deadline_day', value: v });
      setDeadlineDay(v);
      setDeadlineInput(String(v));
      setEditingDeadline(false);
      loadLogs(page);
    } catch (_) { /* ignore */ }
  };

  const fmtTime = (iso) => {
    const d = new Date(iso);
    const pad = (n) => String(n).padStart(2, '0');
    return `${pad(d.getDate())}/${pad(d.getMonth() + 1)}/${d.getFullYear()} ${pad(d.getHours())}:${pad(d.getMinutes())}`;
  };

  const uniqueUsers = useMemo(() => {
    const s = new Set(logs.map((l) => l.username));
    return [...s].sort();
  }, [logs]);

  const fmtDate = (iso) => {
    const d = new Date(iso);
    const pad = (n) => String(n).padStart(2, '0');
    return `${pad(d.getDate())}/${pad(d.getMonth() + 1)}/${d.getFullYear()}`;
  };

  const grouped = useMemo(() => {
    const map = new Map();
    for (const l of logs) {
      const day = fmtDate(l.created_at);
      const key = day + '|' + l.username + '|' + l.action;
      if (!map.has(key)) {
        map.set(key, {
          key, day, username: l.username, ho_ten: l.ho_ten,
          role: l.role, bu: l.bu, action: l.action,
          row_count: 0, count: 0, first_at: l.created_at, last_at: l.created_at, details: [],
        });
      }
      const g = map.get(key);
      g.row_count += l.row_count || 0;
      g.count++;
      if (l.created_at < g.first_at) g.first_at = l.created_at;
      if (l.created_at > g.last_at) g.last_at = l.created_at;
      if (l.details) g.details.push(l.details);
    }
    return [...map.values()];
  }, [logs]);

  const exportExcel = async () => {
    const XLSX = await loadXLSX();
    const header = ['Ngày', 'Username', 'Họ tên', 'Vai trò', 'Team', 'Thao tác', 'Số lần', 'Tổng dòng', 'Deadline', 'Khoảng giờ'];
    const rows = grouped.map((g) => [
      g.day, g.username, g.ho_ten || '', g.role || '',
      (TEAMS[g.bu] && TEAMS[g.bu].label) || g.bu || '',
      ACTION_LABELS[g.action] || g.action, g.count, g.row_count,
      isLate(g.last_at) ? 'Trễ hạn' : 'Đúng hạn',
      g.count > 1
        ? fmtTime(g.first_at).split(' ')[1] + ' – ' + fmtTime(g.last_at).split(' ')[1]
        : fmtTime(g.last_at).split(' ')[1],
    ]);
    const ws = XLSX.utils.aoa_to_sheet([header, ...rows]);
    ws['!cols'] = [{ wch: 12 }, { wch: 14 }, { wch: 20 }, { wch: 14 }, { wch: 10 }, { wch: 18 }, { wch: 8 }, { wch: 10 }, { wch: 10 }, { wch: 14 }];
    const wb = XLSX.utils.book_new();
    XLSX.utils.book_append_sheet(wb, ws, 'Lịch sử');
    XLSX.writeFile(wb, 'lich_su_cap_nhat.xlsx');
  };

  const dashboardData = useMemo(() => {
    const byUser = new Map();
    for (const l of logs) {
      if (!byUser.has(l.username)) {
        byUser.set(l.username, {
          username: l.username, ho_ten: l.ho_ten || l.username,
          role: l.role, bu: l.bu, count: 0, lastAt: l.created_at, onTime: 0, late: 0,
        });
      }
      const u = byUser.get(l.username);
      u.count++;
      if (l.created_at > u.lastAt) u.lastAt = l.created_at;
      if (isLate(l.created_at)) u.late++;
      else u.onTime++;
    }
    return [...byUser.values()].sort((a, b) => b.count - a.count);
  }, [logs, deadlineDay]);

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
      <div className="flex items-center justify-between">
        <div className="flex items-center gap-3">
          <Clock size={20} className="text-emerald-600" />
          <h2 className="text-lg font-bold text-slate-800">Lịch sử cập nhật</h2>
          <span className="text-[12px] text-slate-400">{total + ' bản ghi'}</span>
        </div>
        <div className="flex items-center gap-2">
          <div className="flex items-center gap-1.5 px-3 py-1.5 bg-slate-50 rounded-md border border-slate-200">
            <Settings size={13} className="text-slate-400" />
            <span className="text-[12px] text-slate-600">Deadline: ngày </span>
            {editingDeadline ? (
              <>
                <input type="number" min={1} max={28} value={deadlineInput} onChange={(e) => setDeadlineInput(e.target.value)} className="w-10 px-1 py-0.5 text-[12px] border border-emerald-300 rounded text-center outline-none" />
                <button onClick={saveDeadline} className="ml-1 text-emerald-600 hover:text-emerald-800 text-[12px] font-semibold">Lưu</button>
                <button onClick={() => { setEditingDeadline(false); setDeadlineInput(String(deadlineDay)); }} className="ml-1 text-slate-400 hover:text-slate-600 text-[12px]">Hủy</button>
              </>
            ) : (
              <>
                <span className="font-bold text-slate-800 text-[13px]">{deadlineDay}</span>
                {isAdmin && (
                  <button onClick={() => setEditingDeadline(true)} className="ml-1 text-emerald-500 hover:text-emerald-700 text-[11px] underline">Sửa</button>
                )}
              </>
            )}
          </div>
          <button onClick={exportExcel} className="flex items-center gap-1.5 px-3 py-1.5 text-[12px] font-medium bg-emerald-600 hover:bg-emerald-700 text-white rounded-md">
            <Download size={13} />
            Xuất Excel
          </button>
        </div>
      </div>
      <div className="flex items-center gap-2">
        {subTabBtn('log', 'Chi tiết log', Clock)}
        {subTabBtn('dashboard', 'Tổng quan deadline', User)}
      </div>
      {subTab === 'dashboard' ? (
        <DeadlineDashboard data={dashboardData} deadlineDay={deadlineDay} fmtTime={fmtTime} />
      ) : (
        <>
          <div className="flex items-center gap-2 flex-wrap">
            <Filter size={13} className="text-slate-400" />
            <select value={filterUser} onChange={(e) => setFilterUser(e.target.value)} className="px-2 py-1.5 text-[12px] border border-slate-200 rounded-md outline-none">
              <option value="">Tất cả user</option>
              {uniqueUsers.map((u) => <option key={u} value={u}>{u}</option>)}
            </select>
            <select value={filterAction} onChange={(e) => setFilterAction(e.target.value)} className="px-2 py-1.5 text-[12px] border border-slate-200 rounded-md outline-none">
              <option value="">Tất cả thao tác</option>
              {Object.entries(ACTION_LABELS).map(([k, v]) => <option key={k} value={k}>{v}</option>)}
            </select>
            <select value={filterBu} onChange={(e) => setFilterBu(e.target.value)} className="px-2 py-1.5 text-[12px] border border-slate-200 rounded-md outline-none">
              <option value="">Tất cả team</option>
              {Object.entries(TEAMS).map(([k, t]) => <option key={k} value={k}>{t.label}</option>)}
            </select>
            <button onClick={() => loadLogs(page)} className="px-2 py-1.5 text-[12px] text-emerald-600 hover:text-emerald-800">
              <RefreshCw size={13} />
            </button>
          </div>
          <div className="bg-white rounded-lg border border-slate-200 overflow-hidden">
            <div className="overflow-x-auto">
              <table className="w-full text-[12px]">
                <thead>
                  <tr className="bg-slate-50 border-b border-slate-200">
                    <th className="px-3 py-2 text-left font-semibold text-slate-600">Ngày</th>
                    <th className="px-3 py-2 text-left font-semibold text-slate-600">Người dùng</th>
                    <th className="px-3 py-2 text-left font-semibold text-slate-600">Vai trò</th>
                    <th className="px-3 py-2 text-left font-semibold text-slate-600">Team</th>
                    <th className="px-3 py-2 text-left font-semibold text-slate-600">Thao tác</th>
                    <th className="px-3 py-2 text-right font-semibold text-slate-600">Số lần</th>
                    <th className="px-3 py-2 text-right font-semibold text-slate-600">Tổng dòng</th>
                    <th className="px-3 py-2 text-center font-semibold text-slate-600">Deadline</th>
                    <th className="px-3 py-2 text-left font-semibold text-slate-600">Khoảng giờ</th>
                  </tr>
                </thead>
                <tbody>
                  {loading ? (
                    <tr><td colSpan={9} className="px-3 py-8 text-center text-slate-400"><Loader2 size={16} className="inline animate-spin mr-2" />Đang tải...</td></tr>
                  ) : grouped.length === 0 ? (
                    <tr><td colSpan={9} className="px-3 py-8 text-center text-slate-400">Chưa có bản ghi nào</td></tr>
                  ) : (
                    grouped.map((g) => {
                      const hasChanges = g.action === 'updateCells' && g.details.some((d) => d && d.changes && d.changes.length > 0);
                      const isExpanded = expandedGroup === g.key;
                      const allChanges = hasChanges ? g.details.flatMap((d) => (d && d.changes) || []) : [];
                      return (
                        <tr key={g.key} className={'border-b border-slate-100 hover:bg-slate-50/50' + (hasChanges ? ' cursor-pointer' : '') + (isExpanded ? ' bg-blue-50/40' : '')} onClick={hasChanges ? () => setExpandedGroup(isExpanded ? null : g.key) : undefined}>
                          <td className="px-3 py-2 text-slate-700 whitespace-nowrap">
                            {hasChanges && <ChevronDown size={12} className={'inline mr-1 text-slate-400 transition-transform' + (isExpanded ? ' rotate-180' : '')} />}
                            {g.day}
                          </td>
                          <td className="px-3 py-2">
                            <div className="font-medium text-slate-800">{g.ho_ten || g.username}</div>
                            {g.ho_ten && <div className="text-[10px] text-slate-400">{g.username}</div>}
                          </td>
                          <td className="px-3 py-2 text-slate-600">{ROLE_LABELS[g.role] || g.role}</td>
                          <td className="px-3 py-2 text-slate-600">{(TEAMS[g.bu] && TEAMS[g.bu].label) || g.bu || ''}</td>
                          <td className="px-3 py-2">
                            <span className={`inline-block px-2 py-0.5 rounded-full text-[10px] font-semibold ${ACTION_COLORS[g.action] || 'bg-slate-100 text-slate-600'}`}>{ACTION_LABELS[g.action] || g.action}</span>
                          </td>
                          <td className="px-3 py-2 text-right tabular-nums font-medium text-slate-700">{g.count > 1 ? g.count + ' lần' : '1 lần'}</td>
                          <td className="px-3 py-2 text-right tabular-nums font-medium text-slate-700">{g.row_count}</td>
                          <td className="px-3 py-2 text-center">{deadlineTag(g.last_at)}</td>
                          <td className="px-3 py-2 text-slate-500 whitespace-nowrap">
                            {g.count > 1
                              ? fmtTime(g.first_at).split(' ')[1] + ' – ' + fmtTime(g.last_at).split(' ')[1]
                              : fmtTime(g.last_at).split(' ')[1]}
                          </td>
                        </tr>
                      );
                    })
                  )}
                </tbody>
              </table>
            </div>
          </div>
          {totalPages > 1 && (
            <div className="flex items-center justify-between pt-2">
              <span className="text-[12px] text-slate-500">Trang {page}/ {totalPages}({total}bản ghi)</span>
              <div className="flex items-center gap-1">
                <button disabled={page <= 1} onClick={() => setPage((p) => Math.max(1, p - 1))} className="px-2.5 py-1 text-[12px] rounded border border-slate-200 disabled:opacity-40 hover:bg-slate-50">Trước</button>
                <button disabled={page >= totalPages} onClick={() => setPage((p) => Math.min(totalPages, p + 1))} className="px-2.5 py-1 text-[12px] rounded border border-slate-200 disabled:opacity-40 hover:bg-slate-50">Sau</button>
              </div>
            </div>
          )}
        </>
      )}
    </div>
  );
}
