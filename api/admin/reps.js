// api/admin/reps.js
export const config = { runtime: 'nodejs' };

// --- CORS ---
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

// --- Simple in-memory Fallback (ersetze das mit Upstash/DB) ---
const mem = globalThis.__REPS__ || (globalThis.__REPS__ = new Map()); // id -> rep
let counter = globalThis.__REPS_CNT__ || 1;
function newId() { globalThis.__REPS_CNT__ = ++counter; return `rep_${counter}`; }

// --- Handler ---
export default async function handler(req, res) {
  setCors(req, res);
  if (req.method === 'OPTIONS') { res.status(204).end(); return; }
  if (!requireAdmin(req, res)) return;

  try {
    if (req.method === 'GET') {
      // Liste
      const list = Array.from(mem.values());
      res.status(200).end(JSON.stringify(list));
      return;
    }

    if (req.method === 'POST') {
      const body = safeJson(req);
      const action = (body.action || '').toString();

      if (action === 'create') {
        const rep = {
          id: newId(),
          firstName: (body.firstName || '').toString(),
          lastName:  (body.lastName  || '').toString(),
          email:     (body.email     || '').toString(),
          region:    (body.region    || '').toString(),
          createdAt: new Date().toISOString(),
        };
        if (!rep.firstName || !rep.lastName || !rep.email || !rep.region) {
          res.status(400).end(JSON.stringify({ error: 'missing fields'}));
          return;
        }
        mem.set(rep.id, rep);
        res.status(201).end(JSON.stringify(rep));
        return;
      }

      if (action === 'delete') {
        const id = (body.id || '').toString();
        mem.delete(id);
        res.status(204).end();
        return;
      }

      res.status(400).end(JSON.stringify({ error: 'invalid action' }));
      return;
    }

    if (req.method === 'DELETE') {
      const url = new URL(req.url, 'http://x'); // dummy base
      const id  = (url.searchParams.get('id') || '').toString();
      mem.delete(id);
      res.status(204).end();
      return;
    }

    res.status(405).end(JSON.stringify({ error: 'method not allowed' }));
  } catch (e) {
    res.status(500).end(JSON.stringify({ error: String(e?.message || e) }));
  }
}

function safeJson(req) {
  try { return JSON.parse(req.body || '{}'); } catch { return {}; }
}
