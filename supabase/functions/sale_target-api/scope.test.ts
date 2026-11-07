// Test logic phạm vi quyền (chạy bằng vitest: `npm test`). scope.ts quyết định mỗi vai trò
// thấy / sửa được dòng nào — lỗi ở đây là lộ hoặc ghi đè dữ liệu của người khác.
import { describe, it, expect } from "vitest";
import { applyScope, scopeParams, readScopeParams, parseGroups } from "./scope.ts";
import type { Session } from "../_shared/auth.ts";

// Query builder giả: ghi lại các lời gọi lọc để so sánh.
function fakeQuery() {
  const calls: string[] = [];
  const q: Record<string, (...a: unknown[]) => unknown> = {};
  for (const m of ["eq", "in", "or", "is", "neq"]) {
    q[m] = (...a: unknown[]) => {
      calls.push(`${m}(${a.map((x) => JSON.stringify(x)).join(",")})`);
      return q;
    };
  }
  return { q, calls };
}

const sess = (o: Partial<Session>): Session => ({
  u: "u", n: "U", r: "ps", s: "", b: "chcs", m: "MB", g: "", exp: 0, ...o,
});

// deno-lint-ignore no-explicit-any
const run = (s: Session, payload: Record<string, unknown> = {}) => {
  const { q, calls } = fakeQuery();
  // deno-lint-ignore no-explicit-any
  applyScope(q as any, s, payload);
  return calls;
};

describe("parseGroups", () => {
  it("splits and trims comma lists", () => {
    expect(parseGroups(" A , B,,C ")).toEqual(["A", "B", "C"]);
    expect(parseGroups(null)).toEqual([]);
  });
});

describe("applyScope", () => {
  it("ps sees only own BU and own PS", () => {
    expect(run(sess({ r: "ps", s: "Tùng Phạm", b: "chcs" }))).toEqual([
      'eq("bu","chcs")', 'eq("ps","Tùng Phạm")',
    ]);
  });

  it("ps cannot widen scope through payload.bu", () => {
    const c = run(sess({ r: "ps", s: "Tùng Phạm", b: "chcs" }), { bu: "cttm" });
    expect(c).toContain('eq("bu","chcs")');
    expect(c).not.toContain('eq("bu","cttm")');
  });

  it("area_manager is limited to BU and listed regions", () => {
    expect(run(sess({ r: "area_manager", s: "Miền Bắc, Miền Trung", b: "chcs" }))).toEqual([
      'eq("bu","chcs")', 'in("mien",["Miền Bắc","Miền Trung"])',
    ]);
  });

  it("area_manager with empty region list sees nothing", () => {
    expect(run(sess({ r: "area_manager", s: "", b: "chcs" }))).toContain('eq("mien","__none__")');
  });

  it("admin without bu excludes demo BU; with bu filters to it", () => {
    expect(run(sess({ r: "admin" }))).toEqual(['or("bu.is.null,bu.neq.test")']);
    expect(run(sess({ r: "admin" }), { bu: "cttm" })).toEqual(['eq("bu","cttm")']);
  });

  it("product_manager sees only listed groups, intersected with nhom_san_pham", () => {
    expect(run(sess({ r: "product_manager", s: "A,B" }))).toEqual([
      'or("bu.is.null,bu.neq.test")', 'in("nhom_san_pham",["A","B"])',
    ]);
    expect(run(sess({ r: "product_manager", s: "A,B", g: "B,C" }))).toEqual([
      'or("bu.is.null,bu.neq.test")', 'eq("nhom_san_pham","B")',
    ]);
    expect(run(sess({ r: "product_manager", s: "", g: "" }))).toContain('eq("nhom_san_pham","__none__")');
  });

  it("unknown role is treated like ps (never sees everything)", () => {
    expect(run(sess({ r: "khach", s: "X", b: "chcs" }))).toEqual(['eq("bu","chcs")', 'eq("ps","X")']);
  });

  it("nhom_san_pham narrows any role", () => {
    expect(run(sess({ r: "manager", g: "A" }))).toEqual([
      'or("bu.is.null,bu.neq.test")', 'eq("nhom_san_pham","A")',
    ]);
  });
});

describe("scopeParams", () => {
  it("admin/manager unrestricted except groups", () => {
    expect(scopeParams(sess({ r: "admin" }))).toEqual({ p_bu: null, p_mien: null, p_ps: null, p_groups: null });
    expect(scopeParams(sess({ r: "manager", g: "A,B" })).p_groups).toEqual(["A", "B"]);
  });
  it("ps is pinned to own BU and PS", () => {
    expect(scopeParams(sess({ r: "ps", s: "P1", b: "cttm" }))).toEqual({
      p_bu: "cttm", p_mien: null, p_ps: "P1", p_groups: null,
    });
  });
  it("area_manager gets region list, or __none__ when empty", () => {
    expect(scopeParams(sess({ r: "area_manager", s: "Miền Nam", b: "cttm" })).p_mien).toBe("Miền Nam");
    expect(scopeParams(sess({ r: "area_manager", s: "", b: "cttm" })).p_mien).toBe("__none__");
  });
  it("product_manager with no groups gets __none__", () => {
    expect(scopeParams(sess({ r: "product_manager", s: "" })).p_groups).toEqual(["__none__"]);
  });
  it("readScopeParams lets only admin/manager pick a BU", () => {
    expect(readScopeParams(sess({ r: "admin" }), { bu: "thnk" }).p_bu).toBe("thnk");
    expect(readScopeParams(sess({ r: "ps", s: "P", b: "chcs" }), { bu: "thnk" }).p_bu).toBe("chcs");
  });
});
