// Nhãn, nhóm thao tác và hàm định dạng dùng chung cho tab Lịch sử cập nhật và lịch sử sản phẩm.
import { MASK_MONEY } from '../config/constants.js';

export const ACTION_LABELS = {
  updateCells: 'Sửa kế hoạch',
  addProduct: 'Thêm sản phẩm',
  deleteProduct: 'Xóa sản phẩm',
  deleteCustomer: 'Xóa khách hàng',
  ensureMonthRow: 'Tạo dòng tháng',
  importKHKD: 'Nạp file KHKD',
  saveGiaiTrinh: 'Giải trình',
  chotKeHoach: 'Chụp kế hoạch tháng',
  xoaChotKy: 'Xóa bản chụp',
  saveQuotaThau: 'Lưu quota thầu',
  saveDotThau: 'Lưu đợt thầu',
  deleteDotThau: 'Xóa đợt thầu',
  duyetQuotaThau: 'Duyệt quota',
  loaiQuotaThau: 'Loại quota',
  duyetDotThau: 'Duyệt đợt thầu',
  loaiDotThau: 'Loại đợt thầu',
  saveDiaBan: 'Lưu địa bàn',
  deleteDiaBan: 'Xóa địa bàn',
  chuyenDiaBan: 'Chuyển địa bàn',
  dopChongLan: 'Dọn PS chồng lấn',
  savePs: 'Lưu PS',
  suaPsHoaDon: 'Sửa PS hóa đơn',
  suaPsHoaDonBulk: 'Sửa PS hóa đơn (hàng loạt)',
  syncThucHien: 'Đồng bộ thực hiện',
  luuHoaDonLoaiTru: 'Loại trừ hóa đơn',
  xoaHoaDonLoaiTru: 'Bỏ loại trừ hóa đơn',
  setAppConfig: 'Đổi cấu hình',
};

// Nhóm thao tác cho bộ lọc: người xem thường hỏi theo mảng việc, không theo tên action.
export const ACTION_GROUPS = {
  kehoach: {
    label: 'Kế hoạch',
    color: 'bg-blue-100 text-blue-700',
    actions: ['updateCells', 'addProduct', 'deleteProduct', 'deleteCustomer', 'ensureMonthRow', 'importKHKD', 'saveGiaiTrinh', 'chotKeHoach', 'xoaChotKy'],
  },
  quota: {
    label: 'Quota – Thầu',
    color: 'bg-emerald-100 text-emerald-700',
    actions: ['saveQuotaThau', 'saveDotThau', 'deleteDotThau', 'duyetQuotaThau', 'loaiQuotaThau', 'duyetDotThau', 'loaiDotThau'],
  },
  diaban: {
    label: 'Địa bàn – PS',
    color: 'bg-violet-100 text-violet-700',
    actions: ['saveDiaBan', 'deleteDiaBan', 'chuyenDiaBan', 'dopChongLan', 'savePs', 'suaPsHoaDon', 'suaPsHoaDonBulk'],
  },
  hoadon: {
    label: 'Hóa đơn – Thực hiện',
    color: 'bg-amber-100 text-amber-700',
    actions: ['syncThucHien', 'luuHoaDonLoaiTru', 'xoaHoaDonLoaiTru'],
  },
  hethong: {
    label: 'Hệ thống',
    color: 'bg-slate-200 text-slate-700',
    actions: ['setAppConfig'],
  },
};

const GROUP_OF = {};
for (const [k, g] of Object.entries(ACTION_GROUPS)) for (const a of g.actions) GROUP_OF[a] = k;

const DESTRUCTIVE = new Set(['deleteProduct', 'deleteCustomer', 'deleteDotThau', 'deleteDiaBan', 'loaiQuotaThau', 'loaiDotThau', 'xoaChotKy']);

export function actionLabel(action) {
  return ACTION_LABELS[action] || action;
}

export function actionColor(action) {
  if (DESTRUCTIVE.has(action)) return 'bg-red-100 text-red-700';
  const g = ACTION_GROUPS[GROUP_OF[action]];
  return g ? g.color : 'bg-slate-100 text-slate-600';
}

// Cột: log lưu tên trường giao diện (details.columns) và tên cột DB (diff) — gộp cả hai.
export const COL_LABELS = {
  revUpd: 'SL KH update',
  sl_ke_hoach_update: 'SL KH update',
  rev: 'SL KH đầu năm',
  sl_ke_hoach_dau_nam: 'SL KH đầu năm',
  price: 'Đơn giá',
  don_gia: 'Đơn giá',
  dt: 'Dthu KH đầu năm',
  doanh_thu_kh_dau_nam: 'Dthu KH đầu năm',
  doanh_thu_kh_update: 'Dthu KH update',
  prod: 'Sản phẩm',
  san_pham: 'Sản phẩm',
  mset: 'Bộ vật tư',
  bo_vat_tu: 'Bộ vật tư',
  act: 'SL thực hiện',
  sl_thuc_hien: 'SL thực hiện',
  note: 'Ghi chú',
  qOld: 'Quota thầu cũ',
  quota_thau_cu_con_lai: 'Quota thầu cũ',
  qMain: 'Quota thầu chính',
  quota_thau_chinh: 'Quota thầu chính',
  qAdd: 'Quota thầu BS',
  quota_bo_sung: 'Quota thầu BS',
  mMain: 'Tháng thầu chính',
  thang_thau_chinh: 'Tháng thầu chính',
  mAdd: 'Tháng thầu BS',
  thang_thau_bo_sung: 'Tháng thầu BS',
  thoi_gian_thau_chinh: 'TG thầu chính',
};

export const colLabel = (c) => COL_LABELS[c] || c;

const MONEY_COLS = new Set(['price', 'don_gia', 'dt', 'doanh_thu_kh_dau_nam', 'doanh_thu_kh_update']);
const TEXT_COLS = new Set(['prod', 'san_pham', 'mset', 'bo_vat_tu', 'note', 'mMain', 'mAdd', 'thang_thau_chinh', 'thang_thau_bo_sung']);

export const isMoneyCol = (c) => MONEY_COLS.has(c);
export const isTextCol = (c) => TEXT_COLS.has(c);

// Giá trị một ô trong log. null / '' hiện "trống" để phân biệt với 0.
export function fmtGiaTri(col, v) {
  if (v === null || v === undefined || v === '') return 'trống';
  if (isTextCol(col)) return String(v);
  const n = Number(v);
  if (!Number.isFinite(n)) return String(v);
  if (isMoneyCol(col) && MASK_MONEY) return '•••';
  return n.toLocaleString('en-US', { maximumFractionDigits: 2 });
}

// Chênh lệch mới − cũ cho cột số; null nếu không tính được (cột chữ, ẩn tiền).
export function chenhLech(col, cu, moi) {
  if (isTextCol(col)) return null;
  if (isMoneyCol(col) && MASK_MONEY) return null;
  const a = cu === null || cu === undefined || cu === '' ? 0 : Number(cu);
  const b = moi === null || moi === undefined || moi === '' ? 0 : Number(moi);
  if (!Number.isFinite(a) || !Number.isFinite(b)) return null;
  return b - a;
}

export const fmtThang = (ym) => {
  const m = /^(\d{4})-(\d{2})/.exec(String(ym || ''));
  return m ? `T${Number(m[2])}/${m[1].slice(2)}` : ym || '';
};

const pad = (n) => String(n).padStart(2, '0');
export const fmtGio = (iso) => {
  const d = new Date(iso);
  return `${pad(d.getHours())}:${pad(d.getMinutes())}`;
};
export const fmtNgay = (iso) => {
  const d = new Date(iso);
  return `${pad(d.getDate())}/${pad(d.getMonth() + 1)}/${d.getFullYear()}`;
};
export const fmtNgayGio = (iso) => (iso ? `${fmtNgay(iso)} ${fmtGio(iso)}` : '');

const THU = ['Chủ nhật', 'Thứ hai', 'Thứ ba', 'Thứ tư', 'Thứ năm', 'Thứ sáu', 'Thứ bảy'];
// 'YYYY-MM-DD' (ngày giờ VN do server tính) → "Thứ sáu, 07/11/2026" + Hôm nay / Hôm qua.
export function tieuDeNgay(ymd, now = new Date()) {
  const [y, m, d] = String(ymd).split('-').map(Number);
  if (!y) return String(ymd);
  const dt = new Date(y, m - 1, d);
  const homNay = new Date(now.getFullYear(), now.getMonth(), now.getDate());
  const diff = Math.round((homNay - dt) / 86400000);
  const base = `${THU[dt.getDay()]}, ${pad(d)}/${pad(m)}/${y}`;
  if (diff === 0) return 'Hôm nay · ' + base;
  if (diff === 1) return 'Hôm qua · ' + base;
  return base;
}

// Khoảng thời gian cho bộ lọc, theo giờ máy người xem: [from, to) dạng ISO.
export function khoangNgay(preset, tuNgay, denNgay, now = new Date()) {
  const dau = (d) => new Date(d.getFullYear(), d.getMonth(), d.getDate());
  const homNay = dau(now);
  const cong = (d, n) => new Date(d.getFullYear(), d.getMonth(), d.getDate() + n);
  let from = null;
  let to = null;
  if (preset === 'today') from = homNay;
  else if (preset === '7d') from = cong(homNay, -6);
  else if (preset === '30d') from = cong(homNay, -29);
  else if (preset === 'month') from = new Date(now.getFullYear(), now.getMonth(), 1);
  else if (preset === 'custom') {
    if (tuNgay) from = new Date(tuNgay + 'T00:00:00');
    if (denNgay) to = cong(new Date(denNgay + 'T00:00:00'), 1);
  }
  return { from: from ? from.toISOString() : null, to: to ? to.toISOString() : null };
}

// Câu tóm tắt một nhóm (ngày + người + thao tác) để đọc được mà không phải mở chi tiết.
export function tomTatNhom(g) {
  const parts = [];
  const cot = (g.cot || []).map(colLabel).filter((v, i, a) => a.indexOf(v) === i);
  if (g.action === 'updateCells' && cot.length) parts.push(cot.join(', '));
  if (g.tong_dong) parts.push(`${Number(g.tong_dong).toLocaleString('en-US')} dòng`);
  const kh = g.khach_hang || [];
  if (kh.length) {
    const them = (g.so_kh || kh.length) - kh.length;
    parts.push(kh.join(', ') + (them > 0 ? ` +${them} KH` : ''));
  } else if ((g.ps || []).length) {
    const them = (g.so_ps || g.ps.length) - g.ps.length;
    parts.push('PS ' + g.ps.join(', ') + (them > 0 ? ` +${them}` : ''));
  }
  return parts.join(' · ');
}

// Nhãn các khoá hay gặp trong details của thao tác không phải updateCells.
export const DETAIL_KEY_LABELS = {
  ps: 'PS', cust: 'Khách hàng', custId: 'Mã KH', customer_id: 'Mã KH', grp: 'Nhóm SP',
  mset: 'Bộ vật tư', prod: 'Sản phẩm', price: 'Đơn giá', qty: 'SL', loai: 'Loại',
  dot: 'Đợt', thang: 'Tháng', month: 'Tháng', thoiGian: 'TG (tháng)', fy: 'Năm TC',
  key: 'Cấu hình', value: 'Giá trị', ky: 'Kỳ', so_tai_lieu: 'Số chứng từ',
  ngay_tai_lieu: 'Ngày chứng từ', ly_do: 'Lý do', dang_loai_tru: 'Đang loại trừ',
  file: 'File', inserted: 'Thêm mới', count: 'Số dòng', jobId: 'Job', note: 'Ghi chú',
  ten_ps: 'Tên PS', psMoi: 'PS mới', tuThang: 'Từ tháng', ghi_de: 'Ghi đè',
  thang_hien_tai: 'Tháng hiện tại', bu: 'Team',
};

// Gộp các ô cùng khách hàng / sản phẩm / cột / giá trị cũ → mới khác tháng thành một dòng
// (đổi đơn giá ghi vào cả 12 tháng → 1 dòng "T4/26 – T3/27"). Giữ thứ tự xuất hiện đầu tiên.
export function gopThang(rows) {
  const map = new Map();
  for (const r of rows) {
    const k = [r.kh, r.sp, r.bo, r.cot, JSON.stringify(r.cu ?? null), JSON.stringify(r.moi ?? null)].join('\u0001');
    const g = map.get(k);
    if (g) g.thangs.push(r.thang);
    else map.set(k, { ...r, thangs: [r.thang] });
  }
  return [...map.values()].map((g) => ({ ...g, thangs: [...new Set(g.thangs.filter(Boolean))].sort() }));
}

const thangSo = (ym) => {
  const m = /^(\d{4})-(\d{2})/.exec(String(ym || ''));
  return m ? Number(m[1]) * 12 + Number(m[2]) - 1 : null;
};

// ['2026-04', ..., '2027-03'] → "T4/26 – T3/27"; rời rạc → "T4/26, T6/26".
export function fmtKhoangThang(thangs) {
  if (!thangs || !thangs.length) return '';
  if (thangs.length === 1) return fmtThang(thangs[0]);
  const so = thangs.map(thangSo);
  const lienTuc = so.every((v, i) => i === 0 || (v !== null && v === so[i - 1] + 1));
  if (lienTuc) return `${fmtThang(thangs[0])} – ${fmtThang(thangs[thangs.length - 1])}`;
  if (thangs.length <= 4) return thangs.map(fmtThang).join(', ');
  return `${thangs.slice(0, 3).map(fmtThang).join(', ')} +${thangs.length - 3}`;
}
