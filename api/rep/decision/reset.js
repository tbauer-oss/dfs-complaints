// api/rep/decision/reset.js
export const config = { runtime: 'nodejs' };

import { Redis } from '@upstash/redis';
import { getRepFromAuthHeader } from '../_lib/repAuth.js';

// ---- Utils ----
const S = (v) => (v ?? '').toString().trim();

// ---- Upstash identisch zu /api/rep/decision.js ----
const redisUrl =
  process.env.REDIS_URL ||
  process.env.UPSTASH_REDIS_REST_URL || '';
const redisToken =
  process.env.REDIS_TOKEN ||
  process.env.UPSTASH_REDIS_REST_TOKEN || '';
const redis = (redisUrl && redisToken) ? new Redis({ url: redisUrl, token: redisToken }) : null;

function requireRedis() { if (!redis) throw new Error('Redis not configured'); }

// ---- CORS wie in decision.js ----
function setCors(res) {
  const origin = process.env.WEB_ORIGIN || 'https://dfs-complaints-web.vercel.app';
  res.setHeader('Access-Control-Allow-Origin', origin);
  res.setHeader('Vary', 'Origin');
  res.setHeader('Access-Control-Allow-Credentials', 'true');
  res.setHeader('Access-Control-Allow-Methods', 'POST,OPTIONS');
  res.setHeader('Access-Control-Allow-Headers', 'Content-Type, Authorization, X-Gate');
  res.setHeader('Access-Control-Max-Age', '600');
  res.setHeader('Content-Type', 'application/json; charset=utf-8');
}

// ---- Key-Präfixe & Index (kompatibel mit alt/neu) ----
const PFXS = ['dfs:complaints:', 'dfs:complaint:']; // plural + singular
const INDEX_KEYS = ['dfs:complaints:index', 'dfs:complaint:index'];

// JSON-read helper (wie in decision.js)
async function redisGetParsed(key) {
  const v = await redis.get(key);
  if (!v) return null;
  if (typeof v === 'string') {
    try { return JSON.parse(v); } catch { return null; }
  }
  return v; // Objekt
}

// Reklamation per Ticket robust finden → { key, c }
async function loadComplaintByTicket(ticket) {
  const t = S(ticket);
  if (!t) return null;

  // 1) Direkter Key
  for (const pfx of PFXS) {
    const k = `${pfx}${t}`;
    try {
      const c = await redisGetParsed(k);
      if (c) return { key: k, c };
    } catch {}
  }

  // 2) Index-Hash
  for (const idx of INDEX_KEYS) {
    try {
      const mapped = await redis.hget(idx, t);
      if (S(mapped)) {
        const c = await redisGetParsed(mapped);
        if (c) return { key: mapped, c };
      }
    } catch {}
  }

  // 3) Fallback: SCAN + Abgleich value.ticket / value.id
  for (const pfx of PFXS) {
    try {
      let cursor = 0;
      do {
        const [next, keys] = await redis.scan(cursor, { match: `${pfx}*`, count: 200 });
        cursor = Number(next || 0);
        if (keys && keys.length) {
          const vals = await redis.mget(...keys);
          for (let i = 0; i < keys.length; i++) {
            let obj = vals[i];
            if (!obj) continue;
            if (typeof obj === 'string') {
              try { obj = JSON.parse(obj); } catch { continue; }
            }
            const vt = S(obj.ticket);
            const vid = S(obj.id);
            if (vt === t || vid === t) {
              return { key: keys[i], c: obj };
            }
          }
        }
      } while (cursor !== 0);
    } catch {}
  }

  return null;
}

// ---- Handler ----
export default async function handler(req, res) {
  setCors(res);
  if (req.method === 'OPTIONS') return res.status(204).end();
  if (req.method !== 'POST') return res.status(405).json({ error: 'method not allowed' });

  try {
    requireRedis();

    // Auth (nur eingeloggter Vertreter)
    let auth = null;
    try { auth = getRepFromAuthHeader(req); } catch {}
    if (!auth || !auth.repId) return res.status(401).json({ error: 'unauthorized' });
    const repId = S(auth.repId);

    // Body
    let body = req.body;
    if (typeof body === 'string') { try { body = JSON.parse(body || '{}'); } catch { body = {}; } }
    body = body || {};
    const ticket = S(body.ticket || body.id);
    if (!ticket) return res.status(400).json({ error: 'ticket required' });

    // Reklamation laden
    const found = await loadComplaintByTicket(ticket);
    if (!found) return res.status(404).json({ error: 'complaint not found' });

    const { key, c } = found;

    // Nur eigener Rep darf zurücknehmen, sofern repId im Datensatz steht
    if (S(c.repId) && S(c.repId) !== repId) {
      return res.status(403).json({ error: 'forbidden (wrong rep)' });
    }

    // Vertreter-Entscheidung zurücknehmen (Adminfelder bleiben unberührt)
    delete c.repDecision;
    delete c.repDecisionAt;
    delete c.repDecisionBy;
    delete c.repId; // entkoppeln
    c.updatedAt = Date.now();

    await redis.set(key, c);

    // Optionales Debug-JSON statt 204
    if (S(req.query?.debug) === '1') {
      return res.status(200).json({ ok: true, ticket, savedKey: key });
    }
    return res.status(204).end();

  } catch (e) {
    console.error('[rep/decision/reset] error', e);
    return res.status(500).json({ error: String(e?.message || e) });
  }
}
