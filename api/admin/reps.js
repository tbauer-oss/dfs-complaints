// api/admin/reps.js
export const config = { runtime: 'nodejs' };

// ---------------- CORS ----------------
const PROD_FE  = 'https://dfs-complaints-web.vercel.app';
const PREVIEW  = /^https:\/\/dfs-complaints-web-[a-z0-9-]+(?:-[a-z0-9-]+)?\.vercel\.app$/i;

function setCors(req, res) {
  const origin = req.headers.origin || '';
  const allow  = origin && (origin === PROD_FE || PREVIEW.test(origin)) ? origin : PROD_FE;
  res.setHeader('Access-Control-Allow-Origin', allow);
  res.setHeader('Vary', 'Origin');
  res.setHeader('Access-Control-Allow-Credentials', 'true');
  res.setHeader('Access-Control-Allow-Methods', 'GET,POST,DELETE,OPTIONS');
  res.setHeader('Access-Control-Allow-Headers', 'Content-Type, Authorization, X-Admin-Secret');
  res.setHeader('Content-Type', 'application/json; charset=utf-8');
}

function requireAdmin(req, res) {
  const sec = (req.headers['x-admin-secret'] || '').toString();
  if (!sec || sec !== process.env.ADMIN_SECRET) {
    res.statusCode = 401;
    res.end(JSON.stringify({ error: 'unauthorized' }));
    return false;
  }
  return true;
}

// --------------- Upstash Redis ---------------
import { Redis } from '@upstash/redis';

// env wie in deinem store.js: UPSTASH_REDIS_REST_URL / UPSTASH_REDIS_REST_TOKEN
const redis = (process.env.UPSTASH_REDIS_REST_URL && process.env.UPSTASH_REDIS_REST_TOKEN)
  ? new Redis({ url: process.UPSTASH_REDIS_REST_URL, token: process.env.UPSTASH_REDIS_REST_TOKEN })
  : null;

const P = 'dfs:';                 // Prefix
const SET_ALL = `${P}reps:all`;   // Set mit allen IDs
const CNT     = `${P}reps:counter`;
const IDX_E   = (email) => `${P}reps:email:${email.toLowerCase()}`;
const KEY     = (id)    => `${P}reps:${id}`;

async function nextId() {
  const n = await redis.incr(CNT);
  return `rep_${String(n)}`;
}

async function loadRepById(id) {
  const j = await redis.get(KEY(id));
  return j || null;
}

async function loadRepIdByEmail(email) {
  return await redis.get(IDX_E(email));
}

async function saveRep(rep) {
  // rep: {id, firstName, lastName, email, region, createdAt?, updatedAt?}
  await redis.set(KEY(rep.id), rep);
  await redis.sadd(SET_ALL, rep.id);
  await redis.set(IDX_E(rep.email), rep.id);
}

async function deleteRepById(id) {
  const rep = await loadRepById(id);
  if (rep && rep.email) {
    await redis.del(IDX_E(rep.email));
  }
  await redis.del(KEY(id));
  await redis.srem(SET_ALL, id);
}

// --------- Utils ----------
function safeJson(req) {
  try {
    if (!req.body) return {};
    if (typeof req.body === 'string') return JSON.parse(req.body);
    if (typeof req.body === 'object') return req.body;
    return {};
  } catch { return {}; }
}
function normalizeStr(v) { return (v ?? '').toString().trim(); }

export default async function handler(req, res) {
  setCors(req, res);
  if (req.method === 'OPTIONS') { res.status(204).end(); return; }
  if (!requireAdmin(req, res)) return;

  if (!redis) {
    res.status(500).end(JSON.stringify({ error: 'redis not configured (UPSTASH_REDIS_REST_URL/UPSTASH_REDIS_REST_TOKEN)' }));
    return;
  }

  try {
    // --------- GET: Liste aller Vertreter ---------
    if (req.method === 'GET') {
      const ids = await redis.smembers(SET_ALL);
      if (!ids || ids.length === 0) {
        res.status(200).end(JSON.stringify([]));
        return;
      }
      // mget aller Reps
      const keys = ids.map((id) => KEY(id));
      const rows = await redis.mget(...keys);
      const list = (rows || []).filter(Boolean);
      res.status(200).end(JSON.stringify(list));
      return;
    }

    // --------- POST: UPSERT (anlegen/ändern) ---------
    if (req.method === 'POST') {
      const body = safeJson(req);
      // tolerant: action optional; akzeptiere 'upsert' | 'create' | ''
      const action = normalizeStr(body.action) || 'upsert';
      if (action !== 'upsert' && action !== 'create') {
        if (action === 'delete') {
          res.status(405).end(JSON.stringify({ error: 'use DELETE for delete' }));
          return;
        }
        res.status(400).end(JSON.stringify({ error: 'invalid action' }));
        return;
      }

      let   id        = normalizeStr(body.id);
      const firstName = normalizeStr(body.firstName);
      const lastName  = normalizeStr(body.lastName);
      const email     = normalizeStr(body.email).toLowerCase();
      const region    = normalizeStr(body.region);

      if (!firstName || !lastName || !email || !region) {
        res.status(400).end(JSON.stringify({ error: 'missing fields' }));
        return;
      }

      // Upsert-Strategie:
      // 1) wenn id angegeben & existiert -> update
      // 2) sonst per email Index suchen -> update
      // 3) sonst create
      let existing = null;
      if (id) {
        existing = await loadRepById(id);
      }
      if (!existing) {
        const viaEmailId = await loadRepIdByEmail(email);
        if (viaEmailId) {
          id = viaEmailId;
          existing = await loadRepById(id);
        }
      }

      if (existing) {
        const updated = {
          ...existing,
          firstName, lastName, email, region,
          updatedAt: new Date().toISOString(),
        };
        // Email-Index ggf. umhängen, falls E-Mail geändert wurde
        if (existing.email && existing.email.toLowerCase() !== email) {
          await redis.del(IDX_E(existing.email));
        }
        await saveRep(updated);
        res.status(200).end(JSON.stringify(updated));
        return;
      } else {
        const newId = await nextId();
        const rep = {
          id: newId,
          firstName, lastName, email, region,
          createdAt: new Date().toISOString(),
        };
        await saveRep(rep);
        res.status(201).end(JSON.stringify(rep));
        return;
      }
    }

    // --------- DELETE: löschen (Query ODER Body) ---------
    if (req.method === 'DELETE') {
      let id = '';
      try {
        const url = new URL(req.url, 'http://x'); // dummy base
        id = normalizeStr(url.searchParams.get('id'));
      } catch { /* ignore */ }

      if (!id) {
        const body = safeJson(req);
        const action = normalizeStr(body.action) || 'delete';
        if (action !== 'delete') {
          res.status(400).end(JSON.stringify({ error: 'invalid action' }));
          return;
        }
        id = normalizeStr(body.id);
      }

      if (!id) {
        res.status(400).end(JSON.stringify({ error: 'missing id' }));
        return;
      }

      await deleteRepById(id);
      res.status(204).end();
      return;
    }

    res.status(405).end(JSON.stringify({ error: 'method not allowed' }));
  } catch (e) {
    res.status(500).end(JSON.stringify({ error: String(e?.message || e) }));
  }
}
