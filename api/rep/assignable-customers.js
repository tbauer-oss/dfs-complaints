// api/rep/assignable-customers.js
export const config = { runtime: 'nodejs' };

import { setCors } from '../_lib/cors.js';
import { getRepFromAuthHeader } from '../_lib/repAuth.js';

// Upstash REST (ENV-Namen exakt wie gefordert)
const KV_URL   = process.env.UPSTASH_REDIS_REST_URL;
const KV_TOKEN = process.env.UPSTASH_REDIS_REST_TOKEN;

function S(v) { return (v ?? '').toString().trim(); }

// ---------------- Upstash (REST) ----------------
async function kv(cmd) {
  const r = await fetch(KV_URL, {
    method: 'POST',
    headers: {
      Authorization: `Bearer ${KV_TOKEN}`,
      'Content-Type': 'application/json',
    },
    body: JSON.stringify({ cmd }),
  });
  if (!r.ok) throw new Error(`Upstash ${r.status}: ${await r.text()}`);
  return r.json();
}

async function scanAll(pattern, count = 1000) {
  const keys = [];
  let cursor = '0';
  do {
    const { result } = await kv(['SCAN', cursor, 'MATCH', pattern, 'COUNT', String(count)]);
    cursor = result?.[0] ?? '0';
    const batch = result?.[1] ?? [];
    keys.push(...batch);
  } while (cursor !== '0');
  return keys;
}

async function mget(keys) {
  if (!keys?.length) return [];
  const { result } = await kv(['MGET', ...keys]);
  return result;
}

// ----------- Daten aus KV normalisieren -----------
function isActiveCustomer(u) {
  if (!u || typeof u !== 'object') return false;
  const em = S(u.email).toLowerCase();
  if (!em) return false;
  const status  = S(u.status).toLowerCase();
  const revoked = Boolean(u.revoked);
  return status === 'active' && !revoked;
}

function labelFor(u) {
  const em = S(u.email).toLowerCase();
  const co = S(u.company || u.companyName || u.org);
  const nm = S(u.name || u.contact || `${S(u.firstName)} ${S(u.lastName)}`.trim());
  return co || (nm ? `${nm} • ${em}` : em);
}

async function loadCustomers() {
  const userKeys = await scanAll('dfs:user:*');              // Kunden-Stammsätze
  const userVals = await mget(userKeys);

  const items = [];
  for (const v of userVals) {
    let u = null;
    try { u = typeof v === 'string' ? JSON.parse(v) : v; } catch {}
    if (!isActiveCustomer(u)) continue;
    items.push({
      email: S(u.email).toLowerCase(),
      company: S(u.company || u.companyName || u.org),
      name: S(u.name || u.contact || `${S(u.firstName)} ${S(u.lastName)}`.trim()),
      _raw: u,
    });
  }
  // dedupe nach E-Mail
  const map = new Map();
  for (const it of items) map.set(it.email, it);
  return Array.from(map.values());
}

async function loadAssignments() {
  // Zuweisungen liegen als Keys: dfs:repOf<customerEmail> -> value = repEmail
  const keys = await scanAll('dfs:repOf*');
  const vals = await mget(keys);
  const out = {};
  for (let i = 0; i < keys.length; i++) {
    const email = keys[i].replace(/^dfs:repOf/i, '').toLowerCase();
    const rep   = S(vals[i]).toLowerCase();
    if (email) out[email] = rep || null;
  }
  return out;
}

// -------------------- Handler --------------------
export default async function handler(req, res) {
  // 1) CORS immer zuerst – identisch zu customers.js
  setCors(req, res, 'Content-Type, Authorization, X-Gate');
  if (req.method === 'OPTIONS') return res.status(204).end();

  try {
    // 2) Nur GET erlaubt; Auth wie rep/customers.js
    if (req.method !== 'GET') {
      return res.status(405).end(JSON.stringify({ error: 'method not allowed' }));
    }

    let auth = null;
    try { auth = getRepFromAuthHeader(req); } catch {}
    if (!auth) {
      return res.status(401).end(JSON.stringify({ error: 'unauthorized' }));
    }
    // auth.repId (E-Mail) steht jetzt bereit – aktuell nicht zwingend benötigt,
    // aber so bleibt das Verhalten konsistent.

    // 3) Daten robust laden – niemals 500 zurückgeben
    let customers = [];
    let assigned  = {};
    try { customers = await loadCustomers(); } catch (e) {
      console.warn('[assignable-customers] loadCustomers failed:', e?.message || e);
    }
    try { assigned  = await loadAssignments(); } catch (e) {
      console.warn('[assignable-customers] loadAssignments failed:', e?.message || e);
    }

    // 4) Nur NICHT zugewiesene Kunden für Vertreter zurückgeben
    const free = customers
      .filter(c => !assigned[c.email]) // kein Eintrag => frei
      .map(c => ({
        email: c.email,
        company: c.company,
        name: c.name,
        label: labelFor(c._raw || c),
      }))
      .sort((a, b) => a.label.toLowerCase().localeCompare(b.label.toLowerCase(), 'de'));

    return res.status(200).end(JSON.stringify(free));
  } catch (e) {
    console.error('[rep/assignable-customers] FATAL:', e);
    // CORS bleibt gesetzt; stabil mit leerer Liste antworten
    return res.status(200).end(JSON.stringify([]));
  }
}
