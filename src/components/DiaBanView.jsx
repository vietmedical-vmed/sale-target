import React, { useState, useEffect, useMemo, useRef } from 'react';
import { Check, ChevronDown, ChevronRight, Loader2, Plus, RefreshCw, Search, Settings, Trash2, XIcon } from './icons.jsx';
import { CURRENT_MONTH, MONTHS, MONTH_LABELS } from '../config/constants.js';
import { fmtInt } from '../lib/format.js';
import { custLabel, deaccent, fmtCust, inSel } from '../lib/text.js';
import { api } from '../api/client.js';
import { CustomerPicker } from './CustomerPicker.jsx';
import { Modal } from './Modal.jsx';

// ============ CẤU HÌNH ĐỊA BÀN (Khách hàng × Ngành hàng → PS, có thời gian hiệu lực) ============
// dm_dia_ban khai báo ai phụ trách ngành hàng nào của khách hàng nào, VÀ TỪ THÁNG
// NÀO ĐẾN THÁNG NÀO. Đổi người phụ trách giữa năm KHÔNG sửa bản cũ mà "Chuyển PS":
// đóng bản cũ ở tháng liền trước + mở bản mới → tháng cũ vĩnh viễn thuộc PS cũ, dù
// sau đó cấu hình đổi bao nhiêu lần.
//
// Kế hoạch KHÔNG tự đổi theo khai báo: phải bấm "Áp dụng", và mỗi bản chỉ ghi vào
// các tháng nó phủ nên bản mới không bao giờ ghi đè tháng đã qua (khoá khớp actual
// tháng|PS|maKH|bộVT|SP của quá khứ được giữ nguyên).
//
// Ràng buộc: tổ hợp (KH × ngành hàng) ĐÃ khai báo thì MỌI tháng đang có dòng kế
// hoạch phải được một bản nào đó phủ. Thiếu tháng = "khoảng trống" → backend chặn
// lưu; màn hình cảnh báo ngay tại chỗ để không phải thử rồi mới biết.
const MAX_DIA_BAN_ROWS = 500; // bảng phẳng (không gập nhóm như màn chi tiết) → phải có trần
const MO_ALL = 'all'; // giá trị ô "Xem theo tháng" = xem cả lịch sử

// Khoá đối chiếu khách hàng giữa dm_dia_ban và sale_target: ưu tiên mã KH, rỗng
// thì rơi về tên GỐC trong DB (cust đã fmtCust không dùng được để so khớp).
// Phải khớp đúng cột sinh cust_key của dm_dia_ban.
export const dbCustKey = (custId, cust) =>
  String(custId || '').trim() || String(cust || '').trim();
// '2026-07' -> 'T7/26'
const fmtMo = (mo) => {
  if (!mo) return '';
  const p = String(mo).split('-');
  return p.length < 2 ? String(mo) : 'T' + Number(p[1]) + '/' + p[0].slice(2);
};
const fmtHieuLuc = (tu, den) =>
  (tu ? fmtMo(tu) : fmtMo(MONTHS[0])) + ' → ' + (den ? fmtMo(den) : 'nay');
// Bản khai báo có phủ tháng mo không (tu rỗng = từ đầu năm, den rỗng = còn hiệu lực)
const phuThang = (v, mo) =>
  (!v.tuThang || v.tuThang <= mo) && (!v.denThang || v.denThang >= mo);
// Tháng đang có kế hoạch mà không bản nào phủ. versions rỗng = chưa khai báo gì →
// KHÔNG tính là khoảng trống (đó là mục "chưa khai báo", backend cũng bỏ qua).
export const khoangTrong = (planMonths, versions) => {
  if (
    !planMonths ||
    planMonths.size === 0 ||
    !versions ||
    versions.length === 0
  )
    return [];
  return MONTHS.filter(
    (mo) => planMonths.has(mo) && !versions.some((v) => phuThang(v, mo)),
  );
};

// Dịch lỗi backend địa bàn sang câu cho người cấu hình. Loại có CHI TIẾT (thiếu
// tháng nào, tháng nào không hợp lệ) được backend trả nguyên văn kèm dữ liệu cụ thể
// → chỉ bỏ tiền tố mã lỗi, giữ nguyên phần nội dung.
export const diaBanErrMsg = (m) => {
  const s = String(m || '');
  if (s === 'dup_dia_ban')
    return 'địa bàn này đã được khai báo cho PS đó từ cùng một tháng.';
  if (s === 'forbidden') return 'chỉ admin được sửa cấu hình địa bàn.';
  if (s === 'forbidden_rows') return 'có dòng ngoài phạm vi quyền của bạn.';
  if (s === 'thieu_du_lieu') return 'thiếu khách hàng / ngành hàng / PS.';
  if (s === 'khong_ton_tai')
    return 'bản khai báo này không còn tồn tại — hãy tải lại.';
  if (s.startsWith('khoang_trong:')) {
    return (
      'sẽ có tháng không ai phụ trách — ' +
      s.slice('khoang_trong:'.length).trim()
    );
  }
  const i = s.indexOf(':');
  if (i > 0 && /^[a-z_]+$/.test(s.slice(0, i))) return s.slice(i + 1).trim();
  return s;
};

// mienByPs: PS -> Miền (suy từ dữ liệu kế hoạch, chỉ khi PS đó thuộc đúng 1 miền).
// Miền KHÔNG phải trường nhập tay: nó là thuộc tính của PS, chọn tay chỉ tạo cơ hội
// gán lệch miền cho cùng một PS. Backend cũng tự suy lại khi lưu, không tin client.
export function DiaBanView({
  rows,
  diaBan,
  customers,
  psOptions,
  mienByPs,
  psKnown,
  groupOptions,
  canEdit,
  psFilter,
  regionFilter,
  groupFilter,
  custFilter,
  onSave,
  onDelete,
  onDopChongLan,
  busy,
  prefill,
  onPrefillDone,
  viewBu,
  onToolbar,
  curMonth,
  isAdmin,
  onMonthChange,
}) {
  // PS lạ = có trong kế hoạch/khai báo nhưng KHÔNG có trong danh mục dm_ps.
  // psKnown rỗng (chưa tải được danh mục) → không kiểm tra, tránh báo động nhầm.
  const psLa = (ps) =>
    psKnown &&
    psKnown.size > 0 &&
    !psKnown.has(
      String(ps || '')
        .trim()
        .toLowerCase(),
    );
  // Lọc diaBan theo team đang xem (viewBu). Không lọc khi xem tất cả hoặc test.
  const filteredDiaBan = useMemo(
    () =>
      viewBu && viewBu !== 'test'
        ? diaBan.filter((d) => d.bu === viewBu)
        : diaBan,
    [diaBan, viewBu],
  );
  // Từ 2026-08-07: bỏ chia theo tháng. Cấu hình áp cho cả năm, save = auto apply.
  // Các state theo tháng (viewMo/move) đã gỡ; nRow không còn tu_thang (backend
  // tự set '2026-04' khi insert).
  const [edits, setEdits] = useState({}); // { id: ps } — PS đã đổi, chưa lưu
  const [search, setSearch] = useState('');
  const [showMissing, setShowMissing] = useState(false);
  const [closed, setClosed] = useState(() => new Set()); // KH đang gập
  const [closedRegions, setClosedRegions] = useState(() => new Set()); // miền đang gập
  // Modal "Thêm địa bàn" — cho thêm NHIỀU dòng trong 1 lượt lưu. Nút "+ Thêm dòng"
  // thêm ô mới; Xác nhận gửi toàn bộ danh sách vào onSave (backend auto-apply cả
  // năm cho tất cả tổ hợp không chồng lấn).
  const [addOpen, setAddOpen] = useState(false);
  const emptyAddRow = { custKey: '', grp: '', ps: '' };
  const [addRows, setAddRows] = useState([emptyAddRow]);
  // Ref để scroll dòng khai báo cần chú ý (prefill purpose='chuyen') vào tầm nhìn.
  const highlightRef = useRef(null);

  // Prefill từ modal OOP:
  //  purpose='add'    → mở modal Thêm địa bàn với 1 dòng điền sẵn (KH + grp).
  //  purpose='chuyen' → tìm KH đó trong bảng, mở nhóm KH đó, scroll + highlight.
  useEffect(() => {
    if (!prefill) return;
    if (prefill.purpose === 'chuyen') {
      setSearch(prefill.custId || '');
      const custKey = dbCustKey(prefill.custId, prefill.cust);
      setClosed((prev) => {
        if (!prev.has(custKey)) return prev;
        const next = new Set(prev);
        next.delete(custKey);
        return next;
      });
      setTimeout(() => {
        const el = highlightRef.current;
        if (el && el.scrollIntoView)
          el.scrollIntoView({ behavior: 'smooth', block: 'center' });
      }, 100);
    } else {
      // 'add' hoặc mặc định — mở modal Thêm địa bàn với 1 dòng điền sẵn
      setAddRows([
        {
          custKey: prefill.custId || prefill.cust || '',
          grp: prefill.grp || '',
          ps: '',
        },
      ]);
      setAddOpen(true);
    }
    if (onPrefillDone) onPrefillDone();
  }, [prefill]);

  // (Khách hàng × ngành hàng) -> PS đang THẬT SỰ có dòng kế hoạch, TÁCH THEO THÁNG
  // (khai báo có khoảng hiệu lực nên đối chiếu cũng phải theo tháng).
  const planIdx = useMemo(() => {
    const m = new Map();
    rows.forEach((r) => {
      if (!r.grp || !r.ps || !r.mo) return;
      const k = dbCustKey(r.custId, r.custRaw || r.cust);
      if (!k) return;
      const mk = k + '||' + r.grp;
      let e = m.get(mk);
      if (!e) {
        e = {
          custId: r.custId || '',
          cust: r.custRaw || r.cust,
          grp: r.grp,
          mien: r.region || '',
          psByMonth: new Map(),
          months: new Set(),
        };
        m.set(mk, e);
      }
      e.months.add(r.mo);
      let s = e.psByMonth.get(r.mo);
      if (!s) {
        s = new Set();
        e.psByMonth.set(r.mo, s);
      }
      s.add(r.ps);
    });
    return m;
  }, [rows]);

  // Mọi bản khai báo của một tổ hợp (KHÔNG lọc theo tháng đang xem) — dùng để tính
  // khoảng trống và để biết tổ hợp đã khai báo hay chưa.
  const cfgByPair = useMemo(() => {
    const m = new Map();
    filteredDiaBan.forEach((d) => {
      const k = dbCustKey(d.custId, d.cust) + '||' + d.grp;
      let a = m.get(k);
      if (!a) {
        a = [];
        m.set(k, a);
      }
      a.push(d);
    });
    return m;
  }, [filteredDiaBan]);

  // Có kế hoạch nhưng CHƯA khai báo địa bàn. Suy khai báo theo TỪNG KHOẢNG THÁNG
  // LIÊN TIẾP của mỗi PS trong kế hoạch → khai báo lại đúng lịch sử, không tạo
  // khoảng trống và không tạo chồng lấn vô cớ.
  const missing = useMemo(() => {
    // Bỏ khoảng thời gian: mỗi (tổ hợp × PS) chỉ cần 1 dòng khai báo cho cả năm.
    // Tổ hợp có nhiều PS trong kế hoạch → mỗi PS 1 dòng (khai báo → ambiguous,
    // user tự dọn).
    const out = [];
    planIdx.forEach((e, pairKey) => {
      if (cfgByPair.has(pairKey)) return;
      const psSet = new Set();
      e.psByMonth.forEach((s) => s.forEach((p) => psSet.add(p)));
      psSet.forEach((ps) =>
        out.push({ custId: e.custId, cust: e.cust, grp: e.grp, ps }),
      );
    });
    return out.sort(
      (a, b) =>
        (a.cust || '').localeCompare(b.cust || '') ||
        a.grp.localeCompare(b.grp) ||
        a.ps.localeCompare(b.ps),
    );
  }, [planIdx, cfgByPair]);

  // Danh sách hiển thị: mọi bản khai báo qua bộ lọc chung + ô tìm kiếm, kèm
  // trạng thái đối chiếu kế hoạch. Bỏ chia theo tháng: đối chiếu trên TOÀN BỘ
  // tháng của tổ hợp (không giới hạn theo tu_thang/den_thang của bản).
  const list = useMemo(() => {
    const q = deaccent(search.trim());
    const out = [];
    for (const d of filteredDiaBan) {
      const ps = edits[d.id] || d.ps;
      const mien = mienByPs.get(ps) || d.mien || '';
      if (!inSel(regionFilter, mien)) continue;
      if (!inSel(psFilter, ps)) continue;
      if (!inSel(groupFilter, d.grp)) continue;
      if (!inSel(custFilter, custLabel(d.custId, d.cust))) continue;
      if (
        q &&
        !(
          deaccent(d.cust).includes(q) ||
          deaccent(custLabel(d.custId, d.cust)).includes(q) ||
          deaccent(d.custId).includes(q) ||
          deaccent(ps).includes(q) ||
          deaccent(d.grp).includes(q)
        )
      )
        continue;
      const plan = planIdx.get(dbCustKey(d.custId, d.cust) + '||' + d.grp);
      let status = 'noplan',
        planPs = [];
      if (plan) {
        const inAll = new Set();
        plan.psByMonth.forEach((s) => s.forEach((p) => inAll.add(p)));
        if (inAll.size === 0) status = 'noplan';
        else if (inAll.size === 1 && inAll.has(ps)) status = 'ok';
        else {
          status = 'diff';
          planPs = Array.from(inAll).filter((p) => p !== ps);
          if (!planPs.length) planPs = Array.from(inAll);
        }
      }
      out.push({ ...d, ps, mien, status, planPs });
    }
    return out;
  }, [
    filteredDiaBan,
    edits,
    mienByPs,
    planIdx,
    search,
    psFilter,
    regionFilter,
    groupFilter,
    custFilter,
  ]);

  // Gom theo KHÁCH HÀNG: 1 KH thường có nhiều ngành hàng (và có thể khác PS mỗi
  // ngành) → xem theo nhóm dễ soát hơn bảng phẳng lặp tên KH ở mọi dòng.
  const groups = useMemo(() => {
    const m = new Map();
    for (const d of list) {
      const k = dbCustKey(d.custId, d.cust);
      let g = m.get(k);
      if (!g) {
        g = {
          key: k,
          custId: d.custId,
          cust: d.cust,
          rows: [],
          diff: 0,
          gaps: [],
        };
        m.set(k, g);
      }
      g.rows.push(d);
      if (d.status === 'diff') g.diff++;
    }
    const arr = Array.from(m.values());
    arr.forEach((g) => {
      g.rows.sort(
        (a, b) => a.grp.localeCompare(b.grp) || a.ps.localeCompare(b.ps),
      );
    });
    arr.sort((a, b) =>
      custLabel(a.custId, a.cust).localeCompare(custLabel(b.custId, b.cust)),
    );
    return arr;
  }, [list]);

  // Gom khách hàng theo MIỀN: mỗi miền = 1 thẻ cha, bên trong là bảng chi tiết.
  // KH có ngành hàng ở nhiều miền → xuất hiện ở cả 2 thẻ (chỉ hiện dòng thuộc miền đó).
  const regionGroups = useMemo(() => {
    const m = new Map();
    for (const g of groups) {
      const byRgn = new Map();
      for (const d of g.rows) {
        const rgn = d.mien || '(Không rõ miền)';
        if (!byRgn.has(rgn)) byRgn.set(rgn, []);
        byRgn.get(rgn).push(d);
      }
      for (const [rgn, rgnRows] of byRgn) {
        if (!m.has(rgn)) m.set(rgn, []);
        const splitKey = byRgn.size > 1 ? g.key + '||' + rgn : g.key;
        m.get(rgn).push({
          key: splitKey,
          custId: g.custId,
          cust: g.cust,
          rows: rgnRows,
          diff: rgnRows.filter((r) => r.status === 'diff').length,
          gaps: g.gaps,
        });
      }
    }
    return Array.from(m.entries())
      .map(([rgn, custs]) => ({ region: rgn, groups: custs }))
      .sort((a, b) => a.region.localeCompare(b.region, 'vi'));
  }, [groups]);

  // Trần hiển thị tính theo dòng nhưng CẮT Ở RANH GIỚI KHÁCH HÀNG (không hiện nửa KH).
  const shownRegionData = useMemo(() => {
    let total = 0;
    return regionGroups.map((rg) => {
      const shown = [];
      for (const g of rg.groups) {
        if (total >= MAX_DIA_BAN_ROWS) break;
        shown.push(g);
        total += g.rows.length;
      }
      return { ...rg, shownGroups: shown };
    });
  }, [regionGroups]);
  const shownRows = shownRegionData.reduce(
    (s, rg) => rg.shownGroups.reduce((ss, g) => ss + g.rows.length, s),
    0,
  );
  const allShownGroupKeys = shownRegionData.flatMap((rg) =>
    rg.shownGroups.map((g) => g.key),
  );
  const allClosed =
    closed.size >= allShownGroupKeys.length && allShownGroupKeys.length > 0;

  // Bỏ khoảng trống + diffIds: cấu hình tự apply cả năm sau save, không còn khái
  // niệm "thiếu tháng" hay "áp dụng thủ công".
  // Đếm tổ hợp chồng lấn (>1 PS distinct trong cùng bu × cust_key × nhóm) để
  // hiện nút "Dọn chồng lấn". Tính trên TOÀN BỘ diaBan (không phụ thuộc filter).
  const overlapCount = useMemo(() => {
    const m = new Map();
    filteredDiaBan.forEach((d) => {
      if (d.active === false) return;
      const k = d.bu + '|' + dbCustKey(d.custId, d.cust) + '|' + d.grp;
      if (!m.has(k)) m.set(k, new Set());
      m.get(k).add(d.ps);
    });
    let n = 0;
    m.forEach((s) => {
      if (s.size > 1) n++;
    });
    return n;
  }, [filteredDiaBan]);
  const editCount = Object.keys(edits).length;
  const custCount = groups.length;
  const psLaList = useMemo(
    () =>
      Array.from(
        new Set(list.filter((d) => psLa(d.ps)).map((d) => d.ps)),
      ).sort(),
    [list, psKnown],
  );

  // Chỉ PS là sửa được tại chỗ (sửa sai cho CẢ khoảng hiệu lực của bản đó); đổi
  // người phụ trách giữa năm phải dùng "Chuyển PS". Miền đi theo PS.
  const setEdit = (d, ps) =>
    setEdits((prev) => {
      if (ps === d.ps) {
        // về đúng giá trị gốc → bỏ khỏi danh sách chưa lưu
        const o = { ...prev };
        delete o[d.id];
        return o;
      }
      return { ...prev, [d.id]: ps };
    });
  const toggleGroup = (key) =>
    setClosed((prev) => {
      const next = new Set(prev);
      if (next.has(key)) next.delete(key);
      else next.add(key);
      return next;
    });

  const byId = useMemo(
    () => new Map(filteredDiaBan.map((d) => [d.id, d])),
    [filteredDiaBan],
  );
  const saveEdits = async () => {
    // KHÔNG gửi mien (backend suy theo PS) và KHÔNG gửi khoảng hiệu lực (giữ nguyên).
    const payload = Object.entries(edits)
      .map(([id, ps]) => {
        const base = byId.get(Number(id)) || {};
        return {
          id: Number(id),
          custId: base.custId,
          cust: base.cust,
          grp: base.grp,
          ps,
        };
      })
      .filter((r) => r.ps && r.grp);
    if (!payload.length) return;
    if (await onSave(payload)) setEdits({});
  };

  // Modal Thêm địa bàn — thao tác trên addRows (nhiều dòng cùng lúc).
  const custById = useMemo(() => {
    const m = new Map();
    customers.forEach((c) => m.set(c.custId || c.cust, c));
    return m;
  }, [customers]);
  const setAddRowAt = (i, patch) =>
    setAddRows((prev) =>
      prev.map((r, idx) => (idx === i ? { ...r, ...patch } : r)),
    );
  const removeAddRow = (i) =>
    setAddRows((prev) =>
      prev.length > 1 ? prev.filter((_, idx) => idx !== i) : prev,
    );
  const appendAddRow = () => setAddRows((prev) => prev.concat([emptyAddRow]));
  const readyRows = addRows.filter((r) => r.custKey && r.grp && r.ps);
  const openAdd = () => {
    setAddRows([emptyAddRow]);
    setAddOpen(true);
  };
  const closeAdd = () => {
    setAddOpen(false);
    setAddRows([emptyAddRow]);
  };
  const saveBatch = async () => {
    if (!readyRows.length) return;
    // Backend nhận (custId, cust, grp, ps) — không gửi tuThang (mặc định 2026-04).
    const payload = readyRows.map((r) => {
      const c = custById.get(r.custKey);
      return {
        custId: (c && c.custId) || '',
        cust: (c && c.cust) || r.custKey,
        grp: r.grp,
        ps: r.ps,
      };
    });
    const ok = await onSave(payload);
    if (ok) closeAdd();
  };

  const declareMissing = async () => {
    // Khai báo đúng những gì kế hoạch đang có → không sinh thay đổi nào cho
    // sale_target (backend tự apply nhưng nội dung y hệt).
    const batch = missing.slice(0, MAX_DIA_BAN_ROWS).map((m) => ({
      custId: m.custId,
      cust: m.cust,
      grp: m.grp,
      ps: m.ps,
    }));
    if (!batch.length) return;
    if (
      !confirm(
        `Khai báo ${batch.length} địa bàn theo đúng PS đang có trong kế hoạch?`,
      )
    )
      return;
    await onSave(batch);
  };

  const doDelete = (d) => {
    if (
      confirm(
        `Xóa khai báo địa bàn "${d.grp}" của ${custLabel(d.custId, d.cust)} — PS ${d.ps}?\n\n` +
          `Các dòng kế hoạch đã có KHÔNG bị xóa; PS trên dòng kế hoạch giữ nguyên đến khi bạn khai báo bản mới hoặc sửa tay.`,
      )
    )
      onDelete([d.id]);
  };

  const lbl =
    'block text-[10.5px] uppercase tracking-wide text-slate-500 font-medium mb-1';
  const sel =
    'w-full px-2.5 py-2 text-[13px] border border-slate-200 rounded-md bg-white outline-none focus:border-emerald-500 focus:ring-2 focus:ring-emerald-100 disabled:bg-slate-50';
  const cellSel =
    'w-full px-1.5 py-1 text-[12px] border rounded bg-white outline-none focus:border-emerald-500';
  const th =
    'px-2 py-2 text-[10.5px] uppercase tracking-wide text-slate-500 font-semibold whitespace-nowrap';
  const td = 'px-2 py-1.5 text-[12px] border-t border-slate-100';
  const BADGE = {
    ok: ['bg-emerald-50 text-emerald-700', 'Khớp kế hoạch'],
    diff: ['bg-amber-50 text-amber-700', 'Lệch kế hoạch'],
    noplan: ['bg-slate-100 text-slate-500', 'Chưa có kế hoạch'],
  };
  const COLS = canEdit ? 4 : 3; // Ngành hàng · PS · Đối chiếu (+ thao tác)

  // Đăng ký toolbar buttons lên thanh lọc chung của App.
  useEffect(() => {
    if (!onToolbar) return;
    onToolbar(() => (
      <React.Fragment>
        {canEdit && overlapCount > 0 && (
          <button
            onClick={onDopChongLan}
            disabled={busy}
            title={
              'Dọn tổ hợp chồng lấn theo bản hiệu lực tại tháng ' +
              CURRENT_MONTH
            }
            className="flex items-center gap-1.5 px-3 py-1.5 text-[13px] font-semibold bg-amber-500 hover:bg-amber-600 text-white rounded-md disabled:opacity-50"
          >
            <RefreshCw size={14} />
            Dọn {overlapCount}chồng lấn
          </button>
        )}
        {canEdit && (
          <button
            onClick={openAdd}
            disabled={busy}
            title="Mở popup Thêm địa bàn"
            className="flex items-center gap-1.5 px-3 py-1.5 text-[13px] font-semibold bg-emerald-600 hover:bg-emerald-700 text-white rounded-md disabled:opacity-50"
          >
            <Plus size={14} />
            Thêm địa bàn
          </button>
        )}
        {allShownGroupKeys.length > 0 && (
          <button
            onClick={() =>
              setClosed(allClosed ? new Set() : new Set(allShownGroupKeys))
            }
            className="px-2.5 py-1.5 text-[13px] text-slate-600 hover:bg-slate-100 rounded-md"
          >
            {allClosed ? 'Mở tất cả' : 'Gập tất cả'}
          </button>
        )}
        <div className="relative">
          <Search
            size={14}
            className="absolute left-2.5 top-1/2 -translate-y-1/2 text-slate-400"
          />
          <input
            value={search}
            onChange={(e) => setSearch(e.target.value)}
            placeholder="Tìm KH, mã KH, PS, ngành hàng…"
            className="pl-8 pr-3 py-1.5 text-[13px] border border-slate-200 rounded-md w-64 outline-none focus:border-emerald-500 focus:ring-2 focus:ring-emerald-100"
          />
        </div>
        {canEdit && editCount > 0 && (
          <React.Fragment>
            <button
              onClick={() => setEdits({})}
              disabled={busy}
              className="px-3 py-1.5 text-[13px] text-slate-500 hover:text-red-600 hover:bg-red-50 rounded-md disabled:opacity-50"
            >
              Hủy
            </button>
            <button
              onClick={saveEdits}
              disabled={busy}
              className="flex items-center gap-1.5 px-4 py-1.5 text-[13px] font-semibold bg-emerald-600 hover:bg-emerald-700 text-white rounded-md disabled:opacity-50"
            >
              {busy ? (
                <Loader2 size={14} className="animate-spin" />
              ) : (
                <Check size={14} />
              )}
              Lưu & áp dụng ({editCount})
            </button>
          </React.Fragment>
        )}
      </React.Fragment>
    ));
    return () => {
      if (onToolbar) onToolbar(null);
    };
  }, [
    canEdit,
    overlapCount,
    busy,
    allShownGroupKeys,
    allClosed,
    search,
    editCount,
  ]);

  const [savingMonth, setSavingMonth] = useState(false);
  const handleMonthChange = async (mo) => {
    if (!onMonthChange || mo === curMonth) return;
    setSavingMonth(true);
    try {
      await onMonthChange(mo);
    } finally {
      setSavingMonth(false);
    }
  };
  const [syncing, setSyncing] = useState(false);
  const [syncResult, setSyncResult] = useState(null);

  return (
    <div className="px-6 pb-8">
      {
        // ---- Cấu hình hệ thống (admin only) ----
        isAdmin && (
          <div className="bg-white rounded-lg border border-slate-200 mb-3 px-4 py-3">
            <div className="flex items-center gap-3 flex-wrap">
              <Settings size={15} className="text-slate-400" />
              <span className="text-[13px] font-semibold text-slate-700">
                Cấu hình hệ thống
              </span>
              <div className="flex items-center gap-2 ml-4">
                <span className="text-[12px] text-slate-500">
                  Tháng hiện tại:
                </span>
                <select
                  value={curMonth || ''}
                  onChange={(e) => handleMonthChange(e.target.value)}
                  disabled={savingMonth}
                  className="px-2 py-1 text-[13px] font-medium border border-slate-200 rounded-md outline-none focus:border-emerald-400 focus:ring-2 focus:ring-emerald-100 disabled:opacity-50"
                >
                  {MONTHS.map((mo, i) => (
                    <option key={mo} value={mo}>
                      {MONTH_LABELS[i] + ' (' + mo + ')'}
                    </option>
                  ))}
                </select>
                {savingMonth && (
                  <span className="text-[11px] text-slate-400 animate-pulse">
                    Đang lưu...
                  </span>
                )}
              </div>
              <div className="flex items-center gap-2 ml-6 border-l border-slate-200 pl-6">
                <button
                  disabled={syncing}
                  onClick={async () => {
                    setSyncing(true);
                    setSyncResult(null);
                    try {
                      const r = await api('syncThucHien');
                      const d = r.result || {};
                      setSyncResult({
                        ok: true,
                        matched: d.matched_keys || 0,
                        unmatched: d.unmatched_keys || 0,
                        set: d.set_rows || 0,
                      });
                    } catch (e) {
                      setSyncResult({ ok: false, msg: e.message });
                    } finally {
                      setSyncing(false);
                    }
                  }}
                  className="flex items-center gap-1.5 px-3 py-1.5 text-[13px] font-medium border border-blue-200 bg-blue-50 text-blue-700 hover:bg-blue-100 rounded-md disabled:opacity-50"
                >
                  {syncing ? (
                    <Loader2 size={14} className="animate-spin" />
                  ) : (
                    <RefreshCw size={14} />
                  )}
                  {syncing ? ' Đang đồng bộ...' : ' Đồng bộ thực hiện'}
                </button>
                {syncResult &&
                  (syncResult.ok ? (
                    <span className="text-[11px] text-emerald-600">
                      Khớp: {syncResult.matched}/ Lệch: {syncResult.unmatched}/
                      Cập nhật: {syncResult.set}
                    </span>
                  ) : (
                    <span className="text-[11px] text-red-600">
                      Lỗi: {syncResult.msg}
                    </span>
                  ))}
              </div>
            </div>
          </div>
        )
      }
      {
        // ---- Chưa khai báo (có kế hoạch nhưng thiếu trong danh mục) ----
        missing.length > 0 && (
          <div className="bg-white rounded-lg border border-slate-200 mb-3">
            <div className="flex items-center gap-2 px-3 py-2.5">
              <button
                onClick={() => setShowMissing((v) => !v)}
                className="flex items-center gap-2 text-left"
              >
                {showMissing ? (
                  <ChevronDown size={15} className="text-slate-500" />
                ) : (
                  <ChevronRight size={15} className="text-slate-500" />
                )}
                <span className="text-[13px] font-semibold text-slate-700">
                  Có kế hoạch nhưng chưa khai báo địa bàn ({missing.length})
                </span>
              </button>
              <div className="flex-1" />
              {canEdit && (
                <button
                  onClick={declareMissing}
                  disabled={busy}
                  className="flex items-center gap-1.5 px-3 py-1.5 text-[13px] font-medium border border-emerald-200 bg-emerald-50 text-emerald-700 hover:bg-emerald-100 rounded-md disabled:opacity-50"
                >
                  <Plus size={14} />
                  Khai báo theo kế hoạch
                  {missing.length > MAX_DIA_BAN_ROWS
                    ? ` (${MAX_DIA_BAN_ROWS} dòng đầu)`
                    : ''}
                </button>
              )}
            </div>
            {showMissing && (
              <div className="px-3 pb-3 max-h-64 overflow-auto scroll-shadow">
                <table className="w-full">
                  <tbody>
                    {missing.slice(0, MAX_DIA_BAN_ROWS).map((m, i) => (
                      <tr key={i}>
                        <td
                          className={
                            td + ' font-mono text-slate-400 whitespace-nowrap'
                          }
                        >
                          {m.custId || '—'}
                        </td>
                        <td className={td + ' text-slate-700'}>
                          {custLabel(m.custId, m.cust)}
                        </td>
                        <td className={td + ' text-slate-600'}>{m.grp}</td>
                        <td className={td + ' font-medium text-slate-800'}>
                          {m.ps}
                        </td>
                      </tr>
                    ))}
                  </tbody>
                </table>
              </div>
            )}
          </div>
        )
      }
      {
        // ---- Modal Thêm địa bàn (nhiều dòng) — mở qua nút "+ Thêm địa bàn" ở toolbar
        canEdit && addOpen && (
          <div
            className="fixed inset-0 bg-slate-900/40 z-50 flex items-center justify-center p-4"
            onClick={closeAdd}
          >
            <div
              onClick={(e) => e.stopPropagation()}
              className="bg-white rounded-xl border border-slate-200 shadow-xl w-full max-w-4xl max-h-[85vh] flex flex-col"
            >
              <div className="px-4 py-3 border-b border-slate-100 flex items-center gap-3">
                <Plus size={16} className="text-emerald-600" />
                <div className="text-[14px] font-semibold text-slate-800">
                  Thêm địa bàn
                </div>
                <span className="text-[11.5px] text-slate-500">
                  {addRows.length}dòng · sẽ áp cả năm sau khi lưu
                </span>
                <div className="flex-1" />
                <button
                  onClick={closeAdd}
                  className="p-1 text-slate-400 hover:text-slate-700 hover:bg-slate-100 rounded"
                >
                  <XIcon size={16} />
                </button>
              </div>
              <div className="px-4 py-3 space-y-2 overflow-auto flex-1">
                {addRows.map((r, i) => {
                  const cust = custById.get(r.custKey);
                  const mien = (r.ps && mienByPs.get(r.ps)) || '';
                  return (
                    <div
                      key={i}
                      className="grid grid-cols-12 gap-2 items-end p-2 rounded-md border border-slate-100 bg-slate-50/40"
                    >
                      <div className="col-span-12 md:col-span-4">
                        <label className={lbl}>Khách hàng</label>
                        <CustomerPicker
                          customers={customers}
                          value={r.custKey}
                          onChange={(v) => setAddRowAt(i, { custKey: v })}
                          className={sel}
                        />
                      </div>
                      <div className="col-span-6 md:col-span-3">
                        <label className={lbl}>Ngành hàng</label>
                        <select
                          value={r.grp}
                          onChange={(e) =>
                            setAddRowAt(i, { grp: e.target.value })
                          }
                          disabled={!cust}
                          className={sel}
                        >
                          <option value="">— Chọn —</option>
                          {groupOptions.map((g) => (
                            <option key={g} value={g}>
                              {g}
                            </option>
                          ))}
                        </select>
                      </div>
                      <div className="col-span-6 md:col-span-4">
                        <label className={lbl}>
                          PS phụ trách
                          {mien && (
                            <span className="text-slate-400 normal-case tracking-normal">
                              · miền {mien}
                            </span>
                          )}
                        </label>
                        <select
                          value={r.ps}
                          onChange={(e) =>
                            setAddRowAt(i, { ps: e.target.value })
                          }
                          disabled={!cust}
                          className={sel}
                        >
                          <option value="">— Chọn —</option>
                          {psOptions.map((p) => (
                            <option key={p} value={p}>
                              {p}
                            </option>
                          ))}
                        </select>
                      </div>
                      <div className="col-span-12 md:col-span-1 flex justify-end">
                        {addRows.length > 1 && (
                          <button
                            onClick={() => removeAddRow(i)}
                            title="Bỏ dòng này"
                            className="p-1.5 text-slate-400 hover:text-red-600 hover:bg-red-50 rounded"
                          >
                            <Trash2 size={14} />
                          </button>
                        )}
                      </div>
                    </div>
                  );
                })}
                <button
                  onClick={appendAddRow}
                  className="w-full py-2 text-[12.5px] font-medium text-emerald-700 border-2 border-dashed border-emerald-200 hover:bg-emerald-50 rounded-md"
                >
                  + Thêm dòng nữa
                </button>
              </div>
              <div className="px-4 py-3 border-t border-slate-100 flex items-center gap-3">
                <span className="text-[11.5px] text-slate-500">
                  {readyRows.length}/ {addRows.length}dòng đầy đủ (KH · Ngành
                  hàng · PS)
                </span>
                <div className="flex-1" />
                <button
                  onClick={closeAdd}
                  className="px-3 py-1.5 text-[13px] text-slate-600 hover:bg-slate-100 rounded-md"
                >
                  Huỷ
                </button>
                <button
                  onClick={saveBatch}
                  disabled={busy || !readyRows.length}
                  className="flex items-center gap-1.5 px-4 py-1.5 text-[13px] font-semibold bg-emerald-600 hover:bg-emerald-700 text-white rounded-md disabled:opacity-50"
                >
                  {busy ? (
                    <Loader2 size={14} className="animate-spin" />
                  ) : (
                    <Check size={14} />
                  )}
                  Lưu {readyRows.length}địa bàn & áp dụng
                </button>
              </div>
            </div>
          </div>
        )
      }
      {
        // ---- Bảng địa bàn theo miền ----
        shownRegionData.length === 0 ||
        shownRegionData.every((rg) => rg.shownGroups.length === 0) ? (
          <div className="bg-white rounded-lg border border-slate-200 px-4 py-12 text-center text-slate-400 text-sm">
            {filteredDiaBan.length === 0
              ? 'Chưa có địa bàn nào được khai báo'
              : 'Không có địa bàn nào khớp bộ lọc'}
          </div>
        ) : (
          shownRegionData
            .filter((rg) => rg.shownGroups.length > 0)
            .map((rg) => {
              const rgnOpen = !closedRegions.has(rg.region);
              const rgnCustCount = rg.shownGroups.length;
              const rgnRowCount = rg.shownGroups.reduce(
                (s, g) => s + g.rows.length,
                0,
              );
              return (
                <div
                  key={'rgn:' + rg.region}
                  className="bg-white rounded-lg border border-slate-200 overflow-hidden mb-3"
                >
                  <div
                    className="px-3 py-2.5 flex items-center gap-2 cursor-pointer select-none border-b border-slate-100"
                    onClick={() =>
                      setClosedRegions((prev) => {
                        const next = new Set(prev);
                        if (next.has(rg.region)) next.delete(rg.region);
                        else next.add(rg.region);
                        return next;
                      })
                    }
                  >
                    {rgnOpen ? (
                      <ChevronDown
                        size={16}
                        className="text-emerald-600 shrink-0"
                      />
                    ) : (
                      <ChevronRight
                        size={16}
                        className="text-emerald-600 shrink-0"
                      />
                    )}
                    <span className="text-[14px] font-bold text-slate-800">
                      {rg.region}
                    </span>
                    <span className="text-[11px] text-slate-400 ml-1">
                      {fmtInt(rgnRowCount)}địa bàn · {fmtInt(rgnCustCount)}khách
                      hàng
                    </span>
                  </div>
                  {rgnOpen && (
                    <div className="overflow-auto scroll-shadow">
                      <table className="w-full">
                        <thead className="bg-slate-50 sticky top-0 z-10">
                          <tr>
                            <th className={th}>Khách hàng / Ngành hàng</th>
                            <th className={th}>PS phụ trách</th>
                            <th className={th}>Đối chiếu kế hoạch</th>
                            {canEdit && <th className={th} />}
                          </tr>
                        </thead>
                        <tbody>
                          {rg.shownGroups.map((g) => {
                            const gOpen = !closed.has(g.key);
                            const custKey =
                              prefill &&
                              dbCustKey(prefill.custId, prefill.cust);
                            const focused =
                              prefill &&
                              prefill.purpose === 'chuyen' &&
                              (g.key === custKey ||
                                g.key.startsWith(custKey + '||'));
                            return (
                              <React.Fragment key={'g:' + g.key}>
                                <tr
                                  ref={focused ? highlightRef : null}
                                  className={
                                    'bg-slate-50/80 border-t border-slate-200' +
                                    (focused ? ' ring-2 ring-amber-400' : '')
                                  }
                                >
                                  <td className="px-2 py-1.5" colSpan={COLS}>
                                    <button
                                      onClick={() => toggleGroup(g.key)}
                                      className="flex items-center gap-2 text-left w-full"
                                    >
                                      {gOpen ? (
                                        <ChevronDown
                                          size={14}
                                          className="text-emerald-600 shrink-0"
                                        />
                                      ) : (
                                        <ChevronRight
                                          size={14}
                                          className="text-emerald-600 shrink-0"
                                        />
                                      )}
                                      <span className="font-mono text-[11px] text-slate-400 shrink-0">
                                        {g.custId || '—'}
                                      </span>
                                      <span className="text-[13px] font-semibold text-slate-800 truncate">
                                        {custLabel(g.custId, g.cust)}
                                      </span>
                                      <span className="text-[11px] text-slate-400 shrink-0">
                                        {g.rows.length}ngành hàng
                                      </span>
                                    </button>
                                  </td>
                                </tr>
                                {gOpen &&
                                  g.rows.map((d) => {
                                    const dirty = !!edits[d.id];
                                    const [cls, text] = BADGE[d.status];
                                    return (
                                      <tr
                                        key={d.id}
                                        className={
                                          dirty
                                            ? 'bg-amber-50/60'
                                            : 'hover:bg-slate-50/60'
                                        }
                                      >
                                        <td
                                          className={
                                            td + ' text-slate-700 pl-8'
                                          }
                                        >
                                          {d.grp}
                                        </td>
                                        <td
                                          className={td}
                                          style={{ minWidth: 150 }}
                                        >
                                          {canEdit ? (
                                            <select
                                              value={d.ps}
                                              onChange={(e) =>
                                                setEdit(
                                                  byId.get(d.id) || d,
                                                  e.target.value,
                                                )
                                              }
                                              title="Sửa PS — sau khi Lưu, kế hoạch cả năm tự chuyển sang PS mới."
                                              className={
                                                cellSel +
                                                (dirty
                                                  ? ' border-amber-400'
                                                  : ' border-slate-200')
                                              }
                                            >
                                              {psOptions.map((p) => (
                                                <option key={p} value={p}>
                                                  {p}
                                                </option>
                                              ))}
                                              {!psOptions.includes(d.ps) && (
                                                <option value={d.ps}>
                                                  {d.ps}
                                                </option>
                                              )}
                                            </select>
                                          ) : (
                                            d.ps
                                          )}
                                          {psLa(d.ps) && (
                                            <span
                                              title='PS này không có trong danh mục PS (dm_ps) — hoá đơn của họ được dịch tên theo dm_ps nên sẽ KHÔNG khớp dòng kế hoạch, số rơi hết sang "ngoài kế hoạch". Sửa tên trong dm_ps hoặc chọn đúng PS trong danh mục.'
                                              className="ml-1 px-1 rounded bg-red-100 text-red-700 text-[10px] font-bold cursor-help"
                                            >
                                              !
                                            </span>
                                          )}
                                        </td>
                                        <td className={td}>
                                          <span
                                            className={`inline-block px-1.5 py-0.5 rounded text-[10.5px] font-medium ${cls}`}
                                          >
                                            {text}
                                          </span>
                                          {d.status === 'diff' && (
                                            <span className="text-[11px] text-slate-500 ml-1.5">
                                              kế hoạch: {d.planPs.join(', ')}
                                              <span className="opacity-70">
                                                · nhiều PS chồng lấn → không tự
                                                apply
                                              </span>
                                            </span>
                                          )}
                                        </td>
                                        {canEdit && (
                                          <td
                                            className={
                                              td +
                                              ' whitespace-nowrap text-right'
                                            }
                                          >
                                            <button
                                              onClick={() => doDelete(d)}
                                              disabled={busy}
                                              className="p-1 text-slate-400 hover:text-red-600 hover:bg-red-50 rounded disabled:opacity-50"
                                            >
                                              <Trash2 size={13} />
                                            </button>
                                          </td>
                                        )}
                                      </tr>
                                    );
                                  })}
                              </React.Fragment>
                            );
                          })}
                        </tbody>
                      </table>
                    </div>
                  )}
                </div>
              );
            })
        )
      }
      {list.length > shownRows && (
        <div className="px-3 py-2 text-[12px] text-slate-500 bg-white rounded-lg border border-slate-200 mt-1 text-center">
          Đang hiện {fmtInt(shownRows)}/{fmtInt(list.length)}dòng (
          {fmtInt(allShownGroupKeys.length)}/{fmtInt(groups.length)}khách hàng)
          — dùng bộ lọc hoặc ô tìm kiếm để thu hẹp.
        </div>
      )}
    </div>
  );
}

// ============ MAIN APP ============
