import { useState, useRef, useEffect, useMemo } from 'react';
import { ChevronDown } from './icons.jsx';
import { TEAMS, TEAM_ALL, MONTHS, CURRENT_MONTH } from '../config/constants.js';
import { moneyTy3 } from '../lib/format.js';

export function TeamSwitcher({ value, onChange }) {
  const [open, setOpen] = useState(false);
  const boxRef = useRef(null);
  useEffect(() => {
    const onDocClick = (e) => {
      if (boxRef.current && !boxRef.current.contains(e.target)) setOpen(false);
    };
    document.addEventListener('mousedown', onDocClick);
    return () => document.removeEventListener('mousedown', onDocClick);
  }, []);
  const options = [
    { key: '', name: 'Tất cả team' },
    ...Object.keys(TEAMS).map((k) => ({ key: k, name: TEAMS[k].name })),
  ];
  const current = options.find((o) => o.key === value) || options[0];
  return (
    <div
      ref={boxRef}
      style={{ position: 'relative', display: 'inline-block' }}
      className="ml-2 align-middle"
    >
      <button
        type="button"
        onClick={() => setOpen((o) => !o)}
        className="flex items-center gap-1 text-[12px] font-medium border border-slate-200 rounded px-1.5 py-0.5 bg-slate-50 hover:bg-slate-100 text-slate-700"
      >
        {current.name}
        <ChevronDown size={12} className="text-slate-400" />
      </button>
      {open && (
        <div className="absolute left-0 top-full mt-1 min-w-[140px] bg-white border border-slate-200 rounded-md shadow-lg z-50 py-1 overflow-hidden">
          {options.map((o) => (
            <div
              key={o.key}
              onClick={() => {
                onChange(o.key);
                setOpen(false);
              }}
              className={`px-3 py-1.5 text-[13px] cursor-pointer ${o.key === value ? 'bg-emerald-50 text-emerald-700 font-medium' : 'text-slate-700 hover:bg-slate-50'}`}
            >
              {o.name}
            </div>
          ))}
        </div>
      )}
    </div>
  );
}

export function TeamSummaryBar({ rows, oopRows, value, onChange }) {
  const realTeams = Object.keys(TEAMS).filter((k) => k !== 'test');
  const teamStats = useMemo(() => {
    const m = {};
    realTeams.forEach((k) => {
      m[k] = { dtUpd: 0, dtYtd: 0, khYtdDt: 0 };
    });
    m[''] = { dtUpd: 0, dtYtd: 0, khYtdDt: 0 };
    const process = (r, isOop) => {
      const bu = r.bu || '';
      const idx = MONTHS.indexOf(r.mo);
      if (idx < 0) return;
      const pr = Number(r.price) || 0;
      const rev = Number(r.rev) || 0;
      const act = Number(r.act) || 0;
      const dtActR = Number(r.dtAct) || 0;
      const rawUpd =
        r.revUpd !== undefined && r.revUpd !== '' && r.revUpd !== null
          ? Number(r.revUpd) || 0
          : rev;
      const useAct =
        MONTHS[idx] < CURRENT_MONTH ||
        (MONTHS[idx] === CURRENT_MONTH && act !== 0);
      const inYtd = MONTHS[idx] <= CURRENT_MONTH;
      const upd = useAct ? act * pr : rawUpd * pr;
      const actDt = dtActR;
      const khDt = rawUpd * pr;
      if (m[bu]) {
        m[bu].dtUpd += upd;
        if (inYtd) {
          m[bu].dtYtd += actDt;
          if (!isOop) m[bu].khYtdDt += khDt;
        }
      }
      m[''].dtUpd += upd;
      if (inYtd) {
        m[''].dtYtd += actDt;
        if (!isOop) m[''].khYtdDt += khDt;
      }
    };
    for (const r of rows) process(r, false);
    for (const r of oopRows) process(r, true);
    return m;
  }, [rows, oopRows]);
  const items = [
    { key: '', label: TEAM_ALL.label, gradient: TEAM_ALL.gradient },
    ...realTeams.map((k) => ({
      key: k,
      label: TEAMS[k].label,
      gradient: TEAMS[k].gradient,
    })),
  ];
  return (
    <div
      className="grid gap-2 mb-3"
      style={{ gridTemplateColumns: `repeat(${items.length}, 1fr)` }}
    >
      {items.map((t) => {
        const s = teamStats[t.key] || { dtUpd: 0, dtYtd: 0, khYtdDt: 0 };
        const pct = s.dtUpd > 0 ? Math.round((s.dtYtd / s.dtUpd) * 100) : 0;
        const pctColor =
          pct >= 100
            ? 'text-emerald-600'
            : pct >= 80
              ? 'text-amber-600'
              : 'text-slate-400';
        const active = value === t.key;
        const masked = value !== '' && !active;
        return (
          <button
            key={t.key}
            type="button"
            onClick={() => onChange(t.key)}
            className={`rounded-lg px-3 py-2.5 text-left transition-all ${active ? 'ring-2 ring-emerald-500 bg-emerald-50' : 'bg-white border border-slate-200 hover:border-slate-300'}`}
          >
            <div className="flex items-center gap-1.5 mb-1.5">
              <div
                className="w-2 h-2 rounded-full shrink-0"
                style={{ background: t.gradient }}
              />
              <span
                className={`text-[11px] font-semibold tracking-wide ${active ? 'text-emerald-700' : 'text-slate-600'}`}
              >
                {t.label}
              </span>
            </div>
            <div className="leading-tight mb-0.5">
              <span className="text-[18px] font-bold tabular-nums text-slate-800">
                {masked ? '**' : moneyTy3(s.dtUpd)}
              </span>
              <span className="text-[11px] text-slate-400 ml-1">KH Update</span>
            </div>
            <div className="flex items-baseline gap-1 mb-1.5">
              <span
                className={`text-[15px] font-bold tabular-nums ${masked ? 'text-slate-400' : pctColor}`}
              >
                {masked ? '**' : s.dtUpd > 0 ? pct + '%' : '—'}
              </span>
              <span className="text-[10px] text-slate-400">TH FY26</span>
            </div>
            <div className="h-1 bg-slate-100 rounded-full overflow-hidden">
              {masked ? null : (
                <div
                  className="h-full rounded-full"
                  style={{
                    width: Math.min(pct, 100) + '%',
                    background: t.gradient,
                  }}
                />
              )}
            </div>
          </button>
        );
      })}
    </div>
  );
}
