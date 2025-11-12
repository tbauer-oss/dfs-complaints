// =======================================================
// api/_lib/store.js  (ESM) – DFS Complaints Backend
// =======================================================
import { Redis } from '@upstash/redis';

/* =========================================================
   KV / Redis – ENV robust erkennen (Upstash & Vercel KV)
   ========================================================= */
const REDIS_URL =
  process.env.UPSTASH_REDIS_REST_KV_REST_API_URL ||
  process.env.UPSTASH_REDIS_REST_URL ||
  process.env.KV_REST_API_URL ||
  process.env.REDIS_URL ||
  null;

const REDIS_TOKEN =
  process.env.UPSTASH_REDIS_REST_KV_REST_API_TOKEN ||
  process.env.UPSTASH_REDIS_REST_TOKEN ||
  process.env.KV_REST_API_TOKEN ||
  process.env.REDIS_TOKEN ||
  null;

let _redis = null;
function getRedis() {
  if (_redis) return _redis;
  if (!REDIS_URL || !REDIS_TOKEN) return null;
  _redis = new Redis({ url: REDIS_URL, token: REDIS_TOKEN });
  return _redis;
}

const P = 'dfs:';

// ===== In-Memory Fallback (Preview / Dev) =====
const mem = {
  users: new Map(),
  pending: new Map(),
  complaints: new Map(),
  counters: { ticket: 1 },
  catalogConfig: {},
  repPushTokens: new Map(),
  adminPushTokens: [],
};

const SUPPORTED_LANGS = new Set(['de', 'en', 'fr', 'it', 'es']);

function normLang(x) {
  const lc = String(x || '').trim().toLowerCase();
  if (SUPPORTED_LANGS.has(lc)) return lc;
  const two = lc.split(/[-_]/)[0];
  return SUPPORTED_LANGS.has(two) ? two : 'de';
}

function normalizePushTokens(list) {
  const out = [];
  const seen = new Set();
  const arr = Array.isArray(list) ? list : [];
  for (const entry of arr) {
    const token = (entry?.token || '').toString().trim();
    if (!token || seen.has(token)) continue;
    seen.add(token);
    const created = Number(entry?.createdAt || Date.now());
    const updated = Number(entry?.updatedAt || created);
    const platform = (entry?.platform || '').toString().trim();
    const locale = (entry?.locale || '').toString().trim();
    const lang = normLang(entry?.lang || '');
    out.push({
      token,
      platform: platform || undefined,
      lang,
      locale: locale || undefined,
      createdAt: Number.isFinite(created) ? created : Date.now(),
      updatedAt: Number.isFinite(updated) ? updated : Date.now(),
    });
  }
  return out;
}

const KEY_REP_PUSH = (repId) => `${P}rep:${repId}:pushTokens`;
const KEY_ADMIN_PUSH = `${P}admin:pushTokens`;
const CATALOG_KEYS = ['lab_default', 'lab_esfr', 'dent_default', 'dent_esfr'];

function _normalizeCatalogConfig(input) {
  const src = input && typeof input === 'object' ? input : {};
  const out = {};
  for (const key of CATALOG_KEYS) {
    const raw = src[key];
    if (raw == null) continue;
    const val = typeof raw === 'string' ? raw.trim() : String(raw ?? '').trim();
    if (val) out[key] = val;
  }
  return out;
}

// ===== Helper (Redis IO) =====
async function rget(k) { try { const r = getRedis(); return r ? await r.get(k) : null; } catch (e) { console.error('KV GET', k, e); return null; } }
async function rset(k, v) { try { const r = getRedis(); return r ? await r.set(k, v) : null; } catch (e) { console.error('KV SET', k, e); return null; } }
async function rdel(k) { try { const r = getRedis(); return r ? await r.del(k) : null; } catch (e) { console.error('KV DEL', k, e); return null; } }

// ===== Key-Scan kompatibel zu Upstash =====
async function rkeys(pattern) {
  const r = getRedis();
  if (!r) return [];
  if (typeof r.keys === 'function') {
    try { return await r.keys(pattern); } catch { /* continue */ }
  }
  if (typeof r.scan === 'function') {
    let cursor = 0, out = [];
    do {
      const res = await r.scan(cursor, { match: pattern, count: 1000 });
      if (Array.isArray(res)) {
        cursor = Number(res[0]);
        out.push(...(res[1] || []));
      } else {
        cursor = Number(res.cursor || 0);
        out.push(...(res.members || res.keys || []));
      }
    } while (cursor !== 0);
    return out;
  }
  return [];
}

/* ============== Catalog Configuration ============== */
const CATALOG_KEY = `${P}catalogs:config`;

export async function catalogConfigGet() {
  const r = getRedis();
  if (r) {
    const raw = await rget(CATALOG_KEY);
    if (raw && typeof raw === 'string') {
      try { return _normalizeCatalogConfig(JSON.parse(raw)); }
      catch { return _normalizeCatalogConfig({}); }
    }
    return _normalizeCatalogConfig(raw);
  }
  return _normalizeCatalogConfig(mem.catalogConfig);
}

export async function catalogConfigSet(updates = {}) {
  const next = { ...(await catalogConfigGet()) };

  for (const key of CATALOG_KEYS) {
    if (!Object.prototype.hasOwnProperty.call(updates, key)) continue;
    const raw = updates[key];
    const val = raw == null ? '' : (typeof raw === 'string' ? raw : String(raw));
    const trimmed = val.trim();
    if (trimmed) next[key] = trimmed;
    else delete next[key];
  }

  const r = getRedis();
  if (r) {
    if (Object.keys(next).length === 0) await rdel(CATALOG_KEY); else await rset(CATALOG_KEY, next);
  }

  // Für In-Memory-Fallback immer aktualisieren (auch bei Redis, falls offline)
  mem.catalogConfig = { ...next };

  return next;
}

/* ============== Diagnose /api/diag/kv ============== */
export async function kvStatus() {
  const r = getRedis();
  if (!r) {
    return {
      ok: true, useRedis: false,
      reason: 'missing Upstash/Vercel KV ENV',
      needed: ['KV_REST_API_URL & KV_REST_API_TOKEN', 'oder', 'UPSTASH_REDIS_REST_URL & UPSTASH_REDIS_REST_TOKEN'],
    };
  }
  const t0 = Date.now();
  try {
    const pong = await r.ping();
    const pingMs = Date.now() - t0;
    const keys = await rkeys(`${P}*`);
    const counts = {
      users: keys.filter(k => k.startsWith(`${P}user:`)).length,
      pending: keys.filter(k => k.startsWith(`${P}pending:`)).length,
      complaints: keys.filter(k => k.startsWith(`${P}complaint:`)).length,
      total: keys.length,
    };
    return { ok: true, useRedis: true, ping: pong, pingMs, prefix: P, counts };
  } catch (e) {
    return { ok: false, useRedis: true, error: e?.message || String(e) };
  }
}

/* ============== Tickets ============== */
export async function nextTicket() {
  const r = getRedis();
  if (r) {
    const n = await r.incr(`${P}counter:ticket`);
    return `DFS_CP${String(n).padStart(6, '0')}`;
  }
  const n = mem.counters.ticket++;
  return `DFS_CP${String(n).padStart(6, '0')}`;
}

/* ============== Users ============== */
export async function userByEmail(email) {
  if (!email) return null;
  const key = `${P}user:${String(email).toLowerCase()}`;
  const r = getRedis();
  const raw = r ? await rget(key) : mem.users.get(String(email).toLowerCase()) ?? null;
  if (raw && typeof raw === 'object') {
    const normalized = normalizePushTokens(raw.pushTokens);
    if (normalized.length > 0) raw.pushTokens = normalized; else delete raw.pushTokens;
    raw.lang = normLang(raw.lang || '');
  }
  return raw;
}

export async function userSave(u) {
  const email = String(u?.email || '').toLowerCase();
  if (!email) return false;
  const key = `${P}user:${email}`;
  const r = getRedis();
  const toSave = { ...u, email };
  if (Array.isArray(toSave.pushTokens)) {
  const toSave = { ...u, email };
  if (Array.isArray(toSave.pushTokens)) {
    const normalized = normalizePushTokens(toSave.pushTokens);
    if (normalized.length > 0) toSave.pushTokens = normalized;
    else delete toSave.pushTokens;
  }
  if (!toSave.lang) toSave.lang = normLang(toSave.lang || '');
  if (r) await rset(key, toSave); else mem.users.set(email, toSave);
     return true;
}

export async function userDelete(email) {
  email = String(email || '').toLowerCase();
  const key = `${P}user:${email}`;
  const r = getRedis();
  if (r) await rdel(key); else mem.users.delete(email);
  return true;
}

export async function usersList() {
  const r = getRedis();
  if (r) {
    const keys = await rkeys(`${P}user:*`);
    const vals = await Promise.all(keys.map(k => rget(k)));
    return vals
      .filter(Boolean)
      .map(u => {
        if (u && typeof u === 'object') {
          const normalized = normalizePushTokens(u.pushTokens);
          if (normalized.length > 0) u.pushTokens = normalized; else delete u.pushTokens;
          u.lang = normLang(u.lang || '');
        }
        return u;
      });
  }
  return Array.from(mem.users.values());
}

export async function pushTokensForEmail(email) {
  const user = await userByEmail(email);
  if (!user) return [];
  const normalized = normalizePushTokens(user.pushTokens);
  if (user.pushTokens && normalized.length !== user.pushTokens.length) {
    try { await userSave({ ...user, pushTokens: normalized }); }
    catch (e) { console.error('pushTokensForEmail/save', e); }
  }
  return normalized;
}

export async function pushTokenRegister(email, token, meta = {}) {
  const mail = String(email || '').trim().toLowerCase();
  const tok = (token || '').toString().trim();
  if (!mail || !tok) return null;
  const user = (await userByEmail(mail)) || { email: mail, createdAt: Date.now() };
  const tokens = normalizePushTokens(user.pushTokens);
  const now = Date.now();
  const platform = (meta?.platform || '').toString().trim();
  const locale = (meta?.locale || '').toString().trim();
  const lang = normLang(meta?.lang || user.lang || '');

  const existingIdx = tokens.findIndex(t => t.token === tok);
  if (existingIdx >= 0) {
    tokens[existingIdx] = {
      ...tokens[existingIdx],
      platform: platform || tokens[existingIdx].platform,
      lang,
      locale: locale || tokens[existingIdx].locale,
      updatedAt: now,
    };
  } else {
    tokens.push({
      token: tok,
      platform: platform || undefined,
      lang,
      locale: locale || undefined,
      createdAt: now,
      updatedAt: now,
    });
  }

  user.pushTokens = tokens;
  user.lang = lang || user.lang;
  await userSave(user);
  return tokens[existingIdx >= 0 ? existingIdx : tokens.length - 1];
}

export async function pushTokenRemove(email, token) {
  const mail = String(email || '').trim().toLowerCase();
  const tok = (token || '').toString().trim();
  if (!mail || !tok) return false;
  const user = await userByEmail(mail);
  if (!user) return false;
  const tokens = normalizePushTokens(user.pushTokens).filter(t => t.token !== tok);
  if (tokens.length > 0) user.pushTokens = tokens; else delete user.pushTokens;
  await userSave(user);
  return true;
}

export async function repPushTokens(repId) {
  const id = (repId || '').toString().trim();
  if (!id) return [];
  const key = KEY_REP_PUSH(id);
  const r = getRedis();
  if (r) {
    const raw = await rget(key);
    let list = null;
    if (Array.isArray(raw)) list = raw;
    else if (typeof raw === 'string' && raw.trim()) {
      try { list = JSON.parse(raw); }
      catch { list = []; }
    } else if (raw && typeof raw === 'object') {
      list = raw;
    }
    const normalized = normalizePushTokens(list);
    if (Array.isArray(list) && normalized.length !== list.length) {
      try { await rset(key, normalized); }
      catch (e) { console.error('repPushTokens/normalize', e); }
    }
    return normalized;
  }
  const list = normalizePushTokens(mem.repPushTokens.get(id));
  mem.repPushTokens.set(id, list);
  return list;
}

export async function repPushTokenRegister(repId, token, meta = {}) {
  const id = (repId || '').toString().trim();
  const tok = (token || '').toString().trim();
  if (!id || !tok) return null;
  const now = Date.now();
  const platform = (meta?.platform || '').toString().trim();
  const locale = (meta?.locale || '').toString().trim();
  const lang = normLang(meta?.lang || '');

  const existing = await repPushTokens(id);
  const idx = existing.findIndex(t => t.token === tok);
  if (idx >= 0) {
    existing[idx] = {
      ...existing[idx],
      platform: platform || existing[idx].platform,
      lang,
      locale: locale || existing[idx].locale,
      updatedAt: now,
    };
  } else {
    existing.push({
      token: tok,
      platform: platform || undefined,
      lang,
      locale: locale || undefined,
      createdAt: now,
      updatedAt: now,
    });
  }

  const r = getRedis();
  if (r) {
    try { await rset(KEY_REP_PUSH(id), existing); }
    catch (e) { console.error('repPushTokenRegister/save', e); }
  }

  mem.repPushTokens.set(id, existing);

  return existing[idx >= 0 ? idx : existing.length - 1];
}

export async function repPushTokenRemove(repId, token) {
  const id = (repId || '').toString().trim();
  const tok = (token || '').toString().trim();
  if (!id || !tok) return false;
  const list = (await repPushTokens(id)).filter(t => t.token !== tok);
  const r = getRedis();
  if (list.length > 0) {
    if (r) {
      try { await rset(KEY_REP_PUSH(id), list); }
      catch (e) { console.error('repPushTokenRemove/save', e); }
    }
    mem.repPushTokens.set(id, list);
  } else {
    if (r) {
      try { await rdel(KEY_REP_PUSH(id)); }
      catch (e) { console.error('repPushTokenRemove/del', e); }
    }
    mem.repPushTokens.delete(id);
  }
  return true;
}

export async function adminPushTokens() {
  const key = KEY_ADMIN_PUSH;
  const r = getRedis();
  if (r) {
    const raw = await rget(key);
    let list = null;
    if (Array.isArray(raw)) list = raw;
    else if (typeof raw === 'string' && raw.trim()) {
      try { list = JSON.parse(raw); }
      catch { list = []; }
    } else if (raw && typeof raw === 'object') {
      list = raw;
    }
    const normalized = normalizePushTokens(list);
    if (Array.isArray(list) && normalized.length !== list.length) {
      try { await rset(key, normalized); }
      catch (e) { console.error('adminPushTokens/normalize', e); }
    }
    return normalized;
  }
  const normalized = normalizePushTokens(mem.adminPushTokens);
  mem.adminPushTokens = normalized;
  return normalized;
}

export async function adminPushTokenRegister(token, meta = {}) {
  const tok = (token || '').toString().trim();
  if (!tok) return null;
  const now = Date.now();
  const platform = (meta?.platform || '').toString().trim();
  const locale = (meta?.locale || '').toString().trim();
  const lang = normLang(meta?.lang || '');

  const list = await adminPushTokens();
  const idx = list.findIndex(t => t.token === tok);
  if (idx >= 0) {
    list[idx] = {
      ...list[idx],
      platform: platform || list[idx].platform,
      lang,
      locale: locale || list[idx].locale,
      updatedAt: now,
    };
  } else {
    list.push({
      token: tok,
      platform: platform || undefined,
      lang,
      locale: locale || undefined,
      createdAt: now,
      updatedAt: now,
    });
  }

  const r = getRedis();
  if (r) {
    try { await rset(KEY_ADMIN_PUSH, list); }
    catch (e) { console.error('adminPushTokenRegister/save', e); }
  }

  mem.adminPushTokens = list;

  return list[idx >= 0 ? idx : list.length - 1];
}

export async function adminPushTokenRemove(token) {
  const tok = (token || '').toString().trim();
  if (!tok) return false;
  const list = (await adminPushTokens()).filter(t => t.token !== tok);
  const r = getRedis();
  if (list.length > 0) {
    if (r) {
      try { await rset(KEY_ADMIN_PUSH, list); }
      catch (e) { console.error('adminPushTokenRemove/save', e); }
    }
    mem.adminPushTokens = list;
  } else {
    if (r) {
      try { await rdel(KEY_ADMIN_PUSH); }
      catch (e) { console.error('adminPushTokenRemove/del', e); }
    }
    mem.adminPushTokens = [];
  }
  return true;
}

/* ============== Pending Registrations ============== */
export async function pendingSave(e) {
  const mail = String(e?.email || '').toLowerCase();
  if (!mail) return false;
  const key = `${P}pending:${mail}`;
  const r = getRedis();
  if (r) await rset(key, e); else mem.pending.set(mail, e);
  return true;
}

export async function pendingGet(email) {
  email = String(email || '').toLowerCase();
  const key = `${P}pending:${email}`;
  const r = getRedis();
  if (r) return await rget(key);
  return mem.pending.get(email) ?? null;
}

export async function pendingDelete(email) {
  email = String(email || '').toLowerCase();
  const key = `${P}pending:${email}`;
  const r = getRedis();
  if (r) await rdel(key); else mem.pending.delete(email);
  return true;
}

export async function pendingList() {
  const r = getRedis();
  if (r) {
    const keys = await rkeys(`${P}pending:*`);
    const vals = await Promise.all(keys.map(k => rget(k)));
    return vals.filter(Boolean);
  }
  return Array.from(mem.pending.values());
}

/* ============== Complaints Core ============== */

export const Status = {
  SENT: 1,
  IN_PROGRESS: 2,
  NEEDS_INFO: 3,
  FINAL_DECISION: 4,
  REWORK: 5,
  CLOSED: 6,
};

export async function complaintSave(c) {
  if (!c?.ticket) c.ticket = await nextTicket();
  const key = `${P}complaint:${c.ticket}`;
  const r = getRedis();
  if (r) await rset(key, c); else mem.complaints.set(c.ticket, c);
  return c;
}

export async function complaintDelete(ticket) {
  if (!ticket) return false;
  const key = `${P}complaint:${ticket}`;
  const r = getRedis();
  if (r) await rdel(key); else mem.complaints.delete(ticket);
  return true;
}

export async function complaintGet(ticket) {
  const key = `${P}complaint:${ticket}`;
  const r = getRedis();
  if (r) return await rget(key);
  return mem.complaints.get(ticket) ?? null;
}

export async function complaintUpdate(ticket, patch) {
  const cur = await complaintGet(ticket);
  if (!cur) return null;
  const updated = { ...cur, ...patch, updatedAt: Date.now() };
  await complaintSave(updated);
  return updated;
}

/* ============== Mail-Normalisierung ============== */
function _nm(v) { return (v ?? '').toString().trim().toLowerCase(); }

function _emailsFromComplaint(c) {
  const out = new Set();
  const p = c?.payload || {};
  [_nm(c?.email), _nm(c?.customerEmail), _nm(c?.userEmail),
   _nm(c?.account?.email), _nm(c?.user?.email),
   _nm(p?.email), _nm(p?.customerEmail),
   _nm(p?.userEmail), _nm(p?.account?.email), _nm(p?.user?.email)]
    .forEach(e => e && out.add(e));
  return Array.from(out);
}

/* ============== Complaint-Filter nach Email ============== */
export async function complaintsByEmail(email) {
  const target = _nm(email);
  if (!target) return [];
  const r = getRedis();
  const extract = (c) => _emailsFromComplaint(c).includes(target);

  if (r) {
    const keys = await rkeys(`${P}complaint:*`);
    const vals = await Promise.all(keys.map(k => rget(k)));
    const list = vals.filter(v => extract(v));
    list.sort((a, b) => (b?.createdAt || 0) - (a?.createdAt || 0));
    return list;
  }
  const list = Array.from(mem.complaints.values()).filter(v => extract(v));
  list.sort((a, b) => (b?.createdAt || 0) - (a?.createdAt || 0));
  return list;
}

/* ============== Komplettlisten / Admin / Rep ============== */
export async function complaintsAll() {
  const r = getRedis();
  if (r) {
    const keys = await rkeys(`${P}complaint:*`);
    const vals = await Promise.all(keys.map(k => rget(k)));
    return vals.filter(Boolean);
  }
  return Array.from(mem.complaints.values());
}

export async function complaintByTicket(ticket) {
  return await complaintGet(ticket);
}

export async function complaintsOpen() {
  const all = await complaintsAll();
  const open = all.filter(c => {
    const s = Number(c?.status || 0);
    const dec = (c?.decision || '').toString();
    const closedByStatus = (s === Status.CLOSED);
    const closedByRej = (s === Status.FINAL_DECISION && dec === 'rejected');
    return !(closedByStatus || closedByRej);
  });
  open.sort((a, b) => (b?.createdAt || 0) - (a?.createdAt || 0));
  return open;
}

/* ============== Mehrfach-Abruf (Emails[]) ============== */
export async function complaintsByEmails(emails, { status = '' } = {}) {
  const mails = (Array.isArray(emails) ? emails : []).map(_nm).filter(Boolean);
  if (mails.length === 0) return [];

  const all = [];
  for (const m of mails) {
    try {
      const list = await complaintsByEmail(m);
      if (Array.isArray(list)) all.push(...list);
    } catch (e) { console.warn('[store] complaintsByEmail failed for', m, e?.message); }
  }

  // Dedup Tickets
  const seen = new Set();
  const dedup = [];
  for (const c of all) {
    const t = (c?.ticket ?? '').toString().trim();
    if (!t || seen.has(t)) continue;
    seen.add(t);
    dedup.push(c);
  }

  // Filter optional nach Status
  const s = (status ?? '').toString().trim();
  const filtered = s ? dedup.filter(c => String(c?.status ?? '') === s) : dedup;

  filtered.sort((a, b) => {
    const ta = a?.updatedAt ?? a?.createdAt ?? 0;
    const tb = b?.updatedAt ?? b?.createdAt ?? 0;
    return (tb || 0) - (ta || 0);
  });

  return filtered;
}

/* ============== Vertreter-spezifische Sammelabfrage ============== */
export async function complaintsForRepEmails(emails, { status = '' } = {}) {
  const wanted = new Set((Array.isArray(emails) ? emails : []).map(_nm).filter(Boolean));
  if (wanted.size === 0) return [];

  const all = await complaintsAll();
  const wantStatus = (status ?? '').toString().trim();

  const seen = new Set();
  const out = [];

  for (const c of (all || [])) {
    const t = (c?.ticket ?? '').toString().trim();
    if (!t || seen.has(t)) continue;
    if (wantStatus && String(c?.status ?? '') !== wantStatus) continue;

    const mails = _emailsFromComplaint(c);
    if (!mails.some(m => wanted.has(m))) continue;

    seen.add(t);
    out.push(c);
  }

  out.sort((a, b) => {
    const ta = a?.updatedAt ?? a?.createdAt ?? 0;
    const tb = b?.updatedAt ?? b?.createdAt ?? 0;
    return (tb || 0) - (ta || 0);
  });

  return out;
}
