import React, { useState, useEffect, useMemo, useRef } from 'react';
import { Loader2, Plus, UserPlus, XIcon } from './icons.jsx';
import { NO_MSET } from '../config/constants.js';
import { custLabel, isLooseSet } from '../lib/text.js';
import { CustomerPicker } from './CustomerPicker.jsx';
import { Modal } from './Modal.jsx';
import { dbCustKey } from './DiaBanView.jsx';

// ============ ADD PRODUCT PANEL (inline — nằm ngay dưới bộ lọc, chỉ giữ ở đây) ============
// Cho phép chọn khách hàng từ danh sách rồi thêm sản phẩm, không cần mở từng KH.
// Dropdown khách hàng có ô tìm kiếm gần đúng (theo tên hoặc mã KH, bỏ dấu).

// Chỉ số danh mục sản phẩm — dựng MỘT LẦN ở App rồi truyền xuống mọi thẻ KH.
// Nếu để từng thẻ tự filter cả danh mục thì mở 100 KH = hàng trăm nghìn
// phép lọc mỗi lần render. Ở đây chỉ còn tra Map.
export function buildCatalogIndex(catalog) {
  const byGrp = new Map();
  const codeMap = new Map();
  // bu (nhãn dài "CH&CS"/"CTTM & CTUT"/"THNS & CSVT" từ dm_bo_vat_tu_mapping.bu)
  // → tập nhóm SP thuộc BU đó. Dùng cho form thêm SP: PS chỉ được chọn nhóm
  // trong BU của mình (không giới hạn theo rows kế hoạch hiện có).
  const grpsByBuLabel = new Map();
  for (const c of catalog || []) {
    const g = c.grp || '';
    if (!g) continue;
    let node = byGrp.get(g);
    if (!node) {
      node = { msets: new Map(), noMset: [] };
      byGrp.set(g, node);
    }
    const m = c.mset || '';
    if (!m) {
      node.noMset.push(c);
      continue;
    }
    let arr = node.msets.get(m);
    if (!arr) {
      arr = [];
      node.msets.set(m, arr);
    }
    arr.push(c);
    const code = isLooseSet(m) ? c.maSp || '' : c.maBvt || '';
    if (code) codeMap.set(`${g}||${m}||${c.prod || ''}`, code);
    if (c.bu) {
      let s = grpsByBuLabel.get(c.bu);
      if (!s) {
        s = new Set();
        grpsByBuLabel.set(c.bu, s);
      }
      s.add(g);
    }
  }
  const sorted = new Map(); // cache danh sách bộ vật tư đã sort theo nhóm
  return {
    groups: Array.from(byGrp.keys()).sort(),
    grpsByBuLabel,
    // Nhóm "lai" (vừa có dòng có bộ vật tư, vừa có dòng bo_vat_tu rỗng) được thêm
    // một mục NO_MSET ở cuối — nếu không thì các SP rỗng bộ vật tư không cách nào chọn.
    msetsOf(g) {
      const n = byGrp.get(g);
      if (!n) return [];
      if (!sorted.has(g)) {
        const list = Array.from(n.msets.keys()).sort();
        if (list.length && n.noMset.length) list.push(NO_MSET);
        sorted.set(g, list);
      }
      return sorted.get(g);
    },
    // Nhóm không có bộ vật tư → trả thẳng sản phẩm của nhóm; ngược lại phải chọn bộ vật tư.
    prodsOf(g, m) {
      const n = byGrp.get(g);
      if (!n) return [];
      if (n.msets.size === 0) return n.noMset;
      if (m === NO_MSET) return n.noMset;
      return m ? n.msets.get(m) || [] : [];
    },
    codeOf(g, m, p) {
      return codeMap.get(`${g}||${m}||${p}`) || '';
    },
  };
}

// Form chọn sản phẩm (nhóm SP → bộ vật tư → sản phẩm) — dùng chung cho thẻ KH đã có
// và thẻ KH vừa thêm. KH / miền đã biết sẵn nên không hỏi lại.

// Form thêm sản phẩm (dùng trong popup ở thẻ KH và ở bước 2 của popup thêm KH).
// Chọn ĐƯỢC NHIỀU sản phẩm một lượt: mỗi dòng tick là 1 sản phẩm + 1 đơn giá riêng,
// bấm 1 lần thêm hết (mỗi sản phẩm vẫn là 12 dòng T4→T3, SL = 0).
export function ProductPickerForm({
  catIdx,
  groupsByPs,
  psOptions,
  existing,
  priceOf,
  onSubmit,
  prefill,
}) {
  const opts = psOptions && psOptions.length ? psOptions : [];
  const [ps, setPs] = useState(
    opts.length === 1 ? opts[0] : (prefill && prefill.ps) || '',
  );
  const [grp, setGrp] = useState((prefill && prefill.grp) || '');
  const [mset, setMset] = useState((prefill && prefill.mset) || '');
  // Thêm CẢ BỘ hay các VẬT TƯ RIÊNG LẺ trong bộ:
  //   - cả bộ    → san_pham ghi vào DB = đúng tên bộ vật tư, chỉ có 1 dòng để tick.
  //   - riêng lẻ → tick bao nhiêu vật tư trong bộ cũng được.
  const [mode, setMode] = useState('le');
  // Đơn giá theo tr.VND cho khớp mọi chỗ hiển thị, ghi DB theo VND (×1e6).
  // Nhận cả dấu phẩy thập phân kiểu vi-VN ("1,5"). Mặc định lấy đơn giá đang dùng
  // cho đúng vật tư đó trong kế hoạch (danh mục không có cột đơn giá).
  const [sel, setSel] = useState(() => new Map()); // tên SP -> đơn giá (chuỗi tr.VND)
  const [busy, setBusy] = useState(false);
  const [done, setDone] = useState(0);
  const [msg, setMsg] = useState('');
  const [err, setErr] = useState('');
  // Tháng thầu là thuộc tính của NHÓM SP (ghi lên mọi dòng của nhóm) — form này
  // mỗi lần chỉ thêm trong 1 nhóm nên dùng chung cho cả lô. Không bắt buộc.
  const [mMain, setMMain] = useState('');
  const [mAdd, setMAdd] = useState('');

  const parseTr = (v) => {
    const n = parseFloat(String(v).replace(/\s/g, '').replace(',', '.'));
    return Number.isFinite(n) && n > 0 ? Math.round(n * 1e6) : null;
  };
  const fmtTr = (vnd) => (vnd ? String(vnd / 1e6).replace('.', ',') : '');

  // Nhóm SP được phép chọn = mọi nhóm trong BU của PS (nguồn danh mục
  // dm_bo_vat_tu_mapping, ghép qua dm_ps.bu_code — xem groupsByPs ở AppInner)
  // ∩ danh mục. PS mới/chưa có plan vẫn thấy đủ nhóm của BU mình.
  const groups = useMemo(() => {
    if (!ps) return [];
    const allowed = groupsByPs.get(ps);
    if (!allowed) return [];
    return catIdx.groups.filter((g) => allowed.has(g));
  }, [catIdx, groupsByPs, ps]);
  const msets = useMemo(() => (grp ? catIdx.msetsOf(grp) : []), [catIdx, grp]);
  const prods = useMemo(
    () => (grp ? catIdx.prodsOf(grp, mset) : []),
    [catIdx, grp, mset],
  );
  // NO_MSET chỉ là nhãn hiển thị cho nhóm không phân loại → ghi DB là rỗng.
  const msetVal = mset === NO_MSET ? '' : mset;
  // "cả bộ" chỉ có nghĩa với một bộ vật tư THẬT: chưa chọn bộ, hoặc bộ là rổ
  // "Vật tư riêng lẻ - ..." thì luôn ở chế độ chọn từng vật tư.
  const looseOnly = isLooseSet(msetVal);
  const canWholeSet = !!msetVal && !looseOnly;
  useEffect(() => {
    if (!canWholeSet && mode === 'bo') setMode('le');
  }, [canWholeSet, mode]);

  // Danh sách dòng để tick: cả bộ → đúng 1 dòng là tên bộ; riêng lẻ → các vật tư trong bộ.
  const items = useMemo(() => {
    if (!grp) return [];
    if (mode === 'bo') return canWholeSet ? [msetVal] : [];
    const seen = new Set();
    const out = [];
    for (const c of prods) {
      if (c.prod && !seen.has(c.prod)) {
        seen.add(c.prod);
        out.push(c.prod);
      }
    }
    return out;
  }, [grp, mode, prods, msetVal, canWholeSet]);
  const isDup = (name) =>
    !!(existing && existing.has(`${ps}||${grp}||${msetVal}||${name}`));
  const conTrong = useMemo(
    () => items.filter((n) => !isDup(n)),
    [items, existing, ps, grp, msetVal],
  );

  // Đổi PS / nhóm / bộ / kiểu chọn thì bỏ hết tick cũ (không còn hợp lệ).
  useEffect(() => {
    setSel(new Map());
    setMsg('');
    setErr('');
  }, [ps, grp, mset, mode]);

  // Prefill.prod (từ modal OOP → ly_do=thieu_dong_ke_hoach): sau khi items có,
  // tự tick sản phẩm này để user chỉ cần nhập đơn giá và bấm Xác nhận.
  // Chỉ chạy một lần cho mỗi prefill mới (theo ref) để không đè lên thao tác của user.
  const prefillProdRef = useRef(null);
  useEffect(() => {
    const p = prefill && prefill.prod;
    if (!p || !items.length) return;
    if (prefillProdRef.current === p) return;
    if (grp !== (prefill.grp || grp) || mset !== (prefill.mset || mset)) return;
    if (items.includes(p) && !isDup(p)) {
      prefillProdRef.current = p;
      setSel(new Map([[p, fmtTr(priceOf && priceOf(grp, msetVal, p))]]));
    }
  }, [items, prefill, grp, mset]);

  const toggle = (name) =>
    setSel((prev) => {
      const n = new Map(prev);
      if (n.has(name)) n.delete(name);
      else n.set(name, fmtTr(priceOf && priceOf(grp, msetVal, name)));
      return n;
    });
  const setPrice = (name, v) =>
    setSel((prev) => {
      const n = new Map(prev);
      n.set(name, v);
      return n;
    });
  const chonHet = () =>
    setSel((prev) =>
      prev.size >= conTrong.length
        ? new Map()
        : new Map(
            conTrong.map((n) => [
              n,
              fmtTr(priceOf && priceOf(grp, msetVal, n)),
            ]),
          ),
    );

  const thieuGia = useMemo(
    () =>
      Array.from(sel.entries())
        .filter(([, v]) => parseTr(v) == null)
        .map(([k]) => k),
    [sel],
  );
  const ready = !!ps && !!grp && sel.size > 0 && thieuGia.length === 0 && !busy;
  const lbl =
    'block text-[10.5px] uppercase tracking-wide text-slate-500 font-medium mb-1';
  const sels =
    'w-full px-2.5 py-2 text-[13px] border border-slate-200 rounded-md bg-white outline-none focus:border-emerald-500 focus:ring-2 focus:ring-emerald-100 disabled:bg-slate-50';

  const confirm = async () => {
    if (!ready) return;
    setBusy(true);
    setMsg('');
    setErr('');
    setDone(0);
    const list = Array.from(sel.entries());
    let ok = 0;
    for (const [name, priceTr] of list) {
      const res = await onSubmit({
        ps,
        grp,
        mset: msetVal,
        prod: name,
        price: parseTr(priceTr),
        mMain,
        mAdd,
      });
      if (!res) {
        setErr(`Dừng ở "${name}" — xem thông báo lỗi phía trên.`);
        break;
      }
      ok++;
      setDone(ok);
    }
    setBusy(false);
    if (ok > 0) {
      setMsg(`Đã thêm ${ok} sản phẩm`);
      setSel(new Map()); // giữ nguyên nhóm/bộ để thêm tiếp bộ khác
    }
  };

  const radio = (v, nhan, moTa, disabled) => (
    <label
      className={
        'flex-1 flex items-start gap-2 px-3 py-2 rounded-md border ' +
        (disabled
          ? 'opacity-50 cursor-not-allowed border-slate-200 '
          : 'cursor-pointer ' +
            (mode === v
              ? 'border-emerald-400 bg-emerald-50/60'
              : 'border-slate-200 hover:bg-slate-50'))
      }
    >
      <input
        type="radio"
        checked={mode === v}
        disabled={disabled}
        onChange={() => !disabled && setMode(v)}
        className="accent-emerald-600 mt-0.5"
      />
      <span>
        <span className="text-[12.5px] font-medium text-slate-700 block">
          {nhan}
        </span>
        <span className="text-[11px] text-slate-400">{moTa}</span>
      </span>
    </label>
  );

  return (
    <div className="px-4 py-3 space-y-3">
      <div
        className={`grid gap-3 ${opts.length > 1 ? 'grid-cols-3' : 'grid-cols-2'}`}
      >
        {opts.length > 1 && (
          <div>
            <label className={lbl}>PS phụ trách</label>
            <select
              value={ps}
              onChange={(e) => setPs(e.target.value)}
              className={sels}
            >
              <option value="">— Chọn PS —</option>
              {opts.map((p) => (
                <option key={p} value={p}>
                  {p}
                </option>
              ))}
            </select>
          </div>
        )}
        <div>
          <label className={lbl}>
            Nhóm sản phẩm
            {ps && (
              <span className="text-slate-400 normal-case tracking-normal">
                · theo PS {ps}
              </span>
            )}
          </label>
          <select
            value={grp}
            onChange={(e) => {
              setGrp(e.target.value);
              setMset('');
            }}
            disabled={!ps || groups.length === 0}
            className={sels}
          >
            <option value="">
              {!ps
                ? '— Chọn PS trước —'
                : groups.length
                  ? '— Chọn nhóm —'
                  : '(PS này chưa có nhóm SP nào)'}
            </option>
            {groups.map((g) => (
              <option key={g} value={g}>
                {g}
              </option>
            ))}
          </select>
        </div>
        <div>
          <label className={lbl}>Bộ vật tư</label>
          <select
            value={mset}
            onChange={(e) => setMset(e.target.value)}
            disabled={!grp || msets.length === 0}
            className={sels}
          >
            <option value="">
              {msets.length ? '— Chọn bộ vật tư —' : '(không có)'}
            </option>
            {msets.map((m) => (
              <option key={m} value={m}>
                {m}
              </option>
            ))}
          </select>
        </div>
      </div>
      <div className="grid grid-cols-2 gap-3">
        <div>
          <label className={lbl}>
            Tháng thầu chính
            <span className="text-slate-400 normal-case tracking-normal">
              · không bắt buộc
            </span>
          </label>
          <input
            type="month"
            value={mMain}
            onChange={(e) => setMMain(e.target.value)}
            disabled={!grp}
            className={sels}
          />
        </div>
        <div>
          <label className={lbl}>
            Tháng thầu bổ sung
            <span className="text-slate-400 normal-case tracking-normal">
              · không bắt buộc
            </span>
          </label>
          <input
            type="month"
            value={mAdd}
            onChange={(e) => setMAdd(e.target.value)}
            disabled={!grp}
            className={sels}
          />
        </div>
      </div>
      {(mMain || mAdd) && (
        <p className="text-[11px] text-slate-400 -mt-1">
          Tháng thầu ghi cho cả nhóm{' '}
          <span className="font-medium text-slate-600">{grp}</span>của khách
          hàng này — sửa lại được ở thẻ KH sau khi thêm.
        </p>
      )}
      <div className="flex gap-2">
        {radio('le', 'Vật tư riêng lẻ', 'chọn từng vật tư trong bộ', false)}
        {radio(
          'bo',
          'Cả bộ',
          canWholeSet
            ? 'ghi 1 dòng tên bộ vật tư'
            : looseOnly
              ? 'bộ này vốn là vật tư lẻ'
              : 'chọn bộ vật tư trước',
          !canWholeSet,
        )}
      </div>
      <div>
        <div className="flex items-end justify-between mb-1">
          <label className={lbl + ' mb-0'}>
            Sản phẩm{' '}
            <span className="text-slate-400 normal-case tracking-normal">
              · tick nhiều dòng để thêm một lượt
            </span>
          </label>
          {conTrong.length > 1 && (
            <button
              onClick={chonHet}
              className="text-[11.5px] text-emerald-700 hover:underline"
            >
              {sel.size >= conTrong.length ? 'Bỏ chọn tất cả' : 'Chọn tất cả'}
            </button>
          )}
        </div>
        <div className="border border-slate-200 rounded-md max-h-[52vh] min-h-[8rem] overflow-y-auto divide-y divide-slate-100">
          {items.length === 0 ? (
            <div className="px-3 py-6 text-center text-[12.5px] text-slate-400">
              {!grp
                ? 'Chọn nhóm sản phẩm để bắt đầu'
                : 'Bộ này chưa có vật tư trong danh mục'}
            </div>
          ) : (
            items.map((name) => {
              const dup = isDup(name);
              const on = sel.has(name);
              const goiY = priceOf ? priceOf(grp, msetVal, name) : null;
              return (
                <div
                  key={name}
                  className={
                    'flex items-center gap-2 px-3 py-1.5 ' +
                    (dup ? 'bg-slate-50' : on ? 'bg-emerald-50/40' : '')
                  }
                >
                  <input
                    type="checkbox"
                    checked={on}
                    disabled={dup || busy}
                    onChange={() => toggle(name)}
                    className="accent-emerald-600 flex-shrink-0"
                  />
                  <span
                    className={
                      'flex-1 min-w-0 truncate text-[12.5px] ' +
                      (dup ? 'text-slate-400' : 'text-slate-700')
                    }
                    title={name}
                  >
                    {name}
                  </span>
                  {dup ? (
                    <span className="text-[11px] text-amber-600 flex-shrink-0">
                      đã có trong kế hoạch
                    </span>
                  ) : (
                    <React.Fragment>
                      <input
                        value={on ? sel.get(name) || '' : fmtTr(goiY)}
                        onChange={(e) => setPrice(name, e.target.value)}
                        disabled={!on || busy}
                        inputMode="decimal"
                        placeholder={goiY ? '' : 'nhập giá'}
                        title={
                          goiY
                            ? 'Giá đang dùng cho vật tư này trong kế hoạch'
                            : 'Vật tư này chưa có đơn giá trong kế hoạch — nhập tay'
                        }
                        className={
                          'w-24 px-2 py-1 text-[12.5px] text-right border rounded-md outline-none focus:border-emerald-500 ' +
                          (on && parseTr(sel.get(name)) == null
                            ? 'border-amber-400 bg-amber-50'
                            : on && goiY
                              ? 'border-slate-200 bg-emerald-50/60'
                              : 'border-slate-200')
                        }
                      />
                      <span className="text-[11px] text-slate-400 w-11 flex-shrink-0">
                        tr.VND
                      </span>
                    </React.Fragment>
                  )}
                </div>
              );
            })
          )}
        </div>
      </div>
      <div className="flex items-center gap-3 flex-wrap">
        {sel.size > 0 && (
          <span className="text-[12px] text-slate-600">
            Đã chọn{' '}
            <span className="font-semibold text-slate-800">{sel.size}</span>sản
            phẩm · {sel.size * 12}dòng (T4→T3), SL = 0
          </span>
        )}
        {thieuGia.length > 0 && (
          <span className="text-[12px] text-amber-600">
            Còn {thieuGia.length}dòng chưa có đơn giá
          </span>
        )}
        {err && <span className="text-[12px] text-red-600">{err}</span>}
        {msg && <span className="text-[12px] text-emerald-600">{msg}</span>}
        <div className="flex-1" />
        <button
          onClick={confirm}
          disabled={!ready}
          className="flex items-center gap-1.5 px-4 py-1.5 text-[13px] font-semibold bg-emerald-600 hover:bg-emerald-700 text-white rounded-md disabled:opacity-50"
        >
          {busy ? (
            <React.Fragment>
              <Loader2 size={14} className="animate-spin" />
              {` Đang thêm ${done}/${sel.size}…`}
            </React.Fragment>
          ) : (
            <React.Fragment>
              <Plus size={14} />
              {sel.size > 1 ? ` Thêm ${sel.size} sản phẩm` : ' Thêm sản phẩm'}
            </React.Fragment>
          )}
        </button>
      </div>
    </div>
  );
}

// Panel "Thêm khách hàng": chọn KH + PS + miền. Chưa ghi DB (schema không có bảng
// riêng cho KH của kế hoạch — KH chỉ tồn tại khi có dòng sản phẩm), chỉ tạo 1 thẻ KH
// tạm ở đầu danh sách để người dùng thêm sản phẩm ngay tại đó.
// Popup "Thêm khách hàng" — mở từ nút trên thanh bộ lọc (màn chi tiết).
// KH mới CHƯA vào DB: bấm Xác nhận chỉ tạo thẻ KH tạm ở client, phải thêm sản
// phẩm đầu tiên thì mới thực sự ghi (xem NewCustomerCard).
// KHÔNG có ô Miền: miền là thuộc tính của PS, suy từ PS đã chọn (PS nào có nhiều
// miền thì rơi về miền đã khai báo trong địa bàn); client không suy được thì để
// trống, server tự điền bằng mienForPs().
export function AddCustomerModal({
  open,
  onClose,
  customers,
  psOptions,
  regionsByPs,
  diaBanByCust,
  existingCustKeys,
  catIdx,
  groupsByPs,
  priceOf,
  onAdd,
  onAddProduct,
  prefill,
}) {
  const [custKey, setCustKey] = useState('');
  const [ps, setPs] = useState(
    psOptions && psOptions.length === 1 ? psOptions[0] : '',
  );
  const [step, setStep] = useState(1); // 1 = chọn KH/PS, 2 = thêm sản phẩm đầu tiên
  const [added, setAdded] = useState(0); // số SP đã thêm trong lần mở này
  // Mỗi lần mở lại là một lần thêm mới → xoá lựa chọn cũ, TRỪ KHI có prefill từ
  // modal OOP (thieu_dong_ke_hoach): điền sẵn KH + PS + nhóm SP và nhảy thẳng step 2.
  useEffect(() => {
    if (!open) return;
    if (prefill && (prefill.custId || prefill.cust)) {
      setCustKey(prefill.custId || prefill.cust);
      if (prefill.ps) setPs(prefill.ps);
      setStep(2);
    } else {
      setCustKey('');
      setPs(psOptions && psOptions.length === 1 ? psOptions[0] : '');
      setStep(1);
    }
    setAdded(0);
  }, [open, prefill]);
  const cust = useMemo(
    () => customers.find((c) => (c.custId || c.cust) === custKey),
    [customers, custKey],
  );
  // Địa bàn đã khai báo cho KH này (dm_dia_ban) — nguồn chuẩn cho PS/Miền.
  const terr = useMemo(
    () =>
      (cust &&
        diaBanByCust &&
        diaBanByCust.get(dbCustKey(cust.custId, cust.cust))) ||
      null,
    [diaBanByCust, cust],
  );
  // Chọn KH → tự điền PS nếu địa bàn chỉ khai báo đúng 1 PS cho KH đó.
  useEffect(() => {
    if (terr && terr.ps.length === 1) setPs(terr.ps[0]);
  }, [terr]);
  const psRegions = useMemo(
    () => (ps && regionsByPs.get(ps)) || [],
    [regionsByPs, ps],
  );
  const region =
    psRegions.length === 1
      ? psRegions[0]
      : terr && terr.mien.length === 1
        ? terr.mien[0]
        : '';
  const already = !!(
    cust &&
    (existingCustKeys.has(custLabel(cust.custId, cust.cust)) ||
      (cust.custId && existingCustKeys.has(cust.custId)))
  );
  const lbl =
    'block text-[10.5px] uppercase tracking-wide text-slate-500 font-medium mb-1';
  const sel =
    'w-full px-2.5 py-2 text-[13px] border border-slate-200 rounded-md bg-white outline-none focus:border-emerald-500 focus:ring-2 focus:ring-emerald-100 disabled:bg-slate-50';
  const ready = !!cust && !!ps && !already;
  // Bỏ qua bước sản phẩm → chỉ tạo thẻ KH tạm ở client (chưa ghi DB)
  const chiThemKH = () => {
    if (!ready) return;
    onAdd({ custId: cust.custId || '', cust: cust.cust, ps, region });
    onClose();
  };
  const themSanPham = async (sp) => {
    const ok = await onAddProduct({
      ...sp,
      custId: cust.custId || '',
      cust: cust.cust,
      region,
    });
    if (ok) setAdded((n) => n + 1);
    return ok;
  };
  const coDanhMuc = !!(catIdx && groupsByPs);
  return (
    <Modal
      open={open}
      onClose={onClose}
      title={
        step === 1
          ? 'Thêm khách hàng'
          : `Sản phẩm đầu tiên · ${cust ? custLabel(cust.custId, cust.cust) : ''}`
      }
      icon={<UserPlus size={16} className="text-emerald-600" />}
      width={step === 1 ? 520 : 760}
      footer={
        step === 1 ? (
          <div className="flex items-center gap-2 px-4 py-3 border-t border-slate-100">
            <div className="flex-1" />
            <button
              onClick={onClose}
              className="px-3 py-1.5 text-[13px] text-slate-600 hover:bg-slate-100 rounded-md"
            >
              Hủy
            </button>
            {
              // Vẫn giữ đường cũ: tạo thẻ KH rồi thêm sản phẩm sau, cho ai chưa chọn được SP ngay
              coDanhMuc && (
                <button
                  onClick={chiThemKH}
                  disabled={!ready}
                  className="px-3 py-1.5 text-[13px] text-slate-600 border border-slate-200 rounded-md hover:bg-slate-100 disabled:opacity-50"
                >
                  Chỉ thêm KH
                </button>
              )
            }
            <button
              onClick={() => (coDanhMuc ? setStep(2) : chiThemKH())}
              disabled={!ready}
              className="flex items-center gap-1.5 px-4 py-1.5 text-[13px] font-semibold bg-emerald-600 hover:bg-emerald-700 text-white rounded-md disabled:opacity-50"
            >
              {coDanhMuc ? (
                'Xác nhận & thêm SP'
              ) : (
                <React.Fragment>
                  <Plus size={14} />
                  Xác nhận
                </React.Fragment>
              )}
            </button>
          </div>
        ) : (
          <div className="flex items-center gap-2 px-4 py-3 border-t border-slate-100">
            {added > 0 ? (
              <span className="text-[12px] text-emerald-600">
                Đã thêm {added}sản phẩm — khách hàng đã vào kế hoạch
              </span>
            ) : (
              <span className="text-[12px] text-slate-400">
                Chưa thêm sản phẩm nào thì khách hàng chưa vào kế hoạch
              </span>
            )}
            <div className="flex-1" />
            <button
              onClick={() => setStep(1)}
              className="px-3 py-1.5 text-[13px] text-slate-600 hover:bg-slate-100 rounded-md"
            >
              Quay lại
            </button>
            <button
              onClick={() => {
                if (added === 0) chiThemKH();
                else onClose();
              }}
              className="px-4 py-1.5 text-[13px] font-semibold text-emerald-700 border border-emerald-200 rounded-md hover:bg-emerald-50"
            >
              {added > 0 ? 'Xong' : 'Bỏ qua, thêm SP sau'}
            </button>
          </div>
        )
      }
    >
      {step === 1 ? (
        <div className="px-4 py-3 space-y-3">
          <div>
            <label className={lbl}>Khách hàng</label>
            <CustomerPicker
              customers={customers}
              value={custKey}
              onChange={setCustKey}
              className={sel}
            />
          </div>
          <div>
            <label className={lbl}>
              PS phụ trách
              {terr && terr.ps.length === 1 && (
                <span className="text-slate-400 normal-case tracking-normal">
                  · theo địa bàn
                </span>
              )}
            </label>
            <select
              value={ps}
              onChange={(e) => setPs(e.target.value)}
              disabled={!cust}
              className={sel}
            >
              <option value="">— Chọn PS —</option>
              {
                // PS đã khai báo địa bàn cho KH này lên đầu; vẫn cho chọn PS khác vì
                // địa bàn có thể chưa khai báo kịp (màn "Cấu hình địa bàn" để bù).
                terr && terr.ps.length > 0 && (
                  <optgroup label="Theo địa bàn đã khai báo">
                    {terr.ps.map((p) => (
                      <option key={'d:' + p} value={p}>
                        {p}
                      </option>
                    ))}
                  </optgroup>
                )
              }
              <optgroup label="Tất cả PS">
                {(psOptions || []).map((p) => (
                  <option key={p} value={p}>
                    {p}
                  </option>
                ))}
              </optgroup>
            </select>
            {ps && (
              <p className="text-[11px] text-slate-400 mt-1">
                {region
                  ? `Miền: ${region} (theo PS)`
                  : 'Miền suy theo PS khi lưu'}
              </p>
            )}
          </div>
          {already && (
            <p className="text-[12px] text-amber-600">
              Khách hàng này đã có trong kế hoạch — dùng nút “Thêm SP” ở thẻ của
              họ.
            </p>
          )}
        </div>
      ) : (
        <ProductPickerForm
          catIdx={catIdx}
          groupsByPs={groupsByPs}
          psOptions={[ps]}
          existing={null}
          priceOf={priceOf}
          onSubmit={themSanPham}
          prefill={prefill}
        />
      )}
    </Modal>
  );
}

// Thẻ KH vừa thêm nhưng CHƯA có sản phẩm nào → chưa có dòng nào trong DB.
// Chỉ tồn tại ở client cho tới khi thêm sản phẩm đầu tiên (lúc đó KH xuất hiện
// trong danh sách thật và thẻ tạm này tự biến mất).
export function NewCustomerCard({
  cust,
  catIdx,
  groupsByPs,
  priceOf,
  onAddProduct,
  onDismiss,
}) {
  return (
    <div className="bg-white rounded-lg border-2 border-dashed border-emerald-300 mb-3 overflow-hidden">
      <div className="flex items-stretch">
        <div className="bg-emerald-600 text-white px-3 py-3 flex items-center justify-center min-w-[88px]">
          <div className="text-[11px] opacity-90 font-mono">
            {cust.custId || '—'}
          </div>
        </div>
        <div className="flex-1 flex items-center gap-3 px-4 py-3 min-w-0">
          <div className="flex-1 min-w-0">
            <h3 className="text-[14px] font-semibold text-slate-900 truncate">
              {custLabel(cust.custId, cust.cust)}
            </h3>
            <p className="text-[11px] text-slate-500 mt-0.5">
              KH mới · PS {cust.ps}· {cust.region}
              <span className="text-amber-600">
                · chưa lưu — thêm sản phẩm đầu tiên để lưu vào kế hoạch
              </span>
            </p>
          </div>
          <button
            onClick={onDismiss}
            title="Bỏ khách hàng này khỏi danh sách (chưa có gì được lưu)"
            className="p-1.5 text-slate-400 hover:text-red-600 hover:bg-red-50 rounded-md"
          >
            <XIcon size={15} />
          </button>
        </div>
      </div>
      <ProductPickerForm
        catIdx={catIdx}
        groupsByPs={groupsByPs}
        psOptions={[cust.ps]}
        existing={null}
        priceOf={priceOf}
        onSubmit={(s) =>
          onAddProduct({
            ...s,
            custId: cust.custId,
            cust: cust.cust,
            region: cust.region,
          })
        }
      />
    </div>
  );
}
