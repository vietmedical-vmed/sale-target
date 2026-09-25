import React, { useState, useEffect, useMemo } from 'react';
import { AlertCircle, ChevronDown, ChevronRight, Search, XIcon } from './icons.jsx';
import { LY_DO_LABEL } from '../config/constants.js';
import { fmtInt, money } from '../lib/format.js';
import { deaccent, fmtCust } from '../lib/text.js';
import { Modal } from './Modal.jsx';

export function TabBtn({ active, onClick, label }) {
  return (
    <button
      onClick={onClick}
      className={`px-3 py-2 text-[13px] font-medium border-b-2 -mb-px transition-colors ${active ? 'border-emerald-500 text-emerald-700' : 'border-transparent text-slate-500 hover:text-slate-700'}`}
    >
      {label}
    </button>
  );
}
// Nút "Đối chiếu thực hiện": gom oopRows theo ly_do, bấm mở popup breakdown. Đây là
// bước cảnh báo mức 1 theo yêu cầu người dùng — cho phép, không chặn, chỉ ra hành động
// sửa. Không có UI dm_ps nên ps_la chỉ hiển thị để nhận biết. Nằm trong thẻ Cấu hình
// hệ thống ở màn Cấu hình địa bàn. Mọi action đều đóng popup trước khi chạy.
export function OopReasonButton({
  total,
  byReason,
  onOpenDetail: openDetail,
  onQuickFixSaiPs: quickFixSaiPs,
  onQuickAddDiaBan: quickAddDiaBan,
  onQuickAddThieu: quickAddThieu,
}) {
  const [open, setOpen] = useState(false);
  const close = () => setOpen(false);
  const wrap = (fn) =>
    fn &&
    ((...a) => {
      close();
      fn(...a);
    });
  const onOpenDetail = wrap(openDetail);
  const onQuickFixSaiPs = wrap(quickFixSaiPs);
  const onQuickAddDiaBan = wrap(quickAddDiaBan);
  const onQuickAddThieu = wrap(quickAddThieu);
  const rows = Array.from(byReason.entries())
    .filter(([_, a]) => a.rows > 0)
    .sort((a, b) => b[1].rows - a[1].rows);
  const colorCls = (c) =>
    ({
      red: 'bg-red-50 text-red-700 border-red-200',
      orange: 'bg-orange-50 text-orange-700 border-orange-200',
      amber: 'bg-amber-50 text-amber-700 border-amber-200',
    })[c] || 'bg-slate-50 text-slate-700 border-slate-200';
  return (
    <React.Fragment>
      <button
        onClick={() => setOpen(true)}
        disabled={total === 0}
        title={total === 0 ? 'Không có dòng thực hiện ngoài kế hoạch' : undefined}
        className={`flex items-center gap-1.5 px-3 py-1.5 text-[13px] font-medium border rounded-md disabled:opacity-50 ${total > 0 ? 'border-red-200 bg-red-50 text-red-700 hover:bg-red-100' : 'border-slate-200 bg-white text-slate-500'}`}
      >
        <AlertCircle size={14} />
        Đối chiếu thực hiện
        {total > 0 && (
          <span className="ml-0.5 px-1.5 rounded-full bg-red-600 text-white text-[11px] font-semibold tabular-nums">
            {fmtInt(total)}
          </span>
        )}
      </button>
      <Modal
        open={open}
        onClose={close}
        title={
          <React.Fragment>
            Đối chiếu thực hiện —{' '}
            <span className="text-red-600">{fmtInt(total)}</span> dòng ngoài kế
            hoạch
          </React.Fragment>
        }
        icon={<AlertCircle size={16} className="text-red-600" />}
        width={960}
        footer={
          <div className="flex justify-end px-4 py-3 border-t border-slate-100">
            <button
              onClick={() => onOpenDetail('all')}
              className="px-3 py-1.5 text-[13px] font-medium border border-red-200 bg-red-50 text-red-700 hover:bg-red-100 rounded-md"
            >
              Xem tất cả
            </button>
          </div>
        }
      >
        <div className="p-4 max-h-[65vh] overflow-y-auto">
          <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-2">
            {rows.map(([ly, a]) => {
              const lb = LY_DO_LABEL[ly] || {
                short: ly,
                color: 'slate',
                desc: ly,
              };
              const action =
                ly === 'chua_co_dia_ban'
                  ? 'Khai báo địa bàn cho các KH này'
                  : ly === 'sai_ps'
                    ? 'Đồng bộ PS ở màn Cấu hình địa bàn'
                    : ly === 'sai_bo_vat_tu'
                      ? 'Bấm "Xem" rồi chọn "Sửa bộ VT" trên từng dòng'
                      : ly === 'thieu_dong_ke_hoach'
                        ? 'Thêm SP vào kế hoạch cho các KH này'
                        : ly === 'ps_la'
                          ? 'Bổ sung/sửa tên PS trong shared.dm_ps'
                          : null;
              const canGoDb = ly === 'chua_co_dia_ban' || ly === 'sai_ps';
              return (
                <div
                  key={ly}
                  className={`border rounded-md px-2.5 py-2 ${colorCls(lb.color)}`}
                >
                  <div className="flex items-center gap-2">
                    <span className="text-[11.5px] font-semibold">
                      {lb.short}
                    </span>
                    <span className="ml-auto text-[11px] tabular-nums font-semibold">
                      {fmtInt(a.rows)}dòng
                    </span>
                    <span className="text-[10.5px] opacity-70">
                      · {fmtInt(a.custCount)}KH
                    </span>
                  </div>
                  <div className="text-[11px] mt-0.5 opacity-90">{lb.desc}</div>
                  {action && (
                    <div className="text-[11px] mt-1 flex items-center gap-2">
                      <span className="opacity-70">→ {action}</span>
                      {
                        // sai_ps / chua_co_dia_ban có action gọn: bulk trực tiếp, không mở
                        // modal. Vẫn giữ nút "Xem" cho user muốn soi kỹ.
                        ly === 'sai_ps' && onQuickFixSaiPs && (
                          <button
                            onClick={() => onQuickFixSaiPs()}
                            className="ml-auto px-2 py-0.5 text-[11px] font-medium bg-white/70 hover:bg-white rounded border border-current/30"
                          >
                            Sửa {fmtInt(a.rows)}dòng hoá đơn
                          </button>
                        )
                      }
                      {ly === 'chua_co_dia_ban' && onQuickAddDiaBan && (
                        <button
                          onClick={() => onQuickAddDiaBan()}
                          className="ml-auto px-2 py-0.5 text-[11px] font-medium bg-white/70 hover:bg-white rounded border border-current/30"
                        >
                          Khai báo theo hoá đơn
                        </button>
                      )}
                      {ly === 'thieu_dong_ke_hoach' && onQuickAddThieu && (
                        <button
                          onClick={() => onQuickAddThieu()}
                          className="ml-auto px-2 py-0.5 text-[11px] font-medium bg-white/70 hover:bg-white rounded border border-current/30"
                        >
                          Thêm SP thiếu vào KH
                        </button>
                      )}
                      <button
                        onClick={() => onOpenDetail(ly)}
                        className={
                          (ly === 'sai_ps' ||
                          ly === 'chua_co_dia_ban' ||
                          ly === 'thieu_dong_ke_hoach'
                            ? ''
                            : 'ml-auto ') +
                          'px-2 py-0.5 text-[11px] font-medium bg-white/70 hover:bg-white rounded border border-current/30'
                        }
                      >
                        {ly === 'sai_ps' ||
                        ly === 'chua_co_dia_ban' ||
                        ly === 'thieu_dong_ke_hoach'
                          ? 'Xem'
                          : 'Xem ' + fmtInt(a.rows) + ' dòng'}
                      </button>
                    </div>
                  )}
                </div>
              );
            })}
          </div>
        </div>
      </Modal>
    </React.Fragment>
  );
}

// Modal "Đối chiếu ngoài kế hoạch — chi tiết". Nhận toàn bộ oopRows đã filter theo
// bộ lọc chung, cho phép lọc tiếp theo lý do + tìm KH/nhóm SP. Mỗi dòng có nút hành
// động tương ứng với ly_do — cross-tab jump về màn Cấu hình địa bàn (khai báo/chuyển
// PS) hoặc màn Chi tiết (thêm SP với dữ liệu điền sẵn), hoặc mở form dm_ps.
export function FixBoVatTuModal({ row, planMatches, onApply, onClose, busy }) {
  const [msetVal, setMsetVal] = useState(row.mset || '');
  const [prodVal, setProdVal] = useState(row.prod || '');
  const inp =
    'w-full px-2.5 py-2 text-[13px] border border-slate-200 rounded-md bg-white outline-none focus:border-emerald-500 focus:ring-2 focus:ring-emerald-100';
  const lbl =
    'block text-[10.5px] uppercase tracking-wide text-slate-500 font-medium mb-1';
  return (
    <div
      className="fixed inset-0 bg-slate-900/40 z-[60] flex items-center justify-center p-4"
      onClick={onClose}
    >
      <div
        onClick={(e) => e.stopPropagation()}
        className="bg-white rounded-xl border border-slate-200 shadow-xl w-full max-w-lg"
      >
        <div className="px-4 py-3 border-b border-slate-100 flex items-center gap-3">
          <div className="text-[14px] font-semibold text-slate-800">
            Sửa bộ vật tư / sản phẩm
          </div>
          <div className="flex-1" />
          <button
            onClick={onClose}
            className="p-1 text-slate-400 hover:text-slate-700 hover:bg-slate-100 rounded"
          >
            <XIcon size={16} />
          </button>
        </div>
        <div className="p-4 space-y-3">
          <div className="text-[12px] text-slate-600 space-y-1">
            <div>
              <span className="font-medium">KH: </span>
              {row.cust}
            </div>
            <div>
              <span className="font-medium">SP hoá đơn: </span>
              {row.prod || '—'}
            </div>
            <div>
              <span className="font-medium">Bộ VT hoá đơn: </span>
              {row.mset || '—'}
            </div>
          </div>
          {planMatches.length > 0 && (
            <div className="border border-orange-200 bg-orange-50 rounded-md p-2.5">
              <div className="text-[10.5px] uppercase tracking-wide text-orange-600 font-semibold mb-1">
                Dòng kế hoạch hiện tại ({planMatches.length}dòng)
              </div>
              <div className="text-[12px] text-orange-800 space-y-0.5">
                {Array.from(
                  new Set(planMatches.map((r) => r.mset || '(trống)')),
                ).map((m) => (
                  <div key={m}>
                    Bộ VT: <span className="font-medium">{m}</span>
                  </div>
                ))}
              </div>
            </div>
          )}
          <div className="border-t border-slate-100 pt-3">
            <div className="text-[11px] text-slate-500 mb-2">
              Đổi bộ vật tư / sản phẩm của dòng kế hoạch cho khớp hoá đơn:
            </div>
            <div className="grid grid-cols-2 gap-3">
              <div>
                <label className={lbl}>Bộ vật tư</label>
                <input
                  value={msetVal}
                  onChange={(e) => setMsetVal(e.target.value)}
                  className={inp}
                />
              </div>
              <div>
                <label className={lbl}>Sản phẩm</label>
                <input
                  value={prodVal}
                  onChange={(e) => setProdVal(e.target.value)}
                  className={inp}
                />
              </div>
            </div>
          </div>
        </div>
        <div className="px-4 py-3 border-t border-slate-100 flex items-center gap-2">
          <div className="text-[11px] text-slate-400 flex-1">
            {planMatches.length}dòng kế hoạch sẽ được cập nhật
          </div>
          <button
            onClick={onClose}
            className="px-3 py-1.5 text-[12.5px] text-slate-600 hover:bg-slate-100 rounded"
          >
            Huỷ
          </button>
          <button
            onClick={() => onApply(planMatches, msetVal.trim(), prodVal.trim())}
            disabled={
              busy ||
              (!msetVal.trim() && !prodVal.trim()) ||
              planMatches.length === 0
            }
            className="px-4 py-1.5 text-[12.5px] font-semibold bg-orange-600 hover:bg-orange-700 text-white rounded disabled:opacity-50"
          >
            {busy ? 'Đang lưu…' : 'Cập nhật ' + planMatches.length + ' dòng'}
          </button>
        </div>
      </div>
    </div>
  );
}

export function OopDetailModal({
  filterReason,
  oopRows,
  isAdmin,
  onClose,
  onGoDiaBan,
  onAddProduct,
  onBulkAddProducts,
  onEditDmps,
  onSuaPsHoaDon,
  onSuaPsHoaDonBulk,
  onFixBoVatTu,
  planRows,
  busy,
}) {
  const [ly, setLy] = useState(
    filterReason === 'all' ? '' : filterReason || '',
  );
  const [q, setQ] = useState('');
  useEffect(() => {
    setLy(filterReason === 'all' ? '' : filterReason || '');
  }, [filterReason]);
  const list = useMemo(() => {
    const nq = deaccent((q || '').trim());
    return oopRows.filter((r) => {
      if (ly && r._lyDo !== ly) return false;
      if (nq) {
        const hay = deaccent(
          (r.cust || '') +
            ' ' +
            (r.grp || '') +
            ' ' +
            (r.prod || '') +
            ' ' +
            (r.ps || ''),
        );
        if (!hay.includes(nq)) return false;
      }
      return true;
    });
  }, [oopRows, ly, q]);
  const cntByLy = useMemo(() => {
    const m = new Map();
    oopRows.forEach((r) =>
      m.set(r._lyDo || 'unknown', (m.get(r._lyDo || 'unknown') || 0) + 1),
    );
    return m;
  }, [oopRows]);
  const thieuRows = useMemo(
    () => list.filter((r) => r._lyDo === 'thieu_dong_ke_hoach'),
    [list],
  );
  const thieuByCust = useMemo(() => {
    const m = new Map();
    for (const r of thieuRows) {
      const ck = r.custId || r.cust || '';
      if (!m.has(ck)) m.set(ck, []);
      m.get(ck).push(r);
    }
    return m;
  }, [thieuRows]);
  // Trần hiện: 500 dòng — đủ để soi hầu hết case, còn lại lọc tiếp bằng lý do/tìm.
  const MAX = 500;
  const shown = list.slice(0, MAX);
  const cellCls = 'px-2 py-1.5 text-[11.5px] border-t border-slate-100';
  const th =
    'px-2 py-1.5 text-[10.5px] uppercase tracking-wide text-slate-500 font-semibold whitespace-nowrap bg-slate-50 sticky top-0 z-10';

  const actionFor = (r) => {
    if (!isAdmin) return null;
    if (r._lyDo === 'ps_la')
      return (
        <button
          onClick={() => onEditDmps({ tenPs: r.ps })}
          title="Bổ sung PS này vào shared.dm_ps để hoá đơn dịch được tên sang mã ps rút gọn"
          className="px-1.5 py-0.5 text-[10.5px] font-medium text-red-700 hover:bg-red-100 rounded"
        >
          Thêm vào dm_ps
        </button>
      );
    if (r._lyDo === 'sai_ps') {
      // 2 hành động cho sai_ps: sửa ngay (fix nhanh) hoặc mở màn địa bàn (đổi
      // khai báo). "Sửa ngay" cập nhật ten_ps trong hoa_don_bovattu theo PS
      // địa bàn rồi map lại — số về đúng dòng kế hoạch tương ứng.
      return (
        <React.Fragment>
          {r._psDiaBan && (
            <button
              onClick={() => onSuaPsHoaDon(r)}
              disabled={busy}
              title={`Đổi PS trong hoá đơn ${r.ps} → ${r._psDiaBan} cho tổ hợp (tháng, KH, bộ vật tư, sản phẩm) này, rồi map lại actual`}
              className="px-1.5 py-0.5 text-[10.5px] font-medium text-blue-700 hover:bg-blue-100 rounded mr-1 disabled:opacity-50"
            >
              Sửa hoá đơn → {r._psDiaBan}
            </button>
          )}
          <button
            onClick={() =>
              onGoDiaBan({
                custId: r.custId,
                cust: r.cust,
                grp: r.grp,
                purpose: 'chuyen',
              })
            }
            title={`Đổi bản khai báo địa bàn (hiện là ${r._psDiaBan || '?'}) — sẽ mở màn địa bàn, tìm KH này và highlight dòng khai báo tương ứng`}
            className="px-1.5 py-0.5 text-[10.5px] font-medium text-emerald-700 hover:bg-emerald-100 rounded"
          >
            Đổi địa bàn
          </button>
        </React.Fragment>
      );
    }
    if (r._lyDo === 'chua_co_dia_ban')
      return (
        <button
          onClick={() =>
            onGoDiaBan({
              custId: r.custId,
              cust: r.cust,
              grp: r.grp,
              purpose: 'add',
            })
          }
          title="Chuyển sang màn Cấu hình địa bàn — form Thêm địa bàn sẽ điền sẵn KH và ngành hàng"
          className="px-1.5 py-0.5 text-[10.5px] font-medium text-emerald-700 hover:bg-emerald-100 rounded"
        >
          Mở màn địa bàn
        </button>
      );
    if (r._lyDo === 'thieu_dong_ke_hoach') {
      const ck = r.custId || r.cust || '';
      const custGroup = thieuByCust.get(ck) || [];
      const uniqCount = new Set(
        custGroup.map((x) => `${x.grp}||${x.mset}||${x.prod}`),
      ).size;
      return (
        <React.Fragment>
          <button
            onClick={() =>
              onAddProduct({
                custId: r.custId,
                cust: r.cust,
                grp: r.grp,
                ps: r._psDiaBan || r.ps,
                mset: r.mset,
                prod: r.prod,
              })
            }
            title="Chuyển sang màn Chi tiết và mở form Thêm sản phẩm với dữ liệu điền sẵn"
            className="px-1.5 py-0.5 text-[10.5px] font-medium text-blue-700 hover:bg-blue-100 rounded mr-1"
          >
            Thêm SP
          </button>
          {uniqCount > 1 && onBulkAddProducts && (
            <button
              onClick={() => onBulkAddProducts(custGroup)}
              disabled={busy}
              title={`Thêm tất cả ${uniqCount} SP thiếu của KH "${r.cust}" vào kế hoạch (mỗi SP = 12 dòng, đơn giá lấy từ hoá đơn)`}
              className="px-1.5 py-0.5 text-[10.5px] font-medium text-amber-700 hover:bg-amber-100 rounded disabled:opacity-50"
            >
              Thêm cả {uniqCount}SP của KH
            </button>
          )}
        </React.Fragment>
      );
    }
    if (r._lyDo === 'sai_bo_vat_tu')
      return (
        <button
          onClick={() => onFixBoVatTu && onFixBoVatTu(r)}
          disabled={busy || !onFixBoVatTu}
          title="Mở popup sửa bộ vật tư / sản phẩm trong kế hoạch cho khớp hoá đơn"
          className="px-1.5 py-0.5 text-[10.5px] font-medium text-orange-700 hover:bg-orange-100 rounded disabled:opacity-50"
        >
          Sửa bộ VT
        </button>
      );
    return null;
  };

  return (
    <div
      className="fixed inset-0 bg-slate-900/40 z-50 flex items-center justify-center p-4"
      onClick={onClose}
    >
      <div
        onClick={(e) => e.stopPropagation()}
        className="bg-white rounded-xl border border-slate-200 shadow-xl w-full max-w-6xl max-h-[90vh] flex flex-col"
      >
        <div className="px-4 py-3 border-b border-slate-100 flex items-center gap-3">
          <AlertCircle size={16} className="text-red-600" />
          <div className="text-[14px] font-semibold text-slate-800">
            Đối chiếu ngoài kế hoạch
          </div>
          <span className="text-[11.5px] text-slate-500">
            {fmtInt(list.length)}dòng
            {list.length > MAX ? ` (hiện ${MAX} đầu)` : ''}
          </span>
          <div className="flex-1" />
          <button
            onClick={onClose}
            className="p-1 text-slate-400 hover:text-slate-700 hover:bg-slate-100 rounded"
          >
            <XIcon size={16} />
          </button>
        </div>
        <div className="px-4 py-2 border-b border-slate-100 flex items-center gap-2 flex-wrap">
          <span className="text-[11px] uppercase text-slate-500 font-semibold">
            Lý do
          </span>
          <button
            onClick={() => setLy('')}
            className={`px-2 py-0.5 text-[11.5px] rounded ${!ly ? 'bg-slate-800 text-white' : 'bg-slate-100 hover:bg-slate-200'}`}
          >
            Tất cả <span className="opacity-70">{fmtInt(oopRows.length)}</span>
          </button>
          {[...cntByLy.entries()]
            .sort((a, b) => b[1] - a[1])
            .map(([k, v]) => {
              const lb = LY_DO_LABEL[k] || { short: k };
              return (
                <button
                  key={k}
                  onClick={() => setLy(k)}
                  className={`px-2 py-0.5 text-[11.5px] rounded ${ly === k ? 'bg-slate-800 text-white' : 'bg-slate-100 hover:bg-slate-200'}`}
                >
                  {lb.short} <span className="opacity-70">{fmtInt(v)}</span>
                </button>
              );
            })}
          <div className="flex-1" />
          <div className="relative">
            <Search
              size={12}
              className="absolute left-2 top-1/2 -translate-y-1/2 text-slate-400"
            />
            <input
              value={q}
              onChange={(e) => setQ(e.target.value)}
              placeholder="Tìm KH, ngành hàng, sản phẩm…"
              className="pl-7 pr-2 py-1 text-[11.5px] border border-slate-200 rounded w-52 outline-none focus:border-emerald-500"
            />
          </div>
        </div>
        <div className="flex-1 overflow-auto">
          {list.length === 0 ? (
            <div className="p-12 text-center text-slate-400 text-sm">
              Không có dòng nào khớp bộ lọc
            </div>
          ) : (
            <table className="w-full">
              <thead>
                <tr>
                  <th className={th}>Tháng</th>
                  <th className={th}>Khách hàng</th>
                  <th className={th}>Ngành hàng</th>
                  <th className={th}>PS hoá đơn</th>
                  <th className={th}>PS địa bàn</th>
                  <th className={th}>Bộ vật tư · Sản phẩm</th>
                  <th className={th + ' text-right'}>SL · DT</th>
                  <th className={th}>Lý do</th>
                  {isAdmin && <th className={th}></th>}
                </tr>
              </thead>
              <tbody>
                {shown.map((r, i) => {
                  const lb = LY_DO_LABEL[r._lyDo] || {
                    short: r._lyDo,
                    color: 'slate',
                  };
                  const dt = Number(r.dtAct) || 0;
                  return (
                    <tr key={i} className="hover:bg-slate-50">
                      <td
                        className={
                          cellCls +
                          ' whitespace-nowrap text-slate-500 font-mono'
                        }
                      >
                        {r.mo}
                      </td>
                      <td className={cellCls + ' text-slate-800'}>
                        <div className="font-medium truncate max-w-[220px]">
                          {fmtCust(r.cust) || '—'}
                        </div>
                        {r.custId && (
                          <div className="text-[10px] text-slate-400 font-mono">
                            {r.custId}
                          </div>
                        )}
                      </td>
                      <td
                        className={
                          cellCls + ' text-slate-600 max-w-[140px] truncate'
                        }
                      >
                        {r.grp || '—'}
                      </td>
                      <td
                        className={
                          cellCls + ' text-slate-700 whitespace-nowrap'
                        }
                      >
                        {r.ps || '—'}
                      </td>
                      <td className={cellCls + ' whitespace-nowrap'}>
                        {r._psDiaBan ? (
                          r._psDiaBan === r.ps ? (
                            <span className="text-slate-500">
                              {r._psDiaBan}
                            </span>
                          ) : (
                            <span className="text-emerald-700 font-medium">
                              {r._psDiaBan}
                            </span>
                          )
                        ) : (
                          <span className="text-slate-300">—</span>
                        )}
                      </td>
                      <td
                        className={
                          cellCls + ' text-slate-500 max-w-[280px] truncate'
                        }
                      >
                        <div className="text-[10.5px] text-slate-400 truncate">
                          {r.mset || '—'}
                        </div>
                        <div className="truncate">{r.prod || '—'}</div>
                      </td>
                      <td
                        className={
                          cellCls + ' text-right tabular-nums whitespace-nowrap'
                        }
                      >
                        <div className="font-medium">{fmtInt(r.act)}</div>
                        <div className="text-[10px] text-slate-400">
                          {money(dt)}
                        </div>
                      </td>
                      <td className={cellCls}>
                        <span
                          className={`inline-block px-1.5 py-0.5 rounded text-[10px] font-medium bg-${lb.color}-50 text-${lb.color}-700`}
                        >
                          {lb.short}
                        </span>
                      </td>
                      {isAdmin && (
                        <td className={cellCls + ' whitespace-nowrap'}>
                          {actionFor(r)}
                        </td>
                      )}
                    </tr>
                  );
                })}
              </tbody>
            </table>
          )}
        </div>
        <div className="px-4 py-2 border-t border-slate-100 text-[11px] text-slate-500 flex items-center gap-3 flex-wrap">
          <span>
            Hành động cross-tab chuyển tab tương ứng và điền sẵn form. Vì view
            khớp theo mã KH + tên chuẩn hoá, một số dòng có thể trùng nhau ở SL
            nhưng khác bộ vật tư.
          </span>
          <div className="flex-1" />
          {
            // Bulk fix chỉ hợp lệ khi lọc theo sai_ps (một chiều rõ ràng, mỗi dòng có ps_dia_ban đích).
            // Không dùng cho ly_do khác vì hành động cần bối cảnh khác nhau.
            isAdmin && ly === 'sai_ps' && list.length > 0 && (
              <button
                onClick={() =>
                  onSuaPsHoaDonBulk(list.filter((r) => r._psDiaBan))
                }
                disabled={busy}
                className="px-3 py-1 text-[12px] font-semibold bg-blue-600 hover:bg-blue-700 text-white rounded disabled:opacity-50"
              >
                Sửa tất cả {list.filter((r) => r._psDiaBan).length}dòng hoá đơn
                theo địa bàn
              </button>
            )
          }
          {isAdmin &&
            (ly === 'thieu_dong_ke_hoach' || !ly) &&
            thieuRows.length > 0 &&
            onBulkAddProducts && (
              <button
                onClick={() => onBulkAddProducts(thieuRows)}
                disabled={busy}
                className="px-3 py-1 text-[12px] font-semibold bg-amber-600 hover:bg-amber-700 text-white rounded disabled:opacity-50"
              >
                Thêm tất cả{' '}
                {
                  new Set(
                    thieuRows.map(
                      (r) =>
                        `${r.custId || r.cust}||${r.grp}||${r.mset}||${r.prod}`,
                    ),
                  ).size
                }
                SP thiếu vào KH
              </button>
            )}
          <button
            onClick={onClose}
            className="px-3 py-1 text-[12px] text-slate-600 hover:bg-slate-100 rounded"
          >
            Đóng
          </button>
        </div>
      </div>
    </div>
  );
}

// Modal quản lý danh mục PS (shared.dm_ps). Hiện dùng khi bấm "Thêm vào dm_ps" từ
// modal OOP cho ly_do='ps_la'. Cho phép admin thêm tên đầy đủ ↔ tên rút gọn.
export function DmpsForm({ init, psDir, onSave, onClose, busy }) {
  const [tenPs, setTenPs] = useState(init?.tenPs || '');
  const [ps, setPs] = useState(init?.ps || '');
  const [buCode, setBuCode] = useState(init?.buCode || 'chcs');
  const [mien, setMien] = useState(init?.mien || 'Miền Bắc');
  const [team, setTeam] = useState(init?.team || '');
  const [active, setActive] = useState(init?.active !== false);
  const [err, setErr] = useState('');

  useEffect(() => {
    // Tra dm_ps đã có bản chưa: nếu có, tự điền form (edit mode).
    const nk = String(init?.tenPs || '')
      .trim()
      .toLowerCase();
    if (!nk) return;
    const found =
      psDir &&
      psDir.find(
        (p) =>
          String(p.tenPs || '')
            .trim()
            .toLowerCase() === nk,
      );
    if (found) {
      setPs(found.ps || '');
      setBuCode(found.bu || 'chcs');
      setMien(found.mien || 'Miền Bắc');
      setTeam(found.team || '');
      setActive(found.active !== false);
    } else if (init?.ps) setPs(init.ps);
  }, [init, psDir]);

  const BU_CHOICES = [
    ['chcs', 'CH&CS'],
    ['cttm', 'CTTM & CTUT'],
    ['thnk', 'THNS & CSVT'],
    ['test', 'TEST'],
  ];
  const MIEN_CHOICES = ['Miền Bắc', 'Miền Trung', 'Miền Nam'];
  const lbl =
    'block text-[10.5px] uppercase tracking-wide text-slate-500 font-medium mb-1';
  const inp =
    'w-full px-2.5 py-2 text-[13px] border border-slate-200 rounded-md bg-white outline-none focus:border-emerald-500 focus:ring-2 focus:ring-emerald-100';
  const doSave = async () => {
    setErr('');
    const t = String(tenPs || '').trim();
    const p = String(ps || '').trim();
    if (!t || !p) {
      setErr('thiếu tên đầy đủ / tên rút gọn');
      return;
    }
    if (await onSave({ tenPs: t, ps: p, buCode, mien, team, active }))
      onClose();
    else setErr('lỗi lưu');
  };

  return (
    <div
      className="fixed inset-0 bg-slate-900/40 z-[60] flex items-center justify-center p-4"
      onClick={onClose}
    >
      <div
        onClick={(e) => e.stopPropagation()}
        className="bg-white rounded-xl border border-slate-200 shadow-xl w-full max-w-lg"
      >
        <div className="px-4 py-3 border-b border-slate-100 flex items-center gap-3">
          <div className="text-[14px] font-semibold text-slate-800">
            Danh mục PS (dm_ps)
          </div>
          <div className="flex-1" />
          <button
            onClick={onClose}
            className="p-1 text-slate-400 hover:text-slate-700 hover:bg-slate-100 rounded"
          >
            <XIcon size={16} />
          </button>
        </div>
        <div className="p-4 space-y-3">
          <div>
            <label className={lbl}>Tên đầy đủ (khớp hoá đơn)</label>
            <input
              value={tenPs}
              onChange={(e) => setTenPs(e.target.value)}
              className={inp}
              placeholder="Vd Nguyễn Văn A"
            />
          </div>
          <div className="grid grid-cols-2 gap-2">
            <div>
              <label className={lbl}>Tên rút gọn (khớp sale_target)</label>
              <input
                value={ps}
                onChange={(e) => setPs(e.target.value)}
                className={inp}
                placeholder="Vd A Nguyễn"
              />
            </div>
            <div>
              <label className={lbl}>Team (BU)</label>
              <select
                value={buCode}
                onChange={(e) => setBuCode(e.target.value)}
                className={inp}
              >
                {BU_CHOICES.map(([k, v]) => (
                  <option key={k} value={k}>
                    {k}— {v}
                  </option>
                ))}
              </select>
            </div>
          </div>
          <div className="grid grid-cols-2 gap-2">
            <div>
              <label className={lbl}>Miền</label>
              <select
                value={mien}
                onChange={(e) => setMien(e.target.value)}
                className={inp}
              >
                {MIEN_CHOICES.map((m) => (
                  <option key={m} value={m}>
                    {m}
                  </option>
                ))}
              </select>
            </div>
            <div>
              <label className={lbl}>Team con</label>
              <input
                value={team}
                onChange={(e) => setTeam(e.target.value)}
                className={inp}
                placeholder="vd CHCS 1 MN"
              />
            </div>
          </div>
          <label className="flex items-center gap-2 text-[12px] text-slate-600 cursor-pointer">
            <input
              type="checkbox"
              checked={active}
              onChange={(e) => setActive(e.target.checked)}
              className="accent-emerald-600"
            />
            Active
          </label>
          {err && <div className="text-[11.5px] text-red-600">{err}</div>}
        </div>
        <div className="px-4 py-3 border-t border-slate-100 flex items-center gap-2">
          <div className="text-[11px] text-slate-500">
            Sau khi lưu: chạy “Cập nhật thực hiện” để số của PS này khớp lại
            dòng kế hoạch.
          </div>
          <div className="flex-1" />
          <button
            onClick={onClose}
            className="px-3 py-1.5 text-[12.5px] text-slate-600 hover:bg-slate-100 rounded"
          >
            Huỷ
          </button>
          <button
            onClick={doSave}
            disabled={busy}
            className="px-4 py-1.5 text-[12.5px] font-semibold bg-emerald-600 hover:bg-emerald-700 text-white rounded disabled:opacity-50"
          >
            {busy ? 'Đang lưu…' : 'Lưu vào dm_ps'}
          </button>
        </div>
      </div>
    </div>
  );
}

export function StatCard({ label, value, sublabel, accent }) {
  const dot = {
    emerald: 'bg-emerald-500',
    teal: 'bg-teal-500',
    blue: 'bg-blue-500',
    amber: 'bg-amber-500',
    red: 'bg-red-500',
    slate: 'bg-slate-400',
  };
  const txt = {
    emerald: 'text-emerald-700',
    teal: 'text-teal-700',
    blue: 'text-blue-700',
    amber: 'text-amber-700',
    red: 'text-red-600',
    slate: 'text-slate-900',
  };
  return (
    <div className="bg-white rounded-xl border border-slate-200 px-4 py-3 shadow-sm">
      <div className="flex items-center gap-1.5 mb-1.5">
        <span className={`w-1.5 h-1.5 rounded-full ${dot[accent]}`} />
        <span className="text-[10.5px] uppercase tracking-wider text-slate-500 font-semibold truncate">
          {label}
        </span>
      </div>
      <div
        className={`text-[19px] font-bold tabular-nums leading-none ${txt[accent] || 'text-slate-900'}`}
      >
        {value}
      </div>
      <div className="text-[10.5px] text-slate-400 mt-1 truncate">
        {sublabel}
      </div>
    </div>
  );
}
