// api/_lib/store.js  (ESM)
import { Redis } from '@upstash/redis';

// === ENV sauber abgreifen =====================================
// Vercel KV: KV_REST_API_URL / KV_REST_API_TOKEN
// Upstash Redis: UPSTASH_REDIS_REST_URL / UPSTASH_REDIS_REST_TOKEN
const REDIS_URL =
  process.env.UPSTASH_REDIS_REST_URL ||
  process.env.UPSTASH_REDIS_REST_KV_REST_API_URL ||   // <— hinzugefügt
  process.env.KV_REST_API_URL ||
  process.env.REDIS_URL || null;

const REDIS_TOKEN =
  process.env.UPSTASH_REDIS_REST_TOKEN ||
  process.env.UPSTASH_REDIS_REST_KV_REST_API_TOKEN || // <— hinzugefügt
  process.env.KV_REST_API_TOKEN ||
  process.env.REDIS_TOKEN || null;

// Lazy-Initialisierung (kein Crash bei Preflight/CORS)
let _redis = null;
function getRedis() {
  if (_redis) return _redis;
  if (!REDIS_URL || !REDIS_TOKEN) return null;  // Fallback: In-Memory
  _redis = new Redis({ url: REDIS_URL, token: REDIS_TOKEN });
  return _redis;
}

const P = 'dfs:';

// In-Memory Fallback (nur für Dev/Preview)
const mem = {
  users: new Map(),
  pending: new Map(),
  complaints: new Map(),
  counters: { ticket: 1 },
};

// ---------- Helpers (robust) ----------
async function rget(key) {
  try { const r = getRedis(); if (!r) return null; return await r.get(key); }
  catch (e) { console.error('KV GET failed:', key, e?.message || e); return null; }
}
async function rset(key, v) {
  try { const r = getRedis(); if (!r) return null; return await r.set(key, v); }
  catch (e) { console.error('KV SET failed:', key, e?.message || e); return null; }
}
async function rdel(key) {
  try { const r = getRedis(); if (!r) return null; return await r.del(key); }
  catch (e) { console.error('KV DEL failed:', key, e?.message || e); return null; }
}

// Keys/Scan – REST-Client kann KEYS oder SCAN
async function rkeys(pattern) {
  const r = getRedis();
  if (!r) return [];
  if (typeof r.keys === 'function') {
    try { return await r.keys(pattern); } catch { /* fallthrough */ }
  }
  if (typeof r.scan === 'function') {
    let cursor = 0, out = [];
    do {
      const res = await r.scan(cursor, { match: pattern, count: 1000 });
      if (Array.isArray(res)) { cursor = Number(res[0]); out.push(...(res[1]||[])); }
      else { cursor = Number(res.cursor || 0); out.push(...(res.members || res.keys || [])); }
    } while (cursor !== 0);
    return out;
  }
  return [];
}

/* --------- NEU: Diagnose für /api/diag/kv ---------- */
export async function kvStatus() {
  const r = getRedis();
  if (!r) {
    return {
      ok: true,
      useRedis: false,
      reason: 'missing Upstash ENV',
      needed: ['KV_REST_API_URL/KV_REST_API_TOKEN', 'oder', 'UPSTASH_REDIS_REST_URL/UPSTASH_REDIS_REST_TOKEN'],
    };
  }
  const t0 = Date.now();
  try {
    const pong = await r.ping();                 // erwartet "PONG"
    const pingMs = Date.now() - t0;
    const prefix = P;
    const keys = await rkeys(`${prefix}*`);
    const counts = {
      users:      keys.filter(k => k.startsWith(`${prefix}user:`)).length,
      pending:    keys.filter(k => k.startsWith(`${prefix}pending:`)).length,
      complaints: keys.filter(k => k.startsWith(`${prefix}complaint:`)).length,
      total: keys.length,
    };
    return { ok: true, useRedis: true, ping: pong, pingMs, prefix, counts };
  } catch (e) {
    return { ok: false, useRedis: true, error: e?.message || String(e) };
  }
}
/* --------- Ende Diagnose ---------- */

// ---------- Tickets ----------
export async function nextTicket() {
  const r = getRedis();
  if (r) {
    const n = await r.incr(`${P}counter:ticket`);
    return `DFS_CP${String(n).padStart(6, '0')}`;
  }
  const n = mem.counters.ticket++;
  return `DFS_CP${String(n).padStart(6, '0')}`;
}

// ---------- Users ----------
export async function userByEmail(email) {
  if (!email) return null;
  const key = `${P}user:${String(email).toLowerCase()}`;
  const r = getRedis();
  if (r) return await rget(key);
  return mem.users.get(String(email).toLowerCase()) ?? null;
}

export async function userSave(user) {
  const email = String(user?.email || '').toLowerCase();
  if (!email) return false;
  const key = `${P}user:${email}`;
  const r = getRedis();
  if (r) { await rset(key, user); return true; }
  mem.users.set(email, user); return true;
}

export async function userDelete(email) {
  email = String(email || '').toLowerCase();
  if (!email) return false;
  const key = `${P}user:${email}`;
  const r = getRedis();
  if (r) { await rdel(key); return true; }
  return mem.users.delete(email);
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

// ---------- Pending ----------
export async function pendingSave(entry) {
  const email = String(entry?.email || '').toLowerCase();
  if (!email) return false;
  const key = `${P}pending:${email}`;
  const r = getRedis();
  if (r) { await rset(key, entry); return true; }
  mem.pending.set(email, entry); return true;
}

export async function pendingGet(email) {
  email = String(email || '').toLowerCase();
  if (!email) return null;
  const key = `${P}pending:${email}`;
  const r = getRedis();
  if (r) return await rget(key);
  return mem.pending.get(email) ?? null;
}

// Alias (falls dein register.js noch darauf zugreift)
export async function pendingByEmail(email) { return pendingGet(email); }

export async function pendingDelete(email) {
  email = String(email || '').toLowerCase();
  if (!email) return false;
  const key = `${P}pending:${email}`;
  const r = getRedis();
  if (r) { await rdel(key); return true; }
  return mem.pending.delete(email);
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

// ---------- Complaints ----------
export async function complaintSave(c) {
  if (!c?.ticket) c.ticket = await nextTicket();
  const key = `${P}complaint:${c.ticket}`;
  const r = getRedis();
  if (r) { await rset(key, c); return c; }
  mem.complaints.set(c.ticket, c); return c;
}

export async function complaintsByEmail(email) {
  email = String(email || '').toLowerCase();
  const r = getRedis();
  if (r) {
    const keys = await rkeys(`${P}complaint:*`);
    const vals = await Promise.all(keys.map(k => rget(k)));
    return vals.filter(v => v?.email?.toLowerCase() === email);
    }
  return Array.from(mem.complaints.values()).filter(v => v?.email?.toLowerCase() === email);
}
