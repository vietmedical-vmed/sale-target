import { useRef, useEffect, useLayoutEffect, useCallback } from 'react';

export function useFitHeight() {
  const ref = useRef(null);
  useEffect(() => {
    const el = ref.current;
    if (!el) return;
    let firstFit = true;
    const fit = () => {
      const vh =
        window.innerHeight || document.documentElement.clientHeight || 0;
      const bar = document.querySelector('header.sticky')?.offsetHeight || 0;
      const maxH = vh - bar - 32;
      if (vh < 400 || maxH < 320) {
        el.style.maxHeight = '';
        return;
      }
      el.style.maxHeight = maxH + 'px';
      if (firstFit && el.scrollHeight > el.clientHeight + 4) {
        const docTop = el.getBoundingClientRect().top + window.scrollY;
        if (window.scrollY < docTop - bar) window.scrollTo(0, docTop - bar);
      }
      firstFit = false;
    };
    fit();
    window.addEventListener('resize', fit);
    return () => window.removeEventListener('resize', fit);
  }, []);
  return ref;
}

export function useStickyBars(active, hasCards) {
  useLayoutEffect(() => {
    const root = document.documentElement;
    const measure = () => {
      const head = document.querySelector('header.sticky');
      const filt = document.querySelector('.sticky-filter');
      const cust = document.querySelector('.sticky-cust');
      root.style.setProperty(
        '--app-header-h',
        Math.ceil(head ? head.getBoundingClientRect().height : 0) + 'px',
      );
      root.style.setProperty(
        '--app-filter-h',
        Math.ceil(filt ? filt.getBoundingClientRect().height : 0) + 'px',
      );
      root.style.setProperty(
        '--app-cust-h',
        Math.ceil(cust ? cust.getBoundingClientRect().height : 0) + 'px',
      );
    };
    measure();
    if (!active) return;
    const ro =
      typeof ResizeObserver === 'function' ? new ResizeObserver(measure) : null;
    if (ro) {
      const head = document.querySelector('header.sticky');
      const filt = document.querySelector('.sticky-filter');
      if (head) ro.observe(head);
      if (filt) ro.observe(filt);
    }
    window.addEventListener('resize', measure);
    return () => {
      if (ro) ro.disconnect();
      window.removeEventListener('resize', measure);
    };
  }, [active, hasCards]);
}

export function DetailScrollBox({ children, scrollRef }) {
  const boxRef = useRef(null);
  const setBoxRef = useCallback((node) => {
    boxRef.current = node;
    if (scrollRef) scrollRef.current = node;
  }, [scrollRef]);
  const coverRef = useRef(null);
  const coverLRef = useRef(null);
  useLayoutEffect(() => {
    const box = boxRef.current;
    const cover = coverRef.current;
    const coverL = coverLRef.current;
    if (!box) return;
    let measureId = 0;
    let stickyIndent = 0;
    let rightPad = 0;
    let leftPad = 0;
    let pinEls = [];
    let teamEls = [];
    let lastSl = -1;
    const measure = () => {
      const hasOverflow = box.scrollWidth > box.clientWidth;
      const custEl = box.querySelector('.sticky-cust');
      const custH = custEl
        ? Math.ceil(custEl.getBoundingClientRect().height)
        : 0;
      const grpEl = box.querySelector('.sticky-grp');
      const grpH = grpEl ? Math.ceil(grpEl.getBoundingClientRect().height) : 0;
      leftPad = parseInt(getComputedStyle(box).paddingLeft) || 0;
      const inner = box.querySelector('.detail-inner');
      rightPad = inner
        ? parseInt(getComputedStyle(inner).paddingRight) || 0
        : 0;
      if (custEl) {
        custEl.style.transform = '';
        custEl.style.width = '';
        custEl.style.maxWidth = '';
        const boxL = box.getBoundingClientRect().left;
        stickyIndent =
          custEl.getBoundingClientRect().left - boxL + box.scrollLeft;
      }
      const vw = box.clientWidth - stickyIndent - rightPad;
      box.style.setProperty('--detail-cust-h', custH + 'px');
      box.style.setProperty('--detail-grp-h', grpH + 'px');
      box.style.setProperty('--detail-vw', vw + 'px');
      if (cover) {
        cover.style.display = hasOverflow ? '' : 'none';
        cover.style.width = rightPad + 'px';
        cover.style.height = box.clientHeight + 'px';
      }
      if (coverL) {
        coverL.style.display = hasOverflow ? '' : 'none';
        coverL.style.width = stickyIndent + 'px';
        coverL.style.height = box.clientHeight + 'px';
      }
      pinEls = Array.from(
        box.querySelectorAll(
          '.sticky-cust, .sticky-grp, .meta-sticky-l, .fake-scrollbar-wrap',
        ),
      );
      teamEls = Array.from(box.querySelectorAll('.sticky-team'));
      const w = box.clientWidth - stickyIndent - rightPad + 'px';
      pinEls.forEach((el) => {
        el.style.width = w;
        el.style.maxWidth = w;
      });
      const tw = box.clientWidth - leftPad - rightPad + 'px';
      teamEls.forEach((el) => {
        el.style.width = tw;
        el.style.maxWidth = tw;
      });
      lastSl = -1;
      pinHoriz();
    };
    const scheduleMeasure = () => {
      clearTimeout(measureId);
      measureId = setTimeout(measure, 60);
    };
    const pinHoriz = () => {
      const sl = box.scrollLeft;
      if (sl !== lastSl) {
        lastSl = sl;
        const tx = 'translateX(' + sl + 'px)';
        for (const el of pinEls) el.style.transform = tx;
        for (const el of teamEls) el.style.transform = tx;
      }
      if (cover)
        cover.style.transform =
          'translate(' +
          (sl + box.clientWidth - rightPad) +
          'px,' +
          box.scrollTop +
          'px)';
      if (coverL)
        coverL.style.transform =
          'translate(' + sl + 'px,' + box.scrollTop + 'px)';
    };
    const onScroll = () => pinHoriz();
    // Thanh cuộn giả đặt scrollLeft của box rồi phải ghim lại ngay: sự kiện
    // scroll của box chỉ bắn ở frame sau, chờ nó thì header lệch 1 frame.
    box.__pinHoriz = pinHoriz;
    measure();
    // Parent useStickyBars sets CSS vars AFTER this child effect (React
    // fires child layout effects first). Re-measure once all layout
    // effects finish so maxHeight/clientWidth reflect final CSS vars.
    queueMicrotask(measure);
    box.addEventListener('scroll', onScroll);
    const ro = new ResizeObserver(scheduleMeasure);
    ro.observe(box);
    const mo = new MutationObserver(scheduleMeasure);
    mo.observe(box, { childList: true, subtree: true });
    window.addEventListener('resize', measure);
    return () => {
      clearTimeout(measureId);
      delete box.__pinHoriz;
      box.removeEventListener('scroll', onScroll);
      ro.disconnect();
      mo.disconnect();
      window.removeEventListener('resize', measure);
    };
  }, []);
  return (
    <div
      className="detail-box pl-6"
      ref={setBoxRef}
      style={{
        maxHeight: 'calc(100vh - var(--app-header-h) - var(--app-filter-h))',
        marginTop: -4,
        position: 'relative',
      }}
    >
      <div
        ref={coverRef}
        style={{
          position: 'absolute',
          top: 0,
          left: 0,
          zIndex: 21,
          background: '#f0f2f5',
          pointerEvents: 'none',
        }}
      />
      <div
        ref={coverLRef}
        style={{
          position: 'absolute',
          top: 0,
          left: 0,
          zIndex: 21,
          background: '#f0f2f5',
          pointerEvents: 'none',
        }}
      />
      <div className="detail-inner">{children}</div>
    </div>
  );
}

export function useSummaryScrollbar(boxRef) {
  useEffect(() => {
    const box = boxRef.current;
    if (!box) return;
    const sb = document.createElement('div');
    sb.className = 'summary-sb';
    const spacer = document.createElement('div');
    spacer.style.height = '1px';
    sb.appendChild(spacer);
    box.insertBefore(sb, box.firstChild);

    let syncing = false;
    let tid = 0;
    const measure = () => {
      const has = box.scrollWidth > box.clientWidth + 1;
      sb.style.display = has ? '' : 'none';
      sb.style.width = box.clientWidth + 'px';
      spacer.style.width = box.scrollWidth + 'px';
    };
    const debounceMeasure = () => {
      clearTimeout(tid);
      tid = setTimeout(measure, 60);
    };
    const syncBox = () => {
      if (syncing) return;
      syncing = true;
      sb.scrollLeft = box.scrollLeft;
      requestAnimationFrame(() => {
        syncing = false;
      });
    };
    const syncSb = () => {
      if (syncing) return;
      syncing = true;
      box.scrollLeft = sb.scrollLeft;
      requestAnimationFrame(() => {
        syncing = false;
      });
    };
    measure();
    box.addEventListener('scroll', syncBox, { passive: true });
    sb.addEventListener('scroll', syncSb, { passive: true });
    const ro =
      typeof ResizeObserver === 'function'
        ? new ResizeObserver(debounceMeasure)
        : null;
    if (ro) ro.observe(box);
    const mo =
      typeof MutationObserver === 'function'
        ? new MutationObserver(debounceMeasure)
        : null;
    if (mo) mo.observe(box, { childList: true, subtree: true });
    window.addEventListener('resize', measure);
    return () => {
      clearTimeout(tid);
      box.removeEventListener('scroll', syncBox);
      sb.removeEventListener('scroll', syncSb);
      if (ro) ro.disconnect();
      if (mo) mo.disconnect();
      window.removeEventListener('resize', measure);
      if (sb.parentNode) sb.parentNode.removeChild(sb);
    };
  }, [boxRef]);
}

export function useStickyRows(boxRef) {
  useEffect(() => {
    const box = boxRef.current;
    if (!box) return;
    const thead = box.querySelector('thead');
    let rows = [];
    let baseH = 0;
    let pinned = [];
    let raf = 0;
    const clear = (el) => {
      el.style.position = '';
      el.style.top = '';
      el.style.zIndex = '';
    };

    const remeasure = () => {
      pinned.forEach(clear);
      pinned = [];
      const els = Array.from(box.querySelectorAll('tr[data-lv]'));
      els.forEach(clear);
      if (thead) thead.style.top = '';
      baseH = thead ? thead.offsetHeight : 0;
      const origin = box.getBoundingClientRect().top - box.scrollTop;
      rows = els.map((el) => ({
        el,
        lv: Number(el.dataset.lv) || 0,
        top: el.getBoundingClientRect().top - origin,
        h: el.offsetHeight,
      }));
      const st = [];
      for (let i = rows.length - 1; i >= 0; i--) {
        while (st.length && rows[st[st.length - 1]].lv > rows[i].lv) st.pop();
        rows[i].end = st.length
          ? rows[st[st.length - 1]].top
          : box.scrollHeight;
        st.push(i);
      }
    };

    const apply = () => {
      const hdr = document.querySelector('header.sticky');
      const headerH = hdr ? Math.ceil(hdr.getBoundingClientRect().height) : 0;
      const boxTop = box.getBoundingClientRect().top;
      const pageOff = Math.max(0, Math.ceil(headerH - boxTop));
      const sb = box.querySelector('.summary-sb');
      const sbH =
        sb && sb.style.display !== 'none'
          ? Math.ceil(sb.getBoundingClientRect().height)
          : 0;
      if (sb) sb.style.top = pageOff + 'px';
      if (thead) {
        thead.style.top = pageOff + sbH + 'px';
        thead.style.boxShadow = pageOff > 0 ? '0 2px 4px rgba(0,0,0,0.08)' : '';
      }

      const curBaseH = thead ? thead.offsetHeight : baseH;
      const base = curBaseH + pageOff + sbH;
      const s = box.scrollTop;
      const chain = [];
      for (const r of rows) {
        let pin = base;
        for (let i = 0; i < r.lv; i++) if (chain[i]) pin += chain[i].h;
        if (r.top - s > pin) continue;
        chain.length = r.lv;
        chain[r.lv] = r;
      }
      const keep = chain.filter(Boolean);
      const want = new Set(keep.map((r) => r.el));
      pinned.forEach((el) => {
        if (!want.has(el)) clear(el);
      });
      let top = base;
      keep.forEach((r) => {
        const t = Math.min(top, r.end - s - r.h);
        r.el.style.position = 'sticky';
        r.el.style.top = t + 'px';
        r.el.style.zIndex = String(15 - r.lv);
        top = t + r.h;
      });
      pinned = keep.map((r) => r.el);
    };

    let needRe = false;
    const tick = () => {
      raf = 0;
      if (needRe) {
        needRe = false;
        remeasure();
      }
      apply();
    };
    const schedule = (re) => {
      if (re) needRe = true;
      if (!raf) raf = requestAnimationFrame(tick);
    };

    remeasure();
    apply();
    const onScroll = () => schedule(false);
    const onPageScroll = () => schedule(false);
    const onResize = () => schedule(true);
    box.addEventListener('scroll', onScroll, { passive: true });
    window.addEventListener('scroll', onPageScroll, { passive: true });
    window.addEventListener('resize', onResize);
    const mo =
      typeof MutationObserver === 'function'
        ? new MutationObserver(() => schedule(true))
        : null;
    if (mo) mo.observe(box, { childList: true, subtree: true });
    return () => {
      if (raf) cancelAnimationFrame(raf);
      if (mo) mo.disconnect();
      box.removeEventListener('scroll', onScroll);
      window.removeEventListener('scroll', onPageScroll);
      window.removeEventListener('resize', onResize);
      pinned.forEach(clear);
      if (thead) {
        thead.style.top = '';
        thead.style.boxShadow = '';
      }
    };
  }, [boxRef]);
}
