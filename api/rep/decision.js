// /api/rep/decision.js
export const config = { runtime: 'nodejs' };

import { Redis } from '@upstash/redis';
import { getRepFromAuthHeader } from '../_lib/repAuth.js';

// ---- Upstash ----
const redisUrl =
  process.env.REDIS_URL ||
  process.env.UPSTASH_REDIS_REST_URL || '';
const redisToken =
  process.env.REDIS_TOKEN ||
  process.env.UPSTASH_REDIS_REST_TOKEN || '';
const redis = (redisUrl && redisToken) ? new Redis({ url: redisUrl, token: redisToken }) : null;

function requireRedis() { if (!redis) throw new Error('Redis not configured'); }
const S = (v) => (v ?? '').toString().trim();

// ---- CORS (wie bei dir) ----
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

// ---- Key-Präfixe (beide Varianten unterstützen) ----
const PFXS = ['dfs:complaints:', 'dfs:complaint:']; // plural + singular
const INDEX_KEYS = ['dfs:complaints:index', 'dfs:complaint:index'];

// try get + parse json if needed
async function redisGetParsed(key) {
  const v = await redis.get(key);
  if (!v) return null;
  if (typeof v === 'string') {
    try { return JSON.parse(v); } catch { return null; }
  }
  return v; // bereits Objekt
}

// Robuster Loader: ticket -> { key, c }
async function loadComplaintByTicket(ticket) {
  const t = S(ticket);
  if (!t) return null;

  // 1) direkter Key (über beide Präfixe)
  for (const pfx of PFXS) {
    const k = `${pfx}${t}`;
    try {
      const c = await redisGetParsed(k);
      if (c) return { key: k, c };
    } catch {}
  }

  // 2) Index-Hash (über beide möglichen Index-Namen)
  for (const idx of INDEX_KEYS) {
    try {
      const mapped = await redis.hget(idx, t);
      if (S(mapped)) {
        const c = await redisGetParsed(mapped);
        if (c) return { key: mapped, c };
      }
    } catch {}
  }

  // 3) Fallback: SCAN beider Präfixe + Abgleich value.ticket / value.id
  for (const pfx of PFXS) {
    try {
      let cursor = 0;
      do {
        const [next, keys] = await redis.scan(cursor, { match: `${pfx}*`, count: 200 });
        cursor = Number(next || 0);
        if (keys && keys.length) {
          const vals = await redis.mget(...keys);
          for (let i = 0; i < keys.length; i++) {
            const v = vals[i];
            let obj = v;
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

export default async function handler(req, res) {
  setCors(res);
  if (req.method === 'OPTIONS') return res.status(204).end();
  if (req.method !== 'POST') return res.status(405).json({ error: 'method not allowed' });

  try {
    requireRedis();

    // Auth aus Bearer
    let auth = null;
    try { auth = getRepFromAuthHeader(req); } catch {}
    if (!auth || !auth.repId) return res.status(401).json({ error: 'unauthorized' });
    const repId = S(auth.repId);

    // Body robust parsen
    let body = req.body;
    if (typeof body === 'string') { try { body = JSON.parse(body || '{}'); } catch { body = {}; } }
    body = body || {};

    const ticket = S(body.ticket || body.id);

    // decision-Mapping (accept/approve/... → accepted | rejected)
    const rawDecisionInput =
      body.decision ??
      (typeof body.approve === 'boolean'
        ? (body.approve ? 'accepted' : 'rejected')
        : body.status ?? '');
    const rawByDecision = S(rawDecisionInput).toLowerCase();

    const map = {
      accept: 'accepted',
      accepted: 'accepted',
      approve: 'accepted',
      approved: 'accepted',
      yes: 'accepted',
      reject: 'rejected',
      rejected: 'rejected',
      decline: 'rejected',
      denied: 'rejected',
      deny: 'rejected',
      no: 'rejected',
    };
    const decision = map[rawByDecision];

    if (!ticket || !decision) return res.status(400).json({ error: 'invalid data' });

    // Reklamation laden (jetzt mit singular/plural & index)
    const found = await loadComplaintByTicket(ticket);
    if (!found) return res.status(404).json({ error: 'complaint not found' });

    const { key, c: complaint } = found;

    // Falls bereits repId gesetzt → prüfen (falscher Vertreter darf nicht schreiben)
    if (complaint.repId && S(complaint.repId) !== repId) {
      return res.status(403).json({ error: 'forbidden (wrong rep)' });
    }

    // *** Nur Vertreter-Meinung setzen – Admin-Entscheidung/Status UNVERÄNDERT lassen! ***
    const now = new Date().toISOString();
    complaint.repDecision   = decision;   // 'accepted' | 'rejected'
    complaint.repDecisionAt = now;
    complaint.repDecisionBy = repId;
    if (!complaint.repId) complaint.repId = repId;

    await redis.set(key, JSON.stringify(complaint));

    // Vertreter-Endpoint liefert bewusst keinen Body (nur Erfolg)
    return res.status(204).end();

  } catch (e) {
    console.error('[rep/decision] error', e);
    return res.status(500).json({ error: String(e?.message || e) });
  }
}
