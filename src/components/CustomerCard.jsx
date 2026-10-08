import React, { useState, useMemo, useContext } from 'react';
import { ChevronDown, ChevronRight, Plus, Trash2 } from './icons.jsx';
import { CURRENT_MONTH, MASK_MONEY, MONTHS, NO_MSET, isYtdMonth } from '../config/constants.js';
import { fmtTy3, moneyTy3 } from '../lib/format.js';
import { Modal } from './Modal.jsx';
import { ProductGroupSection } from './ProductGroupSection.jsx';
import { ProductPickerForm } from './AddProduct.jsx';
import { QuotaThauCtx, grpKey, prodKey } from './QuotaThau.jsx';


// ============ CUSTOMER CARD ============
export const CustomerCard = React.memo(function CustomerCard({
  customer,
  custId,
  psList,
  region,
  groups,
  pendingKeys,
  onCommit,
  canEdit,
  isAdmin,
  onDeleteProduct,
  open,
  onToggle,
  showBasePlan,
  onToggleBasePlan,
  catIdx,
  groupsByPs,
  priceOf,
  onAddProduct,
  onDeleteCustomer,
  conflicts,
  onResolveConflict,
  onEnsureMonthRow,
}) {
  const [adding, setAdding] = useState(false);
  // Khoá chống thêm trùng — chỉ tính khi form thêm SP đang mở (tránh chạy cho mọi thẻ).
  const existingKeys = useMemo(() => {
    if (!adding) return null;
    const s = new Set();
    groups.forEach((g) =>
      g.products.forEach((p) => {
        s.add(
          `${g.ps || ''}||${g.name}||${p.mset === NO_MSET ? '' : p.mset}||${p.product}`,
        );
      }),
    );
    return s;
  }, [adding, groups]);
  const quotaCtx = useContext(QuotaThauCtx);
  const stats = useMemo(() => {
    let plan = 0,
      dt = 0,
      dtUpd = 0,
      dtYtd = 0,
      onHandM = 0,
      ytdM = 0;
    const monthlyDt = Array(12).fill(0);
    let productCount = 0;
    groups.forEach((g) => {
      productCount += g.products.length;
      const allGroupRows = g.products.flatMap((p) => p.monthly.flatMap((c) => c.rows));
      const grpFy = allGroupRows.length ? allGroupRows[0].fy : '';
      const gk = grpKey(grpFy, g.ps, custId || '', g.name);
      const dotsNhom = quotaCtx ? quotaCtx.dotsByGroup.get(gk) || [] : [];
      const nhomCoDot = dotsNhom.length > 0;
      const thangCuaDot = new Map();
      for (const d of dotsNhom) thangCuaDot.set(`${d.loai}|${d.dot}`, d.thang || '');
      g.products.forEach((p) => {
        let pOnHand = 0, pPrice = 0;
        const allR = p.monthly.flatMap((c) => c.rows);
        allR.forEach((r) => {
          const rQOld = Number(r.qOld) || 0;
          const rQMain = Number(r.qMain) || 0;
          const rQAdd = Number(r.qAdd) || 0;
          const mainOn = r.mMain && r.mMain <= CURRENT_MONTH;
          const addOn = r.mAdd && r.mAdd <= CURRENT_MONTH;
          pOnHand += rQOld + (mainOn ? rQMain : 0) + (addOn ? rQAdd : 0);
          if (!pPrice && r.price) pPrice = Number(r.price) || 0;
        });
        const quotaSp = quotaCtx
          ? (quotaCtx.quotasByProduct.get(
              prodKey(grpFy, g.ps, custId || '', g.name, p.mset, p.product),
            ) || []).filter((q) => (Number(q.price) || 0) === (Number(p.pPrice) || 0))
          : [];
        if (nhomCoDot || quotaSp.length) {
          pOnHand = 0;
          for (const q of quotaSp) {
            const n = Number(q.qty) || 0;
            if (q.loai === 'cu') { pOnHand += n; }
            else {
              const thang = thangCuaDot.get(`${q.loai}|${q.dot}`) || '';
              if (thang && thang <= CURRENT_MONTH) pOnHand += n;
            }
          }
        }
        onHandM += pOnHand * pPrice;
        p.monthly.forEach((c, i) => {
          plan += c.rev;
          c.rows.forEach((r) => {
            const pr = Number(r.price) || 0;
            const act = Number(r.act) || 0;
            const dtActR = Number(r.dtAct) || 0;
            const useAct =
              MONTHS[i] < CURRENT_MONTH ||
              (MONTHS[i] === CURRENT_MONTH && act !== 0);
            const d = (Number(r.rev) || 0) * pr;
            dt += d;
            monthlyDt[i] += d;
            if (isYtdMonth(MONTHS[i])) {
              dtYtd += dtActR;
              ytdM += dtActR;
            }
            const rawUpd = r.revUpd !== undefined && r.revUpd !== '' && r.revUpd !== null
              ? Number(r.revUpd) || 0
              : Number(r.rev) || 0;
            dtUpd += useAct ? dtActR : rawUpd * pr;
          });
        });
      });
    });
    const khLeftDt = dtUpd - dtYtd;
    const quotaAvailDt = onHandM - ytdM;
    return {
      plan,
      dt,
      dtUpd,
      chenh: dtUpd - dt,
      dtYtd,
      khLeftDt,
      q14Dt: onHandM,
      quotaAvailDt,
      productCount,
      monthlyDt,
    };
  }, [groups, quotaCtx, custId]);
  return (
    <div className="bg-white rounded-lg border border-slate-200 mb-3 shadow-sm cust-wrap">
      <div className="flex items-stretch sticky-cust">
        <button
          onClick={onToggle}
          className="flex-1 min-w-0 flex items-stretch text-left"
        >
          <div className="bg-[#1877f2] text-white px-3 py-3 flex flex-col items-center justify-center min-w-[88px]">
            <div className="text-[11px] opacity-90 font-mono">{custId}</div>
          </div>
          <div className="flex-1 flex items-center gap-4 px-4 py-3 hover:bg-slate-50/60 min-w-0">
            {open ? (
              <ChevronDown size={16} className="text-slate-400 flex-shrink-0" />
            ) : (
              <ChevronRight
                size={16}
                className="text-slate-400 flex-shrink-0"
              />
            )}
            <div className="flex-1 min-w-0">
              <h3 className="text-[14px] font-semibold text-slate-900 truncate">
                {customer}
              </h3>
            </div>
            <div className="hidden md:flex items-center gap-5 flex-shrink-0">
              <div className="text-right">
                <div className="text-[10px] uppercase tracking-wide text-slate-400">
                  Target đầu năm
                </div>
                <div className="text-[13px] font-semibold tabular-nums text-slate-700">
                  {moneyTy3(stats.dt)}
                </div>
              </div>
              <div className="text-right">
                <div className="text-[10px] uppercase tracking-wide text-slate-400">
                  Dthu dự kiến
                </div>
                <div className="text-[13px] font-semibold tabular-nums text-blue-700">
                  {moneyTy3(stats.dtUpd)}
                </div>
              </div>
              <div className="text-right min-w-[60px]">
                <div className="text-[10px] uppercase tracking-wide text-slate-400">
                  Chênh lệch
                </div>
                <div
                  className={`text-[13px] font-semibold tabular-nums ${stats.chenh > 0 ? 'text-emerald-700' : stats.chenh < 0 ? 'text-red-600' : 'text-slate-400'}`}
                >
                  {stats.chenh === 0
                    ? '—'
                    : MASK_MONEY
                      ? '•••'
                      : (stats.chenh > 0 ? '+' : '') + fmtTy3(stats.chenh)}
                </div>
              </div>
              <div className="text-right min-w-[60px]">
                <div className="text-[10px] uppercase tracking-wide text-slate-400">
                  KH còn lại
                </div>
                <div className="text-[13px] font-semibold tabular-nums text-slate-700">
                  {moneyTy3(stats.khLeftDt)}
                </div>
              </div>
              <div className="text-right min-w-[60px]">
                <div className="text-[10px] uppercase tracking-wide text-slate-400">
                  Quota khả dụng
                </div>
                <div
                  className={`text-[13px] font-semibold tabular-nums ${stats.quotaAvailDt > 0 ? 'text-orange-600' : stats.quotaAvailDt < 0 ? 'text-red-600' : 'text-slate-400'}`}
                >
                  {moneyTy3(stats.quotaAvailDt)}
                </div>
              </div>
            </div>
          </div>
        </button>
        {
          // Nút thêm sản phẩm cho CHÍNH khách hàng này (không phải mở panel chọn lại KH).
          ((canEdit && catIdx) || isAdmin) && (
            <div className="flex items-center gap-1.5 pr-3 pl-1">
              {canEdit && catIdx && (
                <button
                  onClick={() => setAdding(true)}
                  title="Thêm sản phẩm cho khách hàng này"
                  className="flex items-center gap-1 px-2.5 py-1.5 text-[12px] font-semibold rounded-md border whitespace-nowrap border-emerald-200 text-emerald-700 hover:bg-emerald-50"
                >
                  <Plus size={14} />
                  Thêm SP
                </button>
              )}
              {
                // Xóa cả khách hàng (mọi sản phẩm, mọi tháng) — chỉ admin.
                isAdmin && onDeleteCustomer && (
                  <button
                    onClick={() => onDeleteCustomer(custId, customer)}
                    title="Xóa toàn bộ kế hoạch của khách hàng này"
                    className="p-1.5 text-slate-400 hover:text-red-600 hover:bg-red-50 rounded-md border border-transparent hover:border-red-200"
                  >
                    <Trash2 size={15} />
                  </button>
                )
              }
            </div>
          )
        }
      </div>
      {canEdit && catIdx && (
        <Modal
          open={adding}
          onClose={() => setAdding(false)}
          title={`Thêm sản phẩm · ${customer}`}
          icon={<Plus size={16} className="text-emerald-600" />}
          width={720}
        >
          <ProductPickerForm
            catIdx={catIdx}
            groupsByPs={groupsByPs}
            psOptions={psList}
            existing={existingKeys}
            priceOf={priceOf}
            onSubmit={(s) =>
              onAddProduct({
                ...s,
                custId: custId,
                cust: customer,
                region: region,
              })
            }
          />
        </Modal>
      )}
      {open && (
        <div>
          {groups.map((g) => (
            <ProductGroupSection
              key={g.name + '||' + (g.ps || '')}
              groupName={g.name}
              ps={g.ps}
              custId={custId}
              aprRow={g.aprRow}
              products={g.products}
              pendingKeys={pendingKeys}
              onCommit={onCommit}
              canEdit={canEdit}
              isAdmin={isAdmin}
              onDeleteProduct={onDeleteProduct}
              showBasePlan={showBasePlan}
              onToggleBasePlan={onToggleBasePlan}
              catIdx={catIdx}
              conflicts={conflicts}
              onResolveConflict={onResolveConflict}
              onEnsureMonthRow={onEnsureMonthRow}
            />
          ))}
        </div>
      )}
    </div>
  );
});

// Khung bảng cao gần trọn màn hình → chỉ có bảng cuộn dọc, nhờ đó header dính
// (.sticky-head) luôn nằm trong tầm nhìn.
// Chiều cao KHÔNG trừ phần thẻ số + bộ lọc phía trên (thanh tiêu đề mới là thứ dính
// lại), nếu trừ thì khung chỉ còn ~340px — lùn. Đổi lại, khi bảng dài hơn khung thì
// kéo trang xuống 1 lần cho khung nằm ngay dưới thanh tiêu đề, chiếm trọn màn hình.
// Là max-height nên bảng ngắn (layer mặc định) vẫn hiện đủ, không sinh thanh cuộn.

