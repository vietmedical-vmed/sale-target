import { MONTHS, HIEN_HET_HIEU_LUC } from '../config/constants.js';

const grpKey = (fy, ps, custId, grp) =>
  [fy || '', ps || '', custId || '', grp || ''].join('||');
const prodKey = (fy, ps, custId, grp, mset, prod) =>
  [fy || '', ps || '', custId || '', grp || '', mset || '', prod || ''].join('||');

// Hiệu lực thầu = số tháng (dot_thau.thoi_gian). Tháng cuối còn hiệu lực (hết hạn)
// = tháng thầu + 3 tháng + hiệu lực − 1 (user chốt 16/10; vd 2026-03, 24 tháng → 2028-05).
export const THANG_CONG_THEM_HIEU_LUC = 3;
export function hetHanDot(thang, hieuLuc) {
  const n = Number(hieuLuc);
  if (!/^\d{4}-\d{2}$/.test(thang || '') || !(n > 0)) return '';
  const [y, m] = thang.split('-').map(Number);
  const t = y * 12 + (m - 1) + THANG_CONG_THEM_HIEU_LUC + Math.trunc(n) - 1;
  return `${Math.floor(t / 12)}-${String((t % 12) + 1).padStart(2, '0')}`;
}

// Trạng thái quota của 1 đợt so với tháng hiện tại:
//   'up'  — chưa tới tháng thầu, hoặc đợt còn thiếu tháng / hiệu lực
//   'on'  — đang trong hiệu lực, HOẶC đã hết hạn nhưng trong năm tài chính đang xem
//   'het' — hết hiệu lực trước đầu năm tài chính (không tính on hand, không vào tổng)
// Đợt hết hạn giữa năm vẫn tính on hand và tổng: thực hiện YTD đã gồm phần bán theo
// đợt đó từ đầu năm, bỏ đợt ra thì tổng giảm và khả dụng (on hand − TH YTD) bị âm.
export function trangThaiDot(thang, hieuLuc, curMonth, fyStart = MONTHS[0]) {
  const het = hetHanDot(thang, hieuLuc);
  if (!het || thang > curMonth) return 'up';
  return het < curMonth && het < fyStart ? 'het' : 'on';
}

// Gắn quota on-hand / upcoming (số lượng) vào từng dòng cho 2 màn tổng hợp:
// r._qOnHand, r._qUp, r._qHet (hết hiệu lực trước năm tài chính, không vào tổng). Cộng mọi dòng của
// 1 sản phẩm là ra quota của sản phẩm đó.
//
// Nguồn duy nhất là shared.quota_thau (sale_target không còn lưu quota / tháng
// thầu); tháng thầu lấy theo TỪNG ĐỢT ở shared.dot_thau. Quota mỗi mức giá đặt lên
// 1 dòng đại diện của đúng mức giá đó (giống lưới chi tiết); quota ở mức giá không
// còn trên kế hoạch thì bỏ qua, như lưới.
export function ganQuotaTheoDot(rows, dots, quotas, curMonth) {
  const thangDot = new Map(); // grpKey → Map(`loai|dot` → { thang, hieuLuc })
  for (const d of dots || []) {
    const k = grpKey(d.fy, d.ps, d.custId, d.grp);
    if (!thangDot.has(k)) thangDot.set(k, new Map());
    thangDot.get(k).set(`${d.loai}|${d.dot}`, { thang: d.thang || '', hieuLuc: d.thoiGian });
  }
  const quotaTheoGia = new Map(); // prodKey|giá → { onHand, up, het }
  for (const q of quotas || []) {
    const gk = grpKey(q.fy, q.ps, q.custId, q.grp);
    const k = `${prodKey(q.fy, q.ps, q.custId, q.grp, q.mset, q.prod)}|${Number(q.price) || 0}`;
    if (!quotaTheoGia.has(k)) quotaTheoGia.set(k, { onHand: 0, up: 0, het: 0 });
    const o = quotaTheoGia.get(k);
    const n = Number(q.qty) || 0;
    if (q.loai === 'cu') o.onHand += n;
    else {
      const d = thangDot.get(gk)?.get(`${q.loai}|${q.dot}`);
      const tt = d ? trangThaiDot(d.thang, d.hieuLuc, curMonth) : 'up';
      if (tt === 'on') o.onHand += n;
      else if (tt === 'het') o.het += n;
      else o.up += n;
    }
  }
  const daGan = new Set();
  return rows.map((r) => {
    const k = `${prodKey(r.fy, r.ps, r.custId, r.grp, r.mset, r.prod)}|${Number(r.price) || 0}`;
    const q = quotaTheoGia.get(k);
    const hasQuota = !!q;
    // Dòng ngoài kế hoạch / ngoài 12 tháng không mang quota.
    if (!q || r._oop || daGan.has(k) || !MONTHS.includes(r.mo))
      return { ...r, _qOnHand: 0, _qUp: 0, _qHet: 0, _hasQuota: hasQuota && !r._oop };
    daGan.add(k);
    return { ...r, _qOnHand: q.onHand, _qUp: q.up, _qHet: q.het, _hasQuota: true };
  });
}

// Quota của MỘT dòng sản phẩm trên lưới chi tiết (khoá KH × nhóm × PS × SP × đơn giá).
// Dùng chung cho lưới (ProductGroupSection) và file Excel tab Chi tiết để hai nơi
// luôn ra cùng một số. anchor = dòng đầu tiên của sản phẩm (lấy fy/ps/custId/grp/price).
// Chỉ lấy quota của đúng mức giá của dòng: cộng cả sản phẩm thì mọi dòng giá đều
// hiện cùng một con số, nhìn như bị nhân đôi.
export function quotaSanPham(dotsByGroup, quotasByProduct, anchor, mset, product, curMonth) {
  if (!dotsByGroup || !quotasByProduct || !anchor) return null;
  const gk = grpKey(anchor.fy, anchor.ps, anchor.custId, anchor.grp);
  const dots = dotsByGroup.get(gk) || [];
  const list =
    quotasByProduct.get(prodKey(anchor.fy, anchor.ps, anchor.custId, anchor.grp, mset, product)) || [];
  const giaDong = Number(anchor.price) || 0;
  const cungGia = list.filter((q) => (Number(q.price) || 0) === giaDong);
  const dotInfo = new Map();
  for (const d of dots) dotInfo.set(`${d.loai}|${d.dot}`, d);
  let cu = 0,
    chinh = 0,
    bo_sung = 0,
    onHand = 0,
    het = 0;
  for (const q of cungGia) {
    const n = Number(q.qty) || 0;
    if (q.loai === 'cu') {
      cu += n;
      onHand += n;
    } else {
      const d = dotInfo.get(`${q.loai}|${q.dot}`);
      const tt = d ? trangThaiDot(d.thang, d.thoiGian, curMonth) : 'up';
      if (tt === 'het') {
        het += n;
        // Đang ẩn phần hết hiệu lực: không cộng vào cột chính / BS để Tổng = cũ + chính + BS.
        if (!HIEN_HET_HIEU_LUC) continue;
      }
      if (q.loai === 'chinh') chinh += n;
      else bo_sung += n;
      if (tt === 'on') onHand += n;
    }
  }
  return { cu, chinh, bo_sung, onHand, het, hasQuota: cungGia.length > 0 };
}
