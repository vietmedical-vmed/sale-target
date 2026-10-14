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

export const DEMO_BU = "test";
export const OOP_CUST = "Ngoài kế hoạch";

export const PAGE = 1000;
export const CONCURRENCY = 6;
