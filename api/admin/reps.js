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

// akzeptiere beide ENV-Varianten
const redisUrl =
  process.env.REDIS_URL ||
  process.env.UPSTASH_REDIS_REST_URL ||
  '';
const redisToken =
  process.env.REDIS_TOKEN ||
  process.env.UPSTASH_REDIS_REST_TOKEN ||
  '';

const redis = (redisUrl && redisToken)
  ? new Redis({ url: redisUrl, token: redisToken })
  : null;

const P = 'dfs:';                           // Prefix
const SET_ALL = `${P}reps:all`;             // Set mit allen IDs
const CNT     = `${P}reps:counter`;
const IDX_E   = (email) => `${P}reps:email:${email.toLowerCase()}`; // email -> repId
const KEY     = (id)    => `${P}reps:${id}`;                        // rep-obj
const SET_CUS = (id)    => `${P}rep:${id}:customers`;               // repId -> Set(emails)
const IDX_ROF = (email) => `${P}repOf:${email.toLowerCase()}`;      // email -> repId (Reverse)

async function nextId() {
  const n = await redis.incr(CNT);
  return `rep_${String(n)}`;
}

async function loadRepById(id) {
  if (!id) return null;
  return await redis.get(KEY(id));
}
async function loadRepIdByEmail(email) {
  if (!email) return null;
  return await redis.get(IDX_E(email));
}
async function repCustomers(id) {
  return await redis.smembers(SET_CUS(id));
}

async function saveRep(rep) {
  await redis.set(KEY(rep.id), rep);
  await redis.sadd(SET_ALL, rep.id);
  await redis.set(IDX_E(rep.email), rep.id);
}

async function deleteRepById(id) {
  const rep = await loadRepById(id);
  if (rep && rep.email) {
    await redis.del(IDX_E(rep.email));
  }
  // Kunden-Zuordnungen lösen
  const customers = await repCustomers(id);
  if (customers?.length) {
    const cmds = [];
    for (const mail of customers) {
      cmds.push(redis.del(IDX_ROF(mail)));
    }
    await Promise.all(cmds);
  }
  await redis.del(SET_CUS(id));
  await redis.del(KEY(id));
  await redis.srem(SET_ALL, id);
}

async function assignCustomer(repId, email) {
  email = email.toLowerCase();
  // ggf. alte Zuordnung entfernen
  const prevRep = await redis.get(IDX_ROF(email));
  if (prevRep && prevRep !== repId) {
    await redis.srem(SET_CUS(prevRep), email);
  }
  await redis.sadd(SET_CUS(repId), email);
  await redis.set(IDX_ROF(email), repId);
}

async function unassignCustomer(repId, email) {
  email = email.toLowerCase();
  await redis.srem(SET_CUS(repId), email);
  // nur entfernen, wenn der Index wirklich auf diesen rep zeigt
  const cur = await redis.get(IDX_ROF(email));
  if (cur === repId) await redis.del(IDX_ROF(email));
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

// --------- Handler ----------
export default async function handler(req, res) {
  setCors(req, res);
  if (req.method === 'OPTIONS') { res.status(204).end(); return; }
  if (!requireAdmin(req, res)) return;

  if (!redis) {
    res.status(500).end(JSON.stringify({ error: 'redis not configured (set REDIS_URL/REDIS_TOKEN or UPSTASH_REDIS_REST_URL/UPSTASH_REDIS_REST_TOKEN)' }));
    return;
  }

  try {
    // --------- GET: Liste der Vertreter (optional inkl. Kunden) ---------
    if (req.method === 'GET') {
      const includeCustomers = String(req.query?.includeCustomers ?? '0') === '1';
      const ids = await redis.smembers(SET_ALL);
      if (!ids?.length) {
        res.status(200).end(JSON.stringify([]));
        return;
      }
      const keys = ids.map((id) => KEY(id));
      const rows = await redis.mget(...keys);
      const reps = (rows || []).filter(Boolean);

      if (includeCustomers) {
        const withCus = await Promise.all(reps.map(async (r) => {
          const list = await repCustomers(r.id);
          return { ...r, customers: list || [] };
        }));
        res.status(200).end(JSON.stringify(withCus));
      } else {
        res.status(200).end(JSON.stringify(reps));
      }
      return;
    }

    // --------- POST: upsert / assign / unassign ---------
    if (req.method === 'POST') {
      const body = safeJson(req);
      const action = normalizeStr(body.action) || 'upsert';

      // --- assign ---
      if (action === 'assign') {
        const repId = normalizeStr(body.repId);
        const email = normalizeStr(body.email).toLowerCase();
        if (!repId || !email) {
          res.status(400).end(JSON.stringify({ error: 'missing repId or email' }));
          return;
        }
        const rep = await loadRepById(repId);
        if (!rep) { res.status(404).end(JSON.stringify({ error: 'rep not found' })); return; }
        await assignCustomer(repId, email);
        const customers = await repCustomers(repId);
        res.status(200).end(JSON.stringify({ ok: true, repId, customers }));
        return;
      }

      // --- unassign ---
      if (action === 'unassign') {
        const repId = normalizeStr(body.repId);
        const email = normalizeStr(body.email).toLowerCase();
        if (!repId || !email) {
          res.status(400).end(JSON.stringify({ error: 'missing repId or email' }));
          return;
        }
        const rep = await loadRepById(repId);
        if (!rep) { res.status(404).end(JSON.stringify({ error: 'rep not found' })); return; }
        await unassignCustomer(repId, email);
        const customers = await repCustomers(repId);
        res.status(200).end(JSON.stringify({ ok: true, repId, customers }));
        return;
      }

      // --- upsert (create/update) ---
      if (action === 'upsert' || action === 'create') {
        let   id        = normalizeStr(body.id);
        const firstName = normalizeStr(body.firstName);
        const lastName  = normalizeStr(body.lastName);
        const email     = normalizeStr(body.email).toLowerCase();
        const region    = normalizeStr(body.region);

        if (!firstName || !lastName || !email || !region) {
          res.status(400).end(JSON.stringify({ error: 'missing fields' }));
          return;
        }

        let existing = null;
        if (id) existing = await loadRepById(id);
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
          if (existing.email && existing.email.toLowerCase() !== email) {
            await redis.del(IDX_E(existing.email));
          }
          await saveRep(updated);
          const customers = await repCustomers(updated.id);
          res.status(200).end(JSON.stringify({ ...updated, customers: customers || [] }));
          return;
        } else {
          const newId = await nextId();
          const rep = {
            id: newId,
            firstName, lastName, email, region,
            createdAt: new Date().toISOString(),
          };
          await saveRep(rep);
          res.status(201).end(JSON.stringify({ ...rep, customers: [] }));
          return;
        }
      }

      res.status(400).end(JSON.stringify({ error: 'invalid action' }));
      return;
    }

    // --------- DELETE: Vertreter löschen ---------
    if (req.method === 'DELETE') {
      let id = normalizeStr(req.query?.id);
      if (!id) {
        try {
          const raw = (typeof req.url === 'string') ? req.url : '';
          if (raw) {
            const u = new URL(raw, 'http://x');
            id = normalizeStr(u.searchParams.get('id'));
          }
        } catch {}
      }
      if (!id) {
        const body = safeJson(req);
        if ((normalizeStr(body.action) || 'delete') === 'delete') {
          id = normalizeStr(body.id);
        }
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
