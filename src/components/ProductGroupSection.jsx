import React, { useState, useEffect, useMemo, useRef, useContext } from 'react';
import { ChevronDown, ChevronRight, Trash2 } from './icons.jsx';
import { CURRENT_MONTH, MASK_MONEY, MONTHS, MONTH_LABELS, isYtdMonth } from '../config/constants.js';
import { fmtInt, fmtTy3, moneyTy3 } from '../lib/format.js';
import { EditableCell, PriceCell } from './EditableCell.jsx';
import { GroupMonthField, QuotaThauCtx, DotThauPanel, QuotaThauModal, QuotaCell, prodKey } from './QuotaThau.jsx';
import { GiaiTrinhModal, _openGiaiTrinh, setOpenGiaiTrinh } from './GiaiTrinhModal.jsx';

// ============ PRODUCT ROW ============
// Inline-edit cho ô sticky (bộ vật tư / sản phẩm) — chỉ dùng cho admin.
function StickyEdit({ value, onSave, className = '', title }) {
  const [editing, setEditing] = useState(false);
  const [draft, setDraft] = useState(value || '');
  const ref = useRef(null);
  useEffect(() => {
    if (editing && ref.current) {
      ref.current.focus();
      ref.current.select();
    }
  }, [editing]);
  useEffect(() => {
    setDraft(value || '');
  }, [value]);
  if (editing) {
    const commit = () => {
      const v = draft.trim();
      if (v !== (value || '')) onSave(v);
      setEditing(false);
    };
    return (
      <input
        ref={ref}
        value={draft}
        onChange={(e) => setDraft(e.target.value)}
        onBlur={commit}
        onKeyDown={(e) => {
          if (e.key === 'Enter') {
            e.preventDefault();
            commit();
          } else if (e.key === 'Escape') setEditing(false);
        }}
        className="w-full px-1 py-0.5 text-[12px] outline-none ring-2 ring-emerald-500 ring-inset bg-white rounded"
      />
    );
  }
  return (
    <div
      className={`${className} cursor-text hover:bg-emerald-50/60 rounded px-0.5 -mx-0.5`}
      title={(title || value || '') + ' — bấm để sửa'}
      onClick={() => {
        setDraft(value || '');
        setEditing(true);
      }}
    >
      {value || '·'}
    </div>
  );
}

// monthly[i] = { rev, dt, revUpd, hasUpd, rows: [...] }
function ProductRow({
  product,
  mset,
  showMset,
  monthly,
  pendingKeys,
  onCommit,
  canEdit,
  isAdmin,
  onDeleteProduct,
  showBasePlan,
  productCode,
}) {
  const allRows = useMemo(() => monthly.flatMap((c) => c.rows), [monthly]);
  const anchor = allRows.length ? allRows[0] : null;
  // Quota nay đọc từ shared.quota_thau (tách theo mức giá và theo đợt). Chừng nào
  // sản phẩm chưa có dòng nào bên bảng mới thì vẫn hiện số cũ trên sale_target,
  // nhờ vậy màn hình không rỗng trong lúc hai nguồn còn chạy song song.
  const quotaCtx = useContext(QuotaThauCtx);
  const [quotaOpen, setQuotaOpen] = useState(false);
  const qInfo = useMemo(() => {
    if (!quotaCtx || !anchor) return null;
    const list = quotaCtx.quotasByProduct.get(
      prodKey(anchor.fy, anchor.ps, anchor.custId, anchor.grp, mset, product),
    );
    if (!list || !list.length) return null;
    let cu = 0,
      chinh = 0,
      bo_sung = 0;
    for (const q of list) {
      const n = Number(q.qty) || 0;
      if (q.loai === 'cu') cu += n;
      else if (q.loai === 'chinh') chinh += n;
      else bo_sung += n;
    }
    return { cu, chinh, bo_sung };
  }, [quotaCtx, anchor, mset, product]);
  const prices = useMemo(() => {
    const s = new Set();
    for (const r of allRows) s.add(Number(r.price) || 0);
    return [...s];
  }, [allRows]);
  const stats = useMemo(() => {
    let q14 = 0,
      qMain = 0,
      qAdd = 0,
      price = 0;
    allRows.forEach((r) => {
      q14 += Number(r.qOld) || 0;
      qMain += Number(r.qMain) || 0;
      qAdd += Number(r.qAdd) || 0;
      if (!price && r.price) price = Number(r.price) || 0; // hiển thị đơn giá đại diện
    });
    let revBase = 0,
      khLeft = 0, // KH còn lại YTD = SL KH update các tháng SAU tháng hiện tại
      ytd = 0, // Thực hiện YTD = SL thực hiện đến hết tháng hiện tại
      dtBase = 0,
      dtUpd = 0;
    monthly.forEach((c, i) => {
      revBase += c.rev;
      if (isYtdMonth(MONTHS[i])) ytd += c.act;
      else khLeft += c.hasUpd ? c.revUpd : c.rev;
      c.rows.forEach((r) => {
        const pr = Number(r.price) || 0;
        const act = Number(r.act) || 0;
        const dtActR = Number(r.dtAct) || 0;
        const useAct =
          MONTHS[i] < CURRENT_MONTH ||
          (MONTHS[i] === CURRENT_MONTH && act !== 0);
        dtBase += (Number(r.rev) || 0) * pr;
        const upd = useAct
          ? act
          : r.revUpd !== undefined && r.revUpd !== '' && r.revUpd !== null
            ? Number(r.revUpd) || 0
            : Number(r.rev) || 0;
        dtUpd += upd * pr;
      });
    });
    if (qInfo) {
      q14 = qInfo.cu;
      qMain = qInfo.chinh;
      qAdd = qInfo.bo_sung;
    }
    const totalQuota = q14 + qMain + qAdd;
    return {
      q14,
      qMain,
      qAdd,
      ytd,
      khLeft,
      price,
      totalQuota,
      quotaAvailable: totalQuota - ytd,
      dtBase,
      dtUpd,
      chenh: dtUpd - dtBase,
    };
  }, [allRows, monthly, qInfo]);
  const commitProductField = (key, value, isText = false) => {
    if (!anchor) return;
    const updates = [
      {
        row: anchor._row,
        key,
        value,
      },
    ];
    allRows.forEach((r) => {
      if (r._row !== anchor._row)
        updates.push({
          row: r._row,
          key,
          value: isText ? '' : 0,
        });
    });
    onCommit(updates);
  };

  // edit SL update cell → write revUpd to first row, zero others
  const commitRevUpd = (monthIdx, newVal) => {
    const cell = monthly[monthIdx];
    if (!cell || cell.rows.length === 0) return;
    const updates = [];
    cell.rows.forEach((r, j) =>
      updates.push({
        row: r._row,
        key: 'revUpd',
        value: j === 0 ? newVal : 0,
      }),
    );
    onCommit(updates);
  };
  // admin sửa SL KH đầu năm → cập nhật rev + dt (doanh thu = SL × đơn giá)
  const commitRevDauNam = (monthIdx, newVal) => {
    const cell = monthly[monthIdx];
    if (!cell || cell.rows.length === 0) return;
    const updates = [];
    cell.rows.forEach((r, j) => {
      const qty = j === 0 ? newVal : 0;
      const pr = Number(r.price) || 0;
      updates.push({ row: r._row, key: 'rev', value: qty });
      updates.push({ row: r._row, key: 'dt', value: qty * pr });
    });
    onCommit(updates);
  };
  // Đơn giá: ghi CÙNG một giá trị vào tất cả các dòng của SP
  // (DThu = Σ SL × đơn_giá theo từng dòng → mọi dòng phải cùng đơn giá).
  const commitPrice = (newVal) => {
    if (!allRows.length) return;
    onCommit(
      allRows.map((r) => ({
        row: r._row,
        key: 'price',
        value: newVal,
      })),
    );
  };
  // Cột nhận diện (bộ vật tư / sản phẩm): ghi CÙNG một giá trị vào MỌI dòng của SP
  // (khác commitProductField — cái đó gộp về dòng anchor và zero dòng khác).
  const commitIdentity = (key, value) => {
    if (!allRows.length) return;
    onCommit(allRows.map((r) => ({ row: r._row, key, value })));
  };
  const handleDelete = () => {
    if (!allRows.length) return;
    if (
      confirm(
        `Xóa sản phẩm "${product}"${mset ? ` (bộ: ${mset})` : ''} — ${allRows.length} dòng (mọi tháng)?\nKhông hoàn tác được.`,
      )
    ) {
      onDeleteProduct(allRows.map((r) => r._row));
    }
  };
  const pend = (key) =>
    allRows.some((r) => pendingKeys.has(`${r._row}:${key}`));
  const pendUpd = (cell) =>
    cell.rows.some((r) => pendingKeys.has(`${r._row}:revUpd`));
  const pendDauNam = (cell) =>
    cell.rows.some((r) => pendingKeys.has(`${r._row}:rev`));
  return (
    <tr className="group hover:bg-slate-50/40">
      <td
        className="px-3 py-1.5 text-[11.5px] text-slate-500 border-r border-b border-slate-100 sticky left-0 bg-white group-hover:bg-slate-50/40 z-[1]"
        style={{
          width: 130,
          minWidth: 130,
          maxWidth: 130,
        }}
      >
        <div className="truncate" title={productCode || ''}>
          {productCode || ''}
        </div>
      </td>
      <td
        className="px-3 py-1.5 text-[12px] text-slate-800 border-r border-b border-slate-100 sticky bg-white group-hover:bg-slate-50/40 z-[1] font-medium"
        style={{
          width: 220,
          minWidth: 220,
          maxWidth: 220,
          left: 130,
        }}
      >
        <div className="flex items-center gap-1">
          <div className="flex-1 min-w-0">
            {isAdmin ? (
              <StickyEdit
                value={product}
                title={product}
                className="truncate font-medium"
                onSave={(v) => commitIdentity('prod', v)}
              />
            ) : (
              <div className="truncate" title={product}>
                {product}
              </div>
            )}
          </div>
          {isAdmin && (
            <button
              onClick={handleDelete}
              title="Xóa sản phẩm (mọi tháng)"
              className="shrink-0 text-slate-300 hover:text-red-600 opacity-0 group-hover:opacity-100 transition"
            >
              <Trash2 size={13} />
            </button>
          )}
        </div>
      </td>
      <PriceCell
        value={stats.price}
        pending={pend('price')}
        locked={!canEdit}
        onCommit={commitPrice}
      />
      <QuotaCell
        value={stats.q14}
        pending={pend('qOld')}
        width={72}
        onOpen={quotaCtx && anchor ? () => setQuotaOpen(true) : null}
        fallbackLocked={!canEdit}
        onCommit={(v) => commitProductField('qOld', v)}
      />
      <QuotaCell
        value={stats.qMain}
        pending={pend('qMain')}
        width={80}
        onOpen={quotaCtx && anchor ? () => setQuotaOpen(true) : null}
        fallbackLocked={!canEdit}
        onCommit={(v) => commitProductField('qMain', v)}
      />
      <QuotaCell
        value={stats.qAdd}
        pending={pend('qAdd')}
        width={72}
        onOpen={quotaCtx && anchor ? () => setQuotaOpen(true) : null}
        fallbackLocked={!canEdit}
        onCommit={(v) => commitProductField('qAdd', v)}
      />
      {quotaOpen && anchor && (
        <QuotaThauModal
          fy={anchor.fy}
          ps={anchor.ps}
          custId={anchor.custId}
          grp={anchor.grp}
          mset={mset}
          prod={product}
          prices={prices}
          locked={!canEdit}
          onClose={() => setQuotaOpen(false)}
        />
      )}
      <td
        className="px-2 py-1.5 text-[12px] text-right tabular-nums text-slate-700 font-medium border-r border-b border-slate-100 bg-slate-50/60"
        style={{
          width: 90,
        }}
      >
        {fmtInt(stats.totalQuota)}
      </td>
      <td
        className="px-2 py-1.5 text-[12px] text-right tabular-nums text-slate-600 border-r border-b border-slate-100 bg-orange-50/40"
        style={{
          width: 90,
        }}
      >
        {fmtInt(stats.ytd)}
      </td>
      <td
        className="px-2 py-1.5 text-[12px] text-right tabular-nums text-slate-700 font-medium border-r border-b border-slate-100 bg-slate-50/60"
        style={{
          width: 110,
        }}
      >
        {fmtInt(stats.quotaAvailable)}
      </td>
      {showBasePlan
        ? MONTHS.map((mo, i) => (
            <EditableCell
              key={'b' + mo}
              value={monthly[i].rev}
              locked={!isAdmin}
              pending={isAdmin ? pendDauNam(monthly[i]) : false}
              width={58}
              bg={isAdmin ? 'bg-amber-50/50' : 'bg-slate-50/40'}
              onCommit={isAdmin ? (nv) => commitRevDauNam(i, nv) : undefined}
            />
          ))
        : [
            <td
              key="b-collapsed"
              className="px-1 py-1 border-r border-b border-slate-100 bg-slate-50/40"
            />,
          ]}
      <td
        className="px-2 py-1.5 text-[12px] text-right tabular-nums font-semibold text-slate-800 border-r border-b border-slate-100 bg-slate-100/70"
        style={{
          width: 100,
        }}
      >
        {moneyTy3(stats.dtBase)}
      </td>
      {MONTHS.map((mo, i) => {
        const cell = monthly[i];
        const isPast = mo < CURRENT_MONTH;
        if (isPast || (mo === CURRENT_MONTH && cell.hasAct)) {
          return (
            <EditableCell
              key={'u' + mo}
              value={cell.act}
              locked
              width={58}
              bg="bg-teal-50/50"
            />
          );
        }
        const eff = cell.hasUpd ? cell.revUpd : cell.rev;
        const locked = cell.rows.length === 0 || !canEdit;
        return (
          <EditableCell
            key={'u' + mo}
            value={eff}
            pending={pendUpd(cell)}
            locked={locked}
            width={58}
            bg={mo === CURRENT_MONTH ? 'bg-blue-100/50' : 'bg-blue-50/30'}
            onCommit={(nv) => commitRevUpd(i, nv)}
          />
        );
      })}
      <td
        className="px-2 py-1.5 text-[12px] text-right tabular-nums font-semibold text-slate-900 border-r border-b border-slate-100 bg-blue-50/40"
        style={{
          width: 100,
        }}
      >
        {moneyTy3(stats.dtUpd)}
      </td>
      <td
        className={`px-2 py-1.5 text-[12px] text-right tabular-nums font-semibold border-b border-slate-100 ${stats.chenh > 0 ? 'text-emerald-700 bg-emerald-50/40' : stats.chenh < 0 ? 'text-red-600 bg-red-50/40' : 'text-slate-400'}`}
        style={{
          width: 110,
        }}
      >
        {stats.chenh === 0
          ? '—'
          : MASK_MONEY
            ? '•••'
            : (stats.chenh > 0 ? '+' : '') + fmtTy3(stats.chenh)}
      </td>
    </tr>
  );
}


// ============ PRODUCT GROUP (Nhóm SP) — 1 bảng, Bộ vật tư là cột ============
export function ProductGroupSection({
  groupName,
  ps,
  custId,
  aprRow,
  products,
  pendingKeys,
  onCommit,
  canEdit,
  isAdmin,
  onDeleteProduct,
  showBasePlan,
  onToggleBasePlan,
  catIdx,
}) {
  const [open, setOpen] = useState(false);
  const [noteModal, setNoteModal] = useState(false);
  const grpSbRef = useRef(null);
  useEffect(() => {
    const sb = grpSbRef.current;
    if (!sb) return;
    const box = sb.closest('.detail-box');
    if (!box) return;
    const spacer = sb.firstElementChild;
    let syncing = false;
    const syncFromBox = () => {
      if (syncing) return;
      syncing = true;
      sb.scrollLeft = box.scrollLeft;
      requestAnimationFrame(() => {
        syncing = false;
      });
    };
    const syncToBox = () => {
      if (syncing) return;
      syncing = true;
      box.scrollLeft = sb.scrollLeft;
      requestAnimationFrame(() => {
        syncing = false;
      });
    };
    const measure = () => {
      if (spacer)
        spacer.style.width =
          box.scrollWidth - box.clientWidth + sb.clientWidth + 'px';
      const sbH = Math.ceil(sb.getBoundingClientRect().height);
      box.style.setProperty('--detail-sb-h', sbH + 'px');
      syncFromBox();
    };
    measure();
    box.addEventListener('scroll', syncFromBox);
    sb.addEventListener('scroll', syncToBox);
    const ro = new ResizeObserver(measure);
    ro.observe(box);
    ro.observe(sb);
    const mo = new MutationObserver(() => requestAnimationFrame(measure));
    mo.observe(box, { childList: true, subtree: true, attributes: true });
    window.addEventListener('resize', measure);
    return () => {
      box.removeEventListener('scroll', syncFromBox);
      sb.removeEventListener('scroll', syncToBox);
      ro.disconnect();
      mo.disconnect();
      window.removeEventListener('resize', measure);
    };
  }, [open]);
  // Tháng thầu chính / bổ sung: 1 ô áp cho cả nhóm SP (ghi vào mọi dòng của nhóm).
  const groupRows = useMemo(
    () => products.flatMap((p) => p.monthly.flatMap((c) => c.rows)),
    [products],
  );
  // Năm tài chính của nhóm, lấy từ chính dữ liệu đang hiển thị — khoá của đợt thầu.
  const quotaCtx = useContext(QuotaThauCtx);
  const grpFy = groupRows.length ? groupRows[0].fy : '';
  const readGroupField = (key) => {
    for (const r of groupRows) if (r[key]) return r[key];
    return '';
  };
  const pendGroupField = (key) =>
    groupRows.some((r) => pendingKeys.has(`${r._row}:${key}`));
  const commitGroupField = (key, value) => {
    if (!groupRows.length) return;
    onCommit(groupRows.map((r) => ({ row: r._row, key, value })));
  };
  // thống kê cấp nhóm SP
  const gs = useMemo(() => {
    let plan = 0,
      dt = 0,
      dtUpd = 0;
    let q14M = 0,
      qMainM = 0,
      qAddM = 0,
      ytdM = 0;
    const mDtBase = Array(12).fill(0);
    const mDtUpd = Array(12).fill(0);
    products.forEach((p) => {
      const allR = p.monthly.flatMap((c) => c.rows);
      let pQ14 = 0,
        pQMain = 0,
        pQAdd = 0,
        pPrice = 0;
      allR.forEach((r) => {
        pQ14 += Number(r.qOld) || 0;
        pQMain += Number(r.qMain) || 0;
        pQAdd += Number(r.qAdd) || 0;
        if (!pPrice && r.price) pPrice = Number(r.price) || 0;
      });
      q14M += pQ14 * pPrice;
      qMainM += pQMain * pPrice;
      qAddM += pQAdd * pPrice;
      p.monthly.forEach((c, i) => {
        plan += c.rev;
        c.rows.forEach((r) => {
          const pr = Number(r.price) || 0;
          const act = Number(r.act) || 0;
          const dtActR = Number(r.dtAct) || 0;
          const useAct =
            MONTHS[i] < CURRENT_MONTH ||
            (MONTHS[i] === CURRENT_MONTH && act !== 0);
          const rb = (Number(r.rev) || 0) * pr;
          dt += rb;
          mDtBase[i] += rb;
          if (isYtdMonth(MONTHS[i])) ytdM += dtActR;
          const upd = useAct
            ? act
            : r.revUpd !== undefined && r.revUpd !== '' && r.revUpd !== null
              ? Number(r.revUpd) || 0
              : Number(r.rev) || 0;
          const ru = upd * pr;
          dtUpd += ru;
          mDtUpd[i] += ru;
        });
      });
    });
    const totalQuotaM = q14M + qMainM + qAddM;
    return {
      plan,
      dt,
      dtUpd,
      chenh: dtUpd - dt,
      q14M,
      qMainM,
      qAddM,
      totalQuotaM,
      ytdM,
      quotaAvailM: totalQuotaM - ytdM,
      mDtBase,
      mDtUpd,
    };
  }, [products]);
  // products: [{ mset, product, monthly }], đã sort theo mset → product
  return (
    <div className="border-t border-slate-200">
      <button
        onClick={() => setOpen(!open)}
        className="w-full flex items-center gap-2 px-4 py-2 hover:bg-slate-100 text-left sticky-grp"
      >
        {open ? (
          <ChevronDown size={14} className="text-slate-600" />
        ) : (
          <ChevronRight size={14} className="text-slate-600" />
        )}
        <span className="text-[12.5px] font-semibold text-slate-800">
          {groupName}
        </span>
        <span className="text-[11px] text-slate-500">
          · {products.length}SP
        </span>
        {ps && (
          <span className="text-[10.5px] font-medium text-sky-700 bg-sky-50 border border-sky-200 rounded px-1.5 py-0.5">
            PS: {ps}
          </span>
        )}
        <div className="flex-1" />
        <div className="hidden md:flex items-center gap-4 flex-shrink-0 pr-1">
          <div className="text-right">
            <div className="text-[9px] uppercase tracking-wide text-slate-400">
              SL kế hoạch
            </div>
            <div className="text-[12px] font-semibold tabular-nums text-slate-700">
              {fmtInt(gs.plan)}
            </div>
          </div>
          <div className="text-right">
            <div className="text-[9px] uppercase tracking-wide text-slate-400">
              DThu đầu năm
            </div>
            <div className="text-[12px] font-semibold tabular-nums text-slate-700">
              {moneyTy3(gs.dt)}
            </div>
          </div>
          <div className="text-right">
            <div className="text-[9px] uppercase tracking-wide text-slate-400">
              DThu update
            </div>
            <div className="text-[12px] font-semibold tabular-nums text-blue-700">
              {moneyTy3(gs.dtUpd)}
            </div>
          </div>
          <div className="text-right min-w-[64px]">
            <div className="text-[9px] uppercase tracking-wide text-slate-400">
              Chênh lệch
            </div>
            <div
              className={`text-[12px] font-semibold tabular-nums ${gs.chenh > 0 ? 'text-emerald-700' : gs.chenh < 0 ? 'text-red-600' : 'text-slate-400'}`}
            >
              {gs.chenh === 0
                ? '—'
                : MASK_MONEY
                  ? '•••'
                  : (gs.chenh > 0 ? '+' : '') + fmtTy3(gs.chenh)}
            </div>
          </div>
        </div>
      </button>
      {open && (
        <React.Fragment>
          <div className="meta-sticky-l px-4 py-2 bg-blue-50/40 border-b border-blue-100 flex flex-wrap items-center gap-x-6 gap-y-2">
            {quotaCtx && grpFy ? (
              <DotThauPanel
                fy={grpFy}
                ps={ps}
                custId={custId || ''}
                grp={groupName}
                locked={!canEdit}
              />
            ) : (
              <React.Fragment>
                <GroupMonthField
                  label="Tháng thầu chính"
                  value={readGroupField('mMain')}
                  pending={pendGroupField('mMain')}
                  locked={!canEdit}
                  onCommit={(v) => commitGroupField('mMain', v)}
                />
                <GroupMonthField
                  label="Tháng thầu bổ sung"
                  value={readGroupField('mAdd')}
                  pending={pendGroupField('mAdd')}
                  locked={!canEdit}
                  onCommit={(v) => commitGroupField('mAdd', v)}
                />
              </React.Fragment>
            )}
            <button
              className="inline-flex items-center gap-1.5 px-3 py-1.5 text-[11px] font-semibold rounded-md border border-amber-200 text-amber-700 bg-white hover:bg-amber-50 ml-auto"
              onClick={() => setNoteModal(true)}
            >
              <span className="text-[13px]">📝</span>Giải trình
            </button>
          </div>
          {noteModal && (
            <GiaiTrinhModal
              info={{ ps: ps, custId: custId || '', grp: groupName }}
              onClose={() => setNoteModal(false)}
              auth={window.__app_auth}
            />
          )}
          <div className="fake-scrollbar-wrap" ref={grpSbRef}>
            <div style={{ height: 1 }} />
          </div>
          <div className="scroll-shadow">
            <table
              className="border-collapse"
              style={{
                tableLayout: 'fixed',
              }}
            >
              <thead>
                <tr className="bg-white">
                  <th
                    rowSpan={2}
                    className="px-3 py-1.5 text-left text-[10px] font-semibold uppercase tracking-wide text-slate-500 border-r border-b border-slate-200 sticky left-0 bg-white z-[2] align-bottom"
                    style={{
                      width: 130,
                    }}
                  >
                    Mã SP
                  </th>
                  <th
                    rowSpan={2}
                    className="px-3 py-1.5 text-left text-[10px] font-semibold uppercase tracking-wide text-slate-500 border-r border-b border-slate-200 sticky bg-white z-[2] align-bottom"
                    style={{
                      width: 220,
                      left: 130,
                    }}
                  >
                    Sản phẩm
                  </th>
                  <th
                    rowSpan={2}
                    className="px-2 py-1.5 text-right text-[10px] font-semibold uppercase tracking-wide text-amber-700 border-r border-b border-slate-200 bg-amber-50/40 align-bottom"
                    style={{
                      width: 85,
                    }}
                  >
                    Đơn giá ✏
                  </th>
                  <th
                    rowSpan={2}
                    className="px-1.5 py-1.5 text-right text-[10px] font-semibold uppercase text-blue-700 border-r border-b border-slate-200 bg-blue-50/40 align-bottom"
                    style={{
                      width: 72,
                    }}
                  >
                    Quota 1/4 ✏
                  </th>
                  <th
                    rowSpan={2}
                    className="px-1.5 py-1.5 text-right text-[10px] font-semibold uppercase text-blue-700 border-r border-b border-slate-200 bg-blue-50/40 align-bottom"
                    style={{
                      width: 80,
                    }}
                  >
                    Quota thầu chính ✏
                  </th>
                  <th
                    rowSpan={2}
                    className="px-1.5 py-1.5 text-right text-[10px] font-semibold uppercase text-blue-700 border-r border-b border-slate-200 bg-blue-50/40 align-bottom"
                    style={{
                      width: 72,
                    }}
                  >
                    Quota thầu bổ sung ✏
                  </th>
                  <th
                    rowSpan={2}
                    className="px-2 py-1.5 text-right text-[10px] font-semibold uppercase tracking-wide text-slate-500 border-r border-b border-slate-200 align-bottom"
                    style={{
                      width: 90,
                    }}
                  >
                    Tổng Quota
                  </th>
                  <th
                    rowSpan={2}
                    className="px-2 py-1.5 text-right text-[10px] font-semibold uppercase tracking-wide text-orange-700 border-r border-b border-slate-200 bg-orange-50/40 align-bottom"
                    style={{
                      width: 90,
                    }}
                  >
                    TH YTD
                  </th>
                  <th
                    rowSpan={2}
                    className="px-2 py-1.5 text-right text-[10px] font-semibold uppercase tracking-wide text-slate-500 border-r border-b border-slate-200 align-bottom"
                    style={{
                      width: 110,
                    }}
                  >
                    Quota khả dụng
                  </th>
                  <th
                    colSpan={showBasePlan ? 12 : 1}
                    onClick={() => onToggleBasePlan && onToggleBasePlan()}
                    className="px-2 py-1 text-center text-[10px] font-bold uppercase tracking-wide text-slate-600 border-r border-b border-slate-200 bg-slate-100/70 cursor-pointer select-none hover:bg-slate-200/70"
                    title={showBasePlan ? 'Bấm để thu gọn' : 'Bấm để mở rộng'}
                  >
                    <span className="inline-flex items-center gap-1">
                      {showBasePlan ? (
                        <ChevronDown size={11} />
                      ) : (
                        <ChevronRight size={11} />
                      )}
                      {showBasePlan
                        ? isAdmin
                          ? 'SL Kế hoạch đầu năm ✏'
                          : 'SL Kế hoạch đầu năm (cố định)'
                        : 'SL đầu năm'}
                    </span>
                  </th>
                  <th
                    rowSpan={2}
                    className="px-2 py-1.5 text-right text-[10px] font-semibold uppercase tracking-wide text-slate-700 border-r border-b border-slate-200 bg-slate-100/70 align-bottom"
                    style={{
                      width: 100,
                    }}
                  >
                    DThu KH đầu năm
                  </th>
                  <th
                    colSpan={12}
                    className="px-2 py-1 text-center text-[10px] font-bold uppercase tracking-wide text-blue-700 border-r border-b border-slate-200 bg-blue-50/50"
                  >
                    SL update (quá khứ = thực hiện · từ tháng này = điều chỉnh
                    ✏)
                  </th>
                  <th
                    rowSpan={2}
                    className="px-2 py-1.5 text-right text-[10px] font-semibold uppercase tracking-wide text-blue-800 border-r border-b border-slate-200 bg-blue-50/50 align-bottom"
                    style={{
                      width: 100,
                    }}
                  >
                    DThu KH Update
                  </th>
                  <th
                    rowSpan={2}
                    className="px-2 py-1.5 text-right text-[10px] font-semibold uppercase tracking-wide text-red-700 border-b border-slate-200 bg-red-50/30 align-bottom"
                    style={{
                      width: 110,
                    }}
                  >
                    Chênh lệch
                  </th>
                </tr>
                <tr className="bg-white">
                  {showBasePlan
                    ? MONTH_LABELS.map((m, i) => (
                        <th
                          key={'bh' + m}
                          className={`px-1 py-1 text-[10px] font-semibold uppercase border-r border-b border-slate-200 text-right text-slate-400 bg-slate-50/40`}
                          style={{
                            width: 58,
                          }}
                        >
                          {m}
                        </th>
                      ))
                    : [
                        <th
                          key="bh-collapsed"
                          className="px-1 py-1 border-r border-b border-slate-200 bg-slate-50/40"
                        />,
                      ]}
                  {MONTH_LABELS.map((m, i) => (
                    <th
                      key={'uh' + m}
                      className={`px-1 py-1 text-[10px] font-semibold uppercase border-r border-b border-slate-200 text-right ${MONTHS[i] < CURRENT_MONTH ? 'bg-teal-50/50 text-teal-700' : MONTHS[i] === CURRENT_MONTH ? 'bg-blue-100/50 text-blue-700' : 'text-blue-600 bg-blue-50/30'}`}
                      style={{
                        width: 58,
                      }}
                    >
                      {m}
                    </th>
                  ))}
                </tr>
              </thead>
              <tbody>
                <tr className="bg-amber-50/60 font-semibold sticky-total">
                  <td
                    colSpan={2}
                    className="px-3 py-2 text-[12px] font-bold text-slate-800 border-r border-b border-amber-200 sticky left-0 bg-amber-50 z-[1] uppercase tracking-wide"
                    style={{ width: 350, minWidth: 350 }}
                  >
                    Tổng cộng
                  </td>
                  <td
                    className="border-r border-b border-amber-200"
                    style={{ width: 85 }}
                  />
                  <td
                    className="px-2 py-2 text-[12px] text-right tabular-nums font-semibold text-slate-700 border-r border-b border-amber-200 bg-blue-50/20"
                    style={{ width: 72 }}
                  >
                    {MASK_MONEY ? '•••' : moneyTy3(gs.q14M)}
                  </td>
                  <td
                    className="px-2 py-2 text-[12px] text-right tabular-nums font-semibold text-slate-700 border-r border-b border-amber-200 bg-blue-50/20"
                    style={{ width: 80 }}
                  >
                    {MASK_MONEY ? '•••' : moneyTy3(gs.qMainM)}
                  </td>
                  <td
                    className="px-2 py-2 text-[12px] text-right tabular-nums font-semibold text-slate-700 border-r border-b border-amber-200 bg-blue-50/20"
                    style={{ width: 72 }}
                  >
                    {MASK_MONEY ? '•••' : moneyTy3(gs.qAddM)}
                  </td>
                  <td
                    className="px-2 py-2 text-[12px] text-right tabular-nums font-bold text-slate-800 border-r border-b border-amber-200 bg-amber-50/80"
                    style={{ width: 90 }}
                  >
                    {MASK_MONEY ? '•••' : moneyTy3(gs.totalQuotaM)}
                  </td>
                  <td
                    className="px-2 py-2 text-[12px] text-right tabular-nums font-semibold text-slate-700 border-r border-b border-amber-200 bg-orange-50/40"
                    style={{ width: 90 }}
                  >
                    {MASK_MONEY ? '•••' : moneyTy3(gs.ytdM)}
                  </td>
                  <td
                    className="px-2 py-2 text-[12px] text-right tabular-nums font-semibold text-slate-700 border-r border-b border-amber-200"
                    style={{ width: 110 }}
                  >
                    {MASK_MONEY ? '•••' : moneyTy3(gs.quotaAvailM)}
                  </td>
                  {showBasePlan
                    ? gs.mDtBase.map((v, i) => (
                        <td
                          key={'tb' + i}
                          className="px-1 py-2 text-[11px] text-right tabular-nums text-slate-700 font-semibold border-r border-b border-amber-200 bg-amber-50/40"
                          style={{ width: 58 }}
                        >
                          {moneyTy3(v)}
                        </td>
                      ))
                    : [
                        <td
                          key="tb-col"
                          className="border-r border-b border-amber-200"
                        />,
                      ]}
                  <td
                    className="px-2 py-2 text-[12px] text-right tabular-nums font-bold text-slate-800 border-r border-b border-amber-200 bg-amber-50/80"
                    style={{ width: 100 }}
                  >
                    {moneyTy3(gs.dt)}
                  </td>
                  {gs.mDtUpd.map((v, i) => (
                    <td
                      key={'tu' + i}
                      className={`px-1 py-2 text-[11px] text-right tabular-nums font-semibold border-r border-b border-amber-200 ${MONTHS[i] < CURRENT_MONTH ? 'text-teal-800 bg-teal-50/60' : MONTHS[i] === CURRENT_MONTH ? 'text-blue-800 bg-blue-100/60' : 'text-blue-700 bg-blue-50/40'}`}
                      style={{ width: 58 }}
                    >
                      {moneyTy3(v)}
                    </td>
                  ))}
                  <td
                    className="px-2 py-2 text-[12px] text-right tabular-nums font-bold text-blue-900 border-r border-b border-amber-200 bg-blue-50/60"
                    style={{ width: 100 }}
                  >
                    {moneyTy3(gs.dtUpd)}
                  </td>
                  <td
                    className={`px-2 py-2 text-[12px] text-right tabular-nums font-bold border-b border-amber-200 ${gs.chenh > 0 ? 'text-emerald-700 bg-emerald-50/60' : gs.chenh < 0 ? 'text-red-600 bg-red-50/60' : 'text-slate-400 bg-amber-50/40'}`}
                    style={{ width: 110 }}
                  >
                    {gs.chenh === 0
                      ? '—'
                      : MASK_MONEY
                        ? '•••'
                        : (gs.chenh > 0 ? '+' : '') + fmtTy3(gs.chenh)}
                  </td>
                </tr>
                {products.map((p, idx) => {
                  const showMset =
                    idx === 0 || products[idx - 1].mset !== p.mset;
                  return (
                    <ProductRow
                      key={p.mset + '||' + p.product + '||' + (p.pPrice || 0)}
                      product={p.product}
                      mset={p.mset}
                      showMset={showMset}
                      monthly={p.monthly}
                      pendingKeys={pendingKeys}
                      onCommit={onCommit}
                      canEdit={canEdit}
                      isAdmin={isAdmin}
                      onDeleteProduct={onDeleteProduct}
                      showBasePlan={showBasePlan}
                      productCode={
                        catIdx
                          ? catIdx.codeOf(groupName, p.mset, p.product)
                          : ''
                      }
                    />
                  );
                })}
              </tbody>
            </table>
          </div>
        </React.Fragment>
      )}
    </div>
  );
}
