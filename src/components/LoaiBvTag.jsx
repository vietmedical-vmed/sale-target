import React from 'react';

// Tag Công/Tư cạnh tên bệnh viện (dm_khach_hang.type_lvl2). Giá trị khác → không hiện.
const STYLE = {
  Công: 'bg-sky-50 text-sky-700 border-sky-200',
  Tư: 'bg-violet-50 text-violet-700 border-violet-200',
};

export function LoaiBvTag({ loaiBv }) {
  const cls = STYLE[loaiBv];
  if (!cls) return null;
  return (
    <span
      title={`Bệnh viện ${loaiBv.toLowerCase()}`}
      className={`flex-shrink-0 px-1.5 py-0.5 text-[10.5px] font-medium rounded border whitespace-nowrap ${cls}`}
    >
      {loaiBv}
    </span>
  );
}
