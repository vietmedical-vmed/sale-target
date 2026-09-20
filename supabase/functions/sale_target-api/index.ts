import { cors, json } from "../_shared/cors.ts";
import { verifyToken } from "../_shared/auth.ts";
import { COL, FIELDS, EDITABLE, ADMIN_EDITABLE, PAGE } from "./config.ts";
import { applyScope, scopeParams } from "./scope.ts";
import {
  admin, getRev, writeAuditLog, diaBanErr,
  psInfo, buForPs, mienForPs,
  fetchAll, fetchOopClassify, fetchQuotaThau,
  applyScopeTombstone,
} from "./helpers.ts";

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: cors });
  if (req.method !== "POST") return json({ ok: false, error: "method" }, 405);

  const secret = Deno.env.get("TOKEN_SECRET");
  if (!secret) return json({ ok: false, error: "TOKEN_SECRET chua duoc set" }, 500);

  let body;
  try { body = await req.json(); } catch { return json({ ok: false, error: "bad_body" }, 400); }

  const { action, token, payload = {} } = body;
  const sess = await verifyToken(token, secret);
  if (!sess) return json({ ok: false, error: "unauthorized" }, 401);
  sess.r = String(sess.r || "").toLowerCase();

  const db = admin();
  const canEdit = ["admin", "ps", "manager", "area_manager"].includes(sess.r);

  try {
    if (action === "ping") {
      return json({ ok: true, role: sess.r, scope: sess.s, bu: sess.b, username: sess.u });
    }

    if (action === "getData") {
      const [allRows, classMap, rev, cfgRows, quotaThau] = await Promise.all([
        fetchAll(db, sess, payload),
        fetchOopClassify(db, sess, payload).catch(() => new Map()),
        getRev(db, sess, payload),
        db.schema("shared").from("app_config").select("key, value").then(r => r.data || []),
        fetchQuotaThau(db, sess, payload).catch(() => ({ dots: [], quotas: [] })),
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
        config: cfg,
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
      else if (role === "area_manager") list = list.filter((p: { mien: unknown }) => p.mien === sess.s);
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
          ids: rowIds.slice(0, 50),
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
      for (let i = 0; i < ids.length; i += CHUNK) {
        const { error } = await db.schema("shared").from("sale_target").delete().in("id", ids.slice(i, i + CHUNK));
        if (error) throw new Error(error.message);
      }
      await writeAuditLog(db, sess, "deleteCustomer", ids.length, { ids: ids.slice(0, 50) });
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
      const price = Number.isFinite(priceNum) && priceNum > 0 ? priceNum : null;
      let bu: string;
      try {
        bu = await buForPs(db, psName, sess.b);
      } catch (e) {
        return json({ ok: false, error: String(e && (e as Error).message || e) }, 409);
      }
      if (sess.r === "area_manager") {
        const psMien = await mienForPs(db, psName);
        if (bu !== sess.b || !psMien || psMien !== sess.s) {
          return json({
            ok: false,
            error: !psMien
              ? `PS "${psName}" chưa xác định được miền (chưa có trong dm_ps và chưa có dữ liệu sale_target). Nhờ admin thêm PS vào dm_ps trước.`
              : `PS "${psName}" không thuộc phạm vi của bạn (${sess.b} / ${sess.s})`,
          }, 403);
        }
      }
      const gLimit = String(sess.g || "").trim();
      if (gLimit && String(s.grp || "").trim() !== gLimit) {
        return json({
          ok: false,
          error: `Nhóm SP "${s.grp || ""}" không thuộc phạm vi của bạn (${gLimit})`,
        }, 403);
      }
      let mien = sess.r === "area_manager" ? sess.s : String(s.region || "").trim();
      if (!mien) mien = await mienForPs(db, psName) || "";
      const thangThau = (v: unknown) => {
        const t = String(v || "").trim();
        return /^\d{4}-\d{2}$/.test(t) ? t : null;
      };
      let dupQ = db.schema("shared").from("sale_target")
        .select("id", { count: "exact", head: true })
        .eq("nam_tai_chinh", fy).eq("thang_ke_hoach", MONTHS[0])
        .eq("ps", psName).eq("ma_khach_hang", s.custId || "")
        .eq("nhom_san_pham", s.grp || "").eq("bo_vat_tu", s.mset || "")
        .eq("san_pham", s.prod || "");
      if (price !== null) dupQ = dupQ.eq("don_gia", price);
      else dupQ = dupQ.is("don_gia", null);
      const { count: dupCount } = await dupQ;
      if (dupCount && dupCount > 0) {
        return json({ ok: false, error: "duplicate", message: "Sản phẩm đã tồn tại trong kế hoạch" }, 409);
      }
      const rowsIns = MONTHS.map((mo) => ({
        nam_tai_chinh: fy, thang_ke_hoach: mo, mien, ps: psName,
        thang_thau_chinh: thangThau(s.mMain), thang_thau_bo_sung: thangThau(s.mAdd),
        khach_hang: s.cust, ma_khach_hang: s.custId, nhom_san_pham: s.grp,
        san_pham: s.prod, bo_vat_tu: s.mset, don_gia: price,
        bu,
        sl_ke_hoach_dau_nam: 0, sl_thuc_hien: 0,
      }));
      const cols = FIELDS.map((f) => COL[f]).join(",") + ",id,_rev";
      const { data: ins, error } = await db.schema("shared").from("sale_target").insert(rowsIns).select(cols);
      if (error) throw new Error(error.message);
      const inserted = ins || [];
      await writeAuditLog(db, sess, "addProduct", inserted.length, {
        ps: psName, cust: s.cust, grp: s.grp, prod: s.prod, mset: s.mset, bu,
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

      const { data: any1 } = await db.schema("shared").from("sale_target")
        .select("nam_tai_chinh").limit(1);
      const fy = any1 && any1[0] ? any1[0].nam_tai_chinh : "FY26";
      const MONTHS = ["2026-04","2026-05","2026-06","2026-07","2026-08","2026-09",
        "2026-10","2026-11","2026-12","2027-01","2027-02","2027-03"];
      const thangThau = (v: unknown) => {
        const t = String(v || "").trim();
        return /^\d{4}-\d{2}$/.test(t) ? t : null;
      };

      const psInfoCache = new Map<string, { bu: string; mien: string } | null>();
      for (const s of items) {
        const ps = sess.r === "ps" ? sess.s : String(s.ps || "").trim();
        if (!ps || psInfoCache.has(ps)) continue;
        try {
          const psBu = await buForPs(db, ps, sess.b);
          let psMien = "";
          if (sess.r === "area_manager") {
            const m = await mienForPs(db, ps);
            if (psBu !== sess.b || !m || m !== sess.s) {
              psInfoCache.set(ps, null);
              continue;
            }
            psMien = sess.s;
          } else {
            psMien = await mienForPs(db, ps) || "";
          }
          psInfoCache.set(ps, { bu: psBu, mien: psMien });
        } catch {
          psInfoCache.set(ps, null);
        }
      }

      const gLimit = String(sess.g || "").trim();
      const candidates: {
        ps: string; bu: string; mien: string; custId: string; cust: string;
        grp: string; mset: string; prod: string; price: number | null;
        mMain: unknown; mAdd: unknown; key: string;
      }[] = [];
      const seenKeys = new Set<string>();
      for (const s of items) {
        const ps = sess.r === "ps" ? sess.s : String(s.ps || "").trim();
        const info = psInfoCache.get(ps);
        if (!info) continue;
        const grp = String(s.grp || "");
        if (gLimit && grp !== gLimit) continue;
        const priceNum = Number(s.price);
        const price = Number.isFinite(priceNum) && priceNum > 0 ? priceNum : null;
        const custId = String(s.custId || "");
        const mset = String(s.mset || "");
        const prod = String(s.prod || "");
        const key = `${ps}\0${custId}\0${grp}\0${mset}\0${prod}\0${price}`;
        if (seenKeys.has(key)) continue;
        seenKeys.add(key);
        candidates.push({
          ps, bu: info.bu, mien: s.region || info.mien, custId, cust: String(s.cust || ""),
          grp, mset, prod, price, mMain: s.mMain, mAdd: s.mAdd, key,
        });
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
            .range(from, from + PAGE - 1);
          if (!data || data.length === 0) break;
          for (const r of data) {
            existSet.add(`${r.ps}\0${r.ma_khach_hang}\0${r.nhom_san_pham}\0${r.bo_vat_tu}\0${r.san_pham}\0${r.don_gia}`);
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
          thang_thau_chinh: thangThau(c.mMain), thang_thau_bo_sung: thangThau(c.mAdd),
          khach_hang: c.cust, ma_khach_hang: c.custId, nhom_san_pham: c.grp,
          san_pham: c.prod, bo_vat_tu: c.mset, don_gia: c.price,
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

      await writeAuditLog(db, sess, "addProduct", inserted.length, {
        batch: items.length, inserted: toInsert.length, skipped,
      });
      return json({
        ok: true,
        rows: inserted.map((r) => FIELDS.map((f) => { const v = r[COL[f]]; return v === null || v === undefined ? "" : v; })),
        rowNums: inserted.map((r) => r.id),
        rowRevs: inserted.map((r) => Number(r._rev) || 0),
        skipped,
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
      if (sess.r !== "admin" && sess.r !== "manager") return json({ ok: false, error: "forbidden" }, 403);
      const rows = payload.rows || [];
      if (!rows.length) return json({ ok: false, error: "no_rows" }, 400);
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
      if (error) return diaBanErr(error);
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
      if (error) return diaBanErr(error);
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
      return json({ ok: true, stats: data, rev: await getRev(db, sess, payload) });
    }

    if (action === "deleteDiaBan") {
      if (sess.r !== "admin" && sess.r !== "manager") return json({ ok: false, error: "forbidden" }, 403);
      const ids = (payload.ids || []).map(Number).filter((n: number) => Number.isFinite(n));
      if (!ids.length) return json({ ok: false, error: "no_rows" }, 400);
      const { data, error } = await db.rpc("delete_dm_dia_ban", {
        p_ids: ids, ...scopeParams(sess),
      });
      if (error) return diaBanErr(error);
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
        if (!info || info.area !== sess.s) return json({ ok: false, error: "out_of_scope" }, 403);
      } else if (sess.r === "product_manager") {
        if (grp) {
          const groups = String(sess.s || "").split(",").map((x: string) => x.trim()).filter(Boolean);
          if (groups.length && !groups.includes(grp)) return json({ ok: false, error: "out_of_scope" }, 403);
        }
      }
      const gLimit = String(sess.g || "").trim();
      if (gLimit && grp && grp !== gLimit) return json({ ok: false, error: "out_of_scope" }, 403);
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
        if (!info || info.area !== sess.s) return json({ ok: false, error: "out_of_scope" }, 403);
      } else if (sess.r === "product_manager") {
        if (grp) {
          const groups = String(sess.s || "").split(",").map((x: string) => x.trim()).filter(Boolean);
          if (groups.length && !groups.includes(grp)) return json({ ok: false, error: "out_of_scope" }, 403);
        }
      }
      const gLimit = String(sess.g || "").trim();
      if (gLimit && grp && grp !== gLimit) return json({ ok: false, error: "out_of_scope" }, 403);
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

    return json({ ok: false, error: "unknown_action" }, 400);
  } catch (err) {
    return json({ ok: false, error: String(err && (err as Error).message || err) }, 500);
  }
});
