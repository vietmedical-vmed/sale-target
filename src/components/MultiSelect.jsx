import { useState, useRef, useEffect } from 'react';
import { Check, ChevronDown } from './icons.jsx';
import { deaccent } from '../lib/text.js';

export function MultiSelect({ label, options, selected, onChange, searchable }) {
  const [open, setOpen] = useState(false);
  const [q, setQ] = useState('');
  const boxRef = useRef(null);
  useEffect(() => {
    const onDoc = (e) => {
      if (boxRef.current && !boxRef.current.contains(e.target)) setOpen(false);
    };
    document.addEventListener('mousedown', onDoc);
    return () => document.removeEventListener('mousedown', onDoc);
  }, []);
  const sel = selected || [];
  const shown =
    searchable && q.trim()
      ? options.filter((o) => deaccent(o.label).includes(deaccent(q.trim())))
      : options;
  const toggle = (v) =>
    sel.includes(v)
      ? onChange(sel.filter((x) => x !== v))
      : onChange([...sel, v]);
  const summary =
    sel.length === 0
      ? 'tất cả'
      : sel.length === 1
        ? (options.find((o) => o.value === sel[0]) || {}).label || sel[0]
        : `${sel.length} mục`;
  return (
    <div ref={boxRef} className="relative inline-block">
      <button
        type="button"
        onClick={() => setOpen((o) => !o)}
        className="flex items-center gap-1.5 px-2.5 py-1.5 text-[13px] border border-slate-200 rounded-md bg-white hover:border-slate-300 outline-none focus:border-emerald-500 focus:ring-2 focus:ring-emerald-100 max-w-[240px]"
      >
        <span className="text-slate-400 shrink-0">{label + ':'}</span>
        <span
          className={`truncate ${sel.length ? 'text-emerald-700 font-medium' : 'text-slate-600'}`}
        >
          {summary}
        </span>
        <ChevronDown size={13} className="text-slate-400 shrink-0" />
      </button>
      {open && (
        <div className="absolute left-0 top-full mt-1 min-w-[220px] max-w-[320px] bg-white border border-slate-200 rounded-md shadow-lg z-50 py-1">
          {searchable && (
            <div className="px-2 pb-1.5 pt-0.5">
              <input
                value={q}
                onChange={(e) => setQ(e.target.value)}
                autoFocus
                placeholder="Tìm…"
                className="w-full px-2 py-1 text-[12px] border border-slate-200 rounded outline-none focus:border-emerald-500"
              />
            </div>
          )}
          <div
            onClick={() => onChange([])}
            className={`px-3 py-1.5 text-[13px] cursor-pointer border-b border-slate-100 ${sel.length === 0 ? 'text-emerald-700 font-medium' : 'text-slate-500 hover:bg-slate-50'}`}
          >
            Tất cả (bỏ lọc)
          </div>
          <div className="max-h-[260px] overflow-y-auto">
            {shown.length === 0 ? (
              <div className="px-3 py-2 text-[12px] text-slate-400">
                Không có mục
              </div>
            ) : (
              shown.map((o) => {
                const on = sel.includes(o.value);
                return (
                  <div
                    key={o.value}
                    onClick={() => toggle(o.value)}
                    className={`flex items-center gap-2 px-3 py-1.5 text-[13px] cursor-pointer ${on ? 'bg-emerald-50/60 text-emerald-800' : 'text-slate-700 hover:bg-slate-50'}`}
                  >
                    <span
                      className={`w-3.5 h-3.5 rounded border flex items-center justify-center shrink-0 ${on ? 'bg-emerald-500 border-emerald-500 text-white' : 'border-slate-300'}`}
                    >
                      {on ? <Check size={11} /> : null}
                    </span>
                    <span className="truncate">{o.label}</span>
                  </div>
                );
              })
            )}
          </div>
        </div>
      )}
    </div>
  );
}
