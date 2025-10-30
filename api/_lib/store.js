// api/_lib/store.js  (ESM)
import { Redis } from '@upstash/redis';

// ---- Upstash-ENV-Namen sauber abgreifen ----
// (nimm NICHT den READ_ONLY_TOKEN für Schreibzugriffe!)
const REDIS_URL =
  process.env.UPSTASH_REDIS_REST_KV_REST_API_URL ||   // von Vercel-Connect (KV)
  process.env.UPSTASH_REDIS_REST_URL ||               // klassisch
  process.env.REDIS_URL;                              // fallback, falls manuell gesetzt

const REDIS_TOKEN =
  process.env.UPSTASH_REDIS_REST_KV_REST_API_TOKEN || // von Vercel-Connect (KV)
  process.env.UPSTASH_REDIS_REST_TOKEN ||             // klassisch
  process.env.REDIS_TOKEN;                            // fallback

const redis = (REDIS_URL && REDIS_TOKEN)
  ? new Redis({ url: REDIS_URL, token: REDIS_TOKEN })
  : null;

const P = 'dfs:';                      // Redis Prefix
const mem = {                          // In-Memory Fallback
  users: new Map(),                    // key: email
  pending: new Map(),                  // key: email
  complaints: new Map(),               // key: ticket
  counters: { ticket: 1 },
};

const useRedis = !!redis;

// ---------- Helpers ----------
async function rget(key) { return await redis.get(key); }
async function rset(key, val) { return await redis.set(key, val); }
async function rdel(key) { return await redis.del(key); }

// ---------- Tickets ----------
export async function nextTicket() {
  if (useRedis) {
    const n = await redis.incr(`${P}counter:ticket`);
    return `DFS_CP${String(n).padStart(6,'0')}`;
  }
  const n = mem.counters.ticket++;
  return `DFS_CP${String(n).padStart(6,'0')}`;
}

// ---------- Users ----------
export async function userByEmail(email) {
  if (!email) return null;
  if (useRedis) return await rget(`${P}user:${email.toLowerCase()}`);
  return mem.users.get(email.toLowerCase()) ?? null;
}

export async function userSave(user) {
  const email = String(user?.email || '').toLowerCase();
  if (!email) return false;
  if (useRedis) { await rset(`${P}user:${email}`, user); return true; }
  mem.users.set(email, user); return true;
}

export async function userDelete(email) {
  email = String(email || '').toLowerCase();
  if (!email) return false;
  if (useRedis) { await rdel(`${P}user:${email}`); return true; }
  return mem.users.delete(email);
}

export async function usersList() {
  if (useRedis) {
    const keys = await redis.keys(`${P}user:*`);
    const vals = await Promise.all(keys.map(k => redis.get(k)));
    return vals.filter(Boolean);
  }
  return Array.from(mem.users.values());
}

// ---------- Pending ----------
export async function pendingSave(entry) {
  const email = String(entry?.email || '').toLowerCase();
  if (!email) return false;
  if (useRedis) { await rset(`${P}pending:${email}`, entry); return true; }
  mem.pending.set(email, entry); return true;
}

export async function pendingGet(email) {
  email = String(email || '').toLowerCase();
  if (!email) return null;
  if (useRedis) return await rget(`${P}pending:${email}`);
  return mem.pending.get(email) ?? null;
}

export async function pendingDelete(email) {
  email = String(email || '').toLowerCase();
  if (!email) return false;
  if (useRedis) { await rdel(`${P}pending:${email}`); return true; }
  return mem.pending.delete(email);
}

export async function pendingList() {
  if (useRedis) {
    const keys = await redis.keys(`${P}pending:*`);
    const vals = await Promise.all(keys.map(k => redis.get(k)));
    return vals.filter(Boolean);
  }
  return Array.from(mem.pending.values());
}

// ---------- Complaints (nur das Nötigste) ----------
export async function complaintSave(c) {
  if (!c?.ticket) c.ticket = await nextTicket();
  const key = `${P}complaint:${c.ticket}`;
  if (useRedis) { await rset(key, c); return c; }
  mem.complaints.set(c.ticket, c); return c;
}

export async function complaintsByEmail(email) {
  email = String(email || '').toLowerCase();
  if (useRedis) {
    const keys = await redis.keys(`${P}complaint:*`);
    const vals = await Promise.all(keys.map(k => redis.get(k)));
    return vals.filter(v => v?.email?.toLowerCase() === email);
  }
  return Array.from(mem.complaints.values()).filter(v => v?.email?.toLowerCase() === email);
}
