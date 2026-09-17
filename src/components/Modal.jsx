import { useEffect } from 'react';
import { XIcon } from './icons.jsx';

export function Modal({ open, onClose, title, icon, width = 560, children, footer }) {
  useEffect(() => {
    if (!open) return;
    const onKey = (e) => {
      if (e.key === 'Escape') onClose();
    };
    document.addEventListener('keydown', onKey);
    return () => document.removeEventListener('keydown', onKey);
  }, [open, onClose]);
  if (!open) return null;
  return (
    <div
      onClick={onClose}
      className="fixed inset-0 z-50 bg-slate-900/40 flex items-start justify-center p-4 pt-20 overflow-y-auto"
    >
      <div
        onClick={(e) => e.stopPropagation()}
        style={{ width, maxWidth: '100%' }}
        className="bg-white rounded-lg shadow-xl border border-slate-200"
      >
        <div className="flex items-center gap-2 px-4 py-3 border-b border-slate-100">
          {icon}
          <span className="text-[14px] font-semibold text-slate-800">
            {title}
          </span>
          <div className="flex-1" />
          <button
            onClick={onClose}
            title="Đóng"
            className="p-1 text-slate-400 hover:text-slate-700 hover:bg-slate-100 rounded"
          >
            <XIcon size={16} />
          </button>
        </div>
        {children}
        {footer}
      </div>
    </div>
  );
}
