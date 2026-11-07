import { describe, it, expect } from "vitest";
import { fmtInt, fmtM, fmtShort, parseNum, parseNumStrict } from "./format.js";

describe("fmtInt", () => {
  it("returns dash for null/undefined", () => {
    expect(fmtInt(null)).toBe("—");
    expect(fmtInt(undefined)).toBe("—");
  });
  it("returns dot for zero", () => {
    expect(fmtInt(0)).toBe("·");
  });
  it("formats positive integers with commas", () => {
    expect(fmtInt(1234)).toBe("1,234");
    expect(fmtInt(1000000)).toBe("1,000,000");
  });
  it("rounds decimals", () => {
    expect(fmtInt(1234.7)).toBe("1,235");
  });
});

describe("fmtM", () => {
  it("returns dash for zero/falsy", () => {
    expect(fmtM(0)).toBe("—");
    expect(fmtM(null)).toBe("—");
  });
  it("formats millions", () => {
    expect(fmtM(50_000_000)).toBe("50.0");
  });
  it("formats billions as integer millions", () => {
    expect(fmtM(2_500_000_000)).toBe("2,500");
  });
});

describe("fmtShort", () => {
  it("returns dash for null", () => {
    expect(fmtShort(null)).toBe("—");
  });
  it("formats billions", () => {
    expect(fmtShort(1_500_000_000)).toBe("1.50tỷ");
  });
  it("formats millions", () => {
    expect(fmtShort(2_300_000)).toBe("2.3tr");
  });
  it("formats thousands", () => {
    expect(fmtShort(5000)).toBe("5k");
  });
  it("returns small numbers as string", () => {
    expect(fmtShort(42)).toBe("42");
  });
});

describe("parseNum", () => {
  it("parses plain number", () => {
    expect(parseNum("1234")).toBe(1234);
  });
  it("strips commas", () => {
    expect(parseNum("1,234,567")).toBe(1234567);
  });
  it("returns 0 for empty/null", () => {
    expect(parseNum("")).toBe(0);
    expect(parseNum(null)).toBe(0);
  });
  it("returns 0 for non-numeric", () => {
    expect(parseNum("abc")).toBe(0);
  });
});

describe("parseNumStrict", () => {
  it("reads Vietnamese decimal comma", () => {
    expect(parseNumStrict("1,5")).toBe(1.5);
    expect(parseNumStrict("12,75")).toBe(12.75);
  });
  it("reads Vietnamese thousand dots", () => {
    expect(parseNumStrict("1.234.567")).toBe(1234567);
    expect(parseNumStrict("1.234.567,5")).toBe(1234567.5);
  });
  it("reads en-US formats the app displays", () => {
    expect(parseNumStrict("1,234")).toBe(1234);
    expect(parseNumStrict("1,234.5")).toBe(1234.5);
    expect(parseNumStrict("1.5")).toBe(1.5);
  });
  it("handles spaces, negatives and empty", () => {
    expect(parseNumStrict(" 2 500 ")).toBe(2500);
    expect(parseNumStrict("-3")).toBe(-3);
    expect(parseNumStrict("")).toBe(0);
    expect(parseNumStrict(null)).toBe(0);
    expect(parseNumStrict(7)).toBe(7);
  });
  it("returns null for invalid input instead of 0", () => {
    expect(parseNumStrict("abc")).toBeNull();
    expect(parseNumStrict("12a")).toBeNull();
    expect(parseNumStrict("1.2,3.4")).toBeNull();
    expect(parseNumStrict("--5")).toBeNull();
    expect(parseNumStrict(",")).toBeNull();
  });
});
