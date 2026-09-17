import { describe, it, expect } from "vitest";
import { fmtInt, fmtM, fmtShort, parseNum } from "./format.js";

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
