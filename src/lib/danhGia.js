// Đánh giá DThu dự kiến của 1 nhóm PS × KH × nhóm SP (gộp với "Dthu KH tiêu chuẩn",
// chốt 11/11/2026). Chỉ admin xem; không đánh giá BV tư và KH ngoài kế hoạch.
//
// Dthu tiêu chuẩn = quota định mức cả năm = quota 1.4 (thầu cũ, tính đủ) + quota chính /
// BS × số tháng hiệu lực trong năm tài chính / hiệu lực (lib/quota.js, _qDinhMuc).
// Ma trận 2 trục:
//   % dự kiến / target       : < 90% → 'thap', còn lại 'dat'
//   % dự kiến / tiêu chuẩn   : > 110% → 'vuot', 90–110% → 'khop', < 90% → 'duoi'
// Cờ phụ: dồn cuối năm (tốc độ cần cho các tháng còn lại > 1,3 × tốc độ TH YTD), độ tin
// cậy thấp (quota 1.4 chiếm > 50% tiêu chuẩn — thầu cũ chưa liên kết được hợp đồng).

export const NGUONG_DG = {
  target: 0.9, // % dự kiến / target dưới mức này là thấp
  tcDuoi: 0.9, // % dự kiến / tiêu chuẩn: dưới mức này là chưa dùng hết quota
  tcTren: 1.1, // trên mức này là vượt quota
  tangToc: 1.3, // tốc độ cần / tốc độ TH YTD
  tyLeQuotaCu: 0.5, // quota 1.4 / tiêu chuẩn
};

export const NHAN_DG = {
  thieu_quota: { mau: 'do', ten: 'Thiếu quota', goiY: 'Dự kiến thấp mà vẫn vượt quota: cần thầu bổ sung hoặc kiểm quota nhập thiếu / sai giá.' },
  vuot_quota: { mau: 'cam', ten: 'Vượt quota', goiY: 'Dự kiến vượt quota: hỏi PS có thầu mới chưa nhập không, nếu không thì hạ dự kiến.' },
  target_cao: { mau: 'vang', ten: 'Target > quota', goiY: 'Quota gần hết nhưng dự kiến vẫn dưới target: xem lại target hoặc tìm KH khác.' },
  phu_hop: { mau: 'xanh', ten: 'Phù hợp', goiY: 'Dự kiến đạt target và khớp quota.' },
  duoi_nang_luc: { mau: 'do', ten: 'Dưới năng lực', goiY: 'Còn quota nhưng dự kiến dưới target: PS giải trình và nâng KH.' },
  du_dia: { mau: 'xanh', ten: 'Còn dư địa', goiY: 'Dự kiến đạt target, quota còn dư để nâng dự kiến.' },
};

const MA_TRAN = {
  vuot: { thap: 'thieu_quota', dat: 'vuot_quota' },
  khop: { thap: 'target_cao', dat: 'phu_hop' },
  duoi: { thap: 'duoi_nang_luc', dat: 'du_dia' },
};

// Mọi giá trị là doanh thu (cùng đơn vị). thangDaQua / thangConLai: số tháng trong năm
// tài chính đã có TH (gồm tháng hiện tại) / còn lại. Trả null khi nhóm không có gì để xét.
export function danhGiaDuKien({ target, duKien, tieuChuan, thYtd, quota14, thangDaQua, thangConLai }, ng = NGUONG_DG) {
  const T = Number(target) || 0;
  const D = Number(duKien) || 0;
  const TC = Number(tieuChuan) || 0;
  const Y = Number(thYtd) || 0;
  if (T <= 0 && D <= 0 && TC <= 0) return null;
  const pTarget = T > 0 ? D / T : null;
  const pTc = TC > 0 ? D / TC : null;
  // Không có quota mà vẫn dự kiến bán → coi như vượt quota.
  const trucTc = TC > 0 ? (pTc > ng.tcTren ? 'vuot' : pTc >= ng.tcDuoi ? 'khop' : 'duoi') : D > 0 ? 'vuot' : 'duoi';
  const trucTarget = T > 0 ? (pTarget < ng.target ? 'thap' : 'dat') : 'dat';
  const nhan = MA_TRAN[trucTc][trucTarget];
  // Tách phần dự kiến hụt so với target: do target vượt quota / do chưa khai thác quota.
  const thieuQuota = Math.max(0, T - TC);
  const chuaKhaiThac = Math.max(0, Math.min(T, TC) - D);
  let tocDoTh = null,
    tocDoCan = null,
    donCuoiNam = false;
  if (thangDaQua > 0 && thangConLai > 0) {
    tocDoTh = Y / thangDaQua;
    tocDoCan = Math.max(0, D - Y) / thangConLai;
    donCuoiNam = tocDoCan > 0 && tocDoCan > ng.tangToc * tocDoTh;
  }
  const tinCayThap = TC > 0 && (Number(quota14) || 0) / TC > ng.tyLeQuotaCu;
  return { nhan, mau: NHAN_DG[nhan].mau, pTarget, pTc, thieuQuota, chuaKhaiThac, tocDoTh, tocDoCan, donCuoiNam, tinCayThap };
}

// Tổng hợp nhiều đánh giá lên cấp KH / PS / miền: đếm theo màu + cộng 2 phần chênh lệch.
export const dgRong = () => ({ do: 0, cam: 0, vang: 0, xanh: 0, donCuoiNam: 0, thieuQuota: 0, chuaKhaiThac: 0 });
export function congDg(a, x) {
  if (!x) return a;
  if (x.mau) {
    a[x.mau] += 1;
    if (x.donCuoiNam) a.donCuoiNam += 1;
  } else {
    a.do += x.do;
    a.cam += x.cam;
    a.vang += x.vang;
    a.xanh += x.xanh;
    a.donCuoiNam += x.donCuoiNam;
  }
  a.thieuQuota += x.thieuQuota;
  a.chuaKhaiThac += x.chuaKhaiThac;
  return a;
}
