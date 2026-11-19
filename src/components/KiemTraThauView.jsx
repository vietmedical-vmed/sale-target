import { useState, useMemo, useContext, useEffect, useCallback, useRef } from 'react';
import { Clock, Download, Loader2, RefreshCw, AlertCircle, Search } from './icons.jsx';
import { CURRENT_MONTH, NO_MSET, TEAMS } from '../config/constants.js';
import { QuotaThauCtx, DotEditor, dotDuThongTin, QuotaThauModal } from './QuotaThau.jsx';
import { MultiSelect } from './MultiSelect.jsx';
import { sanPhamAmQuota } from '../lib/quota.js';
import { deaccent, custLabel } from '../lib/text.js';
import { fmtInt, moneyTy3 } from '../lib/format.js';
import { api } from '../api/client.js';
import {
  BUOC, TRANG_THAI, LOAI_DOT, NHOM_THEO, khoaDot, khoaXuLy, trangThaiCua,
  nhomLyDoAm, viecHopDong, tyLeKhopHopDong, gomNhom, banTruoc,
} from '../lib/kiemTraThau.js';
import { XuLyPill, XuLyModal, BangNhom, ChiTietKhoaModal, KqPill } from './KiemTraThauParts.jsx';

// Tab "Kiểm tra thông tin thầu" (admin + manager). 3 bước theo thứ tự phụ thuộc:
//  1. Đợt chính / bổ sung thiếu tháng thầu hoặc hiệu lực: quota không nhập thêm được.
//  2. SP trên Chi tiết kế hoạch có quota khả dụng âm (nhiều dòng là do bước 1).
//  3. Đối chiếu quota ↔ hợp đồng: khoá KH × SP chưa khớp, gom theo nguyên nhân.
// Mỗi việc có trạng thái xử lý (app_sale.kiem_tra_thau_xu_ly). Việc đang xử lý / bỏ qua mà
// không còn trong danh sách → app tự chuyển 'xong'. Mỗi lần mở tab, app ghi ảnh chụp số liệu
// của ngày (app_sale.kiem_tra_thau_snapshot) để thẻ bước hiện tăng / giảm so với lần trước.
// Ghi liên kết tay, ghép mã, gắn lại tự động: chỉ admin.

const LS_BUOC = 'kt_buoc';
const docLs = (k, d) => {
  try {
    return localStorage.getItem(k) || d;
  } catch {
    return d;
  }
};
const ghiLs = (k, v) => {
  try {
    localStorage.setItem(k, v);
  } catch {
    /* bỏ qua */
  }
};

export function KiemTraThauView({
  customers = [],
  rows = [],
  buRows = [],
  canEdit = false,
  isAdmin = false,
  viewBu = '',
  ganQuotaHd = null,
  xuatQuota = null,
}) {
  const ctx = useContext(QuotaThauCtx);
  const [buoc, setBuocRaw] = useState(() => {
    const v = docLs(LS_BUOC, 'dot');
    return BUOC.some((b) => b.id === v) ? v : 'dot';
  });
  const setBuoc = (v) => {
    setBuocRaw(v);
    ghiLs(LS_BUOC, v);
    setSelected(new Set());
  };
  const [psSel, setPsSel] = useState([]);
  const [grpSel, setGrpSel] = useState([]);
  const [ttLoc, setTtLoc] = useState('mo');
  const [search, setSearch] = useState('');
  const [nhomTheo, setNhomTheo] = useState({ dot: 'ps', am: 'nn', hd: 'nn' });
  const [selected, setSelected] = useState(() => new Set());
  const [loi, setLoi] = useState('');

  // ----- trạng thái xử lý + ảnh chụp -----
  const [xuLy, setXuLy] = useState(null); // Map khoaXuLy → bản ghi
  const [snapshot, setSnapshot] = useState([]);
  const [homNay, setHomNay] = useState('');
  const taiTrangThai = useCallback(() => {
    return api('ktGetTrangThai')
      .then((r) => {
        setXuLy(new Map((r.xuLy || []).map((x) => [khoaXuLy(x.buoc, x.khoa), x])));
        setSnapshot(r.snapshot || []);
        setHomNay(r.homNay || '');
      })
      .catch((e) => setLoi('Tải trạng thái xử lý thất bại: ' + e.message));
  }, []);
  useEffect(() => {
    taiTrangThai();
  }, [taiTrangThai]);

  // ----- đối chiếu quota ↔ HĐ (≈3 giây) -----
  const [hd, setHd] = useState({ rows: null, loading: false, loi: '', lanGan: null });
  const taiHd = useCallback(() => {
    setHd((p) => ({ ...p, loading: true, loi: '' }));
    return api('ktDoiChieuHopDong')
      .then((r) => setHd({ rows: r.rows || [], loading: false, loi: '', lanGan: r.lanGan || null }))
      .catch((e) => setHd((p) => ({ ...p, loading: false, loi: e.message })));
  }, []);
  useEffect(() => {
    taiHd();
  }, [taiHd]);

  // ----- gợi ý đợt theo HĐ -----
  const [goiY, setGoiY] = useState(() => new Map());
  useEffect(() => {
    api('ktGoiYDot')
      .then((r) => setGoiY(new Map((r.rows || []).map((g) => [khoaDot(g), g]))))
      .catch(() => {});
  }, []);

  // ----- BU của việc: theo nhóm SP, rồi theo PS, lấy từ dòng kế hoạch -----
  const buOf = useMemo(() => {
    const g = new Map();
    const p = new Map();
    for (const r of buRows) {
      if (!r.bu) continue;
      if (r.grp && !g.has(r.grp)) g.set(r.grp, r.bu);
      if (r.ps && !p.has(r.ps)) p.set(r.ps, r.bu);
    }
    return (ps, grp) => g.get(grp) || p.get(ps) || '';
  }, [buRows]);
  const tenKh = useMemo(
    () => new Map(customers.map((c) => [String(c.custId), custLabel(c.custId, c.cust)])),
    [customers],
  );
  const loaiBv = useMemo(
    () => new Map(customers.filter((c) => c.loaiBv).map((c) => [String(c.custId), c.loaiBv])),
    [customers],
  );
  const trongBu = useCallback(
    (it) => {
      if (!viewBu) return true;
      if (it.buList) return it.buList.includes(viewBu);
      return it.bu === viewBu;
    },
    [viewBu],
  );

  // ----- bước 1: đợt thiếu -----
  const giaTriDot = useMemo(() => {
    const m = new Map();
    if (!ctx) return m;
    for (const qs of ctx.quotasByProduct.values())
      for (const x of qs) {
        const k = khoaDot(x);
        m.set(k, (m.get(k) || 0) + Number(x.qty || 0) * Number(x.price || 0));
      }
    return m;
  }, [ctx]);
  const dotAll = useMemo(() => {
    if (!ctx) return [];
    const out = [];
    for (const ds of ctx.dotsByGroup.values())
      for (const d of ds) {
        if (dotDuThongTin(d)) continue;
        const k = khoaDot(d);
        const kh = tenKh.get(String(d.custId)) || d.custId;
        out.push({
          key: k,
          buoc: 'dot',
          ps: d.ps || '',
          custId: d.custId || '',
          tenKh: kh,
          grp: d.grp || '',
          bu: buOf(d.ps, d.grp),
          giaTri: giaTriDot.get(k) || 0,
          nn: LOAI_DOT[d.loai] || d.loai,
          moTa: `${d.ps} · ${kh} · ${d.grp} · ${LOAI_DOT[d.loai] || d.loai} đợt ${d.dot}`,
          d,
        });
      }
    return out;
  }, [ctx, tenKh, buOf, giaTriDot]);

  // ----- bước 2: SP quota âm -----
  const amAll = useMemo(() => {
    if (!ctx) return [];
    return sanPhamAmQuota(rows, ctx.dotsByGroup, ctx.quotasByProduct, CURRENT_MONTH).map((s) => {
      const kh = tenKh.get(String(s.custId)) || s.cust;
      return {
        key: s.key,
        buoc: 'am',
        ps: s.ps,
        custId: s.custId,
        tenKh: kh,
        grp: s.grp,
        bu: buOf(s.ps, s.grp),
        giaTri: s.thieuDt,
        nn: nhomLyDoAm(s.lyDo),
        moTa: `${s.ps} · ${kh} · ${s.prod} · giá ${fmtInt(s.price)} · KD ${fmtInt(s.khaDung)}`,
        s,
      };
    });
  }, [ctx, rows, tenKh, buOf]);
  // SL theo HĐ cho từng SP âm (1.4 còn lại đầu năm, ký trong năm).
  const [hdSp, setHdSp] = useState(() => new Map());
  const amSig = amAll.map((x) => x.key).join('\n');
  useEffect(() => {
    if (!amAll.length) return;
    const items = amAll.map((x, i) => ({
      i,
      kh: x.s.custId,
      ps: x.s.ps,
      nhom: x.s.grp,
      bvt: x.s.mset === NO_MSET ? '' : x.s.mset,
      sp: x.s.prod,
    }));
    let huy = false;
    api('ktHopDongTheoSanPham', { items })
      .then((r) => {
        if (huy) return;
        const m = new Map();
        for (const x of r.rows || []) if (amAll[x.i]) m.set(amAll[x.i].key, x);
        setHdSp(m);
      })
      .catch(() => {});
    return () => {
      huy = true;
    };
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [amSig]);

  // ----- bước 3: quota ↔ HĐ -----
  const hdAll = useMemo(() => (hd.rows ? viecHopDong(hd.rows) : []), [hd.rows]);
  const tyLe = useMemo(() => (hd.rows ? tyLeKhopHopDong(hd.rows, viewBu === 'test' ? '' : viewBu) : null), [hd.rows, viewBu]);

  const allByBuoc = useMemo(
    () => ({
      dot: dotAll.filter(trongBu),
      am: amAll.filter(trongBu),
      hd: viewBu === 'test' ? [] : hdAll.filter(trongBu),
    }),
    [dotAll, amAll, hdAll, trongBu, viewBu],
  );
  const recOf = (it) => (xuLy ? xuLy.get(khoaXuLy(it.buoc, it.key)) : null);

  // ----- tự đóng việc: đang xử lý / bỏ qua mà không còn trong danh sách → xong -----
  const daDong = useRef('');
  useEffect(() => {
    if (!xuLy || !ctx || !hd.rows || hd.loi || viewBu === 'test') return;
    const conLai = {
      dot: new Set(dotAll.map((x) => x.key)),
      am: new Set(amAll.map((x) => x.key)),
      hd: new Set(hdAll.map((x) => x.key)),
    };
    const dong = [];
    for (const rec of xuLy.values()) {
      if (rec.trang_thai === 'xong') continue;
      if (viewBu && rec.bu !== viewBu) continue; // bước 2 chỉ có dòng của BU đang xem
      if (!conLai[rec.buoc] || conLai[rec.buoc].has(rec.khoa)) continue;
      dong.push({
        buoc: rec.buoc,
        khoa: rec.khoa,
        bu: rec.bu,
        trangThai: 'xong',
        nguoiPhuTrach: rec.nguoi_phu_trach,
        ghiChu: rec.ghi_chu,
        moTa: rec.mo_ta,
      });
    }
    const sig = dong.map((x) => x.buoc + x.khoa).join('|');
    if (!dong.length || daDong.current === sig) return;
    daDong.current = sig;
    api('ktCapNhatXuLy', { items: dong, tuDong: true })
      .then(taiTrangThai)
      .catch(() => {});
  }, [xuLy, ctx, hd.rows, hd.loi, viewBu, dotAll, amAll, hdAll, taiTrangThai]);

  // ----- số liệu thẻ bước + ghi ảnh chụp trong ngày -----
  const soLieu = useMemo(() => {
    const out = {};
    for (const b of BUOC) {
      const list = allByBuoc[b.id];
      let mo = 0, dang = 0, boQua = 0, giaTri = 0;
      for (const it of list) {
        const tt = trangThaiCua(recOf(it));
        if (tt === 'bo_qua') boQua++;
        else {
          mo++;
          giaTri += it.giaTri || 0;
          if (tt === 'dang_xu_ly') dang++;
        }
      }
      out[b.id] = { tong: list.length, mo, dang, boQua, giaTri };
    }
    return out;
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [allByBuoc, xuLy]);
  const daChup = useRef('');
  useEffect(() => {
    if (!xuLy || !ctx || !hd.rows || hd.loi || viewBu === 'test') return;
    const sig = viewBu + '|' + BUOC.map((b) => `${soLieu[b.id].mo}:${Math.round(soLieu[b.id].giaTri)}`).join('|');
    if (daChup.current === sig) return;
    daChup.current = sig;
    api('ktLuuSnapshot', {
      bu: viewBu || '',
      items: BUOC.map((b) => ({
        buoc: b.id,
        soViec: soLieu[b.id].mo,
        giaTri: soLieu[b.id].giaTri,
        chiTiet: {
          tong: soLieu[b.id].tong,
          dang: soLieu[b.id].dang,
          boQua: soLieu[b.id].boQua,
          ...(b.id === 'hd' && tyLe ? { tyLeKhop: Math.round(tyLe.tyLe * 1000) / 1000 } : {}),
        },
      })),
    }).catch(() => {});
  }, [xuLy, ctx, hd.rows, hd.loi, viewBu, soLieu, tyLe]);

  // ----- lọc -----
  const list = allByBuoc[buoc];
  const q = deaccent(search.trim());
  const locNoTt = useMemo(
    () =>
      list.filter(
        (it) =>
          (!psSel.length || psSel.includes(it.ps)) &&
          (!grpSel.length || grpSel.includes(it.grp)) &&
          (!q ||
            deaccent(
              [it.ps, it.custId, it.tenKh, it.grp, it.moTa, it.nn, it.s ? it.s.prod : '', it.row ? it.row.khoa : '']
                .filter(Boolean)
                .join(' '),
            ).includes(q)),
      ),
    [list, psSel, grpSel, q],
  );
  const locDuoc = useMemo(() => {
    if (ttLoc === 'tat_ca') return locNoTt;
    return locNoTt.filter((it) => {
      const tt = trangThaiCua(recOf(it));
      return ttLoc === 'mo' ? tt !== 'bo_qua' : tt === ttLoc;
    });
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [locNoTt, ttLoc, xuLy]);
  const groups = useMemo(() => gomNhom(locDuoc, nhomTheo[buoc]), [locDuoc, nhomTheo, buoc]);
  const psOptions = useMemo(() => [...new Set(list.map((x) => x.ps).filter(Boolean))].sort((a, b) => a.localeCompare(b, 'vi')), [list]);
  const grpOptions = useMemo(() => [...new Set(list.map((x) => x.grp).filter(Boolean))].sort((a, b) => a.localeCompare(b, 'vi')), [list]);
  const daXong = useMemo(() => {
    if (!xuLy || ttLoc !== 'xong') return [];
    return [...xuLy.values()]
      .filter((r) => r.buoc === buoc && r.trang_thai === 'xong' && (!viewBu || r.bu === viewBu))
      .sort((a, b) => String(b.xong_luc).localeCompare(String(a.xong_luc)));
  }, [xuLy, ttLoc, buoc, viewBu]);

  // ----- cập nhật xử lý -----
  const [suaXuLy, setSuaXuLy] = useState(null); // [items]
  const luuXuLy = async (items, { trangThai, nguoiPhuTrach, ghiChu }) => {
    await api('ktCapNhatXuLy', {
      items: items.map((it) => ({
        buoc: it.buoc,
        khoa: it.key,
        bu: it.bu || '',
        trangThai,
        nguoiPhuTrach: nguoiPhuTrach || it.ps || '',
        ghiChu,
        moTa: it.moTa,
      })),
    });
    setSelected(new Set());
    await taiTrangThai();
  };
  const toggleSel = (keys, on) =>
    setSelected((p) => {
      const s = new Set(p);
      for (const k of keys) on ? s.add(k) : s.delete(k);
      return s;
    });
  const chonList = useMemo(() => locDuoc.filter((x) => selected.has(x.key)), [locDuoc, selected]);

  // ----- popup -----
  const [suaQuota, setSuaQuota] = useState(null);
  const [chiTiet, setChiTiet] = useState(null);
  const itemsNhom = (fy, ps, custId, grp) => {
    const m = new Map();
    for (const r of rows) {
      if (r.ps !== ps || String(r.custId) !== String(custId) || r.grp !== grp || r._oop) continue;
      if (fy && r.fy && r.fy !== fy) continue;
      const mset = r.mset || NO_MSET;
      const price = Number(r.price) || 0;
      const k = `${mset}||${r.prod}||${price}`;
      if (!m.has(k)) m.set(k, { mset, prod: r.prod || '—', price });
    }
    return [...m.values()];
  };
  const moSuaQuotaTuHd = (qLine) => {
    const fy = (rows.find((r) => r.fy) || {}).fy || 'FY26';
    setSuaQuota({
      fy,
      ps: qLine.ps,
      custId: chiTiet.custId,
      grpName: qLine.nhom,
      items: itemsNhom(fy, qLine.ps, chiTiet.custId, qLine.nhom),
      mset: NO_MSET,
      prod: qLine.sp,
      price: Number(qLine.donGia) || 0,
    });
  };

  const luuDot = async (d, thang, thoiGian) => {
    setLoi('');
    try {
      await ctx.saveDot([{ fy: d.fy, ps: d.ps, custId: d.custId, grp: d.grp, loai: d.loai, dot: d.dot, thang, thoiGian }]);
    } catch (e) {
      setLoi(`${d.ps} · ${d.custId} · ${d.grp}: ${e.message}`);
    }
  };
  const ganLai = async () => {
    if (!ganQuotaHd) return;
    await ganQuotaHd.onGan();
    taiHd();
  };

  if (!ctx) return null;
  const lanGan = hd.lanGan || ganQuotaHd?.lanCuoi;
  const td = 'px-3 py-1.5';
  const chk = (it) => (
    <td className={td}>
      <input type="checkbox" checked={selected.has(it.key)} onChange={() => toggleSel([it.key], !selected.has(it.key))} />
    </td>
  );
  const khCell = (it) => (
    <td className={td}>
      <div className="text-slate-800">{it.tenKh}</div>
      <div className="text-[10px] text-slate-400">{it.custId}</div>
    </td>
  );
  const xlCell = (it) => (
    <td className={`${td} whitespace-nowrap`}>
      <XuLyPill rec={recOf(it)} onClick={() => setSuaXuLy([it])} />
    </td>
  );

  // ----- cột + dòng theo bước -----
  let cols;
  let renderRow;
  let emptyText;
  if (buoc === 'dot') {
    cols = [
      { label: 'PS' },
      { label: 'Khách hàng' },
      { label: 'Nhóm SP' },
      { label: 'Loại' },
      { label: 'Tháng thầu · hiệu lực' },
      { label: 'Gợi ý theo HĐ' },
      { label: 'Giá trị thầu', cls: 'text-right' },
      { label: 'Xử lý' },
    ];
    emptyText = 'Mọi đợt đã đủ tháng thầu và hiệu lực';
    renderRow = (it) => {
      const d = it.d;
      const g = goiY.get(it.key);
      return (
        <tr key={it.key} className="border-b border-slate-100">
          {chk(it)}
          <td className={`${td} whitespace-nowrap text-slate-700`}>{d.ps}</td>
          {khCell(it)}
          <td className={`${td} text-slate-600`}>{d.grp}</td>
          <td className={`${td} whitespace-nowrap text-slate-600`}>
            {LOAI_DOT[d.loai] || d.loai} · đợt {d.dot}
          </td>
          <td className={td}>
            <DotEditor
              thang={d.thang}
              thoiGian={d.thoiGian}
              curMonth={CURRENT_MONTH}
              locked={!canEdit}
              onSave={(thang, thoiGian) => luuDot(d, thang, thoiGian)}
            />
          </td>
          <td className={`${td} whitespace-nowrap`}>
            {g ? (
              <div title={`HĐ ${g.soHd} · ký ${g.ngayKy} · hạn ${g.thoiHan || '—'} · khớp ${g.khop}/${g.tong} SP của đợt`}>
                {canEdit && g.hieuLuc ? (
                  <button
                    onClick={() => luuDot(d, g.thang, g.hieuLuc)}
                    className="px-2 py-0.5 text-[11px] font-semibold rounded border border-blue-200 text-blue-700 hover:bg-blue-50"
                  >
                    Điền {g.thang} · {g.hieuLuc} th
                  </button>
                ) : (
                  <span className="text-slate-600">
                    {g.thang}
                    {g.hieuLuc ? ` · ${g.hieuLuc} th` : ' · chưa rõ hạn'}
                  </span>
                )}
                <div className="text-[10px] text-slate-400">
                  {g.soHd} · {g.khop}/{g.tong} SP
                </div>
              </div>
            ) : (
              <span className="text-slate-300">—</span>
            )}
          </td>
          <td className={`${td} text-right tabular-nums text-slate-700`}>{fmtInt(it.giaTri)}</td>
          {xlCell(it)}
        </tr>
      );
    };
  } else if (buoc === 'am') {
    cols = [
      { label: 'PS' },
      { label: 'Khách hàng' },
      { label: 'Loại BV' },
      { label: 'Nhóm SP' },
      { label: 'Sản phẩm' },
      { label: 'Đơn giá', cls: 'text-right' },
      { label: 'Quota on hand', cls: 'text-right' },
      { label: 'SL TH YTD', cls: 'text-right' },
      { label: 'Quota khả dụng', cls: 'text-right' },
      { label: 'Giá trị QKD', cls: 'text-right' },
      { label: 'SL theo HĐ', cls: 'text-right' },
      { label: 'Gợi ý' },
      { label: 'Xử lý' },
      { label: '' },
    ];
    emptyText = 'Không có sản phẩm nào âm quota khả dụng';
    renderRow = (it) => {
      const s = it.s;
      const h = hdSp.get(it.key);
      const h14 = h && h.h14 != null ? Number(h.h14) : null;
      const hFy = h && h.hFy != null ? Number(h.hFy) : null;
      return (
        <tr key={it.key} className="border-b border-slate-100">
          {chk(it)}
          <td className={`${td} whitespace-nowrap text-slate-700`}>{s.ps}</td>
          {khCell(it)}
          <td className={`${td} whitespace-nowrap text-slate-600`}>{loaiBv.get(String(s.custId)) || '—'}</td>
          <td className={`${td} text-slate-600`}>{s.grp}</td>
          <td className={td}>
            <div className="text-slate-800">{s.prod}</div>
            {s.mset !== NO_MSET && <div className="text-[10px] text-slate-400">{s.mset}</div>}
          </td>
          <td className={`${td} text-right tabular-nums text-slate-700`}>{fmtInt(s.price)}</td>
          <td className={`${td} text-right tabular-nums text-slate-700`}>{fmtInt(s.onHand)}</td>
          <td className={`${td} text-right tabular-nums text-slate-700`}>{fmtInt(s.ytd)}</td>
          <td className={`${td} text-right tabular-nums font-semibold text-red-600`}>{fmtInt(s.khaDung)}</td>
          <td className={`${td} text-right tabular-nums font-semibold text-red-600`}>{fmtInt(s.khaDung * s.price)}</td>
          <td
            className={`${td} text-right tabular-nums whitespace-nowrap`}
            title={
              !h
                ? 'Đang tải'
                : !h.khoa
                  ? 'Chưa map được mã SP sang khoá hợp đồng'
                  : `Khoá ${h.khoa}${h.soHd ? '\nHĐ: ' + h.soHd : ''}\nQuota on hand nên ≈ 1.4 còn lại + ký trong năm`
            }
          >
            {!h ? (
              <span className="text-slate-300">…</span>
            ) : !h.khoa ? (
              <span className="text-slate-300">chưa map</span>
            ) : h14 == null && hFy == null ? (
              <span className="text-slate-400">0</span>
            ) : (
              <span className="text-slate-700">
                {h14 != null && <span>1.4: {fmtInt(h14)}</span>}
                {h14 != null && hFy != null && ' · '}
                {hFy != null && <span>Năm: {fmtInt(hFy)}</span>}
              </span>
            )}
          </td>
          <td className={`${td} text-slate-500 max-w-[280px]`}>{s.lyDo}</td>
          {xlCell(it)}
          <td className={`${td} text-right whitespace-nowrap`}>
            <button
              className="px-2 py-1 text-[11px] font-semibold rounded border border-blue-200 text-blue-700 bg-white hover:bg-blue-50"
              onClick={() =>
                setSuaQuota({ fy: s.fy, ps: s.ps, custId: s.custId, grpName: s.grpName, items: s.items, mset: s.mset, prod: s.prod, price: s.price })
              }
            >
              {canEdit ? 'Sửa quota' : 'Xem quota'}
            </button>
          </td>
        </tr>
      );
    };
  } else {
    cols = [
      { label: 'Khách hàng' },
      { label: 'Sản phẩm' },
      { label: 'PS' },
      { label: 'Cửa sổ' },
      { label: 'Kết quả' },
      { label: 'SL quota', cls: 'text-right' },
      { label: 'SL HĐ', cls: 'text-right' },
      { label: 'Chênh (tiền)', cls: 'text-right' },
      { label: 'Nguyên nhân' },
      { label: 'Xử lý' },
      { label: '' },
    ];
    emptyText = hd.loading ? 'Đang tải đối chiếu…' : hd.loi ? 'Không tải được đối chiếu' : 'Mọi khoá đã khớp hợp đồng';
    renderRow = (it) => {
      const r = it.row;
      return (
        <tr key={it.key} className="border-b border-slate-100">
          {chk(it)}
          {khCell(it)}
          <td className={td}>
            <div className="text-slate-800">{r.tenSp || r.khoa}</div>
            <div className="text-[10px] text-slate-400">
              {r.maSp || '—'} · {it.grp}
            </div>
          </td>
          <td className={`${td} text-slate-600`} title={`PS quota: ${r.psQ || '—'}\nPS trên HĐ: ${r.psH || '—'}`}>
            {it.ps || '—'}
          </td>
          <td className={`${td} whitespace-nowrap text-slate-600`}>{it.cuaSoLabel}</td>
          <td className={td}>
            <KqPill kq={it.kq} />
          </td>
          <td className={`${td} text-right tabular-nums text-slate-700`}>{fmtInt(it.slQ)}</td>
          <td className={`${td} text-right tabular-nums text-slate-700`} title={it.soHd || ''}>
            {fmtInt(it.slH)}
          </td>
          <td className={`${td} text-right tabular-nums text-slate-700`}>{moneyTy3(it.giaTri)}</td>
          <td className={`${td} text-slate-500 max-w-[300px]`} title={r.canhBao || ''}>
            {it.nnChiTiet}
          </td>
          {xlCell(it)}
          <td className={`${td} text-right whitespace-nowrap`}>
            <button
              onClick={() => setChiTiet(it)}
              className="px-2 py-1 text-[11px] font-semibold rounded border border-blue-200 text-blue-700 bg-white hover:bg-blue-50"
            >
              Chi tiết
            </button>
          </td>
        </tr>
      );
    };
  }

  const theNho = (b) => {
    const sl = soLieu[b.id];
    const truoc = homNay ? banTruoc(snapshot, viewBu === 'test' ? 'test' : viewBu || '', b.id, homNay) : null;
    const delta = truoc ? sl.mo - truoc.so_viec : null;
    const dangTai = b.id === 'hd' && !hd.rows;
    const on = buoc === b.id;
    return (
      <button
        key={b.id}
        type="button"
        onClick={() => setBuoc(b.id)}
        className={`text-left bg-white rounded-xl p-3.5 border transition-colors ${on ? 'border-emerald-500 ring-2 ring-emerald-100' : 'border-slate-200 hover:border-slate-300'}`}
      >
        <div className="text-[11px] text-slate-400 tracking-wide">
          Bước {BUOC.indexOf(b) + 1} · {b.label}
        </div>
        <div className="flex items-baseline gap-2 mt-1">
          <span className="text-[22px] font-bold text-slate-800 tabular-nums">
            {dangTai ? <Loader2 size={18} className="animate-spin text-slate-400" /> : sl.mo.toLocaleString('en-US')}
          </span>
          <span className="text-[12px] text-slate-500">
            {b.id === 'dot' ? 'đợt' : b.id === 'am' ? 'SP' : 'khoá'} cần xử lý
          </span>
          {delta != null && delta !== 0 && (
            <span
              className={`text-[11px] font-medium tabular-nums ${delta < 0 ? 'text-emerald-600' : 'text-red-600'}`}
              title={`So với ${truoc.ngay}: ${fmtInt(truoc.so_viec)} việc · ${moneyTy3(Number(truoc.gia_tri))}`}
            >
              {delta > 0 ? '+' : '−'}
              {fmtInt(Math.abs(delta))} so với {truoc.ngay.slice(8, 10)}/{truoc.ngay.slice(5, 7)}
            </span>
          )}
        </div>
        <div className="text-[12px] text-slate-500 mt-0.5">
          {b.id === 'am' ? 'Thiếu ' : b.id === 'hd' ? 'Chênh ' : 'Giá trị '}
          {moneyTy3(sl.giaTri)}
          {sl.dang > 0 && ` · đang xử lý ${fmtInt(sl.dang)}`}
          {sl.boQua > 0 && ` · bỏ qua ${fmtInt(sl.boQua)}`}
        </div>
        {b.id === 'hd' ? (
          tyLe ? (
            <div className="mt-2">
              <div className="h-1.5 bg-slate-100 rounded overflow-hidden">
                <div className="h-full bg-emerald-500 rounded" style={{ width: Math.round(tyLe.tyLe * 100) + '%' }} />
              </div>
              <div className="text-[11px] text-slate-400 mt-1">
                Quota on hand khớp HĐ {Math.round(tyLe.tyLe * 100)}% ({moneyTy3(tyLe.khop)} / {moneyTy3(tyLe.tong)})
              </div>
            </div>
          ) : (
            <div className="text-[11px] text-slate-400 mt-2">{hd.loi ? 'Lỗi tải đối chiếu' : 'Đang đối chiếu…'}</div>
          )
        ) : (
          <div className="text-[11px] text-slate-400 mt-2">
            {b.id === 'dot'
              ? 'Chặn bước sau: quota của đợt tính Upcoming, không nhập thêm được'
              : `${allByBuoc.am.filter((x) => x.nn === nhomLyDoAm('Còn ')).length} SP do đợt chưa tới tháng thầu / thiếu thông tin`}
          </div>
        )}
      </button>
    );
  };

  const sel = 'px-2 py-1.5 text-[13px] border border-slate-200 rounded-md bg-white outline-none focus:border-emerald-500';
  return (
    <div className="p-6 space-y-4">
      <div className="flex items-center justify-between flex-wrap gap-3">
        <div className="flex items-center gap-3">
          <Clock size={20} className="text-emerald-600" />
          <h2 className="text-lg font-bold text-slate-800">Kiểm tra thông tin thầu</h2>
          {viewBu && TEAMS[viewBu] && <span className="text-[12px] text-slate-500">· {TEAMS[viewBu].label}</span>}
        </div>
        <div className="flex items-center gap-2 flex-wrap">
          {lanGan && lanGan.luc && (
            <span className="text-[11px] text-slate-400" title={`${lanGan.them || 0} liên kết · ${lanGan.nguoi || ''}`}>
              Gắn HĐ lần cuối {new Date(lanGan.luc).toLocaleString('vi-VN')}
            </span>
          )}
          {xuatQuota && (
            <button
              onClick={xuatQuota.onXuat}
              disabled={xuatQuota.busy}
              title="Xuất quota thầu toàn bộ (đợt thầu mới + cột cũ), kèm On hand / Upcoming và cảnh báo quota lệch kế hoạch"
              className="inline-flex items-center gap-1.5 px-2.5 py-1.5 text-[13px] font-medium text-emerald-700 bg-white border border-emerald-200 rounded-md hover:bg-emerald-50 disabled:opacity-60"
            >
              {xuatQuota.busy ? <Loader2 size={14} className="animate-spin" /> : <Download size={14} />}
              Xuất quota thầu
            </button>
          )}
          {ganQuotaHd && (
            <button
              onClick={ganLai}
              disabled={ganQuotaHd.busy}
              title="Gắn lại liên kết quota ↔ hợp đồng cho các khoá KH × SP đã khớp (tự chạy 01:30 mỗi đêm), rồi tải lại đối chiếu"
              className="inline-flex items-center gap-1.5 px-2.5 py-1.5 text-[13px] font-medium text-emerald-700 bg-white border border-emerald-200 rounded-md hover:bg-emerald-50 disabled:opacity-60"
            >
              {ganQuotaHd.busy ? <Loader2 size={14} className="animate-spin" /> : <RefreshCw size={14} />}
              Gắn quota ↔ HĐ
            </button>
          )}
          <button
            onClick={() => {
              taiHd();
              taiTrangThai();
            }}
            disabled={hd.loading}
            title="Tải lại đối chiếu hợp đồng và trạng thái xử lý"
            className="inline-flex items-center gap-1.5 px-2.5 py-1.5 text-[13px] text-slate-700 bg-white border border-slate-200 rounded-md hover:bg-slate-50 disabled:opacity-60"
          >
            {hd.loading ? <Loader2 size={14} className="animate-spin" /> : <RefreshCw size={14} />}
            Tải lại
          </button>
        </div>
      </div>

      <div className="grid grid-cols-1 md:grid-cols-3 gap-2">{BUOC.map(theNho)}</div>

      <div className="flex items-center gap-2 flex-wrap">
        <MultiSelect label="PS" searchable options={psOptions.map((p) => ({ value: p, label: p }))} selected={psSel} onChange={setPsSel} />
        <MultiSelect label="Nhóm SP" searchable options={grpOptions.map((p) => ({ value: p, label: p }))} selected={grpSel} onChange={setGrpSel} />
        <label className="flex items-center gap-1 text-[13px] text-slate-400">
          Trạng thái:
          <select value={ttLoc} onChange={(e) => setTtLoc(e.target.value)} className={sel}>
            <option value="mo">Cần xử lý (chưa + đang)</option>
            <option value="chua">{TRANG_THAI.chua.label}</option>
            <option value="dang_xu_ly">{TRANG_THAI.dang_xu_ly.label}</option>
            <option value="bo_qua">{TRANG_THAI.bo_qua.label}</option>
            <option value="xong">{TRANG_THAI.xong.label} (60 ngày)</option>
            <option value="tat_ca">Tất cả</option>
          </select>
        </label>
        {ttLoc !== 'xong' && (
          <label className="flex items-center gap-1 text-[13px] text-slate-400">
            Gom theo:
            <select value={nhomTheo[buoc]} onChange={(e) => setNhomTheo((p) => ({ ...p, [buoc]: e.target.value }))} className={sel}>
              {NHOM_THEO.map((o) => (
                <option key={o.id} value={o.id}>
                  {o.id === 'nn' && buoc === 'dot' ? 'Loại thầu' : o.label}
                </option>
              ))}
            </select>
          </label>
        )}
        <div className="relative">
          <Search size={14} className="absolute left-2.5 top-1/2 -translate-y-1/2 text-slate-400" />
          <input
            value={search}
            onChange={(e) => setSearch(e.target.value)}
            placeholder="Tìm KH, SP, mã, nguyên nhân…"
            className="pl-8 pr-3 py-1.5 text-[13px] border border-slate-200 rounded-md w-64 outline-none focus:border-emerald-500 focus:ring-2 focus:ring-emerald-100"
          />
        </div>
        <div className="flex-1" />
        <span className="text-[12px] text-slate-400 tabular-nums">
          {ttLoc === 'xong' ? fmtInt(daXong.length) : fmtInt(locDuoc.length)} việc
          {ttLoc !== 'xong' && ' · ' + moneyTy3(locDuoc.reduce((s, x) => s + (x.giaTri || 0), 0))}
        </span>
      </div>

      {loi && (
        <div className="flex items-center gap-1.5 text-[12px] text-red-600">
          <AlertCircle size={13} /> {loi}
        </div>
      )}
      {buoc === 'hd' && hd.loi && (
        <div className="flex items-center gap-1.5 text-[12px] text-red-600">
          <AlertCircle size={13} /> Tải đối chiếu hợp đồng thất bại: {hd.loi}
        </div>
      )}
      {buoc === 'hd' && viewBu === 'test' && (
        <div className="text-[12px] text-slate-500">Đối chiếu hợp đồng không áp dụng cho dữ liệu test.</div>
      )}

      {chonList.length > 0 && ttLoc !== 'xong' && (
        <div className="flex items-center gap-2 flex-wrap px-3 py-2 rounded-lg bg-emerald-50 border border-emerald-200 text-[12px]">
          <span className="font-medium text-emerald-800">Đã chọn {fmtInt(chonList.length)} việc</span>
          <button onClick={() => setSuaXuLy(chonList)} className="px-2.5 py-1 rounded-md bg-white border border-emerald-300 text-emerald-700 hover:bg-emerald-100">
            Cập nhật xử lý…
          </button>
          <button onClick={() => setSelected(new Set())} className="px-2 py-1 text-slate-500 hover:text-slate-800">
            Bỏ chọn
          </button>
        </div>
      )}

      {ttLoc === 'xong' ? (
        <div className="bg-white rounded-lg border border-slate-200 overflow-x-auto">
          <table className="w-full text-[12px]">
            <thead>
              <tr className="bg-slate-50 border-b border-slate-200 text-left">
                <th className="px-3 py-2 font-semibold text-slate-600">Việc</th>
                <th className="px-3 py-2 font-semibold text-slate-600">Phụ trách</th>
                <th className="px-3 py-2 font-semibold text-slate-600">Ghi chú</th>
                <th className="px-3 py-2 font-semibold text-slate-600">Xong lúc</th>
              </tr>
            </thead>
            <tbody>
              {daXong.length === 0 ? (
                <tr>
                  <td colSpan={4} className="px-3 py-8 text-center text-slate-400">
                    Chưa có việc nào được ghi nhận xong trong 60 ngày
                  </td>
                </tr>
              ) : (
                daXong.map((r) => (
                  <tr key={r.khoa} className="border-b border-slate-100">
                    <td className="px-3 py-1.5 text-slate-700">{r.mo_ta || r.khoa}</td>
                    <td className="px-3 py-1.5 text-slate-600">{r.nguoi_phu_trach || '—'}</td>
                    <td className="px-3 py-1.5 text-slate-500">{r.ghi_chu || '—'}</td>
                    <td className="px-3 py-1.5 text-slate-500 whitespace-nowrap">
                      {r.xong_luc ? new Date(r.xong_luc).toLocaleString('vi-VN') : '—'}
                    </td>
                  </tr>
                ))
              )}
            </tbody>
          </table>
        </div>
      ) : (
        <BangNhom
          groups={groups}
          cols={cols}
          renderRow={renderRow}
          selected={selected}
          onToggleAll={toggleSel}
          emptyText={emptyText}
        />
      )}

      {suaXuLy && (
        <XuLyModal
          items={suaXuLy}
          rec={suaXuLy.length === 1 ? recOf(suaXuLy[0]) : null}
          psOptions={psOptions}
          onSave={(v) => luuXuLy(suaXuLy, v)}
          onClose={() => setSuaXuLy(null)}
        />
      )}
      {chiTiet && (
        <ChiTietKhoaModal
          viec={chiTiet}
          hdRows={hd.rows || []}
          isAdmin={isAdmin}
          canEdit={canEdit}
          onClose={() => setChiTiet(null)}
          onDaDoi={(dong) => {
            taiHd();
            if (dong) setChiTiet(null);
          }}
          onSuaQuota={moSuaQuotaTuHd}
        />
      )}
      {suaQuota && (
        <QuotaThauModal
          fy={suaQuota.fy}
          ps={suaQuota.ps}
          custId={suaQuota.custId}
          grp={suaQuota.grpName}
          items={suaQuota.items}
          focus={{ mset: suaQuota.mset, prod: suaQuota.prod, price: suaQuota.price }}
          locked={!canEdit}
          onClose={() => setSuaQuota(null)}
        />
      )}
    </div>
  );
}
