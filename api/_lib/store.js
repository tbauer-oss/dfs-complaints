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
};

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
  if (r) return await rget(key);
  return mem.users.get(String(email).toLowerCase()) ?? null;
}

export async function userSave(u) {
  const email = String(u?.email || '').toLowerCase();
  if (!email) return false;
  const key = `${P}user:${email}`;
  const r = getRedis();
  if (r) await rset(key, u); else mem.users.set(email, u);
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
    return vals.filter(Boolean);
  }
  return Array.from(mem.users.values());
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
