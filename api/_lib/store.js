// api/_lib/store.js  (ESM)
import { Redis } from '@upstash/redis';

/* =========================================================
   KV / Redis – ENV robust erkennen (Upstash & Vercel KV)
   ========================================================= */
const REDIS_URL =
  process.env.UPSTASH_REDIS_REST_KV_REST_API_URL ||   // bei dir vorhanden
  process.env.UPSTASH_REDIS_REST_URL ||               // klassisch Upstash
  process.env.KV_REST_API_URL ||                      // Vercel KV
  process.env.REDIS_URL ||                            // Fallback
  null;

const REDIS_TOKEN =
  process.env.UPSTASH_REDIS_REST_KV_REST_API_TOKEN || // bei dir vorhanden (WRITE)
  process.env.UPSTASH_REDIS_REST_TOKEN ||             // klassisch Upstash
  process.env.KV_REST_API_TOKEN ||                    // Vercel KV
  process.env.REDIS_TOKEN ||                          // Fallback
  null;

// Lazy-Init (verhindert Crash bei Preflight/CORS)
let _redis = null;
function getRedis() {
  if (_redis) return _redis;
  if (!REDIS_URL || !REDIS_TOKEN) return null; // Fallback: In-Memory
  _redis = new Redis({ url: REDIS_URL, token: REDIS_TOKEN });
  return _redis;
}

// Präfix
const P = 'dfs:';

// In-Memory Fallback (nur Dev/Preview)
const mem = {
  users: new Map(),         // key: email
  pending: new Map(),       // key: email
  complaints: new Map(),    // key: ticket
  counters: { ticket: 1 },
};

// ---------------- Helpers ----------------
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

// KEYS/SCAN – kompatibel für Upstash SDK
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
      if (Array.isArray(res)) {               // [cursor, keys[]]
        cursor = Number(res[0]);
        out.push(...(res[1] || []));
      } else {                                // { cursor, members/keys }
        cursor = Number(res.cursor || 0);
        out.push(...(res.members || res.keys || []));
      }
    } while (cursor !== 0);
    return out;
  }
  return [];
}

/* -------------- Diagnose für /api/diag/kv --------------- */
export async function kvStatus() {
  const r = getRedis();
  if (!r) {
    return {
      ok: true,
      useRedis: false,
      reason: 'missing Upstash/Vercel KV ENV',
      needed: [
        'KV_REST_API_URL & KV_REST_API_TOKEN',
        'oder',
        'UPSTASH_REDIS_REST_URL & UPSTASH_REDIS_REST_TOKEN',
      ],
    };
  }
  const t0 = Date.now();
  try {
    const pong = await r.ping();     // erwartet "PONG"
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
/* -------------- Ende Diagnose --------------- */

// ================= Tickets ==================
export async function nextTicket() {
  const r = getRedis();
  if (r) {
    const n = await r.incr(`${P}counter:ticket`);
    return `DFS_CP${String(n).padStart(6, '0')}`;
  }
  const n = mem.counters.ticket++;
  return `DFS_CP${String(n).padStart(6, '0')}`;
}

// ================= Users ====================
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

// ================= Pending ==================
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

// Alias (kompatibel)
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

// =============== Complaints =================

// Status-Enum (Farblogik liegt im Frontend, Werte fixieren wir hier)
export const Status = {
  SENT: 1,            // gesendet (blau)
  IN_PROGRESS: 2,     // in Bearbeitung (gelb)
  NEEDS_INFO: 3,      // Rückfrage erforderlich (orange)
  FINAL_DECISION: 4,  // Entscheidung (rot/hellgrün via decision)
  REWORK: 5,          // in Nacharbeit (optional)
  CLOSED: 6,          // abgeschlossen (grün)
};

// complaintSave: legt an/überschreibt komplettes Objekt
// Erwartetes Schema:
// {
//   ticket, email,
//   createdAt, updatedAt,
//   status: 1..6,
//   decision: 'accepted'|'rejected'|null,
//   reportLink: string|null,
//   payload: {...}
// }
export async function complaintSave(c) {
  if (!c?.ticket) c.ticket = await nextTicket();
  const key = `${P}complaint:${c.ticket}`;
  const r = getRedis();
  if (r) { await rset(key, c); return c; }
  mem.complaints.set(c.ticket, c); return c;
}

// Complaint löschen (Hard-Delete)
export async function complaintDelete(ticket) {
  if (!ticket) return false;
  const key = `${P}complaint:${ticket}`;
  const r = getRedis();
  if (r) { await rdel(key); return true; }
  return mem.complaints.delete(ticket);
}

export async function complaintGet(ticket) {
  const key = `${P}complaint:${ticket}`;
  const r = getRedis();
  if (r) return await rget(key);
  return mem.complaints.get(ticket) ?? null;
}

// Partielle Updates (status, decision, reportLink, payload …)
export async function complaintUpdate(ticket, patch) {
  const cur = await complaintGet(ticket);
  if (!cur) return null;
  const updated = {
    ...cur,
    ...patch,
    updatedAt: Date.now(),
  };
  await complaintSave(updated);
  return updated;
}

// Alle Reklamationen eines Kunden (sortiert nach Datum desc)
export async function complaintsByEmail(email) {
  email = String(email || '').toLowerCase();
  const r = getRedis();
  if (r) {
    const keys = await rkeys(`${P}complaint:*`);
    const vals = await Promise.all(keys.map(k => rget(k)));
    const list = vals.filter(v => v?.email?.toLowerCase() === email);
    list.sort((a, b) => (b?.createdAt || 0) - (a?.createdAt || 0));
    return list;
  }
  const list = Array.from(mem.complaints.values())
    .filter(v => v?.email?.toLowerCase() === email);
  list.sort((a, b) => (b?.createdAt || 0) - (a?.createdAt || 0));
  return list;
}

/* ================== NEU für Admin/Open-Views ================== */

// Alle Reklamationen (Redis oder Memory), unsortiert – Sortierung im Aufrufer möglich
export async function complaintsAll() {
  const r = getRedis();
  if (r) {
    const keys = await rkeys(`${P}complaint:*`);
    const vals = await Promise.all(keys.map(k => rget(k)));
    return vals.filter(Boolean);
  }
  return Array.from(mem.complaints.values());
}

// Alias: Einzel-Complaint per Ticket
export async function complaintByTicket(ticket) {
  ticket = String(ticket || '').trim();
  if (!ticket) return null;
  return await complaintGet(ticket);
}

// Offene Reklamationen im Sinne deiner Definition:
// Offen = NICHT (Status == 6 "Abgeschlossen") UND NICHT (Status == 4 && decision == 'rejected')
export async function complaintsOpen() {
  const all = await complaintsAll();
  const open = all.filter(c => {
    const s = Number(c?.status || 0);
    const dec = (c?.decision || '').toString();
    const closedByStatus    = (s === Status.CLOSED);
    const closedByRejection = (s === Status.FINAL_DECISION && dec === 'rejected');
    return !(closedByStatus || closedByRejection);
  });
  open.sort((a, b) => (b?.createdAt || 0) - (a?.createdAt || 0));
  return open;
}

// --- Complaints: get/update helper ---
export async function complaintGet(ticket) {
  if (useRedis) {
    return await rget(`${P}complaint:${ticket}`);
  }
  return mem.complaints.get(ticket) || null;
}

export async function complaintUpdate(ticket, patch) {
  const c = await complaintGet(ticket);
  if (!c) return null;
  const updated = { ...c, ...patch };
  if (useRedis) {
    await rset(`${P}complaint:${ticket}`, updated);
  } else {
    mem.complaints.set(ticket, updated);
  }
  return updated;
}

// Speziell: Report-Link leeren
export async function complaintClearReportLink(ticket) {
  return await complaintUpdate(ticket, { reportUrl: null });
}
