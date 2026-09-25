import React, {
  useState,
  useEffect,
  useMemo,
  useRef,
  useCallback,
  useDeferredValue,
} from 'react';

import {
  Search, Download, Check, Loader2, AlertCircle,
  ChevronDown, ChevronRight, RefreshCw,
  LogOut, Eye, EyeOff, UserPlus,
} from './components/icons.jsx';
import {
  MONTHS, MONTH_LABELS, CURRENT_MONTH, setCurrentMonth,
  getCurIdx, getNoteMonth, isYtdMonth, NO_MSET, TOK_KEY,
  TEAMS, canSwitchTeam, OOP_CUST,
  setMaskMoney as setGlobalMaskMoney, ALIAS_MAP, setAliasMap,
} from './config/constants.js';
import { deaccent, fmtCust, custLabel, inSel, planCustKeys, matchSearch } from './lib/text.js';
import { api, onSessionExpired } from './api/client.js';
import { setUser as setSentryUser } from './lib/sentry.js';
import { LoginGate } from './components/LoginGate.jsx';
import { Modal } from './components/Modal.jsx';
import { MultiSelect } from './components/MultiSelect.jsx';
import { AuditLogView } from './components/AuditLogView.jsx';
import { TeamSummaryBar } from './components/TeamBar.jsx';
import { AccountBar, ThYtdBar } from './components/StatBars.jsx';
import { WaterfallChart } from './components/Charts.jsx';
import { useStickyBars, DetailScrollBox } from './hooks/useLayout.jsx';
import { ProductSummaryView } from './components/ProductSummaryView.jsx';
import { SummaryView } from './components/SummaryView.jsx';
import { buildCatalogIndex, AddCustomerModal, NewCustomerCard } from './components/AddProduct.jsx';
import { DiaBanView } from './components/DiaBanView.jsx';
import { TabBtn, OopReasonButton, FixBoVatTuModal, OopDetailModal, DmpsForm, StatCard } from './components/SupportComponents.jsx';
import { QuotaThauCtx, grpKey, prodKey } from './components/QuotaThau.jsx';
import { dbCustKey, diaBanErrMsg } from './components/DiaBanView.jsx';
import { CustomerCard } from './components/CustomerCard.jsx';
import { useVirtualizer, observeElementOffset } from '@tanstack/react-virtual';

const VIRTUAL_THRESHOLD = 30;

// Cuộn ngang không đổi scrollTop nhưng vẫn bật isScrolling -> re-render mọi thẻ.
const observeVerticalOffset = (instance, cb) => {
  let last = null;
  return observeElementOffset(instance, (offset, isScrolling) => {
    if (isScrolling && offset === last) return;
    last = offset;
    cb(offset, isScrolling);
  });
};

function VirtualCardList({ items, scrollRef, cardKey, renderCard }) {
  const virtualizer = useVirtualizer({
    count: items.length,
    getScrollElement: () => scrollRef.current,
    observeElementOffset: observeVerticalOffset,
    estimateSize: () => 72,
    overscan: 5,
  });

  return (
    <div style={{ height: virtualizer.getTotalSize(), position: 'relative' }}>
      {virtualizer.getVirtualItems().map((vItem) => (
        <div
          key={cardKey(items[vItem.index])}
          ref={virtualizer.measureElement}
          data-index={vItem.index}
          style={{
            position: 'absolute',
            top: 0,
            left: 0,
            width: '100%',
            overflow: 'hidden',
            transform: `translateY(${vItem.start}px)`,
          }}
        >
          {renderCard(items[vItem.index])}
        </div>
      ))}
    </div>
  );
}

export function App() {
  const [authed, setAuthed] = useState(false);
  const [auth, setAuth] = useState({
    role: '',
    scope: '',
    username: '',
    bu: '',
    ho_ten: '',
  });
  // Team đang xem trên UI. Chỉ admin/manager mới đổi được; user thường luôn = bu của họ.
  const [viewBu, setViewBu] = useState('');
  // loadScope = phạm vi gọi API: 'test' khi xem TEST, '' khi xem team thật hoặc tất cả.
  // Chuyển giữa các team thật (CHCS/CTTM/THNK/Tất cả) = instant (client-side), không reload.
  const loadScope = viewBu === 'test' ? 'test' : '';
  useEffect(() => {
    window.__app_auth = auth;
  }, [auth]);
  const [initialLoading, setInitialLoading] = useState(true);
  const [refreshing, setRefreshing] = useState(false);
  const [error, setError] = useState('');
  const [rows, setRows] = useState([]);
  // Đợt thầu + quota thầu (shared.dot_thau / shared.quota_thau) — nguồn riêng,
  // không nằm trong rows vì grain khác hẳn (gói thầu, không phải tháng).
  const [dots, setDots] = useState([]);
  const [quotas, setQuotas] = useState([]);
  // Dòng thực hiện NGOÀI KẾ HOẠCH — chỉ dùng cho 2 màn tổng hợp, không vào màn chi tiết.
  const [oopRows, setOopRows] = useState([]);
  const [drafts, setDrafts] = useState({}); // { 'row:key': value } — chưa lưu
  const [saving, setSaving] = useState(false);
  const [savedFlash, setSavedFlash] = useState(false);
  const [tab, setTab] = useState('detail'); // 'detail' | 'summary' | 'prodsum' | 'diaban' | 'audit'
  const [notice, setNotice] = useState(''); // thông báo kết quả thao tác (tự tắt sau 8s)
  const [search, setSearch] = useState('');
  const deferredSearch = useDeferredValue(search);
  // Bộ lọc đa lựa chọn: mảng rỗng = tất cả (không lọc).
  const [psFilter, setPsFilter] = useState([]);
  const [regionFilter, setRegionFilter] = useState([]);
  const [groupFilter, setGroupFilter] = useState([]);
  const [custFilter, setCustFilter] = useState([]);
  const [fields, setFields] = useState([]);
  const [catalog, setCatalog] = useState([]);
  const [customers, setCustomers] = useState([]); // danh mục KH đầy đủ từ dm_khach_hang
  const [psDir, setPsDir] = useState([]); // danh mục PS từ shared.dm_ps
  const [diaBan, setDiaBan] = useState([]); // cấu hình địa bàn (dm_dia_ban)
  const [diaBanBusy, setDiaBanBusy] = useState(false);
  const [dataRev, setDataRev] = useState(0);
  const rowRevsRef = useRef(new Map());
  const scrollContainerRef = useRef(null);
  const checkForUpdatesRef = useRef(null);
  const [stale, setStale] = useState(false);
  // Bản mới của web app đã deploy nhưng user đang có bản nháp chưa lưu → không
  // reload ngay, chờ user lưu/huỷ rồi mới reload để không mất bản nháp.
  const [pendingReload, setPendingReload] = useState(false);
  const [curMonth, setCurMonth] = useState(CURRENT_MONTH);
  const [maskMoney, setMaskMoney] = useState(false);
  const [showBasePlan, setShowBasePlan] = useState(false);
  const [teamOpen, setTeamOpen] = useState(() => new Set());
  // Hàm xuất Excel do màn tổng hợp đang mở đăng ký lên (nút nằm trên thanh bộ lọc).
  // setState với hàm phải bọc thêm 1 lớp, không React sẽ tưởng là updater.
  const [exportFn, setExportFn] = useState(null);
  const [diaBanToolbar, setDiaBanToolbar] = useState(null);
  const [addCustOpen, setAddCustOpen] = useState(false); // popup Thêm khách hàng
  const [openCards, setOpenCards] = useState(new Set());
  const setExporter = useCallback((fn) => setExportFn(() => fn), []);
  const setDiaBanTb = useCallback((fn) => setDiaBanToolbar(() => fn), []);
  setGlobalMaskMoney(maskMoney);
  // Map mã KH → customer_alias (tên hiển thị rút gọn, biên tập tay trong dm_khach_hang).
  // Gán vào ALIAS_MAP toàn cục để custLabel() dùng ở mọi nơi hiển thị tên KH.
  const aliasByCustId = useMemo(() => {
    const m = new Map();
    for (const c of customers)
      if (c.custId && c.alias) m.set(String(c.custId), c.alias);
    return m;
  }, [customers]);
  setAliasMap(aliasByCustId);
  // Sửa số liệu: admin, ps, manager, area_manager (server chốt lại phạm vi ghi của
  // từng role). Xoá dòng / cấu hình địa bàn vẫn chỉ admin -> dùng isAdmin.
  const canEdit = ['admin', 'ps', 'manager', 'area_manager'].includes(
    auth.role,
  );
  const isAdmin = auth.role === 'admin';
  // --- Đợt thầu & quota thầu -------------------------------------------------
  // Hai bảng mới là nguồn CHUẨN cho quota, nhưng các cột quota cũ trên sale_target
  // vẫn được ghi đè bằng số tổng sau mỗi lần lưu: hai màn tổng hợp và các report
  // ngoài app còn đang đọc cột cũ, ngưng ghi là chúng lệch ngay.
  const dotsByGroup = useMemo(() => {
    const m = new Map();
    for (const d of dots) {
      const k = grpKey(d.fy, d.ps, d.custId, d.grp);
      if (!m.has(k)) m.set(k, []);
      m.get(k).push(d);
    }
    return m;
  }, [dots]);
  const quotasByProduct = useMemo(() => {
    const m = new Map();
    for (const q of quotas) {
      const k = prodKey(q.fy, q.ps, q.custId, q.grp, q.mset, q.prod);
      if (!m.has(k)) m.set(k, []);
      m.get(k).push(q);
    }
    return m;
  }, [quotas]);
  // Nạp lại riêng đợt + quota (không đụng tới rows).
  const napLaiQuota = useCallback(async () => {
    const r = await api(
      'getQuotaThau',
      canSwitchTeam(auth.role) ? { bu: loadScope } : {},
    );
    const ds = Array.isArray(r.dots) ? r.dots : [];
    const qs = Array.isArray(r.quotas) ? r.quotas : [];
    setDots(ds);
    setQuotas(qs);
    return qs;
  }, [auth.role, loadScope]);
  const saveDot = useCallback(
    async (rowsIn) => {
      await api('saveDotThau', { rows: rowsIn });
      await napLaiQuota();
    },
    [napLaiQuota],
  );
  const deleteDot = useCallback(
    async (info) => {
      await api('deleteDotThau', info);
      await napLaiQuota();
      await checkForUpdatesRef.current?.();
    },
    [napLaiQuota],
  );
  const saveQuota = useCallback(
    async (rowsIn) => {
      await api('saveQuotaThau', { rows: rowsIn });
      await napLaiQuota();
      await checkForUpdatesRef.current?.();
    },
    [napLaiQuota],
  );
  const quotaThauCtx = useMemo(
    () => ({
      dotsByGroup,
      quotasByProduct,
      saveDot,
      deleteDot,
      saveQuota,
    }),
    [dotsByGroup, quotasByProduct, saveDot, deleteDot, saveQuota],
  );
  useEffect(() => {
    onSessionExpired(() => {
      setAuthed(false);
      setInitialLoading(false);
    });
    const shared = localStorage.getItem('vmed_token');
    if (shared && !sessionStorage.getItem(TOK_KEY))
      sessionStorage.setItem(TOK_KEY, shared);
    if (sessionStorage.getItem(TOK_KEY)) {
      api('ping')
        .then((r) => {
          setAuth({
            role: r.role,
            scope: r.scope,
            username: r.username,
            bu: r.bu,
            ho_ten: r.ho_ten || r.hoTen || '',
          });
          setViewBu(canSwitchTeam(r.role) ? '' : r.bu || '');
          setSentryUser(r.username, r.role);
          setAuthed(true);
        })
        .catch(() => {
          sessionStorage.removeItem(TOK_KEY);
          setInitialLoading(false);
        });
    } else setInitialLoading(false);
  }, []);
  const loadData = useCallback(
    async (isInitial) => {
      if (isInitial) setInitialLoading(true);
      else setRefreshing(true);
      setError('');
      try {
        // admin/manager: gửi kèm loadScope ('' = tất cả team thật, 'test' = chỉ test)
        const r = await api(
          'getData',
          canSwitchTeam(auth.role) ? { bu: loadScope } : {},
        );
        const fields = r.fields || [];
        setFields(fields);
        const arr = r.rows || [];
        const rowNums = r.rowNums || [];
        const rowRevs = r.rowRevs || [];
        const revMap = new Map();
        const objs = new Array(arr.length);
        for (let i = 0; i < arr.length; i++) {
          const row = arr[i];
          if (rowNums[i] && rowRevs[i]) revMap.set(rowNums[i], rowRevs[i]);
          const o = {
            _row: rowNums[i],
          };
          for (let j = 0; j < fields.length; j++) {
            const v = row[j];
            if (v !== '' && v !== null && v !== undefined) o[fields[j]] = v;
          }
          // Tên hiển thị KH = customer_alias (nếu có) hoặc tên chuẩn hoá. custId là khoá.
          // Giữ custRaw = tên gốc trong DB để khi THÊM SẢN PHẨM ghi đúng chuỗi cũ
          // (nếu ghi tên đã format thì cùng 1 KH lại có 2 cách viết trong sale_target).
          if (o.cust) {
            o.custRaw = o.cust;
            o.cust = custLabel(o.custId, o.cust);
          }
          objs[i] = o;
        }
        setRows(objs);
        setDots(Array.isArray(r.dots) ? r.dots : []);
        setQuotas(Array.isArray(r.quotas) ? r.quotas : []);
        // Dòng THỰC HIỆN NGOÀI KẾ HOẠCH: giữ RIÊNG, không trộn vào rows.
        // Chỉ 2 màn tổng hợp dùng tới (cho đủ số); màn chi tiết không thấy, không sửa được.
        // Không đặt _row → mọi thao tác sửa/xoá theo id đều không đụng tới các dòng này.
        const oopArr = r.oopRows || [];
        const oopMeta = r.oopMeta || [];
        const oopRowNums = r.oopRowNums || [];
        const oopRowRevs = r.oopRowRevs || [];
        const oopObjs = new Array(oopArr.length);
        for (let i = 0; i < oopArr.length; i++) {
          const row = oopArr[i];
          if (oopRowNums[i] && oopRowRevs[i]) revMap.set(oopRowNums[i], oopRowRevs[i]);
          const o = { _oop: true };
          for (let j = 0; j < fields.length; j++) {
            const v = row[j];
            if (v !== '' && v !== null && v !== undefined) o[fields[j]] = v;
          }
          // Tên hiển thị như dòng kế hoạch (alias hoặc chuẩn hoá) để cùng 1 KH hiện cùng cách viết.
          // Nhãn chung "Ngoài kế hoạch" (khi actual không có tên KH) giữ nguyên.
          if (o.cust && o.cust !== OOP_CUST) {
            o.custRaw = o.cust;
            o.cust = custLabel(o.custId, o.cust);
          }
          // Meta ngoài FIELDS: ly_do + ps_dia_ban để biết cách sửa cho từng dòng.
          // Bản edge cũ chưa trả oopMeta -> mảng rỗng, o._lyDo undefined, UI ẩn nhãn.
          const m = oopMeta[i];
          if (m) {
            if (m.ly_do) o._lyDo = m.ly_do;
            if (m.ps_dia_ban) o._psDiaBan = m.ps_dia_ban;
          }
          oopObjs[i] = o;
        }
        setOopRows(oopObjs);
        rowRevsRef.current = revMap;
        if (
          r.config &&
          r.config.current_month &&
          MONTHS.includes(r.config.current_month)
        ) {
          setCurrentMonth(r.config.current_month);
          setCurMonth(r.config.current_month);
        }
        if (typeof r.rev === 'number') setDataRev(r.rev);
        setStale(false);
        if (r.role)
          setAuth({
            role: r.role,
            scope: r.scope,
            username: r.username,
            bu: r.bu,
            ho_ten: r.ho_ten || r.hoTen || '',
          });
      } catch (err) {
        setError('Không tải được dữ liệu: ' + err.message);
      }
      setInitialLoading(false);
      setRefreshing(false);
    },
    [auth.role, loadScope],
  );
  useEffect(() => {
    if (authed) loadData(true);
  }, [authed, loadData]);

  // tải danh mục (Catalog) + danh mục khách hàng (dm_khach_hang) để thêm sản phẩm
  useEffect(() => {
    if (!authed) return;
    api('getCatalog')
      .then((r) => setCatalog(r.catalog || []))
      .catch(() => {});
    api('getCustomers')
      .then((r) => setCustomers(r.customers || []))
      .catch(() => {});
  }, [authed]);

  // Danh mục alias (getCustomers) thường về SAU getData → khi có alias, gán lại tên
  // hiển thị của các dòng đã nạp (từ custRaw) để dùng customer_alias thay tên tạm.
  useEffect(() => {
    const relabel = (list) => {
      let changed = false;
      const next = list.map((r) => {
        if (r.custRaw == null || r.cust === OOP_CUST) return r;
        const disp = custLabel(r.custId, r.custRaw);
        if (disp === r.cust) return r;
        changed = true;
        return { ...r, cust: disp };
      });
      return changed ? next : list;
    };
    setRows((prev) => relabel(prev));
    setOopRows((prev) => relabel(prev));
  }, [aliasByCustId]);

  // Danh mục PS (shared.dm_ps) — nguồn chuẩn của PS/miền/team. Phải tải lại khi đổi
  // team đang xem (admin/manager) vì backend lọc theo team. Lỗi KHÔNG chặn app:
  // edge chưa deploy bản mới thì rơi về cách cũ (suy PS từ dữ liệu kế hoạch).
  useEffect(() => {
    if (!authed) return;
    let huy = false;
    api('getPs', canSwitchTeam(auth.role) ? { bu: loadScope } : {})
      .then((r) => {
        if (!huy) setPsDir(r.ps || []);
      })
      .catch(() => {
        if (!huy) setPsDir([]);
      });
    return () => {
      huy = true;
    };
  }, [authed, auth.role, loadScope]);

  // Cấu hình địa bàn (dm_dia_ban): dùng ở màn "Cấu hình địa bàn" và ở panel thêm KH
  // (tự điền PS/Miền). Lọc theo team đang xem như getData. Lỗi ở đây KHÔNG được
  // chặn app: edge function chưa deploy bản mới thì chỉ là danh sách rỗng.
  const loadDiaBan = useCallback(async () => {
    try {
      const r = await api(
        'getDiaBan',
        canSwitchTeam(auth.role) ? { bu: loadScope } : {},
      );
      setDiaBan(r.diaBan || []);
    } catch (e) {
      setDiaBan([]);
    }
  }, [auth.role, loadScope]);
  useEffect(() => {
    if (authed) loadDiaBan();
  }, [authed, loadDiaBan]);
  useEffect(() => {
    if (!notice) return;
    const id = setTimeout(() => setNotice(''), 8000);
    return () => clearTimeout(id);
  }, [notice]);

  // Ghi khai báo địa bàn (thêm/sửa). Chỉ admin — backend cũng chặn lại lần nữa.
  // Từ 2026-08-07: backend TỰ ĐỘNG apply cho cả năm sau khi ghi xong, nên sau
  // save cần loadData để lấy ps/mien mới của dòng kế hoạch.
  const saveDiaBan = useCallback(
    async (rows) => {
      setDiaBanBusy(true);
      setError('');
      try {
        const r = await api('saveDiaBan', { rows });
        const s = r.stats || {};
        const ap = s.apply || {};
        // Reload cả danh mục địa bàn lẫn kế hoạch (ps trong sale_target đã đổi).
        await Promise.all([loadDiaBan(), loadData()]);
        setNotice(
          `Đã lưu địa bàn (thêm ${s.inserted || 0}, sửa ${s.updated || 0}) và áp dụng cả năm: ` +
            `${ap.applied || 0} bản → ${ap.updated_rows || 0} dòng kế hoạch đổi PS.` +
            (ap.ambiguous
              ? ` Bỏ qua ${ap.ambiguous} tổ hợp có nhiều PS chồng lấn — cần dọn thủ công.`
              : ''),
        );
        return true;
      } catch (err) {
        setError('Lưu cấu hình địa bàn thất bại: ' + diaBanErrMsg(err.message));
        return false;
      } finally {
        setDiaBanBusy(false);
      }
    },
    [loadDiaBan, loadData],
  );

  // Dọn tổ hợp có nhiều PS chồng lấn theo bản đang hiệu lực tháng hiện tại.
  // Tổ hợp có 1 PS hiệu lực tại T7 -> giữ PS đó, xoá bản khác, apply cả năm.
  // Tổ hợp ≥2 PS hiệu lực -> bỏ qua, hiện danh sách cho user tự xử.
  const dopChongLan = useCallback(async () => {
    if (
      !confirm(
        `Dọn tổ hợp KH × ngành hàng có nhiều PS chồng lấn theo bản đang hiệu lực tháng ${CURRENT_MONTH}:\n\n` +
          `  • Nếu chỉ 1 PS đang hiệu lực tại tháng đó → giữ PS đó, XOÁ các bản khác, ` +
          `và ghi PS này xuống dòng kế hoạch cả năm của tổ hợp.\n` +
          `  • Nếu vẫn ≥2 PS hiệu lực → bỏ qua, liệt kê để bạn tự xử.\n\n` +
          `Tiếp tục?`,
      )
    )
      return;
    setDiaBanBusy(true);
    setError('');
    try {
      const r = await api('dopChongLan', { thang: CURRENT_MONTH });
      const s = r.stats || {};
      const ap = s.apply || {};
      const amb = (s.ambiguous || []).length;
      await Promise.all([loadDiaBan(), loadData()]);
      setNotice(
        `Dọn xong: giữ ${s.resolved || 0} tổ hợp, xoá ${s.deleted || 0} bản dư, ${ap.updated_rows || 0} dòng kế hoạch đổi PS.` +
          (amb
            ? ` Còn ${amb} tổ hợp có ≥2 PS đang hiệu lực tại ${CURRENT_MONTH} — cần bạn quyết tay (xoá bản dư hoặc đổi PS).`
            : ' Hết chồng lấn.'),
      );
    } catch (err) {
      setError('Dọn chồng lấn thất bại: ' + err.message);
    } finally {
      setDiaBanBusy(false);
    }
  }, [loadDiaBan, loadData]);

  const deleteDiaBan = useCallback(
    async (ids) => {
      setDiaBanBusy(true);
      setError('');
      try {
        await api('deleteDiaBan', { ids });
        await loadDiaBan();
        setNotice(
          `Đã xóa ${ids.length} khai báo địa bàn (dòng kế hoạch giữ nguyên PS cũ đến khi bạn khai báo bản mới hoặc sửa tay).`,
        );
        return true;
      } catch (err) {
        setError('Xóa địa bàn thất bại: ' + diaBanErrMsg(err.message));
        return false;
      } finally {
        setDiaBanBusy(false);
      }
    },
    [loadDiaBan],
  );

  // Lưu vào shared.dm_ps (chỉ admin). Sau khi lưu tải lại psDir để mọi màn dùng tên
  // rút gọn mới. Không tự chạy map — nhắc user chạy "Cập nhật thực hiện" nếu muốn
  // số của PS này khớp lại dòng kế hoạch.
  // Sửa PS trong hoá đơn theo PS địa bàn (dòng OOP có ly_do='sai_ps'). Backend
  // update hoa_don_bovattu.ten_ps + map + refresh trong 1 transaction.
  // Sau khi xong: chỉ reload OOP list (nhẹ, không đụng ~20k dòng sale_target),
  // đặt stale=true để user biết số kế hoạch đã đổi và tự Reload khi cần.
  const [oopFixBusy, setOopFixBusy] = useState(false);
  const reloadOop = useCallback(async () => {
    try {
      const r = await api(
        'getOop',
        canSwitchTeam(auth.role) ? { bu: loadScope } : {},
      );
      const fld = fieldsRef.current;
      const oopArr = r.oopRows || [];
      const oopMeta = r.oopMeta || [];
      const oopObjs = new Array(oopArr.length);
      for (let i = 0; i < oopArr.length; i++) {
        const o = { _oop: true };
        for (let j = 0; j < fld.length; j++) {
          const v = oopArr[i][j];
          if (v !== '' && v !== null && v !== undefined) o[fld[j]] = v;
        }
        if (o.cust && o.cust !== OOP_CUST) {
          o.custRaw = o.cust;
          o.cust = custLabel(o.custId, o.cust);
        }
        const m = oopMeta[i];
        if (m) {
          if (m.ly_do) o._lyDo = m.ly_do;
          if (m.ps_dia_ban) o._psDiaBan = m.ps_dia_ban;
        }
        oopObjs[i] = o;
      }
      setOopRows(oopObjs);
      // sl_thuc_hien đã ghi lại ở sale_target -> rev đổi -> đánh dấu stale để user
      // tự bấm Reload thay vì mình load ngầm cả bảng lớn.
      if (typeof r.rev === 'number' && r.rev !== revRef.current) setStale(true);
    } catch (e) {}
  }, [auth.role, loadScope]);

  const suaPsHoaDon = useCallback(
    async (r) => {
      if (!r || !r._psDiaBan) return;
      if (
        !confirm(
          `Đổi PS trong hoá đơn ${r.ps || '?'} → ${r._psDiaBan} cho:\n` +
            `  Tháng ${r.mo} · ${fmtCust(r.cust) || r.custId} · ${r.grp || '?'}\n` +
            `  ${r.mset || ''} · ${r.prod || ''}\n\n` +
            `Sau đó map lại actual → số của tổ hợp này sẽ chuyển về dòng kế hoạch của ${r._psDiaBan}.`,
        )
      )
        return;
      setOopFixBusy(true);
      setError('');
      try {
        const res = await api('suaPsHoaDon', {
          thang: r.mo,
          maKh: r.custId,
          boVatTu: r.mset,
          sanPham: r.prod,
          psCu: r.ps,
          psMoi: r._psDiaBan,
        });
        const s = res.stats || {};
        await reloadOop();
        setNotice(
          `Đã sửa ${s.updated_hoa_don || 0} dòng hoá đơn sang PS "${s.ten_ps_moi || r._psDiaBan}"; ` +
            `map lại: khớp ${s.map?.matched_keys || 0}/${s.map?.total_keys || 0} khoá. ` +
            `Bấm Reload trên header để tải lại số kế hoạch.`,
        );
      } catch (err) {
        setError('Sửa PS hoá đơn thất bại: ' + err.message);
      } finally {
        setOopFixBusy(false);
      }
    },
    [reloadOop],
  );

  // Bulk: sửa TẤT CẢ dòng sai_ps theo PS địa bàn. Backend gom vào 1 lượt update
  // + 1 lần map + refresh — nhanh hơn nhiều so với gọi single N lần (mỗi lần
  // map zero toàn bộ tháng có trong hoá đơn rồi ghi lại).
  const suaPsHoaDonBulk = useCallback(
    async (rowsSaiPs) => {
      if (!rowsSaiPs.length) return;
      // Gom theo PS cũ → PS mới để confirm cho gọn.
      const grp = new Map();
      for (const r of rowsSaiPs) {
        if (!r._psDiaBan) continue;
        const k = (r.ps || '?') + ' → ' + r._psDiaBan;
        grp.set(k, (grp.get(k) || 0) + 1);
      }
      const brk = [...grp.entries()]
        .sort((a, b) => b[1] - a[1])
        .map(([k, v]) => `  ${v} dòng: ${k}`)
        .join('\n');
      if (
        !confirm(
          `Sửa ${rowsSaiPs.length} dòng hoá đơn theo PS địa bàn:\n\n${brk}\n\n` +
            `Sau đó map + refresh 1 lần. Số kế hoạch tương ứng sẽ chuyển sang PS địa bàn.`,
        )
      )
        return;
      setOopFixBusy(true);
      setError('');
      try {
        const payload = rowsSaiPs
          .filter((r) => r._psDiaBan)
          .map((r) => ({
            thang: r.mo,
            maKh: r.custId,
            boVatTu: r.mset,
            sanPham: r.prod,
            psCu: r.ps,
            psMoi: r._psDiaBan,
          }));
        const res = await api('suaPsHoaDonBulk', { rows: payload });
        const s = res.stats || {};
        await reloadOop();
        const thieu = (s.ps_khong_ton_tai || []).filter(Boolean);
        setNotice(
          `Đã sửa ${s.updated_hoa_don || 0} dòng hoá đơn; khớp ${s.map?.matched_keys || 0}/${s.map?.total_keys || 0} khoá. ` +
            (thieu.length
              ? `Bỏ qua ${thieu.length} PS chưa có trong dm_ps: ${thieu.join(', ')}. `
              : '') +
            `Bấm Reload trên header để tải lại số kế hoạch.`,
        );
      } catch (err) {
        setError('Sửa hàng loạt PS hoá đơn thất bại: ' + err.message);
      } finally {
        setOopFixBusy(false);
      }
    },
    [reloadOop],
  );

  const [fixBvtTarget, setFixBvtTarget] = useState(null);
  const handleFixBoVatTu = useCallback(
    (oopRow) => {
      const matches = rows.filter(
        (r) =>
          (r.custId || r.cust) === (oopRow.custId || oopRow.cust) &&
          r.prod === oopRow.prod &&
          r.mset !== oopRow.mset,
      );
      setFixBvtTarget({ oopRow, planMatches: matches });
    },
    [rows],
  );
  const applyFixBoVatTu = useCallback(
    async (planMatches, msetVal, prodVal) => {
      if (!planMatches.length) return;
      setOopFixBusy(true);
      setError('');
      try {
        const batch = [];
        for (const r of planMatches) {
          if (msetVal) batch.push({ row: r._row, key: 'mset', value: msetVal });
          if (prodVal) batch.push({ row: r._row, key: 'prod', value: prodVal });
        }
        if (!batch.length) return;
        await api('updateCells', { updates: batch });
        const patchByRow = new Map();
        batch.forEach((u) => {
          let p = patchByRow.get(u.row);
          if (!p) {
            p = {};
            patchByRow.set(u.row, p);
          }
          p[u.key] = u.value;
        });
        setRows((prev) =>
          prev.map((r) => {
            const p = patchByRow.get(r._row);
            return p ? { ...r, ...p } : r;
          }),
        );
        setFixBvtTarget(null);
        await reloadOop();
        setNotice(
          `Đã cập nhật ${planMatches.length} dòng kế hoạch: bộ VT → "${msetVal || '(giữ nguyên)'}"${prodVal ? `, SP → "${prodVal}"` : ''}.`,
        );
      } catch (err) {
        setError('Sửa bộ vật tư thất bại: ' + err.message);
      } finally {
        setOopFixBusy(false);
      }
    },
    [reloadOop],
  );

  const [psBusy, setPsBusy] = useState(false);
  const savePs = useCallback(
    async (row) => {
      setPsBusy(true);
      setError('');
      try {
        await api('savePs', row);
        const r = await api(
          'getPs',
          canSwitchTeam(auth.role) ? { bu: loadScope } : {},
        );
        setPsDir(r.ps || []);
        setNotice(
          `Đã lưu "${row.tenPs}" vào dm_ps (tên rút gọn: ${row.ps}). Chạy "Cập nhật thực hiện" để số của PS này khớp lại dòng kế hoạch.`,
        );
        return true;
      } catch (err) {
        setError('Lưu dm_ps thất bại: ' + err.message);
        return false;
      } finally {
        setPsBusy(false);
      }
    },
    [auth.role, loadScope],
  );

  // Ref cho dữ liệu addProduct cần đọc lúc gọi — để hàm addProduct giữ nguyên identity
  // (không tạo lại mỗi khi rows đổi, tránh render lại toàn bộ thẻ KH).
  const fieldsRef = useRef([]);
  useEffect(() => {
    fieldsRef.current = fields;
  }, [fields]);
  const custRawRef = useRef(new Map());
  // Thêm 1 sản phẩm (12 dòng T4→T3). Backend trả luôn các dòng vừa tạo -> chèn thẳng
  // vào state, KHÔNG tải lại toàn bộ ~23k dòng. Nếu Edge Function chưa deploy bản mới
  // (không có rows) thì fallback về loadData() như trước.
  const addProduct = useCallback(
    async (sel) => {
      setError('');
      try {
        // Ghi ĐÚNG tên KH đang có trong DB (custRaw) để không tạo ra 2 cách viết cho
        // cùng 1 khách hàng — pipeline import khớp theo chuỗi này.
        const raw = custRawRef.current.get(sel.custId || sel.cust);
        const res = await api('addProduct', raw ? { ...sel, cust: raw } : sel);
        const flds = fieldsRef.current;
        if (
          res &&
          Array.isArray(res.rows) &&
          Array.isArray(res.rowNums) &&
          flds.length
        ) {
          const objs = res.rows.map((row, i) => {
            const o = { _row: res.rowNums[i] };
            for (let j = 0; j < flds.length; j++) {
              const v = row[j];
              if (v !== '' && v !== null && v !== undefined) o[flds[j]] = v;
            }
            if (o.cust) {
              o.custRaw = o.cust;
              o.cust = custLabel(o.custId, o.cust);
            }
            return o;
          });
          setRows((prev) => prev.concat(objs));
          if (typeof res.rev === 'number') setDataRev(res.rev);
        } else {
          await loadData();
        }
        return true;
      } catch (err) {
        setError('Thêm sản phẩm thất bại: ' + err.message);
        return false;
      }
    },
    [loadData],
  );

  const bulkAddProducts = useCallback(
    async (oopList) => {
      const seen = new Set();
      const uniq = [];
      for (const r of oopList) {
        if (r._lyDo !== 'thieu_dong_ke_hoach') continue;
        const k = `${r.custId || ''}||${r.cust || ''}||${r.grp || ''}||${r.mset || ''}||${r.prod || ''}`;
        if (seen.has(k)) continue;
        seen.add(k);
        uniq.push(r);
      }
      if (!uniq.length) return;
      const n = uniq.length;
      if (
        !confirm(
          `Thêm ${n} sản phẩm thiếu vào kế hoạch?\n\nMỗi SP tạo 12 dòng (T4→T3), SL = 0.\nĐơn giá lấy từ hoá đơn thực hiện.`,
        )
      )
        return;
      setOopFixBusy(true);
      try {
        const items = uniq.map((r) => {
          const raw = custRawRef.current.get(r.custId || r.cust);
          return {
            ps: r._psDiaBan || r.ps,
            grp: r.grp,
            mset: r.mset || '',
            prod: r.prod,
            price: Number(r.price) || null,
            custId: r.custId || '',
            cust: raw || r.cust,
            region: r.region || '',
          };
        });
        const res = await api('addProducts', { items });
        const flds = fieldsRef.current;
        if (res && Array.isArray(res.rows) && Array.isArray(res.rowNums) && flds.length) {
          const objs = res.rows.map((row, i) => {
            const o = { _row: res.rowNums[i] };
            for (let j = 0; j < flds.length; j++) {
              const v = row[j];
              if (v !== '' && v !== null && v !== undefined) o[flds[j]] = v;
            }
            if (o.cust) {
              o.custRaw = o.cust;
              o.cust = custLabel(o.custId, o.cust);
            }
            return o;
          });
          if (objs.length) setRows((prev) => prev.concat(objs));
          if (typeof res.rev === 'number') setDataRev(res.rev);
        } else {
          await loadData();
        }
        const inserted = res?.rows?.length || 0;
        const skipped = res?.skipped || 0;
        if (skipped) setError(`Thêm SP thiếu: ${inserted / 12} mới, ${skipped} đã tồn tại`);
        if (inserted) await reloadOop();
      } catch (err) {
        setError('Thêm SP thiếu thất bại: ' + err.message);
      }
      setOopFixBusy(false);
    },
    [loadData],
  );

  // Warn on leaving with unsaved drafts
  const draftCount = Object.keys(drafts).length;
  useEffect(() => {
    const handler = (e) => {
      if (Object.keys(drafts).length > 0) {
        e.preventDefault();
        e.returnValue = '';
      }
    };
    window.addEventListener('beforeunload', handler);
    return () => window.removeEventListener('beforeunload', handler);
  }, [drafts]);

  // Persist drafts vào localStorage để không mất khi reload/token hết hạn.
  const draftStorageKey = 'sp_drafts_' + (auth.username || '');
  useEffect(() => {
    try {
      if (draftCount > 0)
        localStorage.setItem(draftStorageKey, JSON.stringify(drafts));
      else localStorage.removeItem(draftStorageKey);
    } catch {}
  }, [drafts, draftCount, draftStorageKey]);
  // Khôi phục drafts khi vừa tải xong dữ liệu lần đầu.
  const [draftRestored, setDraftRestored] = useState(false);
  useEffect(() => {
    if (draftRestored || initialLoading || !authed) return;
    setDraftRestored(true);
    try {
      const raw = localStorage.getItem(draftStorageKey);
      if (!raw) return;
      const saved = JSON.parse(raw);
      const keys = Object.keys(saved);
      if (keys.length === 0) return;
      if (
        confirm(
          `Có ${keys.length} thay đổi chưa lưu từ phiên trước. Khôi phục?`,
        )
      ) {
        setDrafts(saved);
      } else {
        localStorage.removeItem(draftStorageKey);
      }
    } catch {
      localStorage.removeItem(draftStorageKey);
    }
  }, [initialLoading, authed, draftRestored, draftStorageKey]);

  // Poll phát hiện dữ liệu thay đổi từ user khác (45s/lần) + version web app mới.
  const revRef = useRef(0);
  useEffect(() => {
    revRef.current = dataRev;
  }, [dataRev]);
  const draftRef = useRef(0);
  useEffect(() => {
    draftRef.current = draftCount;
  }, [draftCount]);
  // Version bản web app đang chạy — đọc từ /version.json (GitHub Actions ghi
  // mỗi lần deploy). Fetch lại khi user focus tab: nếu version khác = có bản
  // mới đã deploy → reload để user không kẹt ở bản cũ do cache.
  const currentVersionRef = useRef(null);
  const pendingReloadRef = useRef(false);
  useEffect(() => {
    pendingReloadRef.current = pendingReload;
  }, [pendingReload]);
  const fetchAppVersion = useCallback(async () => {
    try {
      const r = await fetch('version.json?_=' + Date.now(), {
        cache: 'no-store',
      });
      if (!r.ok) return null;
      const j = await r.json();
      return (j && j.version) || null;
    } catch {
      return null;
    }
  }, []);
  // Đọc version hiện tại 1 lần lúc app khởi động.
  useEffect(() => {
    fetchAppVersion().then((v) => {
      if (v) currentVersionRef.current = v;
    });
  }, [fetchAppVersion]);
  // Kiểm tra cả version web app + rev dữ liệu trong 1 lượt. Không có draft →
  // reload ngay; có draft → cắm cờ chờ, sẽ reload sau khi user lưu/huỷ để
  // không mất bản nháp.
  const parseChangedRows = useCallback(
    (r, fieldsArr) => {
      const arr = r.rows || [];
      const rowNums = r.rowNums || [];
      const rowRevs = r.rowRevs || [];
      const objs = [];
      for (let i = 0; i < arr.length; i++) {
        const row = arr[i];
        const o = { _row: rowNums[i] };
        for (let j = 0; j < fieldsArr.length; j++) {
          const v = row[j];
          if (v !== '' && v !== null && v !== undefined) o[fieldsArr[j]] = v;
        }
        if (o.cust) {
          o.custRaw = o.cust;
          o.cust = custLabel(o.custId, o.cust);
        }
        objs.push(o);
        if (rowNums[i] && rowRevs[i]) rowRevsRef.current.set(rowNums[i], rowRevs[i]);
      }
      return objs;
    },
    [],
  );
  const patchRowsFromChanges = useCallback(
    (changed, deletedIds) => {
      if (!changed.length && !deletedIds.length) return;
      const changedMap = new Map();
      for (const r of changed) if (r._row) changedMap.set(r._row, r);
      const delSet = new Set(deletedIds);
      setRows((prev) => {
        let next = prev;
        if (delSet.size) next = next.filter((r) => !delSet.has(r._row));
        if (changedMap.size) {
          const seen = new Set();
          next = next.map((r) => {
            const upd = changedMap.get(r._row);
            if (upd) { seen.add(r._row); return upd; }
            return r;
          });
          for (const [id, r] of changedMap) if (!seen.has(id)) next.push(r);
        }
        return next;
      });
    },
    [],
  );
  const checkForUpdates = useCallback(async () => {
    const v = await fetchAppVersion();
    if (v && currentVersionRef.current && v !== currentVersionRef.current) {
      if (draftRef.current === 0) {
        location.reload();
        return;
      }
      setPendingReload(true);
    }
    try {
      const scopePayload = canSwitchTeam(auth.role) ? { bu: loadScope } : {};
      const r = await api('getChanges', {
        sinceRev: revRef.current,
        ...scopePayload,
      });
      const hasChanges =
        (r.rows && r.rows.length) ||
        (r.oopRows && r.oopRows.length) ||
        (r.deleted && r.deleted.length);
      if (hasChanges) {
        if (draftRef.current === 0) {
          const changedRows = parseChangedRows(r, fields);
          patchRowsFromChanges(changedRows, r.deleted || []);
        } else {
          setStale(true);
        }
      }
      if (typeof r.maxRev === 'number') setDataRev(r.maxRev);
    } catch {
      try {
        const rc = await api(
          'getRev',
          canSwitchTeam(auth.role) ? { bu: loadScope } : {},
        );
        if (typeof rc.rev === 'number' && rc.rev !== revRef.current) {
          if (draftRef.current === 0) loadData();
          else setStale(true);
        }
      } catch {}
    }
  }, [fetchAppVersion, loadData, auth.role, loadScope, fields, parseChangedRows, patchRowsFromChanges]);
  checkForUpdatesRef.current = checkForUpdates;
  useEffect(() => {
    if (!authed) return;
    const onFocus = () => checkForUpdates();
    const onVis = () => {
      if (document.visibilityState === 'visible') checkForUpdates();
    };
    window.addEventListener('focus', onFocus);
    document.addEventListener('visibilitychange', onVis);
    // Vẫn giữ interval để phát hiện xung đột khi user để tab mở lâu, không focus.
    const id = setInterval(checkForUpdates, 45000);
    return () => {
      window.removeEventListener('focus', onFocus);
      document.removeEventListener('visibilitychange', onVis);
      clearInterval(id);
    };
  }, [authed, checkForUpdates]);

  // Accumulate edits into drafts (NOT sent yet)
  const commit = useCallback((updates) => {
    const arr = Array.isArray(updates) ? updates : [updates];
    setDrafts((prev) => {
      const next = {
        ...prev,
      };
      arr.forEach((u) => {
        next[`${u.row}:${u.key}`] = u.value;
      });
      return next;
    });
  }, []);

  // Xóa 1 sản phẩm (mọi dòng) — admin. Gọi thẳng backend (không qua drafts), rồi bỏ khỏi state.
  const deleteProduct = useCallback(async (rowIds) => {
    const ids = (rowIds || []).map(Number).filter(Number.isFinite);
    if (!ids.length) return;
    const idSet = new Set(ids);
    try {
      const res = await api('deleteProduct', { rows: ids });
      setRows((prev) => prev.filter((r) => !idSet.has(r._row)));
      setDrafts((prev) => {
        const next = {};
        for (const [k, v] of Object.entries(prev)) {
          if (!idSet.has(Number(k.split(':')[0]))) next[k] = v;
        }
        return next;
      });
      if (res && typeof res.rev === 'number') setDataRev(res.rev);
    } catch (err) {
      setError('Xóa thất bại: ' + err.message);
    }
  }, []);

  // Xóa TOÀN BỘ kế hoạch của 1 khách hàng — admin. Gom id từ rows (kể cả phần đang bị
  // bộ lọc ẩn) để xóa đúng những gì thẻ KH đại diện, không đoán theo tên/mã ở backend.
  const deleteCustomer = useCallback(
    async (targetCustId, customer) => {
      const ids = [];
      const prods = new Set();
      rows.forEach((r) => {
        const match = targetCustId
          ? r.custId === targetCustId
          : r.cust === customer || r.custRaw === customer;
        if (!match) return;
        if (Number.isFinite(r._row)) ids.push(r._row);
        if (r.prod) prods.add(`${r.grp}||${r.mset}||${r.prod}`);
      });
      if (!ids.length) return;
      if (
        !confirm(
          `Xóa TOÀN BỘ kế hoạch của "${customer}"?\n\n${prods.size} sản phẩm · ${ids.length} dòng sẽ bị xóa vĩnh viễn (gồm cả phần đang bị bộ lọc ẩn).\nKhông thể hoàn tác.`,
        )
      )
        return;
      const idSet = new Set(ids);
      try {
        const res = await api('deleteCustomer', { rows: ids });
        setRows((prev) => prev.filter((r) => !idSet.has(r._row)));
        setDrafts((prev) => {
          const next = {};
          for (const [k, v] of Object.entries(prev)) {
            if (!idSet.has(Number(k.split(':')[0]))) next[k] = v;
          }
          return next;
        });
        if (res && typeof res.rev === 'number') setDataRev(res.rev);
      } catch (err) {
        setError('Xóa khách hàng thất bại: ' + err.message);
      }
    },
    [rows],
  );

  const [conflicts, setConflicts] = useState([]);
  // Save all drafts to Sheet in one batch
  const saveDrafts = useCallback(async () => {
    const entries = Object.entries(drafts);
    if (entries.length === 0) return;
    setSaving(true);
    setError('');
    setConflicts([]);
    const batch = entries.map(([k, value]) => {
      const [row, key] = k.split(':');
      return {
        row: Number(row),
        key,
        value,
      };
    });
    const affectedRowIds = [...new Set(batch.map((u) => u.row))];
    const revMap = {};
    for (const id of affectedRowIds) {
      const rev = rowRevsRef.current.get(id);
      if (rev) revMap[id] = rev;
    }
    try {
      const res = await api('updateCells', {
        updates: batch,
        rowRevs: revMap,
      });
      const serverConflicts = res.conflicts || [];
      if (serverConflicts.length > 0) {
        setConflicts(serverConflicts);
        const conflictIds = new Set(serverConflicts.map((c) => c.id));
        const resolved = {};
        for (const [k, v] of entries) {
          const rowId = Number(k.split(':')[0]);
          if (conflictIds.has(rowId)) resolved[k] = v;
        }
        setDrafts(resolved);
        const patchByRow = new Map();
        batch.forEach((u) => {
          if (conflictIds.has(u.row)) return;
          let p = patchByRow.get(u.row);
          if (!p) { p = {}; patchByRow.set(u.row, p); }
          p[u.key] = u.value;
        });
        if (patchByRow.size) {
          setRows((prev) =>
            prev.map((r) => {
              const p = patchByRow.get(r._row);
              return p ? { ...r, ...p } : r;
            }),
          );
        }
        for (const c of serverConflicts) {
          if (c._rev) rowRevsRef.current.set(c.id, c._rev);
        }
        setError(
          `${serverConflicts.length} dòng bị xung đột — người khác đã sửa trước bạn. ` +
            'Chọn "Giữ của tôi" hoặc "Lấy bản mới" cho từng dòng, rồi Lưu lại.',
        );
      } else {
        const patchByRow = new Map();
        batch.forEach((u) => {
          let p = patchByRow.get(u.row);
          if (!p) { p = {}; patchByRow.set(u.row, p); }
          p[u.key] = u.value;
        });
        setRows((prev) =>
          prev.map((r) => {
            const p = patchByRow.get(r._row);
            return p ? { ...r, ...p } : r;
          }),
        );
        setDrafts({});
        setSavedFlash(true);
        setTimeout(() => setSavedFlash(false), 2000);
        if (pendingReloadRef.current) {
          setTimeout(() => location.reload(), 600);
          setSaving(false);
          return;
        }
      }
      if (typeof res.rev === 'number') setDataRev(res.rev);
      setStale(false);
    } catch (err) {
      setError(
        err.message === 'forbidden_rows'
          ? 'Lưu thất bại: có dòng không thuộc phạm vi của bạn hoặc đã bị xóa ở nơi khác. Chưa có thay đổi nào được ghi — hãy Reload rồi nhập lại.'
          : 'Lưu thất bại: ' +
              err.message +
              '. Các thay đổi vẫn được giữ, thử lại.',
      );
    }
    setSaving(false);
  }, [drafts]);
  const discardDrafts = () => {
    if (!confirm('Hủy tất cả thay đổi chưa lưu?')) return;
    setDrafts({});
    setConflicts([]);
    if (pendingReloadRef.current) setTimeout(() => location.reload(), 100);
  };
  const resolveConflict = useCallback(
    (rowId, choice) => {
      if (choice === 'take-server') {
        const c = conflicts.find((x) => x.id === rowId);
        if (c && c.values) {
          setRows((prev) =>
            prev.map((r) => (r._row === rowId ? { ...r, ...c.values } : r)),
          );
        }
        setDrafts((prev) => {
          const next = {};
          for (const [k, v] of Object.entries(prev)) {
            if (Number(k.split(':')[0]) !== rowId) next[k] = v;
          }
          return next;
        });
      }
      setConflicts((prev) => prev.filter((x) => x.id !== rowId));
    },
    [conflicts],
  );

  // effective rows overlay drafts
  const effectiveRows = useMemo(() => {
    if (draftCount === 0) return rows;
    const patchByRow = new Map();
    for (const [k, v] of Object.entries(drafts)) {
      const i = k.indexOf(':');
      const id = Number(k.slice(0, i));
      let p = patchByRow.get(id);
      if (!p) patchByRow.set(id, (p = {}));
      p[k.slice(i + 1)] = v;
    }
    return rows.map((r) => {
      const p = patchByRow.get(r._row);
      return p ? { ...r, ...p } : r;
    });
  }, [rows, drafts, draftCount]);
  // Client-side team filter: chuyển team thật = instant, không reload.
  const teamRows = useMemo(() => {
    if (!viewBu || viewBu === 'test') return effectiveRows;
    return effectiveRows.filter((r) => r.bu === viewBu);
  }, [effectiveRows, viewBu]);
  // Dữ liệu cho 2 MÀN TỔNG HỢP: kế hoạch + dòng ngoài kế hoạch (để tổng đủ số).
  // Màn chi tiết, export, sửa/xoá vẫn dùng teamRows -> không thấy các dòng này.
  const summaryRows = useMemo(
    () =>
      oopRows.length
        ? teamRows.concat(
            oopRows.filter(
              (r) => !viewBu || viewBu === 'test' || r.bu === viewBu,
            ),
          )
        : teamRows,
    [teamRows, oopRows, viewBu],
  );
  const draftKeys = useMemo(() => new Set(Object.keys(drafts)), [drafts]);
  const regionList = useMemo(
    () =>
      Array.from(new Set(teamRows.map((r) => r.region).filter(Boolean))).sort(),
    [teamRows],
  );
  const psList = useMemo(() => {
    const s = new Set();
    teamRows.forEach((r) => {
      if (inSel(regionFilter, r.region) && r.ps) s.add(r.ps);
    });
    return Array.from(s).sort();
  }, [teamRows, regionFilter]);
  const allGroups = useMemo(() => {
    const s = new Set();
    teamRows.forEach((r) => {
      if (!inSel(regionFilter, r.region)) return;
      if (!inSel(psFilter, r.ps)) return;
      if (r.grp) s.add(r.grp);
    });
    return Array.from(s).sort();
  }, [teamRows, psFilter, regionFilter]);
  const custList = useMemo(() => {
    const m = new Map();
    teamRows.forEach((r) => {
      if (!inSel(regionFilter, r.region)) return;
      if (!inSel(psFilter, r.ps)) return;
      if (r.cust && !m.has(r.cust)) m.set(r.cust, r.custId);
    });
    return Array.from(m.entries())
      .map(([cust, id]) => ({
        cust,
        id,
      }))
      .sort((a, b) => a.cust.localeCompare(b.cust));
  }, [rows, psFilter, regionFilter]);
  // Chỉ số khách hàng đang có kế hoạch (không phụ thuộc bộ lọc). Gộp 3 việc vào 1 vòng
  // lặp qua rows (~23k dòng): đếm cho header, tra tên gốc trong DB, và kiểm tra KH đã có.
  const custIndex = useMemo(() => {
    const raw = new Map(); // custId (hoặc tên hiển thị) -> tên gốc trong DB
    const has = new Set(); // tên hiển thị + mã KH -> panel "Thêm khách hàng" báo trùng
    rows.forEach((r) => {
      if (!r.cust) return;
      const k = r.custId || r.cust;
      if (raw.has(k)) return;
      raw.set(k, r.custRaw || r.cust);
      has.add(r.cust);
      if (r.custId) has.add(r.custId);
    });
    return { raw, has, count: raw.size };
  }, [rows]);
  const totalCustCount = custIndex.count;
  useEffect(() => {
    custRawRef.current = custIndex.raw;
  }, [custIndex]);
  // Chỉ số danh mục SP dựng 1 lần cho mọi form thêm sản phẩm.
  const catIdx = useMemo(() => buildCatalogIndex(catalog), [catalog]);
  // PS → miền + nhóm SP mà PS đó đang phụ trách, suy từ chính dữ liệu kế hoạch.
  // rows đã được backend lọc theo quyền/team đang xem nên đây luôn là "trong cùng BU"
  // (chỉ khi admin xem TẤT CẢ team, 1 tên PS trùng ở 2 team mới bị gộp).
  // Dùng cho: panel thêm KH tự điền miền, và form thêm SP giới hạn nhóm SP theo PS.
  const { regionsByPs, groupsByPs } = useMemo(() => {
    const reg = new Map();
    const grpPs = new Map(); // ps → nhóm PS đã có plan (fallback khi thiếu mapping)
    const bump = (m, k, v) => {
      let s = m.get(k);
      if (!s) {
        s = new Set();
        m.set(k, s);
      }
      s.add(v);
    };
    rows.forEach((r) => {
      if (!r.ps) return;
      if (r.region) bump(reg, r.ps, r.region);
      if (r.grp) bump(grpPs, r.ps, r.grp);
    });
    const regions = new Map(
      Array.from(reg, ([k, v]) => [k, Array.from(v).sort()]),
    );
    // dm_ps.area là miền chính thức của PS → đè lên phần suy từ kế hoạch (dữ liệu
    // cũ có thể để PS ở 2 miền, khi đó panel thêm KH đang bắt chọn tay).
    psDir.forEach((p) => {
      if (p.ps && p.mien) regions.set(p.ps, [p.mien]);
    });
    // Nhóm SP cho form thêm SP: lấy từ dm_bo_vat_tu_mapping (chuẩn danh mục) theo
    // BU của PS. Không phụ thuộc rows kế hoạch → PS mới/chưa có plan vẫn thấy đủ
    // nhóm. Ghép qua psDir[i].buLabel (nhãn dài "CH&CS") = catalog.bu.
    const grpsByBuLabel = (catIdx && catIdx.grpsByBuLabel) || new Map();
    const groups = new Map();
    psDir.forEach((p) => {
      if (!p.ps) return;
      const pool = p.buLabel ? grpsByBuLabel.get(p.buLabel) : null;
      const s = new Set(pool || []);
      const own = grpPs.get(p.ps);
      if (own) own.forEach((g) => s.add(g)); // phòng nhóm trong plan chưa có trong danh mục
      if (s.size) groups.set(p.ps, s);
    });
    // PS không có trong dm_ps: fallback nhóm PS đã có plan.
    grpPs.forEach((s, ps) => {
      if (!groups.has(ps)) groups.set(ps, s);
    });
    return { regionsByPs: regions, groupsByPs: groups };
  }, [rows, psDir, catIdx]);
  // KH vừa thêm nhưng chưa có sản phẩm nào -> chỉ nằm ở client (xem NewCustomerCard).
  const [newCusts, setNewCusts] = useState([]);
  const pendingCusts = useMemo(
    () =>
      newCusts.filter(
        (c) =>
          !custIndex.has.has(custLabel(c.custId, c.cust)) &&
          !(c.custId && custIndex.has.has(c.custId)),
      ),
    [newCusts, custIndex],
  );
  const addCustomer = useCallback((c) => {
    setNewCusts((prev) =>
      prev.some((x) => (x.custId || x.cust) === (c.custId || c.cust))
        ? prev
        : prev.concat(c),
    );
  }, []);
  // Tên PS có trong danh mục dm_ps (chuẩn hoá lower/trim). Rỗng = chưa tải được
  // danh mục → mọi nơi phải coi như "không kiểm tra", đừng báo động nhầm.
  // PS nằm trong kế hoạch mà KHÔNG có trong tập này là lệch tên với danh mục:
  // hoá đơn của họ được dịch ten_ps → ps theo dm_ps nên sẽ không bao giờ khớp
  // dòng kế hoạch, toàn bộ số rơi sang "ngoài kế hoạch" mà không có lỗi nào báo.
  const psKnown = useMemo(
    () =>
      new Set(
        psDir
          .map((p) =>
            String(p.ps || '')
              .trim()
              .toLowerCase(),
          )
          .filter(Boolean),
      ),
    [psDir],
  );
  // Danh sách PS cho mọi dropdown: DANH MỤC dm_ps là nguồn chính (PS mới chưa có
  // dòng kế hoạch nào vẫn khai báo địa bàn được), cộng thêm PS đang có trong kế
  // hoạch nhưng chưa có trong danh mục để không mất khả năng sửa dữ liệu cũ.
  // PS Inactive vẫn giữ nếu họ còn dòng kế hoạch (doanh số lịch sử thuộc về họ).
  const allPsList = useMemo(() => {
    const inPlan = new Set(rows.map((r) => r.ps).filter(Boolean));
    const s = new Set(inPlan);
    psDir.forEach((p) => {
      if (p.ps && (p.active || inPlan.has(p.ps))) s.add(p.ps);
    });
    return Array.from(s).sort();
  }, [rows, psDir]);
  // Đơn giá gợi ý khi thêm sản phẩm. Danh mục (dm_bo_vat_tu / _mapping) KHÔNG có
  // cột đơn giá — giá chỉ nằm trên từng dòng sale_target, nên lấy theo giá đang
  // dùng nhiều nhất cho đúng (nhóm | bộ vật tư | sản phẩm) đó.
  const priceOf = useMemo(() => {
    const cnt = new Map(); // key -> Map(giá -> số dòng)
    for (const r of rows) {
      const p = Number(r.price) || 0;
      if (!p || !r.prod) continue;
      const k = `${r.grp || ''}||${r.mset || ''}||${r.prod}`;
      let m = cnt.get(k);
      if (!m) {
        m = new Map();
        cnt.set(k, m);
      }
      m.set(p, (m.get(p) || 0) + 1);
    }
    const best = new Map();
    cnt.forEach((m, k) => {
      let top = null,
        n = -1;
      m.forEach((c, p) => {
        if (c > n) {
          n = c;
          top = p;
        }
      });
      best.set(k, top);
    });
    return (grp, mset, prod) =>
      best.get(`${grp || ''}||${mset || ''}||${prod}`) || null;
  }, [rows]);
  // Ngành hàng để khai báo địa bàn: gộp danh mục SP + kế hoạch + khai báo đã có,
  // vì có thể phải gán một ngành hàng chưa từng xuất hiện trong kế hoạch.
  const allGroupNames = useMemo(() => {
    const s = new Set();
    catalog.forEach((c) => {
      if (c.grp) s.add(c.grp);
    });
    rows.forEach((r) => {
      if (r.grp) s.add(r.grp);
    });
    diaBan.forEach((d) => {
      if (d.grp) s.add(d.grp);
    });
    return Array.from(s).sort();
  }, [catalog, rows, diaBan]);
  // PS → Miền. Ưu tiên dm_ps.area (câu trả lời dứt khoát, có cả cho PS chưa có dòng
  // kế hoạch); chỉ khi PS không có trong danh mục mới suy từ kế hoạch, và chỉ nhận
  // khi PS đó thuộc đúng 1 miền. Backend suy lại y hệt khi lưu nên client không
  // quyết được miền — map này chỉ để hiển thị.
  const mienByPs = useMemo(() => {
    const m = new Map();
    regionsByPs.forEach((regs, ps) => {
      if (regs.length === 1) m.set(ps, regs[0]);
    });
    psDir.forEach((p) => {
      if (p.ps && p.mien) m.set(p.ps, p.mien);
    });
    return m;
  }, [regionsByPs, psDir]);
  // Địa bàn theo khách hàng → panel "Thêm khách hàng" tự điền PS/Miền đã khai báo.
  const diaBanByCust = useMemo(() => {
    const m = new Map();
    diaBan.forEach((d) => {
      if (d.active === false) return;
      const k = dbCustKey(d.custId, d.cust);
      if (!k) return;
      let e = m.get(k);
      if (!e) {
        e = { ps: new Set(), mien: new Set() };
        m.set(k, e);
      }
      if (d.ps) e.ps.add(d.ps);
      if (d.mien) e.mien.add(d.mien);
    });
    return new Map(
      Array.from(m, ([k, v]) => [
        k,
        {
          ps: Array.from(v.ps).sort(),
          mien: Array.from(v.mien).sort(),
        },
      ]),
    );
  }, [diaBan]);
  // Nguồn KH cho panel thêm SP: ưu tiên dm_khach_hang (getCustomers); nếu backend chưa
  // deploy action này thì tạm fallback về danh sách KH suy ra từ dữ liệu hiện có.
  const custSource = useMemo(() => {
    if (customers.length) return customers;
    const m = new Map();
    rows.forEach((r) => {
      const k = r.custId || r.cust;
      if (r.cust && !m.has(k))
        m.set(k, { cust: r.cust, custId: r.custId || '' });
    });
    return Array.from(m.values()).sort((a, b) => a.cust.localeCompare(b.cust));
  }, [customers, rows]);
  // Thêm khách hàng: chỉ ở màn chi tiết, cần quyền sửa + có danh mục để chọn
  const canAddCust =
    canEdit && catalog.length > 0 && custSource.length > 0 && tab === 'detail';
  const closeAddCust = useCallback(() => setAddCustOpen(false), []);
  useEffect(() => {
    setAddCustOpen(false);
  }, [tab]); // đổi tab thì đóng popup, khỏi bật lại lúc quay về
  const tree = useMemo(() => {
    const q = deaccent(deferredSearch.trim());
    const byCust = new Map();
    for (const r of teamRows) {
      if (!inSel(regionFilter, r.region)) continue;
      if (!inSel(psFilter, r.ps)) continue;
      if (!inSel(custFilter, r.cust)) continue;
      if (!inSel(groupFilter, r.grp)) continue;
      if (
        q &&
        !(
          deaccent(r.cust).includes(q) ||
          deaccent(r.prod).includes(q) ||
          deaccent(r.custId).includes(q) ||
          deaccent(r.mset).includes(q)
        )
      )
        continue;
      const cKey = r.custId || r.custRaw || r.cust || '—';
      if (!byCust.has(cKey))
        byCust.set(cKey, {
          customer: r.cust || '—',
          custId: r.custId,
          region: r.region,
          psSet: new Set(),
          buSet: new Set(),
          gMap: new Map(),
        });
      const c = byCust.get(cKey);
      if (r.ps) c.psSet.add(r.ps);
      if (r.bu) c.buSet.add(r.bu);
      const grpName = r.grp || 'Khác';
      // Tách theo (nhóm SP, PS): 1 nhóm SP mà 2 PS cùng phụ trách → 2 dòng độc lập, không gộp.
      const gKey = grpName + '||' + (r.ps || '');
      if (!c.gMap.has(gKey))
        c.gMap.set(gKey, {
          name: grpName,
          ps: r.ps,
          aprRow: null,
          pMap: new Map(),
        });
      const g = c.gMap.get(gKey);
      if (!g.ps && r.ps) g.ps = r.ps;
      if (r.mo === getNoteMonth()) {
        if (g.aprRow == null) g.aprRow = r._row;
      }
      // key product by (mset, prod, price) so same product with different đơn giá stays separate
      const msKey = r.mset || NO_MSET;
      const prKey = Number(r.price) || 0;
      const pKey = msKey + '||' + (r.prod || '—') + '||' + prKey;
      if (!g.pMap.has(pKey))
        g.pMap.set(pKey, {
          mset: msKey,
          product: r.prod || '—',
          pPrice: prKey,
          monthly: Array.from(
            {
              length: 12,
            },
            () => ({
              rev: 0,
              dt: 0,
              revUpd: 0,
              act: 0,
              hasUpd: false,
              hasAct: false,
              rows: [],
            }),
          ),
        });
      const p = g.pMap.get(pKey);
      const idx = MONTHS.indexOf(r.mo);
      if (idx >= 0) {
        const cell = p.monthly[idx];
        cell.rows.push(r);
        cell.rev += Number(r.rev) || 0;
        cell.dt += Number(r.dt) || 0;
        cell.act += Number(r.act) || 0;
        if ((Number(r.act) || 0) !== 0) {
          cell.hasAct = true;
        }
        if (r.revUpd !== undefined && r.revUpd !== '' && r.revUpd !== null) {
          cell.hasUpd = true;
          cell.revUpd += Number(r.revUpd) || 0;
        }
      }
    }
    const custDt = (c) => {
      let dt = 0;
      c.gMap.forEach((g) =>
        g.pMap.forEach((p) => {
          p.monthly.forEach((cell) =>
            cell.rows.forEach((r) => {
              dt += (Number(r.rev) || 0) * (Number(r.price) || 0);
            }),
          );
        }),
      );
      return dt;
    };
    // DThu KH update (giống stats.dtUpd): tháng đã qua lấy thực hiện, tháng còn lại lấy SL update (nếu có) hoặc SL đầu năm.
    const custDtUpd = (c) => {
      let v = 0;
      c.gMap.forEach((g) =>
        g.pMap.forEach((p) => {
          p.monthly.forEach((cell, i) => {
            cell.rows.forEach((r) => {
              const pr = Number(r.price) || 0;
              const act = Number(r.act) || 0;
              const dtActR = Number(r.dtAct) || 0;
              const useAct =
                MONTHS[i] < CURRENT_MONTH ||
                (MONTHS[i] === CURRENT_MONTH && act !== 0);
              const upd = useAct
                ? act
                : r.revUpd !== undefined && r.revUpd !== '' && r.revUpd !== null
                  ? Number(r.revUpd) || 0
                  : Number(r.rev) || 0;
              v += upd * pr;
            });
          });
        }),
      );
      return v;
    };
    // DThu thực hiện luỹ kế YTD (đến hết tháng hiện tại).
    const custThYtd = (c) => {
      let v = 0;
      c.gMap.forEach((g) =>
        g.pMap.forEach((p) => {
          p.monthly.forEach((cell, i) => {
            if (!isYtdMonth(MONTHS[i])) return;
            cell.rows.forEach((r) => {
              v += Number(r.dtAct) || 0;
            });
          });
        }),
      );
      return v;
    };
    return Array.from(byCust.values())
      .map((c) => ({
        customer: c.customer,
        custId: c.custId,
        region: c.region,
        psList: Array.from(c.psSet),
        buList: Array.from(c.buSet),
        _dt: custDt(c),
        _dtUpd: custDtUpd(c),
        _thYtd: custThYtd(c),
        groups: Array.from(c.gMap.values())
          .map((g) => {
            const products = Array.from(g.pMap.values()); // hiện mọi SP, kể cả DThu = 0 (SP mới thêm)
            products.sort(
              (a, b) =>
                (a.mset || '').localeCompare(b.mset || '') ||
                (a.product || '').localeCompare(b.product || '') ||
                (a.pPrice || 0) - (b.pPrice || 0),
            );
            let gdt = 0;
            products.forEach((p) =>
              p.monthly.forEach((cell) =>
                cell.rows.forEach((r) => {
                  gdt += (Number(r.rev) || 0) * (Number(r.price) || 0);
                }),
              ),
            );
            return {
              name: g.name,
              ps: g.ps,
              aprRow: g.aprRow,
              products,
              _dt: gdt,
            };
          })
          .filter((g) => g.products.length > 0)
          .sort((a, b) => b._dt - a._dt),
      }))
      .filter((c) => c.groups.length > 0)
      .sort((a, b) => {
        // Ngoài KH luôn xuống cuối
        const oa = a.customer === OOP_CUST ? 1 : 0,
          ob = b.customer === OOP_CUST ? 1 : 0;
        if (oa !== ob) return oa - ob;
        // Có DThu KH update xếp trước (giảm dần theo KH update); không có thì xếp sau (giảm dần theo TH YTD)
        const ha = a._dtUpd > 0 ? 0 : 1,
          hb = b._dtUpd > 0 ? 0 : 1;
        if (ha !== hb) return ha - hb;
        return ha === 0 ? b._dtUpd - a._dtUpd : b._thYtd - a._thYtd;
      });
  }, [
    teamRows,
    deferredSearch,
    psFilter,
    regionFilter,
    custFilter,
    groupFilter,
    curMonth,
  ]);
  // Đo sau khi đã đăng nhập + tải xong (trước đó App return sớm, chưa có thanh
  // tiêu đề/bộ lọc trong DOM) và đo lại khi danh sách KH đổi từ rỗng sang có
  // (thẻ KH đầu tiên mới xuất hiện thì mới đo được chiều cao của nó).
  useStickyBars(authed && !initialLoading && tab === 'detail', tree.length > 0);
  const stats = useMemo(() => {
    let plan = 0,
      dt = 0,
      dtUpd = 0,
      dtYtd = 0, // DThu thực hiện luỹ kế YTD (chỉ trong KH)
      khYtdDt = 0, // DThu KH update luỹ kế YTD (mẫu số của % TH YTD, chỉ trong KH)
      productCount = 0;
    tree.forEach((c) =>
      c.groups.forEach((g) => {
        productCount += g.products.length;
        g.products.forEach((p) => {
          p.monthly.forEach((cell, i) => {
            plan += cell.rev;
            const inYtd = MONTHS[i] <= CURRENT_MONTH;
            cell.rows.forEach((r) => {
              const pr = Number(r.price) || 0;
              const rev = Number(r.rev) || 0;
              const act = Number(r.act) || 0;
              const dtActR = Number(r.dtAct) || 0;
              const rawUpd =
                r.revUpd !== undefined && r.revUpd !== '' && r.revUpd !== null
                  ? Number(r.revUpd) || 0
                  : rev;
              const useAct =
                MONTHS[i] < CURRENT_MONTH ||
                (MONTHS[i] === CURRENT_MONTH && act !== 0);
              dt += rev * pr;
              dtUpd += useAct ? act * pr : rawUpd * pr;
              if (inYtd) {
                dtYtd += dtActR;
                khYtdDt += rawUpd * pr;
              }
            });
          });
        });
      }),
    );
    // Cộng thêm phần THỰC HIỆN NGOÀI KẾ HOẠCH (oopRows) để thẻ tiền khớp với TỔNG CỘNG
    // ở 2 màn tổng hợp — dùng ĐÚNG bộ lọc & công thức như SummaryView.
    const q = search.toLowerCase().trim();
    const oopFiltered =
      viewBu && viewBu !== 'test'
        ? oopRows.filter((r) => r.bu === viewBu)
        : oopRows;
    for (const r of oopFiltered) {
      if (MONTHS.indexOf(r.mo) < 0) continue;
      if (!inSel(regionFilter, r.region)) continue;
      if (!inSel(psFilter, r.ps)) continue;
      if (!inSel(custFilter, r.cust)) continue;
      if (!inSel(groupFilter, r.grp)) continue;
      if (!matchSearch(r, q)) continue;
      const pr = Number(r.price) || 0;
      const act = Number(r.act) || 0;
      const dtActR = Number(r.dtAct) || 0;
      const past =
        (r.mo || '') < CURRENT_MONTH ||
        ((r.mo || '') === CURRENT_MONTH && act !== 0);
      const inYtd = isYtdMonth(r.mo);
      const rev = Number(r.rev) || 0;
      const rawUpd =
        r.revUpd !== undefined && r.revUpd !== '' && r.revUpd !== null
          ? Number(r.revUpd) || 0
          : rev;
      dt += rev * pr;
      dtUpd += past ? act * pr : rawUpd * pr;
      if (inYtd) {
        dtYtd += dtActR;
      }
    }
    return {
      plan,
      dt,
      dtUpd,
      dtYtd,
      khYtdDt,
      chenh: dtUpd - dt,
      customers: tree.length,
      productCount,
    };
  }, [
    tree,
    oopRows,
    viewBu,
    regionFilter,
    psFilter,
    custFilter,
    groupFilter,
    search,
    curMonth,
  ]);

  // Đối chiếu thực hiện: gom oopRows theo ly_do — cảnh báo tổng để người cấu hình
  // biết cần sửa gì. Lọc theo bộ lọc chung (miền/PS/nhóm SP/KH) để khớp với ngữ
  // cảnh đang xem. KH được gom theo (mã KH hoặc tên) như planCustKeys.
  const oopByReason = useMemo(() => {
    const acc = new Map();
    const cnt = new Map(); // ly_do -> {rows, dt, custs:Set}
    for (const r of oopRows) {
      if (!inSel(regionFilter, r.region)) continue;
      if (!inSel(psFilter, r.ps)) continue;
      if (!inSel(groupFilter, r.grp)) continue;
      const ly = r._lyDo || 'unknown';
      let a = cnt.get(ly);
      if (!a) {
        a = { rows: 0, dt: 0, custs: new Set() };
        cnt.set(ly, a);
      }
      a.rows++;
      a.dt += Number(r.dtAct) || 0;
      a.custs.add(r.custId ? '#' + r.custId : '@' + (r.cust || ''));
    }
    for (const [ly, a] of cnt) acc.set(ly, { ...a, custCount: a.custs.size });
    return acc;
  }, [oopRows, regionFilter, psFilter, groupFilter]);
  const oopTotal = useMemo(() => {
    let n = 0;
    oopByReason.forEach((a) => (n += a.rows));
    return n;
  }, [oopByReason]);
  // Dòng OOP lọc theo bộ lọc chung (miền/PS/nhóm/KH) — modal chi tiết dùng cái này.
  // Không lọc theo search vì search chỉ áp cho màn Chi tiết.
  const oopRowsFiltered = useMemo(
    () =>
      oopRows.filter(
        (r) =>
          inSel(regionFilter, r.region) &&
          inSel(psFilter, r.ps) &&
          inSel(groupFilter, r.grp) &&
          inSel(custFilter, r.cust),
      ),
    [oopRows, regionFilter, psFilter, groupFilter, custFilter],
  );
  // Modal "Đối chiếu ngoài kế hoạch — chi tiết": null = đóng, 'all' = mọi lý do,
  // 'chua_co_dia_ban' | 'sai_ps' | ... = đúng 1 lý do (lọc sẵn).
  const [oopDetailReason, setOopDetailReason] = useState(null);
  // Điền sẵn form "Thêm sản phẩm" khi cross-tab từ modal OOP → tab Chi tiết.
  // Đặt {custId, cust, grp, ps, prod, mset} rồi setTab('detail') — AddCustomerModal
  // đọc state này và tự mở với dữ liệu đã điền.
  const [addProductPrefill, setAddProductPrefill] = useState(null);
  // Modal "Danh mục PS" (dm_ps) — dành cho ly_do='ps_la'. null = đóng, {} = thêm mới,
  // { ten_ps } = sửa bản có sẵn.
  const [dmpsForm, setDmpsForm] = useState(null);
  // Prefill cho DiaBanView khi jump từ modal OOP:
  //   purpose='add'    — điền form Thêm địa bàn (chua_co_dia_ban)
  //   purpose='chuyen' — tìm/highlight KH đó (sai_ps — chuyển PS ở bản khai báo hiện có)
  const [diaBanPrefill, setDiaBanPrefill] = useState(null);
  const [showMissing, setShowMissing] = useState(false);

  // Mẫu số của thẻ "Số lượng account": số khách hàng ĐƯỢC PHÂN CHIA theo cấu hình
  // địa bàn (dm_dia_ban), lọc theo đúng bộ lọc đang áp dụng cho tử số (KH có kế hoạch).
  const accountsAssigned = useMemo(() => {
    const q = deaccent(search.trim());
    const set = new Set();
    for (const d of diaBan) {
      if (viewBu && viewBu !== 'test' && d.bu && d.bu !== viewBu) continue;
      const ps = d.ps;
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
      set.add(dbCustKey(d.custId, d.cust));
    }
    return set.size;
  }, [
    diaBan,
    mienByPs,
    viewBu,
    regionFilter,
    psFilter,
    groupFilter,
    custFilter,
    search,
  ]);

  const missingAccounts = useMemo(() => {
    const planKeys = new Set(tree.map((c) => dbCustKey(c.custId, c.customer)));
    const q = deaccent(search.trim());
    const map = new Map();
    for (const d of diaBan) {
      if (viewBu && viewBu !== 'test' && d.bu && d.bu !== viewBu) continue;
      const ps = d.ps;
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
      const k = dbCustKey(d.custId, d.cust);
      if (planKeys.has(k)) continue;
      if (!map.has(k))
        map.set(k, {
          custId: d.custId,
          cust: d.cust,
          ps: new Set(),
          grp: new Set(),
        });
      const e = map.get(k);
      if (d.ps) e.ps.add(d.ps);
      if (d.grp) e.grp.add(d.grp);
    }
    return Array.from(map.values())
      .map((e) => ({
        custId: e.custId,
        cust: e.cust,
        ps: Array.from(e.ps).sort().join(', '),
        grp: Array.from(e.grp).sort().join(', '),
      }))
      .sort((a, b) => (a.cust || '').localeCompare(b.cust || ''));
  }, [
    tree,
    diaBan,
    mienByPs,
    viewBu,
    regionFilter,
    psFilter,
    groupFilter,
    custFilter,
    search,
  ]);

  // nhãn cột giống Google Sheet, theo field key
  const FIELD_LABEL = {
    fy: 'Năm tài chính',
    mo: 'Tháng Kế hoạch',
    region: 'Miền',
    ps: 'PS',
    cust: 'Khách hàng',
    custId: 'Mã Khách hàng',
    grp: 'Nhóm sản phẩm',
    prod: 'Sản phẩm',
    mset: 'Bộ vật tư',
    mcnt: 'Bộ',
    qOld: 'Quota Thầu cũ còn lại',
    mMain: 'Tháng Thầu chính',
    dMain: 'Thời gian Thầu chính',
    qMain: 'Quota Thầu chính',
    mAdd: 'Tháng Thầu bổ sung',
    qAdd: 'Quota thầu bổ sung',
    rev: 'SL Kế hoạch đầu năm',
    price: 'Đơn giá',
    dt: 'DT',
    upd: 'Đã cập nhật',
    ytd: 'Thực hiện YTD',
    revUpd: 'SL Kế hoạch Update',
    act: 'SL thực hiện',
  };
  const exportCsv = () => {
    const cols =
      fields && fields.length
        ? fields
        : [
            'fy',
            'mo',
            'region',
            'ps',
            'cust',
            'custId',
            'grp',
            'prod',
            'mset',
            'qOld',
            'mMain',
            'qMain',
            'mAdd',
            'qAdd',
            'ytd',
            'rev',
            'revUpd',
            'act',
            'price',
            'dt',
          ];
    const header = cols.map((f) => FIELD_LABEL[f] || f);
    const esc = (v) => {
      if (v == null) return '';
      const s = String(v).replace(/"/g, '""');
      return /[",\n]/.test(s) ? `"${s}"` : s;
    };
    const lines = teamRows
      .filter(
        (r) =>
          inSel(regionFilter, r.region) &&
          inSel(psFilter, r.ps) &&
          inSel(custFilter, r.cust),
      )
      .map((r) => cols.map((f) => esc(r[f])).join(','));
    const csv = '\ufeff' + [header.join(','), ...lines].join('\n');
    const blob = new Blob([csv], {
      type: 'text/csv;charset=utf-8;',
    });
    const a = document.createElement('a');
    a.href = URL.createObjectURL(blob);
    a.download = `ke-hoach_${psFilter.length === 0 ? 'all' : psFilter.length === 1 ? psFilter[0].replace(/\s/g, '-') : psFilter.length + 'ps'}_${new Date().toISOString().slice(0, 10)}.csv`;
    a.click();
  };
  const logout = () => {
    if (
      draftCount > 0 &&
      !confirm('Còn thay đổi chưa lưu. Thoát mà không lưu?')
    )
      return;
    sessionStorage.removeItem(TOK_KEY);
    setAuthed(false);
    setRows([]);
    setOopRows([]);
    setDrafts({});
    setAuth({
      role: '',
      scope: '',
      username: '',
      bu: '',
      ho_ten: '',
    });
    setViewBu('');
  };
  if (!authed)
    return (
      <LoginGate
        onAuth={(a) => {
          setAuth(a);
          setViewBu(canSwitchTeam(a.role) ? '' : a.bu || '');
          setSentryUser(a.username, a.role);
          setInitialLoading(true);
          setAuthed(true);
        }}
      />
    );
  if (initialLoading)
    return (
      <div className="min-h-screen flex items-center justify-center bg-slate-50">
        <div className="text-center text-slate-500">
          <Loader2
            size={24}
            className="animate-spin mx-auto mb-2 text-emerald-600"
          />
          Đang tải dữ liệu từ hệ thống…
        </div>
      </div>
    );
  const curLabel = MONTH_LABELS[getCurIdx()];
  return (
    <QuotaThauCtx.Provider value={quotaThauCtx}>
      <div className="min-h-screen bg-slate-50 text-slate-900">
        <header className="bg-white border-b border-slate-200 sticky top-0 z-30">
          <div className="px-6 py-3 flex items-center justify-between gap-4 flex-wrap">
            <div className="flex items-center gap-3">
              <div className="w-11 h-11 rounded-full bg-blue-500 text-white grid place-items-center font-bold text-sm shrink-0">
                {(auth.ho_ten || auth.username || '??')
                  .split(/\s+/)
                  .map((w) => w[0])
                  .join('')
                  .slice(0, 2)
                  .toUpperCase()}
              </div>
              <div className="leading-tight">
                <div className="font-bold text-slate-900 text-base md:text-lg">
                  KẾ HOẠCH KINH DOANH
                </div>
                <div className="flex items-center gap-2 mt-0.5">
                  <span className="text-xs text-slate-500">
                    {auth.ho_ten || auth.username}
                  </span>
                </div>
              </div>
            </div>
            <div className="flex flex-col items-end gap-2">
              <div className="text-[9px] text-slate-400 italic text-right">
                Designed and developed by{' '}
                <span className="font-semibold text-slate-500 not-italic">
                  Do Hoang Giang
                </span>
              </div>
              <div className="flex items-center gap-2">
                {draftCount > 0 ? (
                  <React.Fragment>
                    <button
                      onClick={discardDrafts}
                      disabled={saving}
                      className="px-3 py-1.5 text-[13px] text-slate-500 hover:text-red-600 hover:bg-red-50 rounded-md disabled:opacity-50"
                    >
                      Hủy
                    </button>
                    <button
                      onClick={saveDrafts}
                      disabled={saving}
                      className="flex items-center gap-1.5 px-4 py-1.5 text-[13px] font-semibold bg-amber-500 hover:bg-amber-600 text-white rounded-md shadow-sm disabled:opacity-60"
                    >
                      {saving ? (
                        <React.Fragment>
                          <Loader2 size={14} className="animate-spin" />
                          Đang lưu…
                        </React.Fragment>
                      ) : (
                        <React.Fragment>
                          <Check size={14} />
                          Xác nhận điều chỉnh ({draftCount})
                        </React.Fragment>
                      )}
                    </button>
                  </React.Fragment>
                ) : savedFlash ? (
                  <span className="text-[12px] text-emerald-600 flex items-center gap-1">
                    <Check size={12} />
                    Đã lưu
                  </span>
                ) : null}
                <button
                  onClick={loadData}
                  className="flex items-center gap-1.5 px-4 py-1.5 text-[13px] font-semibold text-white bg-blue-600 hover:bg-blue-700 rounded-md"
                >
                  <RefreshCw size={14} />
                  Reload
                </button>
                <button
                  onClick={logout}
                  className="flex items-center gap-1.5 px-4 py-1.5 text-[13px] font-semibold text-white bg-red-600 hover:bg-red-700 rounded-md"
                >
                  <LogOut size={14} />
                  Đăng xuất
                </button>
              </div>
            </div>
          </div>
          <div className="px-6 py-2 flex items-center gap-2.5 flex-wrap border-t border-slate-100">
            <span className="text-[11px] uppercase tracking-wide text-slate-500 font-semibold pl-1">
              Lọc
            </span>
            <MultiSelect
              label="Nhóm SP"
              options={allGroups.map((g) => ({ value: g, label: g }))}
              selected={groupFilter}
              onChange={setGroupFilter}
            />
            {regionList.length > 0 &&
              (auth.role === 'admin' ||
                auth.role === 'manager' ||
                auth.role === 'product_manager') && (
                <MultiSelect
                  label="Miền"
                  options={regionList.map((rg) => ({ value: rg, label: rg }))}
                  selected={regionFilter}
                  onChange={(v) => {
                    setRegionFilter(v);
                    setPsFilter([]);
                    setCustFilter([]);
                  }}
                />
              )}
            {auth.role !== 'ps' && (
              <MultiSelect
                label="PS"
                searchable
                options={psList.map((p) => ({ value: p, label: p }))}
                selected={psFilter}
                onChange={(v) => {
                  setPsFilter(v);
                  setCustFilter([]);
                }}
              />
            )}
            <MultiSelect
              label="Khách hàng"
              searchable
              options={custList.map((c) => ({ value: c.cust, label: c.cust }))}
              selected={custFilter}
              onChange={setCustFilter}
            />
            <div className="flex-1" />
            {tab === 'detail' && (
              <button
                onClick={() => setShowBasePlan((v) => !v)}
                title={
                  showBasePlan
                    ? 'Ẩn cột SL kế hoạch đầu năm để thu gọn bảng'
                    : 'Hiện lại cột SL kế hoạch đầu năm'
                }
                className={`flex items-center gap-1.5 px-2.5 py-1.5 text-[13px] rounded-md border ${showBasePlan ? 'border-slate-200 text-slate-700 hover:bg-slate-100' : 'border-emerald-200 bg-emerald-50 text-emerald-700'}`}
              >
                {showBasePlan ? <EyeOff size={14} /> : <Eye size={14} />}
                {showBasePlan ? 'Ẩn SL đầu năm' : 'Hiện SL đầu năm'}
              </button>
            )}
            {canAddCust && (
              <button
                onClick={() => setAddCustOpen(true)}
                title="Thêm khách hàng mới vào kế hoạch"
                className="inline-flex items-center gap-1.5 px-2.5 py-1.5 text-[13px] font-medium text-emerald-700 bg-white border border-emerald-200 rounded-md hover:bg-emerald-50"
              >
                <UserPlus size={14} />
                Thêm khách hàng
              </button>
            )}
            {exportFn && (
              <button
                onClick={exportFn}
                title="Xuất Excel giữ nguyên cấu trúc gập/mở"
                className="inline-flex items-center gap-1.5 px-2.5 py-1.5 text-[13px] font-medium text-emerald-700 bg-white border border-emerald-200 rounded-md hover:bg-emerald-50"
              >
                <Download size={14} />
                Xuất Excel
              </button>
            )}
            {tab === 'diaban' && diaBanToolbar && diaBanToolbar()}
            {tab !== 'diaban' && (
              <div className="relative">
                <Search
                  size={14}
                  className="absolute left-2.5 top-1/2 -translate-y-1/2 text-slate-400"
                />
                <input
                  value={search}
                  onChange={(e) => setSearch(e.target.value)}
                  placeholder="Tìm KH, sản phẩm, bộ vật tư…"
                  className="pl-8 pr-3 py-1.5 text-[13px] border border-slate-200 rounded-md w-64 outline-none focus:border-emerald-500 focus:ring-2 focus:ring-emerald-100"
                />
              </div>
            )}
          </div>
          <div className="px-6 flex items-center gap-1 border-t border-slate-100">
            <TabBtn
              active={tab === 'detail'}
              onClick={() => setTab('detail')}
              label="Chi tiết kế hoạch"
            />
            <TabBtn
              active={tab === 'summary'}
              onClick={() => setTab('summary')}
              label="Tổng hợp theo PS"
            />
            <TabBtn
              active={tab === 'prodsum'}
              onClick={() => setTab('prodsum')}
              label="Tổng hợp theo SP"
            />
            <TabBtn
              active={tab === 'diaban'}
              onClick={() => setTab('diaban')}
              label="Cấu hình địa bàn"
            />
            {(auth.role === 'admin' || auth.role === 'manager') && (
              <TabBtn
                active={tab === 'audit'}
                onClick={() => setTab('audit')}
                label="Lịch sử cập nhật"
              />
            )}
          </div>
          {error && (
            <div className="px-6 py-2 bg-red-50 border-t border-red-200 text-[12px] text-red-800 flex items-center gap-2">
              <AlertCircle size={14} /> {error}
            </div>
          )}
          {notice && (
            <div className="px-6 py-2 bg-emerald-50 border-t border-emerald-200 text-[12px] text-emerald-900 flex items-center gap-2">
              <Check size={14} />
              <span>{notice}</span>
              <button
                onClick={() => setNotice('')}
                className="ml-auto text-emerald-600 hover:text-emerald-800"
              >
                Đóng
              </button>
            </div>
          )}
          {stale && (
            <div className="px-6 py-2 bg-amber-50 border-t border-amber-200 text-[12px] text-amber-900 flex items-center gap-3">
              <AlertCircle size={14} />
              <span>
                Người khác vừa cập nhật dữ liệu. Nếu bấm Lưu, hệ thống sẽ hỏi
                lại để tránh ghi đè nhầm.
              </span>
              <button
                onClick={() => {
                  if (
                    draftCount === 0 ||
                    confirm('Tải lại sẽ bỏ các thay đổi chưa lưu. Tiếp tục?')
                  ) {
                    setDrafts({});
                    loadData();
                  }
                }}
                className="ml-auto px-2.5 py-1 text-[12px] font-medium bg-amber-500 hover:bg-amber-600 text-white rounded-md"
              >
                Tải lại bản mới
              </button>
              <button
                onClick={() => setStale(false)}
                className="text-amber-600 hover:text-amber-800 text-[12px]"
              >
                Bỏ qua
              </button>
            </div>
          )}
          {pendingReload && (
            <div className="px-6 py-2 bg-sky-50 border-t border-sky-200 text-[12px] text-sky-900 flex items-center gap-3">
              <AlertCircle size={14} />
              <span>
                Có bản mới của ứng dụng đã được triển khai. Sẽ tự tải lại sau
                khi bạn lưu hoặc huỷ bản nháp.
              </span>
              <button
                onClick={() => {
                  if (
                    draftCount === 0 ||
                    confirm(
                      'Tải lại ngay sẽ mất các thay đổi chưa lưu. Tiếp tục?',
                    )
                  ) {
                    location.reload();
                  }
                }}
                className="ml-auto px-2.5 py-1 text-[12px] font-medium bg-sky-500 hover:bg-sky-600 text-white rounded-md"
              >
                Tải lại ngay
              </button>
            </div>
          )}
          {refreshing && (
            <div className="px-6 py-1.5 bg-blue-50 border-t border-blue-200 text-[12px] text-blue-700 flex items-center gap-2">
              <Loader2 size={12} className="animate-spin" />
              Đang cập nhật dữ liệu…
            </div>
          )}
        </header>
        <div className="px-6 pt-4">
          {canSwitchTeam(auth.role) && (
            <TeamSummaryBar
              rows={effectiveRows}
              oopRows={oopRows}
              value={viewBu}
              onChange={setViewBu}
            />
          )}
          <div className="grid grid-cols-1 md:grid-cols-2 gap-3 mb-4">
            <div className="flex flex-col gap-3">
              <AccountBar
                customers={accountsAssigned - missingAccounts.length}
                assigned={accountsAssigned}
                missing={missingAccounts.length}
                onShowMissing={() => setShowMissing(true)}
              />
              <ThYtdBar dtYtd={stats.dtYtd} khYtdDt={stats.khYtdDt} />
            </div>
            <WaterfallChart dt={stats.dt} dtUpd={stats.dtUpd} dtYtd={stats.dtYtd} />
          </div>
        </div>
        {
          // Modal chi tiết OOP + form dm_ps — treo ở root vì dùng fixed inset-0
          isAdmin && oopDetailReason && (
            <OopDetailModal
              filterReason={oopDetailReason}
              oopRows={oopRowsFiltered}
              isAdmin={isAdmin}
              onClose={() => setOopDetailReason(null)}
              onGoDiaBan={(ctx) => {
                setOopDetailReason(null);
                setTab('diaban');
                // ctx.purpose do OopDetailModal set: 'add' cho chua_co_dia_ban,
                // 'chuyen' cho sai_ps. DiaBanView tự đọc và điền form / tìm dòng.
                setDiaBanPrefill(ctx);
              }}
              onAddProduct={(ctx) => {
                setOopDetailReason(null);
                setTab('detail');
                setAddProductPrefill(ctx);
              }}
              onBulkAddProducts={bulkAddProducts}
              onEditDmps={(init) => setDmpsForm(init)}
              onSuaPsHoaDon={suaPsHoaDon}
              onSuaPsHoaDonBulk={suaPsHoaDonBulk}
              onFixBoVatTu={handleFixBoVatTu}
              planRows={rows}
              busy={oopFixBusy}
            />
          )
        }
        {fixBvtTarget && (
          <FixBoVatTuModal
            row={fixBvtTarget.oopRow}
            planMatches={fixBvtTarget.planMatches}
            onApply={applyFixBoVatTu}
            onClose={() => setFixBvtTarget(null)}
            busy={oopFixBusy}
          />
        )}
        <Modal
          open={showMissing}
          onClose={() => setShowMissing(false)}
          title={missingAccounts.length + ' account chưa có kế hoạch'}
          icon={<AlertCircle size={16} className="text-amber-500" />}
          width={720}
        >
          <div className="max-h-[60vh] overflow-y-auto">
            {missingAccounts.length === 0 ? (
              <div className="px-4 py-8 text-center text-slate-400 text-[13px]">
                Tất cả account đã có kế hoạch
              </div>
            ) : (
              <table className="w-full text-[12px]">
                <thead>
                  <tr className="bg-slate-50 text-left text-[11px] text-slate-500 uppercase tracking-wide">
                    <th className="px-4 py-2 font-semibold">Khách hàng</th>
                    <th className="px-4 py-2 font-semibold">PS</th>
                    <th className="px-4 py-2 font-semibold">Nhóm SP</th>
                  </tr>
                </thead>
                <tbody>
                  {missingAccounts.map((a, i) => (
                    <tr
                      key={i}
                      className={i % 2 === 0 ? 'bg-white' : 'bg-slate-50/50'}
                    >
                      <td className="px-4 py-1.5 text-slate-800">
                        {custLabel(a.custId, a.cust)}
                      </td>
                      <td className="px-4 py-1.5 text-slate-600">{a.ps}</td>
                      <td className="px-4 py-1.5 text-slate-600">{a.grp}</td>
                    </tr>
                  ))}
                </tbody>
              </table>
            )}
          </div>
        </Modal>
        {isAdmin && dmpsForm && (
          <DmpsForm
            init={dmpsForm}
            psDir={psDir}
            onSave={savePs}
            onClose={() => setDmpsForm(null)}
            busy={psBusy}
          />
        )}
        {canAddCust && (
          <AddCustomerModal
            open={addCustOpen || !!addProductPrefill}
            onClose={() => {
              closeAddCust();
              setAddProductPrefill(null);
            }}
            customers={custSource}
            psOptions={allPsList}
            regionsByPs={regionsByPs}
            diaBanByCust={diaBanByCust}
            existingCustKeys={custIndex.has}
            catIdx={catalog.length > 0 ? catIdx : null}
            groupsByPs={groupsByPs}
            priceOf={priceOf}
            onAdd={addCustomer}
            onAddProduct={addProduct}
            prefill={addProductPrefill}
          />
        )}
        {tab === 'audit' ? (
          <AuditLogView auth={auth} viewBu={viewBu} />
        ) : tab === 'diaban' ? (
          <DiaBanView
            rows={teamRows}
            diaBan={diaBan}
            customers={custSource}
            psOptions={allPsList}
            mienByPs={mienByPs}
            psKnown={psKnown}
            groupOptions={allGroupNames}
            canEdit={isAdmin || auth.role === 'manager'}
            psFilter={psFilter}
            regionFilter={regionFilter}
            groupFilter={groupFilter}
            custFilter={custFilter}
            onSave={saveDiaBan}
            onDelete={deleteDiaBan}
            onDopChongLan={dopChongLan}
            busy={diaBanBusy}
            prefill={diaBanPrefill}
            onPrefillDone={() => setDiaBanPrefill(null)}
            viewBu={viewBu}
            onToolbar={setDiaBanTb}
            curMonth={curMonth}
            oopAction={
              // Đối chiếu ngoài kế hoạch — chỉ admin thấy (mọi role khác không có action gì
              // để sửa được, chỉ tăng nhiễu). Backend đã lọc dữ liệu theo phạm vi quyền.
              isAdmin && (
                <OopReasonButton
                  total={oopTotal}
                  byReason={oopByReason}
                  onOpenDetail={(ly) => setOopDetailReason(ly || 'all')}
                  onQuickFixSaiPs={() => {
                    const list = oopRowsFiltered.filter(
                      (r) => r._lyDo === 'sai_ps' && r._psDiaBan,
                    );
                    if (list.length) suaPsHoaDonBulk(list);
                  }}
                  onQuickAddDiaBan={() => {
                    const seen = new Set();
                    const rows = [];
                    for (const r of oopRowsFiltered) {
                      if (r._lyDo !== 'chua_co_dia_ban') continue;
                      if (!r.grp || !r.ps) continue;
                      const k =
                        (r.custId || r.cust || '') + '||' + r.grp + '||' + r.ps;
                      if (seen.has(k)) continue;
                      seen.add(k);
                      rows.push({
                        custId: r.custId || '',
                        cust: r.custRaw || r.cust,
                        grp: r.grp,
                        ps: r.ps,
                      });
                    }
                    if (!rows.length) return;
                    if (
                      !confirm(
                        `Khai báo ${rows.length} bản địa bàn theo hoá đơn (tổ hợp KH × ngành hàng × PS chưa có địa bàn).\n\nSau khi lưu, kế hoạch tự apply cả năm cho các tổ hợp không chồng lấn.`,
                      )
                    )
                      return;
                    saveDiaBan(rows);
                  }}
                  onQuickAddThieu={() => {
                    bulkAddProducts(
                      oopRowsFiltered.filter(
                        (r) => r._lyDo === 'thieu_dong_ke_hoach',
                      ),
                    );
                  }}
                />
              )
            }
            isAdmin={isAdmin}
            onMonthChange={async (mo) => {
              try {
                await api('setAppConfig', { key: 'current_month', value: mo });
                setCurrentMonth(mo);
                setCurMonth(mo);
                await loadData();
              } catch (e) {
                setError('Lưu tháng hiện tại thất bại: ' + e.message);
              }
            }}
          />
        ) : tab === 'summary' ? (
          <SummaryView
            rows={summaryRows}
            psFilter={psFilter}
            regionFilter={regionFilter}
            custFilter={custFilter}
            groupFilter={groupFilter}
            search={search}
            onExport={setExporter}
            auth={auth}
          />
        ) : tab === 'prodsum' ? (
          <ProductSummaryView
            rows={summaryRows}
            psFilter={psFilter}
            regionFilter={regionFilter}
            custFilter={custFilter}
            groupFilter={groupFilter}
            search={search}
            onExport={setExporter}
          />
        ) : (
          <React.Fragment>
            <DetailScrollBox scrollRef={scrollContainerRef}>
              {canEdit &&
                pendingCusts.map((c) => (
                  <NewCustomerCard
                    key={'new:' + (c.custId || c.cust)}
                    cust={c}
                    catIdx={catIdx}
                    groupsByPs={groupsByPs}
                    priceOf={priceOf}
                    onAddProduct={addProduct}
                    onDismiss={() =>
                      setNewCusts((prev) =>
                        prev.filter(
                          (x) => (x.custId || x.cust) !== (c.custId || c.cust),
                        ),
                      )
                    }
                  />
                ))}
              {tree.length === 0
                ? pendingCusts.length === 0 && (
                    <div className="bg-white rounded-lg border border-slate-200 px-4 py-12 text-center text-slate-400 text-sm">
                      {rows.length === 0
                        ? 'Sheet trống'
                        : 'Không có khách hàng nào khớp với bộ lọc'}
                    </div>
                  )
                : (() => {
                    const cardKey = (c) => c.custId || c.customer;
                    const toggleCard = (k) =>
                      setOpenCards((prev) => {
                        const n = new Set(prev);
                        n.has(k) ? n.delete(k) : n.add(k);
                        return n;
                      });
                    const renderOneCard = (c) => (
                      <CustomerCard
                        key={cardKey(c)}
                        {...c}
                        pendingKeys={draftKeys}
                        onCommit={commit}
                        canEdit={canEdit}
                        isAdmin={isAdmin}
                        onDeleteProduct={deleteProduct}
                        open={openCards.has(cardKey(c))}
                        onToggle={() => toggleCard(cardKey(c))}
                        showBasePlan={showBasePlan}
                        onToggleBasePlan={() => setShowBasePlan((v) => !v)}
                        catIdx={catalog.length > 0 ? catIdx : null}
                        groupsByPs={groupsByPs}
                        priceOf={priceOf}
                        onAddProduct={addProduct}
                        onDeleteCustomer={deleteCustomer}
                        conflicts={conflicts}
                        onResolveConflict={resolveConflict}
                      />
                    );
                    const renderCards = (list) => list.map(renderOneCard);
                    if (!viewBu && canSwitchTeam(auth.role)) {
                      const realTeams = Object.keys(TEAMS).filter(
                        (k) => k !== 'test',
                      );
                      return realTeams.map((tk) => {
                        const custs = tree.filter(
                          (c) => c.buList && c.buList.includes(tk),
                        );
                        if (custs.length === 0) return null;
                        const t = TEAMS[tk];
                        let secDt = 0,
                          secDtYtd = 0,
                          secKhYtd = 0;
                        custs.forEach((c) => {
                          secDt += c._dtUpd || 0;
                          secDtYtd += c._thYtd || 0;
                        });
                        const isOpen = teamOpen.has(tk);
                        const toggleTeam = () =>
                          setTeamOpen((prev) => {
                            const s = new Set(prev);
                            s.has(tk) ? s.delete(tk) : s.add(tk);
                            return s;
                          });
                        return (
                          <div key={tk} className="mb-3">
                            <button
                              type="button"
                              onClick={toggleTeam}
                              className="w-full flex items-center gap-2.5 px-4 py-2.5 bg-white border border-slate-200 rounded-lg hover:bg-slate-50 transition-colors sticky-team"
                            >
                              <div
                                className="w-3 h-3 rounded-full shrink-0"
                                style={{ background: t.gradient }}
                              />
                              <span className="text-[14px] font-bold text-slate-800">
                                {t.label}
                              </span>
                              <span className="text-[12px] text-slate-500 tabular-nums">
                                {custs.length}KH
                              </span>
                              <div className="flex-1" />
                              {
                                /*#__PURE__*/ React.createElement(
                                  isOpen ? ChevronDown : ChevronRight,
                                  {
                                    size: 16,
                                    className: 'text-slate-400',
                                  },
                                )
                              }
                            </button>
                            {isOpen && (
                              <div className="mt-1.5">{renderCards(custs)}</div>
                            )}
                          </div>
                        );
                      });
                    }
                    if (tree.length > VIRTUAL_THRESHOLD) {
                      return (
                        <VirtualCardList
                          items={tree}
                          scrollRef={scrollContainerRef}
                          cardKey={cardKey}
                          renderCard={renderOneCard}
                        />
                      );
                    }
                    return renderCards(tree);
                  })()}
            </DetailScrollBox>
          </React.Fragment>
        )}
      </div>
    </QuotaThauCtx.Provider>
  );
}

