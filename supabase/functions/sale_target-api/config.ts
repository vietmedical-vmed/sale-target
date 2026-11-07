export const COL: Record<string, string> = {
  fy: "nam_tai_chinh", mo: "thang_ke_hoach", region: "mien", ps: "ps",
  cust: "khach_hang", custId: "ma_khach_hang", grp: "nhom_san_pham",
  prod: "san_pham", mset: "bo_vat_tu", rev: "sl_ke_hoach_dau_nam",
  revUpd: "sl_ke_hoach_update", price: "don_gia",
  act: "sl_thuc_hien", dtAct: "doanh_thu_thuc_hien",
  dt: "doanh_thu_kh_dau_nam", bu: "bu", oop: "ngoai_ke_hoach",
};

export const FIELDS = [
  "fy","mo","region","ps","cust","custId","grp","prod","mset",
  "rev","revUpd","price","act","dtAct","dt","bu","oop",
];

// Quota / tháng / thời gian thầu nằm ở quota_thau / dot_thau; sale_target không còn các cột đó.
export const EDITABLE = new Set(["revUpd","price"]);
export const ADMIN_EDITABLE = new Set(["mset","prod","rev","dt"]);
// Manager chỉ sửa SL đầu năm; doanh thu đầu năm do server tính = SL × đơn giá.
export const MANAGER_EDITABLE = new Set(["rev"]);

export const DEMO_BU = "test";
export const OOP_CUST = "Ngoài kế hoạch";

// 12 tháng kế hoạch của năm tài chính đang chạy (tháng 4 → tháng 3 năm sau) và mã FY
// suy ra từ tháng đầu ("2026-04" → "FY26", giống public.fy_from_thang). Không đọc FY
// từ một dòng sale_target bất kỳ: bảng còn dòng FY25 (thực hiện ngoài kế hoạch).
export const PLAN_MONTHS = [
  "2026-04","2026-05","2026-06","2026-07","2026-08","2026-09",
  "2026-10","2026-11","2026-12","2027-01","2027-02","2027-03",
];
export function fyFromMonth(mo: string) {
  const y = Number(mo.slice(0, 4)), m = Number(mo.slice(5, 7));
  return "FY" + String(m >= 4 ? y : y - 1).slice(2);
}
export const PLAN_FY = fyFromMonth(PLAN_MONTHS[0]);

// Chỉ dòng thuộc 12 tháng kế hoạch: bảng còn ~5.800 dòng thực hiện ngoài kế hoạch FY25 mà
// client không dùng (màn tổng hợp bỏ tháng ngoài FY) — bỏ ở server cho đỡ tải mỗi lần mở app.
// deno-lint-ignore no-explicit-any
export function onlyPlanMonths(q: any) {
  return q.gte("thang_ke_hoach", PLAN_MONTHS[0]).lte("thang_ke_hoach", PLAN_MONTHS[PLAN_MONTHS.length - 1]);
}

export const PAGE = 1000;
export const CONCURRENCY = 6;
