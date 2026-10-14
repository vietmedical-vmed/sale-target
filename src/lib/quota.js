import { MONTHS } from '../config/constants.js';

const grpKey = (fy, ps, custId, grp) =>
  [fy || '', ps || '', custId || '', grp || ''].join('||');
const prodKey = (fy, ps, custId, grp, mset, prod) =>
  [fy || '', ps || '', custId || '', grp || '', mset || '', prod || ''].join('||');

// Gắn quota on-hand / upcoming (số lượng) vào từng dòng cho 2 màn tổng hợp:
// r._qOnHand, r._qUp. Cộng mọi dòng của 1 sản phẩm là ra quota của sản phẩm đó.
//
// Nguồn duy nhất là shared.quota_thau (sale_target không còn lưu quota / tháng
// thầu); tháng thầu lấy theo TỪNG ĐỢT ở shared.dot_thau. Quota mỗi mức giá đặt lên
// 1 dòng đại diện của đúng mức giá đó (giống lưới chi tiết); quota ở mức giá không
// còn trên kế hoạch thì bỏ qua, như lưới.
export function ganQuotaTheoDot(rows, dots, quotas, curMonth) {
  const thangDot = new Map(); // grpKey → Map(`loai|dot` → tháng)
  for (const d of dots || []) {
    const k = grpKey(d.fy, d.ps, d.custId, d.grp);
    if (!thangDot.has(k)) thangDot.set(k, new Map());
    thangDot.get(k).set(`${d.loai}|${d.dot}`, d.thang || '');
  }
  const quotaTheoGia = new Map(); // prodKey|giá → { onHand, up }
  for (const q of quotas || []) {
    const gk = grpKey(q.fy, q.ps, q.custId, q.grp);
    const k = `${prodKey(q.fy, q.ps, q.custId, q.grp, q.mset, q.prod)}|${Number(q.price) || 0}`;
    if (!quotaTheoGia.has(k)) quotaTheoGia.set(k, { onHand: 0, up: 0 });
    const o = quotaTheoGia.get(k);
    const n = Number(q.qty) || 0;
    if (q.loai === 'cu') o.onHand += n;
    else {
      const thang = thangDot.get(gk)?.get(`${q.loai}|${q.dot}`) || '';
      if (thang && thang <= curMonth) o.onHand += n;
      else o.up += n;
    }
  }
  const daGan = new Set();
  return rows.map((r) => {
    const k = `${prodKey(r.fy, r.ps, r.custId, r.grp, r.mset, r.prod)}|${Number(r.price) || 0}`;
    const q = quotaTheoGia.get(k);
    // Dòng ngoài kế hoạch / ngoài 12 tháng không mang quota.
    if (!q || r._oop || daGan.has(k) || !MONTHS.includes(r.mo))
      return { ...r, _qOnHand: 0, _qUp: 0 };
    daGan.add(k);
    return { ...r, _qOnHand: q.onHand, _qUp: q.up };
  });
}
