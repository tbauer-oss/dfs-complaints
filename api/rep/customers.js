// api/rep/customers.js
export const config = { runtime: 'nodejs' };

import { setCors } from '../_lib/cors.js';
import { getRepFromAuthHeader } from '../_lib/repAuth.js';
import { repCustomers } from '../_lib/repsStore.js';

function S(v) { return (v ?? '').toString().trim(); }

// ------- Minimaler Upstash-Client (REST, unabhängig von _lib/upstash.js) -------
const UP_URL   = process.env.UPSTASH_REDIS_REST_URL  || '';
const UP_TOKEN = process.env.UPSTASH_REDIS_REST_TOKEN || '';

async function kvGet(key) {
  if (!UP_URL || !UP_TOKEN) throw new Error('UPSTASH env missing');
  const r = await fetch(`${UP_URL}/get/${encodeURIComponent(key)}`, {
    headers: { Authorization: `Bearer ${UP_TOKEN}` },
    cache: 'no-store',
  });
  const j = await r.json().catch(() => ({}));
  return j?.result ?? null;
}

async function kvSet(key, value) {
  if (!UP_URL || !UP_TOKEN) throw new Error('UPSTASH env missing');
  const r = await fetch(`${UP_URL}/set/${encodeURIComponent(key)}/${encodeURIComponent(value)}`, {
    headers: { Authorization: `Bearer ${UP_TOKEN}` },
    method: 'POST',
    cache: 'no-store',
  });
  // Upstash gibt { result: "OK" } zurück – Fehler werfen:
  if (!r.ok) throw new Error(`Upstash SET failed: ${r.status}`);
}

async function kvDel(key) {
  if (!UP_URL || !UP_TOKEN) throw new Error('UPSTASH env missing');
  const r = await fetch(`${UP_URL}/del/${encodeURIComponent(key)}`, {
    headers: { Authorization: `Bearer ${UP_TOKEN}` },
    method: 'POST',
    cache: 'no-store',
  });
  if (!r.ok) throw new Error(`Upstash DEL failed: ${r.status}`);
}

// ------- Fallback-Assign/Unassign (falls repsStore keine Funktionen exportiert) -------
async function fallbackRepAssign(repId, email) {
  // Mapping Kunde -> Rep
  await kvSet(`dfs:repOf:${email}`, repId);

  // Liste dfs:repCustomers:<repId> pflegen (JSON-Array)
  const listKey = `dfs:repCustomers:${repId}`;
  let list = [];
  try {
    const raw = await kvGet(listKey);
    if (raw) {
      const j = JSON.parse(raw);
      if (Array.isArray(j)) list = j.map(S);
    }
  } catch { /* egal */ }

  if (!list.includes(email)) {
    list.push(email);
    await kvSet(listKey, JSON.stringify(list));
  }
}

async function fallbackRepUnassign(repId, email) {
  // Mapping entfernen
  try { await kvDel(`dfs:repOf:${email}`); } catch { /* egal */ }

  // Aus Liste entfernen
  const listKey = `dfs:repCustomers:${repId}`;
  let list = [];
  try {
    const raw = await kvGet(listKey);
    if (raw) {
      const j = JSON.parse(raw);
      if (Array.isArray(j)) list = j.map(S);
    }
  } catch { /* egal */ }

  const next = list.filter(e => e.toLowerCase() !== email.toLowerCase());
  if (next.length !== list.length) {
    await kvSet(listKey, JSON.stringify(next));
  }
}

export default async function handler(req, res) {
  // CORS bleibt – inkl. X-Debug für Browser-Tests
  setCors(req, res, 'Content-Type, Authorization, X-Gate, X-Debug');
  if (req.method === 'OPTIONS') return res.status(204).end();

  try {
    // Auth
    let auth = null;
    try { auth = getRepFromAuthHeader(req); } catch (e) {
      console.error('[rep/customers] auth parse failed:', e);
      return res.status(401).end(JSON.stringify({ error: 'unauthorized' }));
    }
    if (!auth) return res.status(401).end(JSON.stringify({ error: 'unauthorized' }));

    // POST: assign/unassign
    if (req.method === 'POST') {
      try {
        let body = {};
        try {
          body = typeof req.body === 'string'
            ? JSON.parse(req.body || '{}')
            : (req.body || {});
        } catch {}

        const action = S(body.action || body.op); // Alias: op
        const email  = (S(body.email) || S(body.customerEmail)).toLowerCase();
        if (!email || !email.includes('@')) {
          return res.status(400).end(JSON.stringify({ error: 'invalid email' }));
        }

        // repsStore (falls vorhanden) nutzen, sonst Fallback
        let store = {};
        try { store = await import('../_lib/repsStore.js'); } catch { /* ignore */ }

        const hasAssign   = typeof store.repAssign   === 'function';
        const hasUnassign = typeof store.repUnassign === 'function';

        if (action === 'assign') {
          if (hasAssign) await store.repAssign(auth.repId, email);
          else           await fallbackRepAssign(auth.repId, email);
          return res.status(204).end();
        }

        if (action === 'unassign') {
          if (hasUnassign) await store.repUnassign(auth.repId, email);
          else             await fallbackRepUnassign(auth.repId, email);
          return res.status(204).end();
        }

        return res.status(400).end(JSON.stringify({ error: 'invalid action' }));
      } catch (e) {
        const xdbg = S(req.headers['x-debug']);
        console.error('[rep/customers] POST error:', e);
        // Bei Debug-Header mehr Details
        if (xdbg) {
          return res.status(500).end(JSON.stringify({
            error: 'server error',
            where: 'post',
            details: e?.message || String(e),
          }));
        }
        return res.status(500).end(JSON.stringify({ error: 'server error' }));
      }
    }

    // GET: Liste / Details
    if (req.method === 'GET') {
      try {
        const details = (req.query?.details || '').toString() === '1';
        const emails = await repCustomers(auth.repId);
        if (!Array.isArray(emails) || emails.length === 0) {
          return res.status(200).end(JSON.stringify([]));
        }

        if (!details) {
          return res.status(200).end(JSON.stringify(emails));
        }

        const { userByEmail } = await import('../_lib/store.js');

        const out = [];
        for (const mail of emails) {
          let name = mail;
          let company = '', address = '', zip = '', city = '', country = '';
          let phone = '', customerNo = '', vatId = '';

          try {
            const u = await userByEmail(mail);
            if (u && typeof u === 'object') {
              const first = S(u.firstName);
              const last  = S(u.lastName);
              const full  = S(`${first} ${last}`);

              company    = S(u.companyName || u.company || u.org);
              name       = company || S(u.contactName || u.name || full || mail) || mail;
              address    = S(u.address || u.street || u.street1 || u.address1);
              zip        = S(u.zip || u.postcode || u.postalCode || u.plz);
              city       = S(u.city || u.town || u.ort);
              country    = S(u.country || u.countryCode || u.land);
              phone      = S(u.phone || u.tel || u.phoneNumber || u.telephone);
              customerNo = S(u.customerNo || u.customerId || u.kundennummer || u.kundenNr);
              vatId      = S(u.vat || u.vatId || u.vatid || u.ustId || u.ustid);
            }
          } catch (e) {
            console.warn('[rep/customers] userByEmail failed for', mail, e?.message || e);
          }

          out.push({ email: mail, name, company, address, zip, city, country, phone, customerNo, vatId });
        }

        return res.status(200).end(JSON.stringify(out));
      } catch (e) {
        console.error('[rep/customers] GET error:', e);
        return res.status(200).end(JSON.stringify([]));
      }
    }

    return res.status(405).end(JSON.stringify({ error: 'method not allowed' }));
  } catch (e) {
    console.error('[rep/customers] FATAL:', e);
    setCors(req, res, 'Content-Type, Authorization, X-Gate, X-Debug');
    return res.status(500).end(JSON.stringify({ error: 'fatal server error' }));
  }
}
