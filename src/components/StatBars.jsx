import { AlertCircle } from './icons.jsx';
import { fmtInt, moneyTy3 } from '../lib/format.js';

export function AccountBar({ customers, assigned, missing, onShowMissing }) {
  const pct = assigned > 0 ? Math.round((customers / assigned) * 100) : 0;
  const barColor = pct >= 90 ? '#10b981' : '#ef4444';
  return (
    <div className="bg-white border border-slate-200 rounded-xl p-3.5">
      <div className="text-[11px] text-slate-400 mb-2 tracking-wide">
        Accounts
      </div>
      <div className="flex items-center justify-between mb-1.5">
        <span className="text-[13px] font-semibold text-slate-800">
          {fmtInt(customers) + ' / ' + fmtInt(assigned) + ' KH'}
        </span>
        <span
          className="text-[14px] font-bold tabular-nums"
          style={{ color: barColor }}
        >
          {pct + '%'}
        </span>
      </div>
      <div className="h-3.5 bg-slate-100 rounded overflow-hidden mb-1.5">
        <div
          className="h-full rounded"
          style={{ width: Math.min(pct, 100) + '%', background: barColor }}
        />
      </div>
      <div className="flex flex-wrap items-center justify-between gap-x-2 gap-y-1">
        <span className="text-[11px] text-slate-400">
          Đã có kế hoạch{' '}
          <b className="font-medium text-slate-500">{fmtInt(customers)}</b>/
          Được phân địa bàn{' '}
          <b className="font-medium text-slate-500">{fmtInt(assigned)}</b>
        </span>
        {missing > 0 && onShowMissing && (
          <button
            type="button"
            onClick={onShowMissing}
            className="flex items-center gap-1 text-[11px] font-medium text-blue-600 border border-blue-200 rounded-md px-2 py-0.5 hover:bg-blue-50 transition-colors"
          >
            <AlertCircle size={13} />
            {missing + ' account chưa có KH'}
          </button>
        )}
      </div>
    </div>
  );
}

export function ThYtdBar({ dtYtd, khYtdDt }) {
  const thPct = khYtdDt > 0 ? Math.round((dtYtd / khYtdDt) * 100) : 0;
  const barColor = thPct >= 90 ? '#10b981' : '#ef4444';
  const barWidth = Math.min(thPct, 150);
  const markPos = thPct > 100 ? Math.round((100 / thPct) * 100) : 100;
  return (
    <div className="bg-white border border-slate-200 rounded-xl p-3.5">
      <div className="text-[11px] text-slate-400 mb-2 tracking-wide">
        % Thực hiện YTD
      </div>
      <div className="flex items-center justify-between mb-1.5">
        <span className="text-[13px] font-semibold text-slate-800">
          {moneyTy3(dtYtd)}/ {moneyTy3(khYtdDt)}
        </span>
        <span
          className="text-[14px] font-bold tabular-nums"
          style={{ color: barColor }}
        >
          {khYtdDt > 0 ? thPct + '%' : '—'}
        </span>
      </div>
      <div className="relative h-3.5 bg-slate-100 rounded overflow-hidden mb-1.5">
        <div
          className="h-full rounded"
          style={{ width: Math.min(barWidth, 100) + '%', background: barColor }}
        />
        {khYtdDt > 0 && (
          <div
            className="absolute top-0 bottom-0 w-0.5 bg-slate-800 opacity-40"
            style={{ left: markPos + '%' }}
          />
        )}
        {khYtdDt > 0 && (
          <div
            className="absolute text-[9px] text-slate-500 font-medium"
            style={{
              left: markPos + '%',
              top: '-14px',
              transform: 'translateX(-50%)',
            }}
          >
            100%
          </div>
        )}
      </div>
      <div className="text-[11px] text-slate-400">
        DThu thực hiện / DThu KH update (YTD)
      </div>
    </div>
  );
}

// Top 5 nhóm SP theo % TH YTD (cao -> thấp). rank đã lọc theo BU/bộ lọc đang chọn.
export function GroupRankCard({ rank }) {
  const top = rank.slice(0, 5);
  return (
    // md+: nội dung absolute nên khung không tự cao thêm, chỉ lấp chiều cao hàng
    // (do cột 2 thanh quyết định) -> 5 nhóm giãn đều vừa khung, waterfall giữ nguyên.
    <div className="bg-white border border-slate-200 rounded-xl relative min-h-[200px]">
      <div className="md:absolute md:inset-0 p-3.5 flex flex-col overflow-hidden">
      <div className="text-[11px] text-slate-400 mb-2 tracking-wide">
        Top 5 nhóm SP · % Thực hiện YTD
      </div>
      {top.length === 0 ? (
        <div className="flex-1 flex items-center justify-center text-[12px] text-slate-400">
          Chưa có KH YTD
        </div>
      ) : (
        // Giãn đều 5 dòng cho vừa chiều cao khung (khung cao theo hàng của lưới).
        <div className="flex-1 flex flex-col justify-between gap-1.5">
          {top.map((g, i) => {
            const color = g.pct >= 90 ? '#10b981' : '#ef4444';
            return (
              <div key={g.name} className="flex gap-2" title={g.name}>
                <span className="w-3 shrink-0 text-[11px] text-slate-400 tabular-nums leading-[18px]">
                  {i + 1}
                </span>
                <div className="flex-1 min-w-0">
                  <div className="flex items-baseline gap-2">
                    <span className="flex-1 min-w-0 truncate text-[12px] font-medium text-slate-700">
                      {g.name}
                    </span>
                    <span
                      className="shrink-0 text-[13px] font-bold tabular-nums"
                      style={{ color }}
                    >
                      {g.pct + '%'}
                    </span>
                  </div>
                  <div className="flex items-center gap-2">
                    <div className="flex-1 h-1.5 bg-slate-100 rounded overflow-hidden">
                      <div
                        className="h-full rounded"
                        style={{ width: Math.min(g.pct, 100) + '%', background: color }}
                      />
                    </div>
                    <span className="shrink-0 text-[11px] text-slate-400 tabular-nums">
                      {moneyTy3(g.th) + ' / ' + moneyTy3(g.kh)}
                    </span>
                  </div>
                </div>
              </div>
            );
          })}
        </div>
      )}
      </div>
    </div>
  );
}
