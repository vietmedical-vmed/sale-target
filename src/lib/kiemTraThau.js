// Logic tab "Kiểm tra thông tin thầu": 3 bước, mỗi bước ra danh sách việc cùng một dạng
//   { key, buoc, ps, custId, tenKh, grp, bu, giaTri, nn, moTa, ... }
// để bộ lọc, gom nhóm, trạng thái xử lý (app_sale.kiem_tra_thau_xu_ly) và ảnh chụp số liệu
// (app_sale.kiem_tra_thau_snapshot) dùng chung.

export const BUOC = [
  { id: 'dot', label: 'Đợt thiếu tháng / hiệu lực', ngan: 'Đợt thầu' },
  { id: 'am', label: 'SP quota khả dụng âm', ngan: 'Quota âm' },
  { id: 'hd', label: 'Quota ↔ hợp đồng', ngan: 'Hợp đồng' },
];

export const TRANG_THAI = {
  chua: { label: 'Chưa xử lý', cls: 'bg-slate-100 text-slate-600' },
  dang_xu_ly: { label: 'Đang xử lý', cls: 'bg-amber-50 text-amber-800 border border-amber-200' },
  bo_qua: { label: 'Bỏ qua', cls: 'bg-slate-50 text-slate-500 border border-slate-200' },
  xong: { label: 'Đã xong', cls: 'bg-emerald-50 text-emerald-700 border border-emerald-200' },
};

export const LOAI_DOT = { cu: 'Thầu cũ', chinh: 'Thầu chính', bo_sung: 'Thầu bổ sung' };
export const khoaDot = (x) => [x.fy, x.ps, x.custId, x.grp, x.loai, x.dot].join('|');
// Nhãn đợt: thầu cũ chỉ có 1 đợt nên không đánh số.
export const tenDot = (d, sep = ' ') =>
  d.loai === 'cu' ? LOAI_DOT.cu : `${LOAI_DOT[d.loai] || d.loai}${sep}đợt ${d.dot}`;
export const khoaXuLy = (buoc, khoa) => buoc + '|' + khoa;

// Trạng thái hiển thị: bản ghi 'xong' mà việc vẫn còn trong danh sách = tái phát → chưa xử lý.
export const trangThaiCua = (rec) => (!rec || rec.trang_thai === 'xong' ? 'chua' : rec.trang_thai);
export const laViecMo = (rec) => trangThaiCua(rec) !== 'bo_qua';

// ---------- bước 2: nhóm lý do của SP quota âm (lib/quota.js sanPhamAmQuota.lyDo) ----------
export function nhomLyDoAm(lyDo) {
  const s = lyDo || '';
  if (s.startsWith('Quota đang nhập ở giá khác')) return 'Quota nhập ở mức giá khác';
  if (s.startsWith('Còn ')) return 'Đợt chưa tới tháng thầu / thiếu thông tin';
  if (s === 'Chưa nhập quota') return 'Chưa nhập quota';
  return 'Quota nhỏ hơn thực hiện';
}

// ---------- bước 3: đối chiếu quota ↔ hợp đồng ----------
// Nhóm nguyên nhân (gộp các mã A1..F3 của phân rã 18/11 thành việc cần làm).
export const NN_HD = {
  lech_ma: 'Nghi lệch mã SP (ghép mã)',
  nham_loai: 'Nhầm loại 1.4 ↔ chính',
  up_da_ky: 'Upcoming đã ký HĐ',
  hd_thieu_quota: 'Có HĐ, thiếu quota',
  quota_chua_hd: 'Quota chưa có HĐ',
  thieu_du_lieu_hd: 'Dữ liệu HĐ thiếu / cũ',
  lech_sl: 'Lệch số lượng',
};
const n = (x) => Number(x) || 0;
const nhom1 = (r) => String(r.nhom || '').split(',')[0].trim();
const cuaSoLabel = { fy: 'Trong năm', 14: 'Quota 1.4' };

// rows: kết quả app_sale.kiem_tra_doi_chieu_hop_dong(). Một khoá KH × SP ra tối đa 2 việc
// (cửa sổ quota 1.4 và cửa sổ trong năm), chỉ lấy kết quả khác 'Khớp'.
export function viecHopDong(rows) {
  const khHdFy = new Set();
  const khHdCu = new Set();
  const khQuota = new Set();
  const tap = { cqFy: new Set(), chFy: new Set(), cq14: new Set(), ch14: new Set() };
  for (const r of rows) {
    if (n(r.hFy) > 0) khHdFy.add(r.kh);
    if (n(r.hTruoc) > 0) khHdCu.add(r.kh);
    if (n(r.q14) + n(r.qChinh) + n(r.qBs) + n(r.qUp) > 0) khQuota.add(r.kh);
    const kn = r.kh + '|' + nhom1(r);
    if (r.kqFy === 'Chỉ có quota') tap.cqFy.add(kn);
    if (r.kqFy === 'Chỉ có HĐ') tap.chFy.add(kn);
    if (r.kq14 === 'Chỉ có quota') tap.cq14.add(kn);
    if (r.kq14 === 'Chỉ có HĐ') tap.ch14.add(kn);
  }
  const nnFy = (r) => {
    const q14 = n(r.q14), qon = n(r.qChinh) + n(r.qBs), qup = n(r.qUp);
    const h14 = n(r.h14), hcu = n(r.hTruoc), hfy = n(r.hFy);
    const kn = r.kh + '|' + nhom1(r);
    if (r.kqFy === 'Chỉ có quota') {
      if (hcu > 0 && q14 < h14) return ['nham_loai', 'HĐ ký trước năm TC → có thể là quota 1.4 ghi nhầm chính / BS'];
      if (!khHdFy.has(r.kh)) return ['thieu_du_lieu_hd', 'KH chưa có HĐ nào ký trong năm (HĐ chưa nạp hoặc chưa ký)'];
      if (tap.chFy.has(kn)) return ['lech_ma', 'Cùng KH × nhóm có SP "chỉ có HĐ" → nghi lệch mã'];
      return ['quota_chua_hd', 'KH có HĐ năm nay nhưng không có SP này'];
    }
    if (r.kqFy === 'Chỉ có HĐ') {
      if (qup > 0) return ['up_da_ky', 'Đã ký HĐ nhưng quota còn ở upcoming → chuyển on hand'];
      if (q14 > 0) return ['nham_loai', 'Có quota 1.4, HĐ ký trong năm → nghi HĐ gia hạn / ghi nhầm 1.4'];
      if (tap.cqFy.has(kn)) return ['lech_ma', 'Cùng KH × nhóm có SP "chỉ có quota" → nghi lệch mã'];
      if (khQuota.has(r.kh)) return ['hd_thieu_quota', 'KH có quota nhưng thiếu quota SP này'];
      return ['hd_thieu_quota', 'KH không có quota nào'];
    }
    if (q14 + qon === h14 + hfy) return ['nham_loai', 'Tổng 1.4 + on hand khớp tổng HĐ → chỉ lệch phân loại 1.4 ↔ chính'];
    if (qon + qup === hfy) return ['up_da_ky', 'Phần upcoming đã ký HĐ → chuyển on hand'];
    return ['lech_sl', 'Lệch SL thật (HĐ khung / phân bổ / nhập sai)'];
  };
  const nn14 = (r) => {
    const q14 = n(r.q14), qon = n(r.qChinh) + n(r.qBs);
    const h14 = n(r.h14), hfy = n(r.hFy);
    const kn = r.kh + '|' + nhom1(r);
    if (r.kq14 === 'HĐ đã bán hết trước 1/4') return ['quota_chua_hd', 'HĐ đã bán hết trước 1/4 → quota 1.4 thừa hoặc thuộc HĐ khác'];
    if (r.kq14 === 'Chỉ có quota') {
      if (hfy > 0 && qon < hfy) return ['nham_loai', 'HĐ ký trong năm, quota lại ghi 1.4 → nghi phân loại nhầm'];
      if (!khHdCu.has(r.kh)) return ['thieu_du_lieu_hd', 'KH không có HĐ cũ trong bảng HĐ (HĐ trước 04/2024 / chưa nạp)'];
      if (tap.ch14.has(kn)) return ['lech_ma', 'Cùng KH × nhóm có SP "chỉ có HĐ" → nghi lệch mã'];
      return ['quota_chua_hd', 'KH có HĐ cũ nhưng không có SP này'];
    }
    if (r.kq14 === 'Chỉ có HĐ') {
      if (qon > 0) return ['nham_loai', 'HĐ cũ còn SL nhưng quota ghi ở chính / BS → nghi phân loại nhầm'];
      if (tap.cq14.has(kn)) return ['lech_ma', 'Cùng KH × nhóm có SP "chỉ có quota" → nghi lệch mã'];
      if (khQuota.has(r.kh)) return ['hd_thieu_quota', 'HĐ cũ còn SL, chưa nhập quota 1.4'];
      return ['hd_thieu_quota', 'KH không có quota nào'];
    }
    if ((r.canhBao || '').includes('thiếu hóa đơn cũ'))
      return ['thieu_du_lieu_hd', 'HĐ ký trước 04/2025, thiếu hóa đơn cũ → SL còn lại chưa chuẩn'];
    if (q14 + qon === h14 + hfy) return ['nham_loai', 'Tổng khớp, chỉ lệch phân loại 1.4 ↔ chính'];
    return ['lech_sl', 'Lệch SL thật'];
  };
  const out = [];
  for (const r of rows) {
    for (const cs of ['14', 'fy']) {
      const kq = cs === 'fy' ? r.kqFy : r.kq14;
      if (!kq || kq === 'Khớp') continue;
      const [nnMa, nnChiTiet] = cs === 'fy' ? nnFy(r) : nn14(r);
      const slQ = cs === 'fy' ? n(r.qChinh) + n(r.qBs) : n(r.q14);
      const slH = cs === 'fy' ? n(r.hFy) : n(r.h14);
      const tienQ = cs === 'fy' ? n(r.tQOn) : n(r.tQ14);
      // Tiền HĐ còn lại đầu năm không có sẵn: SL còn lại × giá HĐ bình quân.
      const tienH = cs === 'fy' ? n(r.tHFy) : slH * n(r.giaH);
      const ps = r.psQ || r.psH || '';
      out.push({
        key: `${cs}|${r.kh}|${r.khoa}`,
        buoc: 'hd',
        cuaSo: cs,
        cuaSoLabel: cuaSoLabel[cs],
        ps,
        custId: r.kh || '',
        tenKh: r.tenKh || r.kh || '',
        grp: nhom1(r),
        bu: String(r.bu || '').split(',')[0].trim(),
        buList: String(r.bu || '').split(',').map((x) => x.trim()).filter(Boolean),
        kq,
        nnMa,
        nn: NN_HD[nnMa],
        nnChiTiet,
        slQ,
        slH,
        tienQ,
        tienH,
        giaTri: Math.abs(tienQ - tienH),
        soHd: cs === 'fy' ? r.soHdFy : r.soHdTruoc,
        moTa: `${cuaSoLabel[cs]} · ${r.tenKh || r.kh} · ${r.tenSp || r.khoa} · ${kq}`,
        row: r,
      });
    }
  }
  return out;
}

// Tỷ lệ tiền quota on hand (1.4 + chính / BS đang hiệu lực) thuộc khoá đã khớp HĐ.
export function tyLeKhopHopDong(rows, viewBu) {
  let tong = 0;
  let khop = 0;
  let nKhop = 0;
  for (const r of rows) {
    if (viewBu && !String(r.bu || '').split(',').map((x) => x.trim()).includes(viewBu)) continue;
    const t14 = n(r.tQ14);
    const tOn = n(r.tQOn);
    tong += t14 + tOn;
    if (r.kq14 === 'Khớp') {
      khop += t14;
      nKhop++;
    }
    if (r.kqFy === 'Khớp') {
      khop += tOn;
      nKhop++;
    }
  }
  return { tyLe: tong > 0 ? khop / tong : 0, nKhop, tong, khop };
}

// ---------- gom nhóm ----------
export const NHOM_THEO = [
  { id: 'nn', label: 'Nguyên nhân' },
  { id: 'ps', label: 'PS' },
  { id: 'kh', label: 'Khách hàng' },
  { id: 'grp', label: 'Nhóm SP' },
  { id: 'none', label: 'Không gom' },
];
const khoaNhom = { nn: (x) => x.nn || '—', ps: (x) => x.ps || '—', kh: (x) => x.tenKh || x.custId || '—', grp: (x) => x.grp || '—' };

export function gomNhom(items, theo) {
  if (theo === 'none' || !khoaNhom[theo]) return [{ key: '', label: '', items }];
  const m = new Map();
  for (const it of items) {
    const k = khoaNhom[theo](it);
    if (!m.has(k)) m.set(k, []);
    m.get(k).push(it);
  }
  return [...m]
    .map(([k, list]) => ({ key: k, label: k, items: list, giaTri: list.reduce((s, x) => s + (x.giaTri || 0), 0) }))
    .sort((a, b) => b.giaTri - a.giaTri || b.items.length - a.items.length || a.label.localeCompare(b.label, 'vi'));
}

// ---------- ảnh chụp số liệu ----------
// snapshot: các bản [{ngay, bu, buoc, so_viec, gia_tri}] mới → cũ. Lấy bản gần nhất TRƯỚC homNay.
export function banTruoc(snapshot, bu, buoc, homNay) {
  for (const s of snapshot || []) {
    if ((s.bu || '') === (bu || '') && s.buoc === buoc && s.ngay < homNay) return s;
  }
  return null;
}
