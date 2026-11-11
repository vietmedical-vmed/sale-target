import { describe, it, expect } from "vitest";
import { danhGiaDuKien, dgRong, congDg } from "./danhGia.js";

const dg = (o) => danhGiaDuKien({ thYtd: 0, quota14: 0, thangDaQua: 8, thangConLai: 4, ...o });

describe("danhGiaDuKien", () => {
  it("places each case in the right matrix cell", () => {
    expect(dg({ target: 100, duKien: 80, tieuChuan: 60 }).nhan).toBe("thieu_quota");
    expect(dg({ target: 100, duKien: 100, tieuChuan: 80 }).nhan).toBe("vuot_quota");
    expect(dg({ target: 100, duKien: 80, tieuChuan: 80 }).nhan).toBe("target_cao");
    expect(dg({ target: 100, duKien: 100, tieuChuan: 100 }).nhan).toBe("phu_hop");
    expect(dg({ target: 100, duKien: 50, tieuChuan: 100 }).nhan).toBe("duoi_nang_luc");
    expect(dg({ target: 100, duKien: 100, tieuChuan: 200 }).nhan).toBe("du_dia");
  });

  it("splits the target gap into missing quota and unused quota", () => {
    const x = dg({ target: 10, duKien: 6, tieuChuan: 8 });
    expect(x.thieuQuota).toBe(2);
    expect(x.chuaKhaiThac).toBe(2);
  });

  it("treats a plan without quota as over quota", () => {
    expect(dg({ target: 0, duKien: 50, tieuChuan: 0 }).nhan).toBe("vuot_quota");
    expect(dg({ target: 100, duKien: 50, tieuChuan: 0 }).nhan).toBe("thieu_quota");
    expect(dg({ target: 0, duKien: 0, tieuChuan: 0 })).toBeNull();
  });

  it("flags back-loaded plans and low-confidence quota", () => {
    // TH YTD 40 trong 8 tháng = 5/tháng; còn 60 cho 4 tháng = 15/tháng > 1,3 × 5
    const x = dg({ target: 100, duKien: 100, tieuChuan: 100, thYtd: 40, quota14: 60 });
    expect(x.donCuoiNam).toBe(true);
    expect(x.tinCayThap).toBe(true);
    const y = dg({ target: 100, duKien: 100, tieuChuan: 100, thYtd: 70, quota14: 50 });
    expect(y.donCuoiNam).toBe(false);
    expect(y.tinCayThap).toBe(false);
  });
});

describe("congDg", () => {
  it("counts colours and sums gaps across levels", () => {
    const a = congDg(congDg(dgRong(), dg({ target: 10, duKien: 6, tieuChuan: 8 })), dg({ target: 10, duKien: 10, tieuChuan: 10 }));
    expect(a).toMatchObject({ do: 1, xanh: 1, thieuQuota: 2, chuaKhaiThac: 2 });
    const b = congDg(dgRong(), a);
    expect(b).toMatchObject({ do: 1, xanh: 1, chuaKhaiThac: 2 });
  });
});
