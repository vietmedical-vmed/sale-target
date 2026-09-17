import { describe, it, expect } from "vitest";
import { deaccent, isLooseSet, titleWord, fmtCust } from "./text.js";

describe("deaccent", () => {
  it("removes Vietnamese diacritics", () => {
    expect(deaccent("Bệnh viện")).toBe("benh vien");
  });
  it("converts đ to d", () => {
    expect(deaccent("Đà Nẵng")).toBe("da nang");
  });
  it("handles null/undefined", () => {
    expect(deaccent(null)).toBe("");
    expect(deaccent(undefined)).toBe("");
  });
});

describe("isLooseSet", () => {
  it("detects loose set name", () => {
    expect(isLooseSet("Vật tư riêng lẻ ABC")).toBe(true);
  });
  it("rejects other names", () => {
    expect(isLooseSet("Bộ vật tư chính")).toBe(false);
  });
});

describe("titleWord", () => {
  it("capitalizes first letter", () => {
    expect(titleWord("hello")).toBe("Hello");
  });
  it("handles empty string", () => {
    expect(titleWord("")).toBe("");
  });
});

describe("fmtCust", () => {
  it("abbreviates Bệnh viện to BV", () => {
    expect(fmtCust("bệnh viện chợ rẫy")).toBe("BV Chợ Rẫy");
  });
  it("title-cases normal names", () => {
    expect(fmtCust("PHONG KHAM DA KHOA")).toBe("Phong Kham Da Khoa");
  });
  it("handles null", () => {
    expect(fmtCust(null)).toBe(null);
  });
});
