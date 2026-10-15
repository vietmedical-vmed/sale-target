import { MONTHS } from '../config/constants.js';

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
//   'on'  — đang trong hiệu lực
//   'het' — đã hết hiệu lực (không tính on hand, không vào tổng quota)
export function trangThaiDot(thang, hieuLuc, curMonth) {
  const het = hetHanDot(thang, hieuLuc);
  if (!het || thang > curMonth) return 'up';
  return het < curMonth ? 'het' : 'on';
}

// Gắn quota on-hand / upcoming (số lượng) vào từng dòng cho 2 màn tổng hợp:
// r._qOnHand, r._qUp, r._qHet (hết hiệu lực, không vào tổng). Cộng mọi dòng của
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
    // Dòng ngoài kế hoạch / ngoài 12 tháng không mang quota.
    if (!q || r._oop || daGan.has(k) || !MONTHS.includes(r.mo))
      return { ...r, _qOnHand: 0, _qUp: 0, _qHet: 0 };
    daGan.add(k);
    return { ...r, _qOnHand: q.onHand, _qUp: q.up, _qHet: q.het };
  });
}
