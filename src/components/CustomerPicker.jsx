import { useState, useEffect, useMemo, useRef, useCallback } from 'react';
import { createPortal } from 'react-dom';
import { custLabel } from '../lib/text.js';

export function CustomerPicker({ customers, value, onChange, className }) {
  const [q, setQ] = useState('');
  const [open, setOpen] = useState(false);
  const [hi, setHi] = useState(0);
  const boxRef = useRef(null);
  const inputRef = useRef(null);
  const dropRef = useRef(null);
  const [pos, setPos] = useState(null);
  const updatePos = useCallback(() => {
    if (!inputRef.current) return;
    const r = inputRef.current.getBoundingClientRect();
    setPos({ top: r.bottom + 4, left: r.left, width: r.width });
  }, []);
  useEffect(() => {
    if (!open) return;
    updatePos();
    window.addEventListener('scroll', updatePos, true);
    window.addEventListener('resize', updatePos);
    return () => {
      window.removeEventListener('scroll', updatePos, true);
      window.removeEventListener('resize', updatePos);
    };
  }, [open, updatePos]);
  const norm = (s) =>
    (s == null ? '' : String(s))
      .toLowerCase()
      .normalize('NFD')
      .replace(/[̀-ͯ]/g, '')
      .replace(/đ/g, 'd');
  const selected = useMemo(
    () => customers.find((c) => (c.custId || c.cust) === value),
    [customers, value],
  );
  const results = useMemo(() => {
    const nq = norm(q).trim();
    if (!nq) return customers.slice(0, 80);
    const toks = nq.split(/\s+/).filter(Boolean);
    return customers
      .filter((c) => {
        const hay = norm(
          (c.cust || '') + ' ' + (c.custId || '') + ' ' + (c.alias || ''),
        );
        return toks.every((t) => hay.includes(t));
      })
      .slice(0, 80);
  }, [customers, q]);
  useEffect(() => {
    setHi(0);
  }, [q, open]);
  useEffect(() => {
    if (!open) return;
    const onDoc = (e) => {
      if (boxRef.current && !boxRef.current.contains(e.target) &&
          (!dropRef.current || !dropRef.current.contains(e.target))) setOpen(false);
    };
    document.addEventListener('mousedown', onDoc);
    return () => document.removeEventListener('mousedown', onDoc);
  }, [open]);
  const pick = (c) => {
    onChange(c.custId || c.cust);
    setOpen(false);
    setQ('');
  };
  const display = selected
    ? custLabel(selected.custId, selected.cust) +
      (selected.custId ? ' · ' + selected.custId : '')
    : '';
  return (
    <div ref={boxRef} className="relative">
      <input
        ref={inputRef}
        value={open ? q : display}
        onChange={(e) => {
          setQ(e.target.value);
          setOpen(true);
        }}
        onFocus={() => {
          setOpen(true);
          setQ('');
        }}
        onKeyDown={(e) => {
          if (e.key === 'ArrowDown') {
            e.preventDefault();
            setOpen(true);
            setHi((i) => Math.min(i + 1, results.length - 1));
          } else if (e.key === 'ArrowUp') {
            e.preventDefault();
            setHi((i) => Math.max(i - 1, 0));
          } else if (e.key === 'Enter') {
            if (open && results[hi]) {
              e.preventDefault();
              pick(results[hi]);
            }
          } else if (e.key === 'Escape') {
            setOpen(false);
          }
        }}
        placeholder={`Tìm theo tên hoặc mã KH… (${customers.length})`}
        className={className}
      />
      {open && pos && createPortal(
        <div
          ref={dropRef}
          style={{ position: 'fixed', top: pos.top, left: pos.left, width: pos.width, zIndex: 9999 }}
          className="bg-white border border-slate-200 rounded-md shadow-lg max-h-64 overflow-y-auto"
        >
          {results.length === 0 ? (
            <div className="px-3 py-2 text-[12px] text-slate-400">
              Không tìm thấy khách hàng
            </div>
          ) : (
            results.map((c, i) => (
              <div
                key={(c.custId || c.cust) + '#' + i}
                onMouseDown={(e) => {
                  e.preventDefault();
                  pick(c);
                }}
                onMouseEnter={() => setHi(i)}
                className={`px-3 py-1.5 text-[12.5px] cursor-pointer flex items-center justify-between gap-2 ${i === hi ? 'bg-emerald-50' : 'hover:bg-slate-50'}`}
              >
                <span className="font-medium text-slate-800 truncate">
                  {custLabel(c.custId, c.cust) || '—'}
                </span>
                {c.custId && (
                  <span className="text-slate-400 text-[11px] font-mono flex-shrink-0">
                    {c.custId}
                  </span>
                )}
              </div>
            ))
          )}
        </div>,
        document.body
      )}
    </div>
  );
}
