import { useState, useEffect } from 'react';
import { api } from '../api/client.js';

export let _openGiaiTrinh = null;
export function setOpenGiaiTrinh(fn) { _openGiaiTrinh = fn; }

export function GiaiTrinhModal({ info, onClose, auth }) {
  const [logs, setLogs] = useState([]);
  const [loading, setLoading] = useState(true);
  const [draft, setDraft] = useState('');
  const [saving, setSaving] = useState(false);
  const canEdit =
    auth &&
    (auth.role === 'admin' ||
      auth.role === 'manager' ||
      auth.role === 'area_manager' ||
      auth.role === 'ps' ||
      auth.role === 'product_manager');

  useEffect(() => {
    if (!info) return;
    setLoading(true);
    api('getGiaiTrinh', {
      ps: info.ps,
      customer_id: info.custId,
      grp: info.grp,
    })
      .then((r) => setLogs(r.logs || []))
      .catch(() => setLogs([]))
      .finally(() => setLoading(false));
  }, [info]);

  const save = async () => {
    if (!draft.trim()) return;
    setSaving(true);
    try {
      const r = await api('saveGiaiTrinh', {
        ps: info.ps,
        customer_id: info.custId,
        grp: info.grp,
        content: draft.trim(),
      });
      if (r.entry) setLogs((prev) => [r.entry, ...prev]);
      setDraft('');
    } catch (e) {
      alert('Lỗi: ' + (e.message || e));
    }
    setSaving(false);
  };

  const fmtDate = (s) => {
    try {
      const d = new Date(s);
      return (
        d.toLocaleDateString('vi-VN', {
          day: '2-digit',
          month: '2-digit',
          year: 'numeric',
        }) +
        ' ' +
        d.toLocaleTimeString('vi-VN', { hour: '2-digit', minute: '2-digit' })
      );
    } catch {
      return s;
    }
  };

  if (!info) return null;
  return (
    <div
      className="fixed inset-0 z-[999] flex items-center justify-center"
      onClick={(e) => {
        if (e.target === e.currentTarget) onClose();
      }}
    >
      <div className="fixed inset-0 bg-black/40" />
      <div className="relative bg-white rounded-xl shadow-2xl w-full max-w-lg mx-4 max-h-[80vh] flex flex-col">
        <div className="flex items-center justify-between px-5 py-3 border-b border-slate-200">
          <div>
            <h3 className="text-[14px] font-bold text-slate-800">Giải trình</h3>
            <p className="text-[11px] text-slate-500 mt-0.5">
              {info.grp}· {info.ps}
            </p>
          </div>
          <button
            className="text-slate-400 hover:text-slate-600 text-xl leading-none p-1"
            onClick={onClose}
          >
            ×
          </button>
        </div>
        {canEdit && (
          <div className="px-5 py-3 border-b border-slate-100">
            <textarea
              className="w-full text-[12px] px-3 py-2 border border-slate-200 rounded-lg resize-none focus:border-emerald-500 focus:ring-2 focus:ring-emerald-100 outline-none"
              rows={3}
              placeholder="Nhập giải trình mới…"
              value={draft}
              onChange={(e) => setDraft(e.target.value)}
            />
            <div className="flex justify-end mt-2">
              <button
                className={
                  'px-4 py-1.5 text-[12px] font-medium rounded-lg ' +
                  (draft.trim() && !saving
                    ? 'bg-emerald-600 text-white hover:bg-emerald-700'
                    : 'bg-slate-100 text-slate-400 cursor-not-allowed')
                }
                disabled={!draft.trim() || saving}
                onClick={save}
              >
                {saving ? 'Đang lưu…' : 'Lưu giải trình'}
              </button>
            </div>
          </div>
        )}
        <div className="flex-1 overflow-y-auto px-5 py-3">
          {loading ? (
            <p className="text-[12px] text-slate-400 text-center py-6">
              Đang tải…
            </p>
          ) : logs.length === 0 ? (
            <p className="text-[12px] text-slate-400 text-center py-6">
              Chưa có giải trình nào
            </p>
          ) : (
            logs.map((l) => (
              <div
                key={l.id}
                className="mb-3 pb-3 border-b border-slate-100 last:border-0"
              >
                <div className="flex items-center gap-2 mb-1">
                  <span className="text-[11px] font-semibold text-slate-700">
                    {l.created_by}
                  </span>
                  <span className="text-[10px] text-slate-400">
                    {fmtDate(l.created_at)}
                  </span>
                </div>
                <p className="text-[12px] text-slate-600 whitespace-pre-wrap break-words">
                  {l.content}
                </p>
              </div>
            ))
          )}
        </div>
      </div>
    </div>
  );
}
