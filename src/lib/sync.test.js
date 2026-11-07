import { describe, it, expect } from "vitest";
import { pickUnknown, pickKnownDeleted } from "./sync.js";

describe("pickUnknown", () => {
  const known = new Map([[1, 10], [2, 20]]);
  it("skips rows already known at the same rev", () => {
    expect(pickUnknown(known, [1, 2], [10, 20])).toEqual([]);
  });
  it("keeps rows with a newer rev or not seen yet", () => {
    expect(pickUnknown(known, [1, 2, 3], [11, 20, 30])).toEqual([0, 2]);
  });
  it("handles missing arrays", () => {
    expect(pickUnknown(known, undefined, undefined)).toEqual([]);
  });
});

describe("pickKnownDeleted", () => {
  it("keeps only ids the client still holds", () => {
    expect(pickKnownDeleted(new Map([[5, 1]]), [5, 6])).toEqual([5]);
    expect(pickKnownDeleted(new Map(), undefined)).toEqual([]);
  });
});
