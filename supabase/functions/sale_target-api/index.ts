import { getAllowedOrigin, corsHeaders, json as _json } from "../_shared/cors.ts";
import { verifyToken, signToken } from "../_shared/auth.ts";
import { COL, FIELDS, EDITABLE, ADMIN_EDITABLE, PAGE } from "./config.ts";
import { applyScope, scopeParams, parseGroups, mienScope } from "./scope.ts";
import {
  admin, getRev, writeAuditLog, diaBanErr, kiemTraPsThemDiaBan,
  psInfo, buForPs, mienForPs,
  fetchAll, fetchOopClassify, fetchQuotaThau, absorbOop,
  applyScopeTombstone, taoDotTuThangThau, kiemTraThangHieuLuc,
  BU_GIA_DANH_MUC, giaDanhMucCttm,
} from "./helpers.ts";

Deno.serve(async (req) => {
  const _origin = getAllowedOrigin(req);
  const requestId = crypto.randomUUID().slice(0, 8);
  const t0 = Date.now();
  let _action = "";
  let _user = "";
  let _role = "";
  const json = (body: Record<string, unknown>, status = 200) => {
    if (_action) {
      console.log(JSON.stringify({
        requestId, action: _action, user: _user, role: _role,
        status, duration: Date.now() - t0,
      }));
    }
    return _json({ ...body, requestId }, status, req);
  };
  if (req.method === "OPTIONS") return new Response("ok", { headers: corsHeaders(_origin) });
  if (req.method !== "POST") return json({ ok: false, error: "method" }, 405);

  const secret = Deno.env.get("TOKEN_SECRET");
  if (!secret) return json({ ok: false, error: "config_error" }, 500);

  let body: Record<string, unknown>;
  try { body = await req.json(); } catch { return json({ ok: false, error: "bad_body" }, 400); }

  const { action, token, payload = {} } = body;
  _action = String(action || "");
  const sess = await verifyToken(token as string, secret);
  if (!sess) return json({ ok: false, error: "unauthorized" }, 401);
  sess.r = String(sess.r || "").toLowerCase();
  _user = sess.u;
  _role = sess.r;

  const db = admin();
  // Token còn hạn chưa đủ: tài khoản bị khoá (shared.users.active = false) phải mất quyền ngay.
  const { data: dbUser, error: userErr } = await db.schema("shared").from("users")
    .select("active").eq("username", sess.u).maybeSingle();
  if (userErr) return json({ ok: false, error: "server_error" }, 500);
  if (!dbUser || dbUser.active === false) return json({ ok: false, error: "unauthorized" }, 401);
  const canEdit = ["admin", "ps", "manager", "area_manager"].includes(sess.r);

  try {
    if (action === "ping") {
      return json({ ok: true, role: sess.r, scope: sess.s, bu: sess.b, username: sess.u });
    }

    if (action === "refreshToken") {
      const remaining = sess.exp - Math.floor(Date.now() / 1000);
      if (remaining < 0) return json({ ok: false, error: "expired" }, 401);
      const exp = Math.floor(Date.now() / 1000) + 2 * 60 * 60;
      const newToken = await signToken({
        username: sess.u, ho_ten: sess.n, role: sess.r,
        mien: sess.m, bu: sess.b, scope: sess.s,
        nhom_san_pham: sess.g, exp,
      }, secret);
      return json({ ok: true, token: newToken, expiresAt: exp });
    }

    if (action === "getData") {
      const [allRows, classMap, rev, cfgRows, quotaThau, maxDocDateRes] = await Promise.all([
        fetchAll(db, sess, payload),
        fetchOopClassify(db, sess, payload).catch(() => new Map()),
        getRev(db, sess, payload),
        db.schema("shared").from("app_config").select("key, value").then(r => r.data || []),
        fetchQuotaThau(db, sess, payload).catch(() => ({ dots: [], quotas: [] })),
        db.schema("app_sale").from("hoa_don_bovattu")
          .select("ngay_tai_lieu")
          .order("ngay_tai_lieu", { ascending: false })
          .limit(1)
          .then(r => (r.data && r.data[0]?.ngay_tai_lieu) || null)
          .catch(() => null),
      ]);
      const cfg: Record<string, unknown> = {};
      for (const r of cfgRows) cfg[r.key] = r.value;
      const dbRows: Record<string, unknown>[] = [];
      const oopDbRows: Record<string, unknown>[] = [];
      for (const r of allRows) {
        if (r[COL.oop]) oopDbRows.push(r);
        else dbRows.push(r);
      }
      const mapRow = (r: Record<string, unknown>) => FIELDS.map((f) => {
        const v = r[COL[f]];
        return v === null || v === undefined ? "" : v;
      });
      const rows = dbRows.map(mapRow);
      const rowNums = dbRows.map((r) => r.id);
      const rowRevs = dbRows.map((r) => Number(r._rev) || 0);
      const oopRows = oopDbRows.map(mapRow);
      const oopMeta = oopDbRows.map((r) => {
        const c = classMap.get(r.id);
        return { ly_do: c?.ly_do || "", ps_dia_ban: c?.ps_dia_ban || "" };
      });
      const oopRowNums = oopDbRows.map((r) => r.id);
      const oopRowRevs = oopDbRows.map((r) => Number(r._rev) || 0);
      return json({
        ok: true, fields: FIELDS, rows, rowNums, rowRevs,
        oopRows, oopMeta, oopRowNums, oopRowRevs, rev,
        dots: quotaThau.dots, quotas: quotaThau.quotas,
        role: sess.r, scope: sess.s, bu: sess.b, username: sess.u,
        config: cfg, maxDocDate: maxDocDateRes,
      });
    }

    if (action === "getRev") {
      return json({ ok: true, rev: await getRev(db, sess, payload) });
    }

    if (action === "getChanges") {
      const sinceRev = Number(payload.sinceRev) || 0;
      const cols = FIELDS.map((f) => COL[f]).join(",") + ",id,_rev";
      const changed: Record<string, unknown>[] = [];
      for (let from = 0; ; from += PAGE) {
        let q = db.schema("shared").from("sale_target").select(cols)
          .gt("_rev", sinceRev)
          .order("_rev", { ascending: true })
          .range(from, from + PAGE - 1);
        q = applyScope(q, sess, payload);
        const { data, error } = await q;
        if (error) throw new Error(error.message);
        changed.push(...(data || []));
        if (!data || data.length < PAGE) break;
      }
      const deleted: number[] = [];
      for (let from = 0; ; from += PAGE) {
        let q = db.schema("shared").from("sale_target_tombstone")
          .select("id, _rev")
          .gt("_rev", sinceRev)
          .order("_rev", { ascending: true })
          .range(from, from + PAGE - 1);
        q = applyScopeTombstone(q, sess, payload);
        const { data, error } = await q;
        if (error) throw new Error(error.message);
        deleted.push(...(data || []).map((d: Record<string, unknown>) => d.id as number));
        if (!data || data.length < PAGE) break;
      }
      const classMap = changed.some((r) => r[COL.oop])
        ? await fetchOopClassify(db, sess, payload).catch(() => new Map())
        : new Map();
      const mapRow = (r: Record<string, unknown>) => FIELDS.map((f) => {
        const v = r[COL[f]];
        return v === null || v === undefined ? "" : v;
      });
      const dbRows = changed.filter((r) => !r[COL.oop]);
      const oopDbRows = changed.filter((r) => r[COL.oop]);
      return json({
        ok: true,
        rows: dbRows.map(mapRow),
        rowNums: dbRows.map((r) => r.id),
        rowRevs: dbRows.map((r) => Number(r._rev) || 0),
        oopRows: oopDbRows.map(mapRow),
        oopMeta: oopDbRows.map((r) => {
          const c = classMap.get(r.id);
          return { ly_do: c?.ly_do || "", ps_dia_ban: c?.ps_dia_ban || "" };
        }),
        oopRowNums: oopDbRows.map((r) => r.id),
        oopRowRevs: oopDbRows.map((r) => Number(r._rev) || 0),
        deleted,
        maxRev: await getRev(db, sess, payload),
      });
    }

    if (action === "getQuotaThau") {
      const { dots, quotas } = await fetchQuotaThau(db, sess, payload);
      return json({ ok: true, dots, quotas });
    }

    if (action === "getCatalog") {
      const catalog: Record<string, unknown>[] = [];
      const seen = new Set<string>();
      for (let from = 0; ; from += PAGE) {
        const { data, error } = await db.schema("shared").from("dm_bo_vat_tu_mapping")
          .select("bu, nhom_san_pham, bo_vat_tu, san_pham, ma_bo_vat_tu, ma_san_pham")
          .order("id", { ascending: true })
          .range(from, from + PAGE - 1);
        if (error) throw new Error(error.message);
        if (!data || data.length === 0) break;
        for (const c of data) {
          const key = `${c.nhom_san_pham || ""}||${c.bo_vat_tu || ""}||${c.san_pham || ""}`;
          if (seen.has(key)) continue;
          seen.add(key);
          catalog.push({
            bu: c.bu || '',
            grp: c.nhom_san_pham, mset: c.bo_vat_tu, prod: c.san_pham,
            maBvt: c.ma_bo_vat_tu || '', maSp: c.ma_san_pham || '',
          });
        }
        if (data.length < PAGE) break;
      }
      // SP của BU CTTM & CTUT kèm đơn giá danh mục (giaDm) để màn thêm SP gợi ý đúng giá
      // addProduct/addProducts sẽ ghi. Mapping lưu nhãn BU dài ("CTTM & CTUT") → tra qua dm_ps.
      const { data: psBu } = await db.schema("shared").from("dm_ps")
        .select("bu").eq("bu_code", BU_GIA_DANH_MUC).limit(500);
      const nhanCttm = new Set((psBu || []).map((r: Record<string, unknown>) => String(r.bu || "")).filter(Boolean));
      if (nhanCttm.size) {
        const giaDm = await giaDanhMucCttm(db);
        for (const c of catalog) {
          if (!nhanCttm.has(String(c.bu))) continue;
          const g = giaDm(c.prod || "", c.maSp || null);
          if (g !== null) c.giaDm = g;
        }
      }
      return json({ ok: true, catalog });
    }

    if (action === "getCustomers") {
      const out: { custId: string; cust: string; alias: string }[] = [];
      for (let from = 0; ; from += PAGE) {
        const { data, error } = await db.schema("shared").from("dm_khach_hang")
          .select("customer_id, customer_name, customer_alias")
          .order("customer_id", { ascending: true })
          .range(from, from + PAGE - 1);
        if (error) throw new Error(error.message);
        if (!data || data.length === 0) break;
        for (const c of data) out.push({ custId: c.customer_id ?? "", cust: c.customer_name ?? "", alias: String(c.customer_alias ?? "").trim() });
        if (data.length < PAGE) break;
      }
      const customers = out.filter((c) => c.cust || c.custId);
      return json({ ok: true, customers });
    }

    if (action === "getPs") {
      const { data, error } = await db.schema("shared").from("dm_ps")
        .select("ps, ten_ps, bu, bu_code, area, team, trang_thai")
        .order("ps", { ascending: true }).limit(1000);
      if (error) throw new Error(error.message);
      let list = (data || []).map((d: Record<string, unknown>) => ({
        ps: d.ps ?? "", tenPs: d.ten_ps ?? "",
        bu: d.bu_code ?? "", buLabel: d.bu ?? "",
        mien: d.area ?? "", team: d.team ?? "",
        active: String(d.trang_thai || "").toLowerCase() !== "inactive",
      })).filter((p: { ps: unknown }) => p.ps);
      const role = sess.r;
      if (role === "ps") list = list.filter((p: { ps: unknown }) => p.ps === sess.s);
      else if (role === "area_manager") list = list.filter((p: { mien: unknown }) => mienScope(sess).includes(String(p.mien)));
      else if ((role === "admin" || role === "manager") && payload.bu) {
        list = list.filter((p: { bu: unknown }) => p.bu === payload.bu);
      }
      return json({ ok: true, ps: list });
    }

    if (action === "savePs") {
      if (sess.r !== "admin") return json({ ok: false, error: "forbidden" }, 403);
      const p = payload || {};
      const ten = String(p.tenPs || "").trim();
      const ps  = String(p.ps || "").trim();
      if (!ten || !ps) return json({ ok: false, error: "thieu_du_lieu" }, 400);
      const bu_code = String(p.buCode || "").trim().toLowerCase();
      const known = new Set(["chcs", "cttm", "thnk", "test"]);
      if (bu_code && !known.has(bu_code)) {
        return json({ ok: false, error: `bu_code không hợp lệ: ${bu_code}` }, 400);
      }
      const row = {
        ten_ps: ten, ps, bu: p.bu || null, bu_code: bu_code || null,
        area: p.mien || null, team: p.team || null,
        trang_thai: p.active === false ? "Inactive" : "Active",
      };
      const q = db.schema("shared").from("dm_ps");
      const { data: existed } = await q.select("ten_ps").eq("ten_ps", ten).limit(1);
      const { error } = existed && existed.length
        ? await q.update(row).eq("ten_ps", ten)
        : await q.insert(row);
      if (error) {
        const msg = String(error.message || "");
        if (msg.includes("duplicate") || msg.includes("unique"))
          return json({ ok: false, error: "dup_ps" }, 409);
        return json({ ok: false, error: msg }, 500);
      }
      await writeAuditLog(db, sess, "savePs", 1, { ten_ps: ten, ps });
      return json({ ok: true });
    }

    if (action === "getOop") {
      const cols = FIELDS.map((f) => COL[f]).join(",") + ",id,_rev";
      const classMap = await fetchOopClassify(db, sess, payload).catch(() => new Map());
      const out: Record<string, unknown>[] = [];
      for (let from = 0; ; from += PAGE) {
        let q = db.schema("shared").from("sale_target").select(cols)
          .eq("ngoai_ke_hoach", true)
          .range(from, from + PAGE - 1);
        q = applyScope(q, sess, payload);
        const { data, error } = await q;
        if (error) throw new Error(error.message);
        out.push(...(data || []));
        if (!data || data.length < PAGE) break;
      }
      const oopRows = out.map((r) => FIELDS.map((f) => {
        const v = r[COL[f]];
        return v === null || v === undefined ? "" : v;
      }));
      const oopMeta = out.map((r) => {
        const c = classMap.get(r.id);
        return { ly_do: c?.ly_do || "", ps_dia_ban: c?.ps_dia_ban || "" };
      });
      return json({ ok: true, oopRows, oopMeta, rev: await getRev(db, sess, payload) });
    }

    if (action === "suaPsHoaDonBulk") {
      if (sess.r !== "admin") return json({ ok: false, error: "forbidden" }, 403);
      const rows = (payload && payload.rows) || [];
      if (!rows.length) return json({ ok: false, error: "no_rows" }, 400);
      const p_rows = rows.map((r: Record<string, unknown>) => ({
        thang:      String(r.thang || ""),
        ma_kh:      String(r.maKh || ""),
        bo_vat_tu:  String(r.boVatTu || ""),
        san_pham:   String(r.sanPham || ""),
        ps_cu:      String(r.psCu || ""),
        ps_moi:     String(r.psMoi || ""),
      })).filter((r: { thang: string; ma_kh: string; ps_moi: string }) => r.thang && r.ma_kh && r.ps_moi);
      if (!p_rows.length) return json({ ok: false, error: "no_rows" }, 400);
      const { data, error } = await db.rpc("sua_ps_hoa_don_bulk", { p_rows });
      if (error) {
        const msg = String(error.message || "");
        if (msg.includes("thieu_du_lieu")) return json({ ok: false, error: msg }, 400);
        return json({ ok: false, error: msg }, 500);
      }
      await writeAuditLog(db, sess, "suaPsHoaDonBulk", p_rows.length, { stats: data });
      return json({ ok: true, stats: data, rev: await getRev(db, sess, payload) });
    }

    if (action === "suaPsHoaDon") {
      if (sess.r !== "admin") return json({ ok: false, error: "forbidden" }, 403);
      const p = payload || {};
      if (!p.thang || !p.maKh || !p.psMoi) {
        return json({ ok: false, error: "thieu_du_lieu" }, 400);
      }
      const { data, error } = await db.rpc("sua_ps_hoa_don", {
        p_thang:     String(p.thang),
        p_ma_kh:     String(p.maKh),
        p_bo_vat_tu: String(p.boVatTu || ""),
        p_san_pham:  String(p.sanPham || ""),
        p_ps_cu:     String(p.psCu || ""),
        p_ps_moi:    String(p.psMoi),
      });
      if (error) {
        const msg = String(error.message || "");
        if (msg.includes("ps_khong_ton_tai")) return json({ ok: false, error: msg }, 404);
        if (msg.includes("thieu_du_lieu"))    return json({ ok: false, error: msg }, 400);
        return json({ ok: false, error: msg }, 500);
      }
      await writeAuditLog(db, sess, "suaPsHoaDon", 1, {
        thang: p.thang, maKh: p.maKh, psCu: p.psCu, psMoi: p.psMoi,
      });
      return json({ ok: true, stats: data, rev: await getRev(db, sess, payload) });
    }

    if (action === "updateCells") {
      if (!canEdit) return json({ ok: false, error: "forbidden" }, 403);
      const isAdmin = sess.r === "admin";
      const updates = payload.updates || [];
      const rowRevs: Record<number, number> = payload.rowRevs || {};
      const byRow = new Map<number, Record<string, unknown>>();
      for (const u of updates) {
        const allowed = EDITABLE.has(u.key) || (isAdmin && ADMIN_EDITABLE.has(u.key));
        if (!allowed) continue;
        const id = Number(u.row);
        if (!Number.isFinite(id)) continue;
        let patch = byRow.get(id);
        if (!patch) { patch = {}; byRow.set(id, patch); }
        patch[COL[u.key]] = u.value === "" ? null : u.value;
      }
      let conflicts: Record<string, unknown>[] = [];
      if (byRow.size > 0) {
        const rowIds = [...byRow.keys()];
        const changedDbCols = new Set<string>();
        for (const [, patch] of byRow) for (const c of Object.keys(patch)) changedDbCols.add(c);
        const selectCols = ["id", "ps", "khach_hang", "ma_khach_hang", ...changedDbCols].join(",");
        const { data: oldRows } = await db.schema("shared").from("sale_target")
          .select(selectCols).in("id", rowIds);
        const oldMap = new Map<number, Record<string, unknown>>();
        if (oldRows) for (const r of oldRows) oldMap.set(r.id, r);

        const p_updates = Array.from(byRow, ([id, patch]) => {
          const rev = rowRevs[id];
          return rev ? { id, patch, _rev: rev } : { id, patch };
        });
        const { data: rpcResult, error } = await db.rpc("update_sale_target_cells", {
          p_updates, ...scopeParams(sess),
        });
        if (error) {
          if (String(error.message || "").includes("out_of_scope")) {
            return json({ ok: false, error: "forbidden_rows" }, 403);
          }
          throw new Error(error.message);
        }
        if (rpcResult && Array.isArray(rpcResult.conflicts)) {
          const COL_INV: Record<string, string> = {};
          for (const [k, v] of Object.entries(COL)) COL_INV[v as string] = k;
          conflicts = rpcResult.conflicts.map((c: Record<string, unknown>) => {
            const vals = (c.values || {}) as Record<string, unknown>;
            const mapped: Record<string, unknown> = {};
            for (const [dbCol, val] of Object.entries(vals)) {
              const field = COL_INV[dbCol];
              if (field) mapped[field] = val;
            }
            return { id: c.id, _rev: c._rev, values: mapped };
          });
        }
        const cols = new Set<string>();
        for (const u of updates) if (EDITABLE.has(u.key) || ADMIN_EDITABLE.has(u.key)) cols.add(u.key);
        const changes = rowIds.slice(0, 50).map(id => {
          const old = oldMap.get(id) || {};
          const patch = byRow.get(id) || {};
          const diff: Record<string, { old: unknown; new: unknown }> = {};
          for (const [col, newVal] of Object.entries(patch)) {
            diff[col] = { old: old[col] ?? null, new: newVal };
          }
          return { id, ps: old.ps, cust: old.khach_hang, custId: old.ma_khach_hang, diff };
        });
        await writeAuditLog(db, sess, "updateCells", byRow.size, {
          columns: [...cols],
          ids: rowIds,
          changes,
        });
      }
      const rev = await getRev(db, sess, payload);
      return json({ ok: true, rev, conflicts });
    }

    if (action === "saveDotThau") {
      if (!canEdit) return json({ ok: false, error: "forbidden" }, 403);
      const rows = Array.isArray(payload.rows) ? payload.rows : [];
      if (!rows.length) return json({ ok: false, error: "no_rows" }, 400);
      const { data, error } = await db.rpc("upsert_dot_thau", {
        p_rows: rows, ...scopeParams(sess), p_actor: sess.u,
      });
      if (error) {
        const msg = String(error.message || "");
        if (msg.includes("out_of_scope")) return json({ ok: false, error: "forbidden_rows" }, 403);
        if (msg.includes("thang_sai_dinh_dang")) return json({ ok: false, error: "thang_sai_dinh_dang" }, 400);
        if (msg.includes("dot_thieu_thong_tin")) return json({ ok: false, error: msg.replace(/^.*dot_thieu_thong_tin:\s*/, "") }, 400);
        if (msg.includes("loai_khong_hop_le")) return json({ ok: false, error: "loai_khong_hop_le" }, 400);
        throw new Error(msg);
      }
      await writeAuditLog(db, sess, "saveDotThau", Number(data) || rows.length, {
        rows: rows.slice(0, 50),
      });
      return json({ ok: true, saved: Number(data) || 0 });
    }

    if (action === "deleteDotThau") {
      if (!canEdit) return json({ ok: false, error: "forbidden" }, 403);
      const dot = Number(payload.dot);
      if (!payload.fy || !payload.ps || !payload.loai || !Number.isFinite(dot)) {
        return json({ ok: false, error: "thieu_tham_so" }, 400);
      }
      const { data, error } = await db.rpc("delete_dot_thau", {
        p_fy: payload.fy, p_ps_row: payload.ps,
        p_cust: payload.custId ?? "", p_grp: payload.grp ?? "",
        p_loai: payload.loai, p_dot: dot,
        ...scopeParams(sess),
      });
      if (error) {
        if (String(error.message || "").includes("out_of_scope")) {
          return json({ ok: false, error: "forbidden_rows" }, 403);
        }
        throw new Error(error.message);
      }
      await writeAuditLog(db, sess, "deleteDotThau", Number(data) || 0, {
        fy: payload.fy, ps: payload.ps, custId: payload.custId ?? "",
        grp: payload.grp ?? "", loai: payload.loai, dot,
      });
      return json({ ok: true, deleted: Number(data) || 0 });
    }

    if (action === "saveQuotaThau") {
      if (!canEdit) return json({ ok: false, error: "forbidden" }, 403);
      const rows = Array.isArray(payload.rows) ? payload.rows : [];
      if (!rows.length) return json({ ok: false, error: "no_rows" }, 400);
      const { data, error } = await db.rpc("upsert_quota_thau", {
        p_rows: rows, ...scopeParams(sess), p_actor: sess.u,
      });
      if (error) {
        const msg = String(error.message || "");
        if (msg.includes("out_of_scope")) return json({ ok: false, error: "forbidden_rows" }, 403);
        if (msg.includes("dot_khong_ton_tai")) return json({ ok: false, error: "dot_khong_ton_tai" }, 400);
        if (msg.includes("dot_thieu_thong_tin")) return json({ ok: false, error: msg.replace(/^.*dot_thieu_thong_tin:\s*/, "") }, 400);
        if (msg.includes("loai_khong_hop_le")) return json({ ok: false, error: "loai_khong_hop_le" }, 400);
        throw new Error(msg);
      }
      await writeAuditLog(db, sess, "saveQuotaThau", Number(data) || rows.length, {
        rows: rows.slice(0, 50),
      });
      return json({ ok: true, saved: Number(data) || 0 });
    }

    if (action === "deleteProduct") {
      if (sess.r !== "admin") return json({ ok: false, error: "forbidden" }, 403);
      const ids = (payload.rows || []).map(Number).filter((n: number) => Number.isFinite(n));
      if (!ids.length) return json({ ok: false, error: "no_rows" }, 400);
      const { error } = await db.schema("shared").from("sale_target").delete().in("id", ids);
      if (error) throw new Error(error.message);
      await writeAuditLog(db, sess, "deleteProduct", ids.length, { ids: ids.slice(0, 50) });
      return json({ ok: true, rev: await getRev(db, sess, payload) });
    }

    if (action === "deleteCustomer") {
      if (sess.r !== "admin") return json({ ok: false, error: "forbidden" }, 403);
      const ids = (payload.rows || []).map(Number).filter((n: number) => Number.isFinite(n));
      if (!ids.length) return json({ ok: false, error: "no_rows" }, 400);
      const CHUNK = 200;
      // Chặn xoá lan sang PS khác: 1 KH thường do nhiều PS cùng phụ trách. Client
      // phải gửi multiPs=true (người dùng đã thấy danh sách PS khi xác nhận).
      const psSet = new Set<string>();
      for (let i = 0; i < ids.length; i += CHUNK) {
        const { data, error } = await db.schema("shared").from("sale_target")
          .select("ps").in("id", ids.slice(i, i + CHUNK));
        if (error) throw new Error(error.message);
        for (const r of data || []) psSet.add(String(r.ps ?? ""));
      }
      if (psSet.size > 1 && payload.multiPs !== true) {
        return json({ ok: false, error: "multi_ps", ps: [...psSet] }, 409);
      }
      for (let i = 0; i < ids.length; i += CHUNK) {
        const { error } = await db.schema("shared").from("sale_target").delete().in("id", ids.slice(i, i + CHUNK));
        if (error) throw new Error(error.message);
      }
      await writeAuditLog(db, sess, "deleteCustomer", ids.length, { ids: ids.slice(0, 50), ps: [...psSet] });
      return json({ ok: true, deleted: ids.length, rev: await getRev(db, sess, payload) });
    }

    if (action === "addProduct") {
      if (!canEdit) return json({ ok: false, error: "forbidden" }, 403);
      const s = payload;
      const { data: any1 } = await db.schema("shared").from("sale_target").select("nam_tai_chinh").limit(1);
      const fy = any1 && any1[0] ? any1[0].nam_tai_chinh : "FY26";
      const MONTHS = ["2026-04","2026-05","2026-06","2026-07","2026-08","2026-09",
        "2026-10","2026-11","2026-12","2027-01","2027-02","2027-03"];
      const psName = sess.r === "ps" ? sess.s : String(s.ps || "").trim();
      if (!psName) return json({ ok: false, error: "Chưa chọn PS phụ trách" }, 400);
      const priceNum = Number(s.price);
      let price = Number.isFinite(priceNum) && priceNum > 0 ? priceNum : null;
      let bu: string;
      try {
        bu = await buForPs(db, psName, sess.b);
      } catch (e) {
        return json({ ok: false, error: String(e && (e as Error).message || e) }, 409);
      }
      if (sess.r === "area_manager") {
        const psMien = await mienForPs(db, psName);
        if (bu !== sess.b || !psMien || !mienScope(sess).includes(psMien)) {
          return json({
            ok: false,
            error: !psMien
              ? `PS "${psName}" chưa xác định được miền (chưa có trong dm_ps và chưa có dữ liệu sale_target). Nhờ admin thêm PS vào dm_ps trước.`
              : `PS "${psName}" không thuộc phạm vi của bạn (${sess.b} / ${sess.s})`,
          }, 403);
        }
      }
      const gLimits = parseGroups(sess.g);
      if (gLimits.length && !gLimits.includes(String(s.grp || "").trim())) {
        return json({
          ok: false,
          error: `Nhóm SP "${s.grp || ""}" không thuộc phạm vi của bạn (${gLimits.join(", ")})`,
        }, 403);
      }
      // area_manager: miền của dòng = miền của PS (đã kiểm tra thuộc phạm vi ở trên).
      let mien = sess.r === "area_manager" ? "" : String(s.region || "").trim();
      if (!mien) mien = await mienForPs(db, psName) || "";
      const prodTrim = String(s.prod || "").trim();
      const msetTrim = String(s.mset || "").trim();
      let maSp: string | null = null;
      let maBvt: string | null = null;
      if (prodTrim) {
        const { data: dvt } = await db.schema("shared").from("dm_vat_tu")
          .select("ma_san_pham").ilike("san_pham", prodTrim).limit(1);
        if (dvt && dvt[0]) maSp = dvt[0].ma_san_pham || null;
      }
      if (msetTrim) {
        const { data: dbvt } = await db.schema("shared").from("dm_bo_vat_tu")
          .select("ma_bo_vat_tu").ilike("bo_vat_tu", msetTrim).limit(1);
        if (dbvt && dbvt[0]) maBvt = dbvt[0].ma_bo_vat_tu || null;
      }
      if (!maSp && prodTrim) {
        const { data: dbvtSp } = await db.schema("shared").from("dm_bo_vat_tu")
          .select("ma_bo_vat_tu").ilike("bo_vat_tu", prodTrim).limit(1);
        if (dbvtSp && dbvtSp[0]) maSp = dbvtSp[0].ma_bo_vat_tu || null;
      }
      // CTTM & CTUT: đơn giá theo danh mục vật tư, thay giá nhập tay khi khớp.
      if (bu === BU_GIA_DANH_MUC) {
        const giaDm = (await giaDanhMucCttm(db))(s.prod || "", maSp);
        if (giaDm !== null) price = giaDm;
      }
      let dupQ = db.schema("shared").from("sale_target")
        .select("id", { count: "exact", head: true })
        .eq("nam_tai_chinh", fy).eq("thang_ke_hoach", MONTHS[0])
        .eq("ps", psName).eq("ma_khach_hang", s.custId || "")
        .eq("nhom_san_pham", s.grp || "").eq("bo_vat_tu", s.mset || "")
        .eq("san_pham", s.prod || "")
        // Dòng OOP (đồng bộ thực hiện) không phải kế hoạch — hấp thụ sau insert.
        .not("ngoai_ke_hoach", "is", true);
      if (price !== null) dupQ = dupQ.eq("don_gia", price);
      else dupQ = dupQ.is("don_gia", null);
      const { count: dupCount } = await dupQ;
      if (dupCount && dupCount > 0) {
        return json({ ok: false, error: "duplicate", message: "Sản phẩm đã tồn tại trong kế hoạch" }, 409);
      }
      const loiHieuLuc = kiemTraThangHieuLuc([s]);
      if (loiHieuLuc) return json({ ok: false, error: loiHieuLuc }, 400);
      const rowsIns = MONTHS.map((mo) => ({
        nam_tai_chinh: fy, thang_ke_hoach: mo, mien, ps: psName,
        khach_hang: s.cust, ma_khach_hang: s.custId, nhom_san_pham: s.grp,
        san_pham: s.prod, bo_vat_tu: s.mset,
        ma_san_pham: maSp, ma_bo_vat_tu: maBvt,
        don_gia: price,
        bu,
        sl_ke_hoach_dau_nam: 0, sl_thuc_hien: 0,
      }));
      const cols = FIELDS.map((f) => COL[f]).join(",") + ",id,_rev";
      const { data: ins, error } = await db.schema("shared").from("sale_target").insert(rowsIns).select(cols);
      if (error) throw new Error(error.message);
      const inserted = ins || [];
      const absorbed = await absorbOop(db, inserted, cols);
      // Tháng thầu → đợt thầu của nhóm (sale_target không còn lưu tháng thầu).
      const dotMoi = await taoDotTuThangThau(db, sess, [
        { fy, ps: psName, custId: s.custId, grp: s.grp, mMain: s.mMain, mAdd: s.mAdd, hlMain: s.hlMain, hlAdd: s.hlAdd },
      ]);
      await writeAuditLog(db, sess, "addProduct", inserted.length, {
        ps: psName, cust: s.cust, grp: s.grp, prod: s.prod, mset: s.mset, bu, absorbed, dotMoi,
      });
      return json({
        ok: true,
        rows: inserted.map((r: Record<string, unknown>) =>
          FIELDS.map((f) => {
            const v = r[COL[f]];
            return v === null || v === undefined ? "" : v;
          })
        ),
        rowNums: inserted.map((r: Record<string, unknown>) => r.id),
        absorbed,
        dotMoi,
        rev: await getRev(db, sess, payload),
      });
    }

    if (action === "ensureMonthRow") {
      const isAdmin = sess.r === "admin";
      if (!isAdmin) return json({ ok: false, error: "forbidden" }, 403);
      const refRow = Number(payload.refRow);
      const month = String(payload.month || "");
      const rev = Number(payload.rev) || 0;
      if (!refRow || !month) return json({ ok: false, error: "refRow and month required" }, 400);
      const cols = FIELDS.map((f) => COL[f]).join(",") + ",id,_rev";
      const { data: ref, error: refErr } = await db.schema("shared").from("sale_target")
        .select(cols).eq("id", refRow).single();
      if (refErr || !ref) return json({ ok: false, error: "ref row not found" }, 404);
      let dupQ = db.schema("shared").from("sale_target")
        .select("id", { count: "exact", head: true })
        .eq("nam_tai_chinh", ref.nam_tai_chinh)
        .eq("thang_ke_hoach", month)
        .eq("ps", ref.ps)
        .eq("ma_khach_hang", ref.ma_khach_hang)
        .eq("nhom_san_pham", ref.nhom_san_pham)
        .eq("bo_vat_tu", ref.bo_vat_tu)
        .eq("san_pham", ref.san_pham)
        .not("ngoai_ke_hoach", "is", true);
      if (ref.don_gia !== null) dupQ = dupQ.eq("don_gia", ref.don_gia);
      else dupQ = dupQ.is("don_gia", null);
      // head:true không trả data — số dòng nằm ở `count`.
      const { count: dupCount } = await dupQ;
      if (dupCount && dupCount > 0) {
        return json({ ok: false, error: "row_exists" }, 409);
      }
      const price = Number(ref.don_gia) || 0;
      const newRow = {
        nam_tai_chinh: ref.nam_tai_chinh,
        thang_ke_hoach: month,
        mien: ref.mien,
        ps: ref.ps,
        khach_hang: ref.khach_hang,
        ma_khach_hang: ref.ma_khach_hang,
        nhom_san_pham: ref.nhom_san_pham,
        san_pham: ref.san_pham,
        bo_vat_tu: ref.bo_vat_tu,
        ma_san_pham: ref.ma_san_pham,
        ma_bo_vat_tu: ref.ma_bo_vat_tu,
        don_gia: ref.don_gia,
        bu: ref.bu,
        sl_ke_hoach_dau_nam: rev,
        doanh_thu_kh_dau_nam: rev * price,
        sl_thuc_hien: 0,
      };
      const { data: ins, error: insErr } = await db.schema("shared").from("sale_target")
        .insert([newRow]).select(cols);
      if (insErr) throw new Error(insErr.message);
      const inserted = (ins || [])[0];
      if (!inserted) return json({ ok: false, error: "insert failed" }, 500);
      await writeAuditLog(db, sess, "ensureMonthRow", 1, {
        refRow, month, rev, newId: inserted.id,
      });
      return json({
        ok: true,
        row: FIELDS.map((f) => {
          const v = (inserted as Record<string, unknown>)[COL[f]];
          return v === null || v === undefined ? "" : v;
        }),
        rowNum: inserted.id,
        rowRev: Number(inserted._rev) || 0,
        rev: await getRev(db, sess, payload),
      });
    }

    if (action === "addProducts") {
      if (!canEdit) return json({ ok: false, error: "forbidden" }, 403);
      const items = payload.items;
      if (!Array.isArray(items) || items.length === 0)
        return json({ ok: false, error: "items required" }, 400);
      if (items.length > 200)
        return json({ ok: false, error: "max 200 items per batch" }, 400);
      const loiHieuLucLo = kiemTraThangHieuLuc(items);
      if (loiHieuLucLo) return json({ ok: false, error: loiHieuLucLo }, 400);

      const { data: any1 } = await db.schema("shared").from("sale_target")
        .select("nam_tai_chinh").limit(1);
      const fy = any1 && any1[0] ? any1[0].nam_tai_chinh : "FY26";
      const MONTHS = ["2026-04","2026-05","2026-06","2026-07","2026-08","2026-09",
        "2026-10","2026-11","2026-12","2027-01","2027-02","2027-03"];

      const psInfoCache = new Map<string, { bu: string; mien: string } | null>();
      for (const s of items) {
        const ps = sess.r === "ps" ? sess.s : String(s.ps || "").trim();
        if (!ps || psInfoCache.has(ps)) continue;
        try {
          const psBu = await buForPs(db, ps, sess.b);
          let psMien = "";
          if (sess.r === "area_manager") {
            const m = await mienForPs(db, ps);
            if (psBu !== sess.b || !m || !mienScope(sess).includes(m)) {
              psInfoCache.set(ps, null);
              continue;
            }
            psMien = m;
          } else {
            psMien = await mienForPs(db, ps) || "";
          }
          psInfoCache.set(ps, { bu: psBu, mien: psMien });
        } catch {
          psInfoCache.set(ps, null);
        }
      }

      const gLimits = parseGroups(sess.g);
      const raws: {
        ps: string; bu: string; mien: string; custId: string; cust: string;
        grp: string; mset: string; prod: string; price: number | null;
        mMain: unknown; mAdd: unknown; hlMain: unknown; hlAdd: unknown;
      }[] = [];
      for (const s of items) {
        const ps = sess.r === "ps" ? sess.s : String(s.ps || "").trim();
        const info = psInfoCache.get(ps);
        if (!info) continue;
        const grp = String(s.grp || "");
        if (gLimits.length && !gLimits.includes(grp)) continue;
        const priceNum = Number(s.price);
        const price = Number.isFinite(priceNum) && priceNum > 0 ? priceNum : null;
        raws.push({
          ps, bu: info.bu, mien: s.region || info.mien, custId: String(s.custId || ""),
          cust: String(s.cust || ""), grp, mset: String(s.mset || ""), prod: String(s.prod || ""),
          price, mMain: s.mMain, mAdd: s.mAdd, hlMain: s.hlMain, hlAdd: s.hlAdd,
        });
      }

      const uniqProds = [...new Set(raws.map(c => c.prod).filter(Boolean))];
      const uniqMsets = [...new Set(raws.map(c => c.mset).filter(Boolean))];
      const maSpMap = new Map<string, string>();
      const maBvtMap = new Map<string, string>();
      if (uniqProds.length) {
        const { data: dvt } = await db.schema("shared").from("dm_vat_tu")
          .select("san_pham, ma_san_pham").in("san_pham", uniqProds);
        for (const r of dvt || []) {
          if (r.san_pham && r.ma_san_pham && !maSpMap.has(r.san_pham))
            maSpMap.set(r.san_pham, r.ma_san_pham);
        }
      }
      if (uniqMsets.length) {
        const { data: dbvt } = await db.schema("shared").from("dm_bo_vat_tu")
          .select("bo_vat_tu, ma_bo_vat_tu").in("bo_vat_tu", uniqMsets);
        for (const r of dbvt || []) {
          if (r.bo_vat_tu && r.ma_bo_vat_tu && !maBvtMap.has(r.bo_vat_tu))
            maBvtMap.set(r.bo_vat_tu, r.ma_bo_vat_tu);
        }
      }
      const prodsNeedFallback = uniqProds.filter(p => !maSpMap.has(p));
      if (prodsNeedFallback.length) {
        const { data: dbvtSp } = await db.schema("shared").from("dm_bo_vat_tu")
          .select("bo_vat_tu, ma_bo_vat_tu").in("bo_vat_tu", prodsNeedFallback);
        for (const r of dbvtSp || []) {
          if (r.bo_vat_tu && r.ma_bo_vat_tu && !maSpMap.has(r.bo_vat_tu))
            maSpMap.set(r.bo_vat_tu, r.ma_bo_vat_tu);
        }
      }

      // CTTM & CTUT: đơn giá theo danh mục vật tư thay cho giá hoá đơn (ex-VAT) gửi lên,
      // để không sinh lại dòng lệch giá danh mục. Không khớp danh mục → giữ giá cũ.
      if (raws.some(c => c.bu === BU_GIA_DANH_MUC)) {
        const giaDm = await giaDanhMucCttm(db);
        for (const c of raws) {
          if (c.bu !== BU_GIA_DANH_MUC) continue;
          const g = giaDm(c.prod, maSpMap.get(c.prod) || null);
          if (g !== null) c.price = g;
        }
      }

      // Khoá dedup / trùng kế hoạch tính theo giá SAU khi thay.
      const candidates: (typeof raws[number] & { key: string })[] = [];
      const seenKeys = new Set<string>();
      for (const c of raws) {
        const key = `${c.ps}\0${c.custId}\0${c.grp}\0${c.mset}\0${c.prod}\0${c.price}`;
        if (seenKeys.has(key)) continue;
        seenKeys.add(key);
        candidates.push({ ...c, key });
      }

      const existSet = new Set<string>();
      const uniquePs = [...new Set(candidates.map(c => c.ps))];
      if (uniquePs.length && candidates.length) {
        for (let from = 0; ; from += PAGE) {
          const { data } = await db.schema("shared").from("sale_target")
            .select("ps, ma_khach_hang, nhom_san_pham, bo_vat_tu, san_pham, don_gia")
            .eq("nam_tai_chinh", fy)
            .eq("thang_ke_hoach", MONTHS[0])
            .in("ps", uniquePs)
            // Dòng OOP (đồng bộ thực hiện) không phải kế hoạch — hấp thụ sau insert.
            .not("ngoai_ke_hoach", "is", true)
            .range(from, from + PAGE - 1);
          if (!data || data.length === 0) break;
          for (const r of data) {
            const p = Number(r.don_gia);
            const price = Number.isFinite(p) && p > 0 ? p : null;
            existSet.add(`${r.ps}\0${r.ma_khach_hang}\0${r.nhom_san_pham}\0${r.bo_vat_tu}\0${r.san_pham}\0${price}`);
          }
          if (data.length < PAGE) break;
        }
      }

      const toInsert = candidates.filter(c => !existSet.has(c.key));
      const skipped = items.length - toInsert.length;

      if (toInsert.length === 0) {
        return json({ ok: true, rows: [], rowNums: [], rowRevs: [], skipped, rev: await getRev(db, sess, payload) });
      }

      const allRowsIns = toInsert.flatMap(c =>
        MONTHS.map(mo => ({
          nam_tai_chinh: fy, thang_ke_hoach: mo, mien: c.mien, ps: c.ps,
          khach_hang: c.cust, ma_khach_hang: c.custId, nhom_san_pham: c.grp,
          san_pham: c.prod, bo_vat_tu: c.mset,
          ma_san_pham: maSpMap.get(c.prod) || null,
          ma_bo_vat_tu: maBvtMap.get(c.mset) || null,
          don_gia: c.price,
          bu: c.bu, sl_ke_hoach_dau_nam: 0, sl_thuc_hien: 0,
        }))
      );

      const cols = FIELDS.map((f) => COL[f]).join(",") + ",id,_rev";
      const inserted: Record<string, unknown>[] = [];
      for (let i = 0; i < allRowsIns.length; i += PAGE) {
        const batch = allRowsIns.slice(i, i + PAGE);
        const { data: ins, error } = await db.schema("shared").from("sale_target").insert(batch).select(cols);
        if (error) throw new Error(error.message);
        inserted.push(...(ins || []));
      }
      const absorbed = await absorbOop(db, inserted, cols);
      const dotMoi = await taoDotTuThangThau(db, sess, toInsert.map((c) => ({
        fy, ps: c.ps, custId: c.custId, grp: c.grp, mMain: c.mMain, mAdd: c.mAdd, hlMain: c.hlMain, hlAdd: c.hlAdd,
      })));

      await writeAuditLog(db, sess, "addProduct", inserted.length, {
        batch: items.length, inserted: toInsert.length, skipped, absorbed, dotMoi,
      });
      return json({
        ok: true,
        rows: inserted.map((r) => FIELDS.map((f) => { const v = r[COL[f]]; return v === null || v === undefined ? "" : v; })),
        rowNums: inserted.map((r) => r.id),
        rowRevs: inserted.map((r) => Number(r._rev) || 0),
        skipped,
        absorbed,
        dotMoi,
        rev: await getRev(db, sess, payload),
      });
    }

    if (action === "getDiaBan") {
      const out: Record<string, unknown>[] = [];
      for (let from = 0; ; from += PAGE) {
        let q = db.schema("shared").from("dm_dia_ban")
          .select("id, bu, ma_khach_hang, khach_hang, nhom_san_pham, mien, ps, active, tu_thang, den_thang")
          .order("id", { ascending: true })
          .range(from, from + PAGE - 1);
        q = applyScope(q, sess, payload);
        const { data, error } = await q;
        if (error) throw new Error(error.message);
        if (!data || data.length === 0) break;
        for (const d of data) {
          out.push({
            id: d.id, bu: d.bu ?? "", custId: d.ma_khach_hang ?? "",
            cust: d.khach_hang ?? "", grp: d.nhom_san_pham ?? "",
            mien: d.mien ?? "", ps: d.ps ?? "", active: d.active !== false,
            tuThang: d.tu_thang ?? "", denThang: d.den_thang ?? "",
          });
        }
        if (data.length < PAGE) break;
      }
      return json({ ok: true, diaBan: out });
    }

    if (action === "saveDiaBan") {
      const isPs = sess.r === "ps";
      if (sess.r !== "admin" && sess.r !== "manager" && !isPs) return json({ ok: false, error: "forbidden" }, 403);
      const rows = payload.rows || [];
      if (!rows.length) return json({ ok: false, error: "no_rows" }, 400);
      if (isPs) {
        const chan = await kiemTraPsThemDiaBan(db, sess, rows);
        if (chan) return json({ ok: false, error: chan.error }, chan.status);
      }
      const ids = rows.map((r: Record<string, unknown>) => Number(r.id)).filter((n: number) => Number.isFinite(n));
      const oldMien = new Map<number, string>();
      if (ids.length) {
        const { data, error } = await db.schema("shared").from("dm_dia_ban").select("id, mien").in("id", ids);
        if (error) throw new Error(error.message);
        for (const d of data || []) oldMien.set(d.id, d.mien ?? "");
      }
      const buCache = new Map<string, string>();
      const mienCache = new Map<string, string | null>();
      const p_rows: Record<string, unknown>[] = [];
      for (const r of rows) {
        const ps = String(r.ps || "").trim();
        const id = Number(r.id);
        let bu = "";
        if (!Number.isFinite(id)) {
          if (!buCache.has(ps)) {
            try {
              buCache.set(ps, await buForPs(db, ps, sess.b));
            } catch (e) {
              return json({ ok: false, error: String(e && (e as Error).message || e) }, 409);
            }
          }
          bu = buCache.get(ps) || "";
        }
        if (!mienCache.has(ps)) mienCache.set(ps, await mienForPs(db, ps));
        p_rows.push({
          id: Number.isFinite(id) ? id : null,
          bu,
          ma_khach_hang: r.custId ?? "",
          khach_hang: r.cust ?? "",
          nhom_san_pham: r.grp ?? "",
          mien: mienCache.get(ps) || oldMien.get(id) || "",
          ps,
          active: r.active !== false,
          tu_thang: r.tuThang ?? "",
          den_thang: r.denThang ?? "",
        });
      }
      const { data, error } = await db.rpc("upsert_dm_dia_ban", {
        p_rows, ...scopeParams(sess),
      });
      if (error) return diaBanErr(error, req);
      await writeAuditLog(db, sess, "saveDiaBan", p_rows.length, { count: p_rows.length });
      return json({ ok: true, stats: data });
    }

    if (action === "chuyenDiaBan") {
      if (sess.r !== "admin" && sess.r !== "manager") return json({ ok: false, error: "forbidden" }, 403);
      const id = Number(payload.id);
      const psMoi = String(payload.ps || "").trim();
      const tuThang = String(payload.tuThang || "").trim();
      if (!Number.isFinite(id) || !psMoi || !tuThang) {
        return json({ ok: false, error: "thieu_du_lieu" }, 400);
      }
      const sc = scopeParams(sess);
      const { data, error } = await db.rpc("chuyen_dia_ban", {
        p_id: id,
        p_ps_moi: psMoi,
        p_mien: await mienForPs(db, psMoi),
        p_tu_thang: tuThang,
        p_bu: sc.p_bu,
        p_mien_scope: sc.p_mien,
        p_ps_scope: sc.p_ps,
        p_groups: sc.p_groups,
      });
      if (error) return diaBanErr(error, req);
      await writeAuditLog(db, sess, "chuyenDiaBan", 1, { id, psMoi, tuThang });
      return json({ ok: true, stats: data });
    }

    if (action === "dopChongLan") {
      if (sess.r !== "admin") return json({ ok: false, error: "forbidden" }, 403);
      const thang = String((payload && payload.thang) || "").trim();
      if (!/^\d{4}-\d{2}$/.test(thang)) {
        return json({ ok: false, error: "thang_khong_hop_le" }, 400);
      }
      const { data, error } = await db.rpc("dep_dia_ban_chong_lan", { p_thang: thang });
      if (error) {
        const msg = String(error.message || "");
        if (msg.includes("thang_khong_hop_le")) return json({ ok: false, error: msg }, 400);
        return json({ ok: false, error: msg }, 500);
      }
      await writeAuditLog(db, sess, "dopChongLan", Number(data) || 0, { thang });
      return json({ ok: true, stats: data, rev: await getRev(db, sess, payload) });
    }

    if (action === "deleteDiaBan") {
      if (sess.r !== "admin" && sess.r !== "manager") return json({ ok: false, error: "forbidden" }, 403);
      const ids = (payload.ids || []).map(Number).filter((n: number) => Number.isFinite(n));
      if (!ids.length) return json({ ok: false, error: "no_rows" }, 400);
      const { data, error } = await db.rpc("delete_dm_dia_ban", {
        p_ids: ids, ...scopeParams(sess),
      });
      if (error) return diaBanErr(error, req);
      await writeAuditLog(db, sess, "deleteDiaBan", ids.length, { ids: ids.slice(0, 50) });
      return json({ ok: true, stats: data });
    }

    if (action === "getAuditLog") {
      if (sess.r !== "admin" && sess.r !== "manager") return json({ ok: false, error: "forbidden" }, 403);
      const page = Math.max(1, Number(payload.page) || 1);
      const limit = Math.min(100, Math.max(1, Number(payload.limit) || 50));
      const from = (page - 1) * limit;
      let q = db.schema("shared").from("audit_log")
        .select("*", { count: "exact" })
        .order("created_at", { ascending: false })
        .range(from, from + limit - 1);
      if (payload.username) q = q.eq("username", payload.username);
      if (payload.action) q = q.eq("action", payload.action);
      if (payload.bu) q = q.eq("bu", payload.bu);
      if (payload.from) q = q.gte("created_at", payload.from);
      if (payload.to) q = q.lte("created_at", payload.to);
      const { data, error, count } = await q;
      if (error) throw new Error(error.message);
      return json({ ok: true, logs: data || [], total: count || 0, page, limit });
    }

    if (action === "getAppConfig") {
      if (sess.r !== "admin" && sess.r !== "manager") return json({ ok: false, error: "forbidden" }, 403);
      const { data, error } = await db.schema("shared").from("app_config").select("key, value");
      if (error) throw new Error(error.message);
      const cfg: Record<string, unknown> = {};
      for (const r of data || []) cfg[r.key] = r.value;
      return json({ ok: true, config: cfg });
    }

    if (action === "setAppConfig") {
      if (sess.r !== "admin") return json({ ok: false, error: "forbidden" }, 403);
      const key = String(payload.key || "").trim();
      if (!key) return json({ ok: false, error: "missing_key" }, 400);
      const { error } = await db.schema("shared").from("app_config")
        .upsert({ key, value: payload.value, updated_at: new Date().toISOString() }, { onConflict: "key" });
      if (error) throw new Error(error.message);
      await writeAuditLog(db, sess, "setAppConfig", 1, { key, value: payload.value });
      return json({ ok: true });
    }

    if (action === "getGiaiTrinh") {
      let ps = String(payload.ps || "").trim();
      const custId = String(payload.customer_id || "").trim();
      const grp = String(payload.grp || "").trim();
      if (!ps || !custId) return json({ ok: false, error: "missing_params" }, 400);
      if (sess.r === "ps") ps = sess.s;
      else if (sess.r === "area_manager") {
        const info = await psInfo(db, ps);
        if (!info || !mienScope(sess).includes(String(info.area))) return json({ ok: false, error: "out_of_scope" }, 403);
      } else if (sess.r === "product_manager") {
        if (grp) {
          const groups = String(sess.s || "").split(",").map((x: string) => x.trim()).filter(Boolean);
          if (groups.length && !groups.includes(grp)) return json({ ok: false, error: "out_of_scope" }, 403);
        }
      }
      const gLimits = parseGroups(sess.g);
      if (gLimits.length && grp && !gLimits.includes(grp)) return json({ ok: false, error: "out_of_scope" }, 403);
      let q = db.schema("shared").from("giai_trinh")
        .select("id, content, created_by, created_at")
        .eq("ps", ps).eq("customer_id", custId);
      if (grp) q = q.eq("grp", grp);
      q = q.order("created_at", { ascending: false }).limit(50);
      const { data, error } = await q;
      if (error) throw new Error(error.message);
      return json({ ok: true, logs: data || [] });
    }

    if (action === "saveGiaiTrinh") {
      if (!canEdit) return json({ ok: false, error: "forbidden" }, 403);
      let ps = String(payload.ps || "").trim();
      const custId = String(payload.customer_id || "").trim();
      const grp = String(payload.grp || "").trim();
      const content = String(payload.content || "").trim();
      if (!ps || !custId || !content) return json({ ok: false, error: "missing_params" }, 400);
      if (sess.r === "ps") ps = sess.s;
      else if (sess.r === "area_manager") {
        const info = await psInfo(db, ps);
        if (!info || !mienScope(sess).includes(String(info.area))) return json({ ok: false, error: "out_of_scope" }, 403);
      } else if (sess.r === "product_manager") {
        if (grp) {
          const groups = String(sess.s || "").split(",").map((x: string) => x.trim()).filter(Boolean);
          if (groups.length && !groups.includes(grp)) return json({ ok: false, error: "out_of_scope" }, 403);
        }
      }
      const gLimits = parseGroups(sess.g);
      if (gLimits.length && grp && !gLimits.includes(grp)) return json({ ok: false, error: "out_of_scope" }, 403);
      const { data, error } = await db.schema("shared").from("giai_trinh")
        .insert({ ps, customer_id: custId, grp, content, created_by: sess.n || sess.u })
        .select("id, content, created_by, created_at")
        .single();
      if (error) throw new Error(error.message);
      await writeAuditLog(db, sess, "saveGiaiTrinh", 1, { ps, customer_id: custId, grp });
      return json({ ok: true, entry: data });
    }

    if (action === "syncThucHien") {
      if (sess.r !== "admin") return json({ ok: false, error: "forbidden" }, 403);
      const { data: jobId, error } = await db.rpc("start_sync_job", { p_actor: sess.u || null });
      if (error) {
        const msg = String(error.message || "");
        if (msg.includes("sync_already_running")) {
          const match = msg.match(/job (\d+)/);
          return json({ ok: true, jobId: match ? Number(match[1]) : null, running: true });
        }
        throw new Error(msg);
      }
      await writeAuditLog(db, sess, "syncThucHien", 0, { jobId });
      return json({ ok: true, jobId });
    }

    if (action === "syncJobStatus") {
      if (sess.r !== "admin") return json({ ok: false, error: "forbidden" }, 403);
      const jid = payload.jobId;
      if (!jid) return json({ ok: false, error: "jobId required" }, 400);
      const { data, error } = await db.schema("shared").from("sync_job")
        .select("id, status, started_at, finished_at, result, error")
        .eq("id", jid).single();
      if (error) throw new Error(error.message);
      return json({ ok: true, job: data });
    }

    // ---- Xuất quota thầu gộp quota_thau + cột cũ sale_target (tạm chỉ admin) ----
    if (action === "exportQuotaThau") {
      if (sess.r !== "admin") return json({ ok: false, error: "forbidden" }, 403);
      const rows: Record<string, unknown>[] = [];
      for (let from = 0; ; from += PAGE) {
        const { data, error } = await db.schema("shared").from("v_quota_thau_xuat")
          .select("*").order("stt", { ascending: true }).range(from, from + PAGE - 1);
        if (error) throw new Error(error.message);
        if (!data || data.length === 0) break;
        rows.push(...data);
        if (data.length < PAGE) break;
      }
      return json({ ok: true, rows });
    }

    // ---- Quota chờ duyệt (chuyển từ cột cũ sale_target, app chưa hiện) — chỉ admin ----
    if (action === "getQuotaChoDuyet") {
      if (sess.r !== "admin") return json({ ok: false, error: "forbidden" }, 403);
      const rows: Record<string, unknown>[] = [];
      for (let from = 0; ; from += PAGE) {
        const { data, error } = await db.schema("shared").from("quota_thau")
          .select("id,nam_tai_chinh,bu,mien,ps,ma_khach_hang,khach_hang,nhom_san_pham,bo_vat_tu,san_pham,don_gia,loai,dot,so_luong,nguon")
          .eq("trang_thai", "cho_duyet").order("id", { ascending: true }).range(from, from + PAGE - 1);
        if (error) throw new Error(error.message);
        if (!data || data.length === 0) break;
        rows.push(...data);
        if (data.length < PAGE) break;
      }
      // Tháng thầu theo đợt (kể cả đợt chờ duyệt) của các nhóm có quota chờ duyệt.
      const nhoms = [...new Set(rows.map((r) => String(r.nhom_san_pham)))];
      const dots: Record<string, unknown>[] = [];
      for (let i = 0; i < nhoms.length; i += 50) {
        const { data, error } = await db.schema("shared").from("dot_thau")
          .select("nam_tai_chinh,ps,ma_khach_hang,nhom_san_pham,loai,dot,thang_thau,trang_thai")
          .in("nhom_san_pham", nhoms.slice(i, i + 50));
        if (error) throw new Error(error.message);
        dots.push(...(data || []));
      }
      const k = (r: Record<string, unknown>) =>
        [r.nam_tai_chinh, r.ps, r.ma_khach_hang, r.nhom_san_pham, r.loai, r.dot].join("||");
      const dotMap = new Map(dots.map((d) => [k(d), d]));
      // Đợt chờ duyệt không gắn quota nào (chỉ có tháng thầu chuyển từ cột cũ).
      const dangDung = new Set<string>();
      for (let from = 0; ; from += PAGE) {
        const { data, error } = await db.schema("shared").from("quota_thau")
          .select("nam_tai_chinh,ps,ma_khach_hang,nhom_san_pham,loai,dot").neq("loai", "cu")
          .order("id", { ascending: true }).range(from, from + PAGE - 1);
        if (error) throw new Error(error.message);
        for (const q of data || []) dangDung.add(k(q));
        if (!data || data.length < PAGE) break;
      }
      const { data: dotCho, error: dErr } = await db.schema("shared").from("dot_thau")
        .select("id,nam_tai_chinh,bu,ps,ma_khach_hang,nhom_san_pham,loai,dot,thang_thau,thoi_gian")
        .eq("trang_thai", "cho_duyet").order("id", { ascending: true });
      if (dErr) throw new Error(dErr.message);
      return json({
        ok: true,
        rows: rows.map((r) => {
          const d = r.loai === "cu" ? null : dotMap.get(k(r));
          return { ...r, thang_thau: d ? d.thang_thau : null, dot_cho_duyet: d ? d.trang_thai === "cho_duyet" : false };
        }),
        dots: (dotCho || []).filter((d) => !dangDung.has(k(d))),
      });
    }

    if (action === "duyetQuotaThau") {
      if (sess.r !== "admin") return json({ ok: false, error: "forbidden" }, 403);
      const ids = (Array.isArray(payload.ids) ? payload.ids : [])
        .map((x: unknown) => Number(x)).filter((x: number) => Number.isFinite(x));
      if (!ids.length) return json({ ok: true, quota: 0, dot: 0 });
      const duyet = payload.duyet === true;
      const { data, error } = await db.rpc("duyet_quota_thau", {
        p_ids: ids, p_duyet: duyet, p_actor: sess.u,
      });
      if (error) throw new Error(error.message);
      await writeAuditLog(db, sess, duyet ? "duyetQuotaThau" : "loaiQuotaThau", ids.length, {
        ids: ids.slice(0, 200),
      });
      return json({ ok: true, ...(data || {}) });
    }

    if (action === "duyetDotThau") {
      if (sess.r !== "admin") return json({ ok: false, error: "forbidden" }, 403);
      const ids = (Array.isArray(payload.ids) ? payload.ids : [])
        .map((x: unknown) => Number(x)).filter((x: number) => Number.isFinite(x));
      if (!ids.length) return json({ ok: true, dot: 0 });
      const duyet = payload.duyet === true;
      const { data, error } = await db.rpc("duyet_dot_thau", { p_ids: ids, p_duyet: duyet, p_actor: sess.u });
      if (error) {
        const msg = String(error.message || "");
        if (msg.includes("dot_thieu_thong_tin")) return json({ ok: false, error: msg.replace(/^.*dot_thieu_thong_tin:\s*/, "") }, 400);
        throw new Error(msg);
      }
      await writeAuditLog(db, sess, duyet ? "duyetDotThau" : "loaiDotThau", ids.length, { ids: ids.slice(0, 200) });
      return json({ ok: true, ...(data || {}) });
    }

    // ---- Loại trừ hóa đơn khỏi thực hiện (app_sale.hoa_don_loai_tru) ----
    // Đổi cấu hình chỉ có hiệu lực sau "Đồng bộ thực hiện" (cap_nhat_thuc_hien).
    if (action === "getHoaDonLoaiTru") {
      if (sess.r !== "admin") return json({ ok: false, error: "forbidden" }, 403);
      const { data, error } = await db.rpc("get_hoa_don_loai_tru");
      if (error) throw new Error(error.message);
      return json({ ok: true, rows: data || [] });
    }

    if (action === "timHoaDon") {
      if (sess.r !== "admin") return json({ ok: false, error: "forbidden" }, 403);
      const q = String(payload.q || "").trim();
      if (q.length < 2) return json({ ok: true, rows: [] });
      const { data, error } = await db.rpc("tim_hoa_don", { p_q: q, p_limit: 50 });
      if (error) throw new Error(error.message);
      return json({ ok: true, rows: data || [] });
    }

    if (action === "luuHoaDonLoaiTru") {
      if (sess.r !== "admin") return json({ ok: false, error: "forbidden" }, 403);
      const soTaiLieu = String(payload.soTaiLieu || "").trim();
      const ngay = String(payload.ngayTaiLieu || "").trim();
      if (!soTaiLieu || !/^\d{4}-\d{2}-\d{2}$/.test(ngay)) {
        return json({ ok: false, error: "thieu_du_lieu" }, 400);
      }
      const dang = typeof payload.dangLoaiTru === "boolean" ? payload.dangLoaiTru : null;
      const lyDo = typeof payload.lyDo === "string" ? payload.lyDo : null;
      const { data, error } = await db.rpc("luu_hoa_don_loai_tru", {
        p_so_tai_lieu: soTaiLieu,
        p_ngay_tai_lieu: ngay,
        p_dang_loai_tru: dang,
        p_ly_do: lyDo,
        p_actor: sess.n || sess.u || null,
      });
      if (error) {
        const msg = String(error.message || "");
        if (msg.includes("khong_tim_thay_hoa_don")) return json({ ok: false, error: "khong_tim_thay_hoa_don" }, 404);
        if (msg.includes("thieu_du_lieu")) return json({ ok: false, error: "thieu_du_lieu" }, 400);
        throw new Error(msg);
      }
      await writeAuditLog(db, sess, "luuHoaDonLoaiTru", 1, {
        so_tai_lieu: soTaiLieu, ngay_tai_lieu: ngay, dang_loai_tru: dang, ly_do: lyDo,
      });
      return json({ ok: true, row: data });
    }

    if (action === "xoaHoaDonLoaiTru") {
      if (sess.r !== "admin") return json({ ok: false, error: "forbidden" }, 403);
      const id = Number(payload.id);
      if (!Number.isFinite(id)) return json({ ok: false, error: "thieu_du_lieu" }, 400);
      const { data, error } = await db.rpc("xoa_hoa_don_loai_tru", { p_id: id });
      if (error) {
        const msg = String(error.message || "");
        if (msg.includes("khong_ton_tai")) return json({ ok: false, error: "khong_ton_tai" }, 404);
        throw new Error(msg);
      }
      await writeAuditLog(db, sess, "xoaHoaDonLoaiTru", 1, {
        so_tai_lieu: data?.so_tai_lieu, ngay_tai_lieu: data?.ngay_tai_lieu,
      });
      return json({ ok: true });
    }

    return json({ ok: false, error: "unknown_action" }, 400);
  } catch (err) {
    const msg = String(err && (err as Error).message || err);
    console.error(JSON.stringify({
      level: "error", requestId, action: _action, user: _user, role: _role,
      error: msg, duration: Date.now() - t0,
    }));
    // Ràng buộc uq_sale_target_khoa (migration 20261017100000): thao tác sẽ tạo 2 dòng
    // cùng KH × PS × nhóm × bộ VT × SP × mã SP × đơn giá × tháng.
    if (msg.includes("uq_sale_target_khoa")) {
      return json({
        ok: false,
        error: "Trùng dòng kế hoạch: đã có sản phẩm cùng bộ vật tư, mã SP và đơn giá cho khách hàng/PS này. Chưa ghi thay đổi.",
      }, 409);
    }
    return json({ ok: false, error: "internal_error" }, 500);
  }
});
