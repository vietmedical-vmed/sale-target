import React, { useState, useRef, useEffect } from 'react';
import { fmtFull, fmtInt, fmtM, parseNum, moneyPrice } from '../lib/format.js';
import { MASK_MONEY } from '../config/constants.js';

export const EditableCell = React.memo(function EditableCell({
  value,
  pending,
  onCommit,
  locked,
  width = 64,
  type = 'int',
  bg = '',
}) {
  const [editing, setEditing] = useState(false);
  const [draft, setDraft] = useState('');
  const inputRef = useRef(null);
  useEffect(() => {
    if (editing && inputRef.current) {
      inputRef.current.focus();
      inputRef.current.select();
    }
  }, [editing]);
  let display;
  if (type === 'text') display = value || '·';
  else if (type === 'price') display = fmtM(value);
  else display = value ? fmtInt(value) : '·';

  if (locked) {
    return (
      <td
        className={`px-1.5 py-1.5 text-[12px] text-right tabular-nums border-r border-b border-slate-100 bg-slate-100/70 text-slate-400 cursor-not-allowed select-none ${bg}`}
        style={{
          width,
          minWidth: width,
        }}
        title="Tháng đã qua — không sửa được"
      >
        {display}
      </td>
    );
  }
  if (editing) {
    const commit = () => {
      const nv = type === 'text' ? draft.trim() : parseNum(draft);
      if (nv !== value) onCommit(nv);
      setEditing(false);
    };
    return (
      <td
        className="p-0 border-r border-b border-slate-100"
        style={{
          width,
          minWidth: width,
        }}
      >
        <input
          ref={inputRef}
          value={draft}
          onChange={(e) => setDraft(e.target.value)}
          onBlur={commit}
          onKeyDown={(e) => {
            if (e.key === 'Enter') {
              e.preventDefault();
              commit();
            } else if (e.key === 'Escape') setEditing(false);
          }}
          className={`w-full h-full px-1.5 py-1.5 text-[12px] outline-none ring-2 ring-emerald-500 ring-inset bg-white tabular-nums ${type === 'text' ? 'text-left' : 'text-right'}`}
        />
      </td>
    );
  }
  return (
    <td
      onClick={() => {
        setDraft(value == null ? '' : value);
        setEditing(true);
      }}
      className={`px-1.5 py-1.5 text-[12px] tabular-nums cursor-text border-r border-b border-slate-100 ${type === 'text' ? 'text-left' : 'text-right'} ${pending ? 'bg-amber-50 text-amber-900 font-semibold' : value ? 'text-slate-900 hover:bg-emerald-50/50' : 'text-slate-300 hover:bg-emerald-50/30'} ${bg}`}
      style={{
        width,
        minWidth: width,
      }}
      title={fmtFull(value)}
    >
      {display}
      {pending && (
        <span className="ml-0.5 inline-block w-1 h-1 rounded-full bg-amber-500 align-middle" />
      )}
    </td>
  );
});

export const PriceCell = React.memo(function PriceCell({ value, pending, onCommit, locked, width = 85 }) {
  const [editing, setEditing] = useState(false);
  const [draft, setDraft] = useState('');
  const inputRef = useRef(null);
  useEffect(() => {
    if (editing && inputRef.current) {
      inputRef.current.focus();
      inputRef.current.select();
    }
  }, [editing]);
  const base =
    'px-2 py-1.5 text-[12px] text-right tabular-nums border-r border-b border-slate-100 bg-amber-50/40';
  if (locked) {
    return (
      <td
        className={`${base} text-slate-400 select-none`}
        style={{ width, minWidth: width }}
      >
        {moneyPrice(value)}
      </td>
    );
  }
  if (MASK_MONEY) {
    return (
      <td
        className={`${base} text-slate-400 cursor-not-allowed select-none`}
        style={{ width, minWidth: width }}
        title='Bấm "Hiện DT" để sửa đơn giá'
      >
        •••
      </td>
    );
  }
  if (editing) {
    const commit = () => {
      const tr = parseNum(draft);
      const nv = tr ? Math.round(tr * 1e6) : 0;
      if (nv !== (Number(value) || 0)) onCommit(nv);
      setEditing(false);
    };
    return (
      <td
        className="p-0 border-r border-b border-slate-100"
        style={{ width, minWidth: width }}
      >
        <input
          ref={inputRef}
          value={draft}
          onChange={(e) => setDraft(e.target.value)}
          onBlur={commit}
          onKeyDown={(e) => {
            if (e.key === 'Enter') {
              e.preventDefault();
              commit();
            } else if (e.key === 'Escape') setEditing(false);
          }}
          className="w-full h-full px-2 py-1.5 text-[12px] text-right outline-none ring-2 ring-emerald-500 ring-inset bg-white tabular-nums"
        />
      </td>
    );
  }
  return (
    <td
      onClick={() => {
        setDraft(value ? String(value / 1e6) : '');
        setEditing(true);
      }}
      className={`${base} cursor-text ${pending ? 'text-amber-900 font-semibold !bg-amber-50' : 'text-slate-700 font-medium hover:bg-amber-100/60'}`}
      style={{ width, minWidth: width }}
      title="Đơn giá (triệu VND) — bấm để sửa"
    >
      {moneyPrice(value)}
      {pending && (
        <span className="ml-0.5 inline-block w-1 h-1 rounded-full bg-amber-500 align-middle" />
      )}
    </td>
  );
});
