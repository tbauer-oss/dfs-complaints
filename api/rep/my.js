// api/rep/my.js
export const config = { runtime: 'nodejs' };

// ---------------- CORS ----------------
const PROD_FE  = 'https://dfs-complaints-web.vercel.app';
const PREVIEW  = /^https:\/\/dfs-complaints-web-[a-z0-9-]+(?:-[a-z0-9-]+)?\.vercel\.app$/i;

function resolveOrigin(req) {
  const origin = req.headers.origin || '';
  if (!origin) return process.env.WEB_ORIGIN || PROD_FE;
  if (origin === PROD_FE) return origin;
  if (PREVIEW.test(origin)) return origin;                  // Vercel Preview-URLs erlauben
  return process.env.WEB_ORIGIN || PROD_FE;                 // Fallback
}

function setCors(req, res) {
  const allow = resolveOrigin(req);
  res.setHeader('Access-Control-Allow-Origin', allow);
  res.setHeader('Vary', 'Origin');
  res.setHeader('Access-Control-Allow-Credentials', 'true');
  res.setHeader('Access-Control-Allow-Headers', 'Content-Type, Authorization, X-Gate');
  res.setHeader('Access-Control-Allow-Methods', 'GET,OPTIONS');
  // Antworte als JSON, wenn ein Body kommt
  res.setHeader('Content-Type', 'application/json; charset=utf-8');
}

// ---------------- Utils ----------------
function getEmailFromJwt(req) {
  const h = req.headers.authorization || '';
  const m = /^Bearer\s+(.+)$/i.exec(h);
  if (!m) return null;
  try {
    const payload = JSON.parse(Buffer.from(m[1].split('.')[1], 'base64').toString('utf8'));
    return (payload.email || '').trim().toLowerCase();
  } catch {
    return null;
  }
}

// Gemeinsamer Store – identisch wie in /api/admin/reps.js
import { getAllRepsWithCustomers } from '../_lib/repsStore.js';

export default async function handler(req, res) {
  try {
    setCors(req, res);

    // Preflight
    if (req.method === 'OPTIONS') { res.status(204).end(); return; }

    if (req.method !== 'GET') {
      res.status(405).end(JSON.stringify({ error: 'method not allowed' }));
      return;
    }

    const email = getEmailFromJwt(req);
    if (!email) {
      res.status(401).end(JSON.stringify({ error: 'unauthorized' }));
      return;
    }

    const reps = await getAllRepsWithCustomers(); // [{... , customers: ['user@mail.tld', ...]}]
    const rep = reps.find(r =>
      Array.isArray(r.customers) &&
      r.customers.some(c => (c || '').trim().toLowerCase() === email)
    );

    // Optionales Debug
    if (String(req.query?.debug || '') === '1') {
      res.status(200).end(JSON.stringify({
        debug: {
          tokenEmail: email,
          repsCount : reps.length,
          sample    : reps.slice(0, 3).map(r => ({
            id: r.id, email: r.email, customers: (r.customers || []).length
          })),
        },
        matched: !!rep,
        rep: rep ? {
          firstName: rep.firstName || '',
          lastName : rep.lastName  || '',
          email    : rep.email     || '',
          region   : rep.region    || '',
        } : null,
      }));
      return;
    }

    if (!rep) { res.status(204).end(); return; } // kein Body bei 204!

    res.status(200).end(JSON.stringify({
      firstName: rep.firstName || '',
      lastName : rep.lastName  || '',
      email    : rep.email     || '',
      region   : rep.region    || '',
    }));
  } catch (e) {
    // Auch im Fehlerfall CORS-Header behalten
    try { setCors(req, res); } catch {}
    res.status(500).end(JSON.stringify({ error: String(e?.message || e) }));
  }
}
