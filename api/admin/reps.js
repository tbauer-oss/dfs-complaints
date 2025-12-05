// api/admin/reps.js
export const config = { runtime: 'nodejs' };

// ---------------- CORS ----------------
const PROD_FE  = 'https://dfs-complaints-web.vercel.app';
const PREVIEW  = /^https:\/\/dfs-complaints-web-[a-z0-9-]+(?:-[a-z0-9-]+)?\.vercel\.app$/i;

function setCors(req, res) {
  const origin = req.headers.origin || '';
  const allow  = origin && (origin === PROD_FE || PREVIEW.test(origin))
    ? origin
    : (process.env.WEB_ORIGIN || PROD_FE);

  res.setHeader('Access-Control-Allow-Origin', allow);
  res.setHeader('Vary', 'Origin');
  res.setHeader('Access-Control-Allow-Credentials', 'true');
  res.setHeader('Access-Control-Allow-Methods', 'GET,POST,DELETE,OPTIONS');
  // wichtig: beide Schreibweisen + Standard-Header erlauben
  res.setHeader(
    'Access-Control-Allow-Headers',
    [
      'Content-Type', 'content-type',
      'Authorization', 'authorization',
      'X-Admin-Secret', 'x-admin-secret',
      'Accept', 'accept',
      'Origin', 'origin'
    ].join(', ')
  );
  res.setHeader('Access-Control-Expose-Headers', '*');
  res.setHeader('Content-Type', 'application/json; charset=utf-8');
}

function safeJson(req) {
  try {
    if (!req.body) return {};
    if (typeof req.body === 'string') return JSON.parse(req.body);
    if (typeof req.body === 'object') return req.body;
    return {};
  } catch { return {}; }
}
const S = v => (v ?? '').toString().trim();

// ---------------- Gemeinsamer Store (gleiche Quelle wie /api/rep/my) -------------
import {
  getAllRepsWithCustomers,
  upsertRep,
  deleteRep,
  assignCustomer,
  unassignCustomer,
} from '../_lib/repsStore.js';
import { removeRepFromDownloadPermissions } from '../_lib/store.js';
import { requirePortalAccess } from './_guard.js';

// ---------------- Handler ----------------
export default async function handler(req, res) {
  setCors(req, res);
  if (req.method === 'OPTIONS') { res.status(204).end(); return; }
  const actor = await requirePortalAccess(req, res, { write: req.method !== 'GET', tile: 'reps' });
  if (!actor) return;

  try {
    // GET: Liste der Vertreter (optional inkl. Kunden)
    if (req.method === 'GET') {
      const includeCustomers = String(req.query?.includeCustomers ?? '0') === '1';
      const list = await getAllRepsWithCustomers();
      if (includeCustomers) {
        res.status(200).end(JSON.stringify(list));
      } else {
        // Kundenliste ausblenden, falls nicht angefordert
        res.status(200).end(JSON.stringify(list.map(r => ({
          id: r.id,
          firstName: r.firstName,
          lastName:  r.lastName,
          email:     r.email,
          region:    r.region,
          lang:      r.lang,
          createdAt: r.createdAt,
          updatedAt: r.updatedAt,
        }))));
      }
      return;
    }

    // POST: upsert / assign / unassign
    if (req.method === 'POST') {
      const body   = safeJson(req);
      const action = (S(body.action) || 'upsert').toLowerCase();

      if (action === 'assign') {
        const repId = S(body.repId);
        const email = S(body.email).toLowerCase();
        if (!repId || !email) {
          res.status(400).end(JSON.stringify({ error: 'missing repId or email' }));
          return;
        }
        try {
          const customers = await assignCustomer(repId, email);
          res.status(200).end(JSON.stringify({ ok: true, repId, customers }));
        } catch (e) {
          const code = e?.statusCode === 409 ? 409 : 500;
          res.status(code).end(JSON.stringify({ error: String(e?.message || e) }));
        }
        return;
      }

      if (action === 'unassign') {
        const repId = S(body.repId);
        const email = S(body.email).toLowerCase();
        if (!repId || !email) {
          res.status(400).end(JSON.stringify({ error: 'missing repId or email' }));
          return;
        }
        try {
          const customers = await unassignCustomer(repId, email);
          res.status(200).end(JSON.stringify({ ok: true, repId, customers }));
        } catch (e) {
          res.status(500).end(JSON.stringify({ error: String(e?.message || e) }));
        }
        return;
      }

      // upsert (create/update)
      if (action === 'upsert' || action === 'create') {
        const rep = await upsertRep({
          id:        S(body.id),
          firstName: S(body.firstName),
          lastName:  S(body.lastName),
          email:     S(body.email).toLowerCase(),
          region:    S(body.region),
          lang:      S(body.lang),
        });
        // rep enthält bereits customers (siehe repsStore)
        res.status(200).end(JSON.stringify(rep));
        return;
      }

      res.status(400).end(JSON.stringify({ error: 'invalid action' }));
      return;
    }

    // DELETE: Vertreter löschen
    if (req.method === 'DELETE') {
      let id = S(req.query?.id);
      if (!id) {
        const b = safeJson(req);
        id = S(b.id);
      }
      if (!id) { res.status(400).end(JSON.stringify({ error: 'missing id' })); return; }
      await deleteRep(id);
      await removeRepFromDownloadPermissions(id);
      res.status(204).end();
      return;
    }

    res.status(405).end(JSON.stringify({ error: 'method not allowed' }));
  } catch (e) {
    console.error('admin/reps error', e);
    res.status(500).end(JSON.stringify({ error: String(e?.message || e) }));
  }
}
