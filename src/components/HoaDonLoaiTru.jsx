import React, { useState, useEffect, useCallback } from 'react';
import { Ban, Loader2, Search, Trash2 } from './icons.jsx';
import { fmtInt, money } from '../lib/format.js';
import { api } from '../api/client.js';
import { Modal } from './Modal.jsx';

// ============ LOẠI TRỪ HÓA ĐƠN KHỎI THỰC HIỆN ============
// Khai báo hóa đơn (số tài liệu + ngày) không tính vào doanh thu thực hiện, lưu ở
// app_sale.hoa_don_loai_tru. Không xoá hóa đơn: tắt "Loại" là tính lại, khai báo
// (lý do, người sửa) vẫn giữ để sau bật lại được. Đổi cấu hình chỉ có hiệu lực
// sau khi chạy "Đồng bộ thực hiện" → báo lên qua onChanged.

// '2026-09-27' -> '27/09/2026'
const fmtNgay = (d) => {
  const p = String(d || '').split('-');
  return p.length === 3 ? p[2] + '/' + p[1] + '/' + p[0] : String(d || '');
};
const errMsg = (e) => {
  const m = String((e && e.message) || e || '');
  if (m === 'khong_tim_thay_hoa_don') return 'Không tìm thấy hóa đơn này trong dữ liệu.';
  if (m === 'khong_ton_tai') return 'Khai báo không còn tồn tại — hãy tải lại.';
  if (m === 'forbidden') return 'Chỉ admin được cấu hình loại trừ hóa đơn.';
  return m;
};

const th =
  'px-2 py-1.5 text-left text-[11px] font-semibold text-slate-500 uppercase tracking-wide whitespace-nowrap';
const td = 'px-2 py-1.5 text-[12.5px] border-t border-slate-100 align-top';

export function HoaDonLoaiTruButton({ onChanged }) {
  const [open, setOpen] = useState(false);
  const [rows, setRows] = useState(null); // null = chưa tải
  const [loading, setLoading] = useState(false);
  const [err, setErr] = useState('');
  const [busyKey, setBusyKey] = useState(''); // khoá dòng đang lưu
  const [q, setQ] = useState('');
  const [lyDo, setLyDo] = useState('');
  const [found, setFound] = useState([]);
  const [searching, setSearching] = useState(false);
  const [changed, setChanged] = useState(false);

  const load = useCallback(async () => {
    setLoading(true);
    setErr('');
    try {
      const r = await api('getHoaDonLoaiTru');
      setRows(r.rows || []);
    } catch (e) {
      setErr(errMsg(e));
    } finally {
      setLoading(false);
    }
  }, []);

  // Tải 1 lần để có số đếm trên nút; mở modal thì tải lại cho mới
  useEffect(() => {
    load();
  }, [load]);
  useEffect(() => {
    if (open) load();
  }, [open, load]);

  // Tìm hóa đơn (debounce)
  useEffect(() => {
    if (!open) return;
    const s = q.trim();
    if (s.length < 2) {
      setFound([]);
      return;
    }
    let stop = false;
    const t = setTimeout(async () => {
      setSearching(true);
      try {
        const r = await api('timHoaDon', { q: s });
        if (!stop) setFound(r.rows || []);
      } catch (e) {
        if (!stop) setErr(errMsg(e));
      } finally {
        if (!stop) setSearching(false);
      }
    }, 350);
    return () => {
      stop = true;
      clearTimeout(t);
    };
  }, [q, open]);

  const markChanged = () => {
    setChanged(true);
    if (onChanged) onChanged();
  };

  const luu = async (h, patch) => {
    const key = h.so_tai_lieu + '|' + h.ngay_tai_lieu;
    setBusyKey(key);
    setErr('');
    try {
      await api('luuHoaDonLoaiTru', {
        soTaiLieu: h.so_tai_lieu,
        ngayTaiLieu: h.ngay_tai_lieu,
        ...patch,
      });
      markChanged();
      await load();
      // cập nhật cờ trong kết quả tìm kiếm đang hiện
      setFound((fs) =>
        fs.map((f) =>
          f.so_tai_lieu === h.so_tai_lieu && f.ngay_tai_lieu === h.ngay_tai_lieu
            ? {
                ...f,
                da_khai_bao: true,
                dang_loai_tru:
                  typeof patch.dangLoaiTru === 'boolean'
                    ? patch.dangLoaiTru
                    : f.dang_loai_tru,
              }
            : f,
        ),
      );
    } catch (e) {
      setErr(errMsg(e));
    } finally {
      setBusyKey('');
    }
  };

  const xoa = async (r) => {
    if (
      !window.confirm(
        'Xoá khai báo hóa đơn ' +
          r.so_tai_lieu +
          ' (' +
          fmtNgay(r.ngay_tai_lieu) +
          ')? Hóa đơn sẽ được tính lại vào thực hiện.',
      )
    )
      return;
    setBusyKey(r.so_tai_lieu + '|' + r.ngay_tai_lieu);
    setErr('');
    try {
      await api('xoaHoaDonLoaiTru', { id: r.id });
      markChanged();
      await load();
      setFound((fs) =>
        fs.map((f) =>
          f.so_tai_lieu === r.so_tai_lieu && f.ngay_tai_lieu === r.ngay_tai_lieu
            ? { ...f, da_khai_bao: false, dang_loai_tru: false }
            : f,
        ),
      );
    } catch (e) {
      setErr(errMsg(e));
    } finally {
      setBusyKey('');
    }
  };

  const nDang = (rows || []).filter((r) => r.dang_loai_tru).length;
  const dtDang = (rows || [])
    .filter((r) => r.dang_loai_tru)
    .reduce((s, r) => s + (Number(r.doanh_thu) || 0), 0);

  return (
    <React.Fragment>
      <button
        onClick={() => setOpen(true)}
        title="Hóa đơn không tính vào doanh thu thực hiện"
        className="flex items-center gap-1.5 px-3 py-1.5 text-[13px] font-medium border border-slate-200 bg-white text-slate-700 hover:bg-slate-50 rounded-md"
      >
        <Ban size={14} />
        Loại trừ hóa đơn
        {nDang > 0 && (
          <span className="ml-0.5 px-1.5 rounded-full bg-slate-600 text-white text-[11px] font-semibold tabular-nums">
            {fmtInt(nDang)}
          </span>
        )}
      </button>
      <Modal
        open={open}
        onClose={() => setOpen(false)}
        title="Loại trừ hóa đơn khỏi doanh thu thực hiện"
        icon={<Ban size={16} className="text-slate-600" />}
        width={1100}
        footer={
          <div className="flex items-center gap-3 px-4 py-3 border-t border-slate-100">
            {changed ? (
              <span className="text-[12px] text-amber-700">
                Đã đổi cấu hình — bấm <b>Đồng bộ thực hiện</b> để số thực hiện
                cập nhật.
              </span>
            ) : (
              <span className="text-[12px] text-slate-500">
                Thay đổi chỉ có hiệu lực sau khi bấm Đồng bộ thực hiện.
              </span>
            )}
            <div className="flex-1" />
            <button
              onClick={() => setOpen(false)}
              className="px-3 py-1.5 text-[13px] font-medium border border-slate-200 hover:bg-slate-50 rounded-md"
            >
              Đóng
            </button>
          </div>
        }
      >
        <div className="p-4 max-h-[70vh] overflow-y-auto space-y-4">
          {err && (
            <div className="px-3 py-2 text-[12.5px] bg-red-50 text-red-700 border border-red-200 rounded-md">
              {err}
            </div>
          )}

          {/* ---- Thêm hóa đơn ---- */}
          <div>
            <div className="text-[12px] font-semibold text-slate-600 mb-1.5">
              Thêm hóa đơn cần loại
            </div>
            <div className="flex items-center gap-2 flex-wrap">
              <div className="relative">
                <Search
                  size={14}
                  className="absolute left-2 top-1/2 -translate-y-1/2 text-slate-400"
                />
                <input
                  value={q}
                  onChange={(e) => setQ(e.target.value)}
                  placeholder="Số tài liệu, số HĐ, mã hoặc tên KH…"
                  className="pl-7 pr-2 py-1.5 w-80 text-[13px] border border-slate-200 rounded-md outline-none focus:border-emerald-400 focus:ring-2 focus:ring-emerald-100"
                />
              </div>
              <input
                value={lyDo}
                onChange={(e) => setLyDo(e.target.value)}
                placeholder="Lý do (tuỳ chọn)"
                className="px-2 py-1.5 flex-1 min-w-[200px] text-[13px] border border-slate-200 rounded-md outline-none focus:border-emerald-400 focus:ring-2 focus:ring-emerald-100"
              />
              {searching && (
                <Loader2 size={14} className="animate-spin text-slate-400" />
              )}
            </div>
            {q.trim().length >= 2 && !searching && found.length === 0 && (
              <div className="mt-2 text-[12px] text-slate-400">
                Không có hóa đơn khớp.
              </div>
            )}
            {found.length > 0 && (
              <div className="mt-2 border border-slate-200 rounded-md max-h-64 overflow-auto">
                <table className="w-full">
                  <thead className="bg-slate-50 sticky top-0">
                    <tr>
                      <th className={th}>Ngày</th>
                      <th className={th}>Số TL</th>
                      <th className={th}>Khách hàng</th>
                      <th className={th}>PS</th>
                      <th className={th}>Nhóm SP</th>
                      <th className={th + ' text-right'}>SL</th>
                      <th className={th + ' text-right'}>DT (tr)</th>
                      <th className={th}></th>
                    </tr>
                  </thead>
                  <tbody>
                    {found.map((f) => {
                      const key = f.so_tai_lieu + '|' + f.ngay_tai_lieu;
                      return (
                        <tr key={key}>
                          <td className={td + ' whitespace-nowrap tabular-nums'}>
                            {fmtNgay(f.ngay_tai_lieu)}
                          </td>
                          <td className={td + ' font-mono whitespace-nowrap'}>
                            {f.so_tai_lieu}
                          </td>
                          <td className={td}>
                            <span className="font-mono text-slate-400 mr-1">
                              {f.ma_kh}
                            </span>
                            {f.ten_kh}
                          </td>
                          <td className={td}>{f.ten_ps}</td>
                          <td className={td}>{f.nhom_san_pham}</td>
                          <td className={td + ' text-right tabular-nums'}>
                            {fmtInt(Number(f.so_luong))}
                          </td>
                          <td className={td + ' text-right tabular-nums'}>
                            {money(Number(f.doanh_thu))}
                          </td>
                          <td className={td + ' text-right whitespace-nowrap'}>
                            {f.dang_loai_tru ? (
                              <span className="text-[11.5px] text-slate-500">
                                Đang loại
                              </span>
                            ) : (
                              <button
                                disabled={busyKey === key}
                                onClick={() =>
                                  luu(f, { dangLoaiTru: true, lyDo })
                                }
                                className="px-2 py-0.5 text-[12px] font-medium border border-red-200 bg-red-50 text-red-700 hover:bg-red-100 rounded disabled:opacity-50"
                              >
                                {f.da_khai_bao ? 'Loại lại' : 'Loại'}
                              </button>
                            )}
                          </td>
                        </tr>
                      );
                    })}
                  </tbody>
                </table>
              </div>
            )}
          </div>

          {/* ---- Danh sách đã khai báo ---- */}
          <div>
            <div className="flex items-center gap-2 mb-1.5">
              <span className="text-[12px] font-semibold text-slate-600">
                Đã khai báo ({(rows || []).length})
              </span>
              {nDang > 0 && (
                <span className="text-[12px] text-slate-500">
                  — đang loại {fmtInt(nDang)} hóa đơn, {money(dtDang)} tr
                </span>
              )}
              {loading && (
                <Loader2 size={13} className="animate-spin text-slate-400" />
              )}
            </div>
            {rows && rows.length === 0 ? (
              <div className="text-[12px] text-slate-400">
                Chưa có hóa đơn nào bị loại.
              </div>
            ) : (
              <div className="border border-slate-200 rounded-md overflow-auto">
                <table className="w-full">
                  <thead className="bg-slate-50">
                    <tr>
                      <th className={th}>Loại</th>
                      <th className={th}>Ngày</th>
                      <th className={th}>Số TL</th>
                      <th className={th}>Khách hàng</th>
                      <th className={th}>PS / Nhóm SP</th>
                      <th className={th + ' text-right'}>DT (tr)</th>
                      <th className={th}>Lý do</th>
                      <th className={th}>Cập nhật</th>
                      <th className={th}></th>
                    </tr>
                  </thead>
                  <tbody>
                    {(rows || []).map((r) => {
                      const key = r.so_tai_lieu + '|' + r.ngay_tai_lieu;
                      const busy = busyKey === key;
                      return (
                        <tr
                          key={r.id}
                          className={r.dang_loai_tru ? '' : 'text-slate-400'}
                        >
                          <td className={td}>
                            <input
                              type="checkbox"
                              checked={!!r.dang_loai_tru}
                              disabled={busy}
                              onChange={(e) =>
                                luu(r, { dangLoaiTru: e.target.checked })
                              }
                              title={
                                r.dang_loai_tru
                                  ? 'Đang loại — bỏ chọn để tính lại'
                                  : 'Đang tính — chọn để loại'
                              }
                              className="accent-red-600"
                            />
                          </td>
                          <td className={td + ' whitespace-nowrap tabular-nums'}>
                            {fmtNgay(r.ngay_tai_lieu)}
                          </td>
                          <td className={td + ' font-mono whitespace-nowrap'}>
                            {r.so_tai_lieu}
                            {!r.con_du_lieu && (
                              <div
                                className="text-[10.5px] font-sans text-amber-600"
                                title="Hóa đơn không còn trong dữ liệu hóa đơn đã nạp"
                              >
                                không còn trong dữ liệu
                              </div>
                            )}
                          </td>
                          <td className={td}>
                            <span className="font-mono text-slate-400 mr-1">
                              {r.ma_kh}
                            </span>
                            {r.ten_kh}
                          </td>
                          <td className={td}>
                            {r.ten_ps}
                            {r.nhom_san_pham && (
                              <div className="text-[11px] text-slate-400">
                                {r.nhom_san_pham}
                              </div>
                            )}
                          </td>
                          <td className={td + ' text-right tabular-nums'}>
                            {money(Number(r.doanh_thu))}
                          </td>
                          <td className={td}>
                            <input
                              defaultValue={r.ly_do || ''}
                              key={r.id + ':' + (r.ly_do || '')}
                              disabled={busy}
                              onBlur={(e) => {
                                const v = e.target.value.trim();
                                if (v !== (r.ly_do || '')) luu(r, { lyDo: v });
                              }}
                              onKeyDown={(e) => {
                                if (e.key === 'Enter') e.target.blur();
                              }}
                              placeholder="—"
                              className="w-full min-w-[160px] px-1.5 py-0.5 text-[12.5px] border border-transparent hover:border-slate-200 focus:border-emerald-400 rounded outline-none bg-transparent"
                            />
                          </td>
                          <td
                            className={
                              td + ' whitespace-nowrap text-[11.5px] text-slate-400'
                            }
                          >
                            {r.updated_by || r.created_by}
                            <div>
                              {r.updated_at
                                ? new Date(r.updated_at).toLocaleDateString('vi-VN')
                                : ''}
                            </div>
                          </td>
                          <td className={td}>
                            <button
                              disabled={busy}
                              onClick={() => xoa(r)}
                              title="Xoá khai báo (tính lại hóa đơn)"
                              className="p-1 text-slate-400 hover:text-red-600 hover:bg-red-50 rounded disabled:opacity-50"
                            >
                              <Trash2 size={14} />
                            </button>
                          </td>
                        </tr>
                      );
                    })}
                  </tbody>
                </table>
              </div>
            )}
          </div>
        </div>
      </Modal>
    </React.Fragment>
  );
}
