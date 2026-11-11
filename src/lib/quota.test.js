import { describe, it, expect } from "vitest";
import { sanPhamAmQuota, buKhaDungBvTu, tyLeDinhMucDot, ganQuotaTheoDot } from "./quota.js";
import { MONTHS } from "../config/constants.js";

const prodKey = (fy, ps, custId, grp, mset, prod) =>
  [fy || "", ps || "", custId || "", grp || "", mset || "", prod || ""].join("||");
const grpKey = (fy, ps, custId, grp) => [fy || "", ps || "", custId || "", grp || ""].join("||");

const CUR = MONTHS[3];
const base = { fy: "FY26", ps: "PS A", custId: "KH1", cust: "Bệnh viện 1", grp: "Nhóm 1", mset: "M1", prod: "SP1", price: 100 };
const row = (mo, act, extra = {}) => ({ ...base, mo, act, ...extra });

function maps(dots, quotas) {
  const d = new Map();
  for (const x of dots) {
    const k = grpKey(x.fy, x.ps, x.custId, x.grp);
    if (!d.has(k)) d.set(k, []);
    d.get(k).push(x);
  }
  const q = new Map();
  for (const x of quotas) {
    const k = prodKey(x.fy, x.ps, x.custId, x.grp, x.mset, x.prod);
    if (!q.has(k)) q.set(k, []);
    q.get(k).push(x);
  }
  return [d, q];
}

describe("sanPhamAmQuota", () => {
  it("flags product whose YTD actual exceeds on-hand quota", () => {
    const rows = [row(MONTHS[0], 30), row(MONTHS[1], 40), row(MONTHS[5], 999)];
    const [d, q] = maps([], [{ ...base, loai: "cu", dot: 1, qty: 50 }]);
    const out = sanPhamAmQuota(rows, d, q, CUR);
    expect(out).toHaveLength(1);
    expect(out[0].onHand).toBe(50);
    expect(out[0].ytd).toBe(70); // tháng sau tháng hiện tại không tính
    expect(out[0].khaDung).toBe(-20);
    expect(out[0].thieuDt).toBe(2000);
    expect(out[0].lyDo).toBe("Quota nhỏ hơn thực hiện");
  });

  it("skips product with enough quota or zero balance", () => {
    const rows = [row(MONTHS[0], 50)];
    const [d, q] = maps([], [{ ...base, loai: "cu", dot: 1, qty: 50 }]);
    expect(sanPhamAmQuota(rows, d, q, CUR)).toHaveLength(0);
  });

  it("treats missing quota as zero on hand", () => {
    const [d, q] = maps([], []);
    const out = sanPhamAmQuota([row(MONTHS[0], 5)], d, q, CUR);
    expect(out).toHaveLength(1);
    expect(out[0].lyDo).toBe("Chưa nhập quota");
    expect(sanPhamAmQuota([row(MONTHS[0], 0)], d, q, CUR)).toHaveLength(0);
  });

  it("hints quota entered at another price", () => {
    const [d, q] = maps([], [{ ...base, price: 120, loai: "cu", dot: 1, qty: 80 }]);
    const out = sanPhamAmQuota([row(MONTHS[0], 10)], d, q, CUR);
    expect(out).toHaveLength(1);
    expect(out[0].lyDo).toMatch(/giá khác/);
  });

  it("hints upcoming quota from a tender not yet started", () => {
    const dot = { ...base, loai: "chinh", dot: 1, thang: MONTHS[8], thoiGian: 12 };
    const [d, q] = maps([dot], [{ ...base, loai: "chinh", dot: 1, qty: 100 }]);
    const out = sanPhamAmQuota([row(MONTHS[0], 10)], d, q, CUR);
    expect(out).toHaveLength(1);
    expect(out[0].onHand).toBe(0);
    expect(out[0].lyDo).toMatch(/chưa tới tháng thầu/);
  });

  it("keeps price levels and PS separate, ignores out-of-plan rows", () => {
    const rows = [
      row(MONTHS[0], 10),
      row(MONTHS[0], 10, { price: 200 }),
      row(MONTHS[0], 10, { ps: "PS B" }),
      row(MONTHS[0], 10, { _oop: true, prod: "SP OOP" }),
    ];
    const [d, q] = maps([], [{ ...base, loai: "cu", dot: 1, qty: 10 }]);
    const out = sanPhamAmQuota(rows, d, q, CUR);
    expect(out.map((x) => `${x.ps}|${x.price}`).sort()).toEqual(["PS A|200", "PS B|100"]);
  });
});

describe("buKhaDungBvTu", () => {
  const ytdMo = MONTHS[0];
  const r = (custId, prod, onHand, act, price = 100) => ({
    ps: "PS A", custId, grp: "G", mset: "M", prod, mo: ytdMo, price,
    _qOnHand: onHand, act, dtAct: act * price,
  });

  it("offsets negative available quota of private hospitals only", () => {
    const tuAm = r("TU1", "SP1", 5, 8); // khả dụng −3
    const tuDuong = r("TU1", "SP2", 10, 4); // khả dụng +6, giữ nguyên
    const congAm = r("CONG1", "SP1", 2, 7); // BV công âm, giữ nguyên
    const bu = buKhaDungBvTu([tuAm, tuDuong, congAm], new Set(["TU1"]));
    expect(bu.get(tuAm)).toEqual({ sl: 3, dt: 300 });
    expect(bu.has(tuDuong)).toBe(false);
    expect(bu.has(congAm)).toBe(false);
  });

  it("nets all rows of one key and puts the offset on the first row only", () => {
    const a = r("TU1", "SP1", 4, 3);
    const b = { ...r("TU1", "SP1", 0, 5), mo: MONTHS[1] };
    const bu = buKhaDungBvTu([a, b], new Set(["TU1"]));
    expect(bu.get(a)).toEqual({ sl: 4, dt: 400 });
    expect(bu.has(b)).toBe(false);
  });

  it("returns empty map without private hospitals", () => {
    expect(buKhaDungBvTu([r("TU1", "SP1", 0, 5)], new Set()).size).toBe(0);
  });
});

describe("tyLeDinhMucDot", () => {
  it("prorates months of validity inside the fiscal year", () => {
    // 2026-09 + 3 = 2026-12 .. 2027-11 → 4 tháng trong FY26 (đến 2027-03)
    expect(tyLeDinhMucDot("2026-09", 12)).toBeCloseTo(4 / 12);
    // 2026-01 + 3 = 2026-04 .. 2027-03 → đủ 12 tháng
    expect(tyLeDinhMucDot("2026-01", 12)).toBe(1);
    // thầu trước năm tài chính: chỉ tính phần còn lại trong FY (2025-10 → 2026-01..2026-12)
    expect(tyLeDinhMucDot("2025-10", 12)).toBeCloseTo(9 / 12);
    // 24 tháng: 2026-06 → 2026-09..2028-08, trong FY26 có 7 tháng
    expect(tyLeDinhMucDot("2026-06", 24)).toBeCloseTo(7 / 24);
  });

  it("returns 0 outside the fiscal year or when data is missing", () => {
    expect(tyLeDinhMucDot("2027-01", 12)).toBe(0); // bắt đầu 2027-04
    expect(tyLeDinhMucDot("2024-10", 12)).toBe(0); // hết 2025-12
    expect(tyLeDinhMucDot("", 12)).toBe(0);
    expect(tyLeDinhMucDot("2026-09", null)).toBe(0);
  });
});

describe("ganQuotaTheoDot _qDinhMuc", () => {
  it("adds old quota in full plus the in-year share of new tenders", () => {
    const k = { fy: "FY26", ps: "PS A", custId: "KH1", grp: "G", mset: "M", prod: "SP1", price: 100 };
    const dots = [
      { ...k, loai: "chinh", dot: 1, thang: "2026-09", thoiGian: 12 },
      { ...k, loai: "bo_sung", dot: 1, thang: "2027-02", thoiGian: 12 },
    ];
    const quotas = [
      { ...k, loai: "cu", dot: 0, qty: 30 },
      { ...k, loai: "chinh", dot: 1, qty: 120 },
      { ...k, loai: "bo_sung", dot: 1, qty: 60 },
      { ...k, loai: "bo_sung", dot: 2, qty: 50 }, // không có đợt → 0
    ];
    const rows = [{ ...k, mo: MONTHS[0] }, { ...k, mo: MONTHS[1] }];
    const out = ganQuotaTheoDot(rows, dots, quotas, MONTHS[7]);
    expect(out[0]._qDinhMuc).toBeCloseTo(30 + 40);
    expect(out[1]._qDinhMuc).toBe(0);
  });
});
