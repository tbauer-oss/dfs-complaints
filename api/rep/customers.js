// api/rep/customers.js
export const config = { runtime: 'nodejs' };

import { setCors } from '../_lib/cors.js';
import { getRepFromAuthHeader } from '../_lib/repAuth.js';
import { repCustomers } from '../_lib/repsStore.js'; // leichtgewichtig belassen

function S(v) { return (v ?? '').toString().trim(); }
function isEmail(x) { return /^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(x); }

export default async function handler(req, res) {
  // 1) CORS IMMER zuerst
  setCors(req, res, 'Content-Type, Authorization, X-Gate');
  if (req.method === 'OPTIONS') return res.status(204).end();

  try {
    // 2) Auth sicher ermitteln
    let auth = null;
    try { auth = getRepFromAuthHeader(req); } catch (e) {
      console.error('[rep/customers] auth parse failed:', e);
      return res.status(401).end(JSON.stringify({ error: 'unauthorized' }));
    }
    if (!auth) {
      return res.status(401).end(JSON.stringify({ error: 'unauthorized' }));
    }

    // 3) POST: assign / unassign
    if (req.method === 'POST') {
      const WANT_DEBUG = String(req.headers['x-debug'] || '').toLowerCase() === '1';
      const dbg = (obj) => {
        if (!WANT_DEBUG) return;
        try { return JSON.stringify(obj, null, 2); } catch { return String(obj); }
      };

      try {
        let body = {};
        try {
          body = typeof req.body === 'string'
            ? JSON.parse(req.body || '{}')
            : (req.body || {});
        } catch (e) {
          console.error('[rep/customers] JSON parse failed:', e);
          return res.status(400).end(JSON.stringify({ error: 'invalid json', ...(WANT_DEBUG ? { details: String(e) } : {}) }));
        }

        // Aliasse zulassen
        const action = ( (body.action ?? body.op) ?? '' ).toString().trim().toLowerCase();
        const email  = ( (body.email  ?? body.customerEmail) ?? '' ).toString().trim().toLowerCase();

        if (!action || !['assign','unassign'].includes(action)) {
          return res.status(400).end(JSON.stringify({ error: 'invalid action', ...(WANT_DEBUG ? { body: dbg(body) } : {}) }));
        }
        if (!email || !/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(email)) {
          return res.status(400).end(JSON.stringify({ error: 'invalid email', ...(WANT_DEBUG ? { email } : {}) }));
        }

        // Optionaler Existenz-Check (nicht abstürzen, nur 404 wenn sicher leer)
        try {
          const { userByEmail } = await import('../_lib/store.js');
          const u = await userByEmail(email);
          if (!u) {
            return res.status(404).end(JSON.stringify({ error: 'customer not found', ...(WANT_DEBUG ? { email } : {}) }));
          }
        } catch (e) {
          // Store kann in Previews fehlen → nur loggen, trotzdem fortfahren
          if (WANT_DEBUG) console.warn('[rep/customers] userByEmail skipped:', e?.message || e);
        }

        const { repAssign, repUnassign } = await import('../_lib/repsStore.js');

        if (action === 'assign') {
          try {
            await repAssign(auth.repId, email);
            return res.status(204).end();
          } catch (e) {
            const msg = (e?.message || String(e)).toLowerCase();
            if (msg.includes('already') || msg.includes('assigned')) {
              return res.status(409).end(JSON.stringify({ error: 'already assigned', ...(WANT_DEBUG ? { details: String(e) } : {}) }));
            }
            if (msg.includes('not found') || msg.includes('unknown')) {
              return res.status(404).end(JSON.stringify({ error: 'customer not found', ...(WANT_DEBUG ? { details: String(e) } : {}) }));
            }
            console.error('[rep/customers] repAssign error:', e);
            return res.status(500).end(JSON.stringify({ error: 'server error', ...(WANT_DEBUG ? { where:'repAssign', details: String(e) } : {}) }));
          }
        }

        if (action === 'unassign') {
          try {
            await repUnassign(auth.repId, email);
            return res.status(204).end();
          } catch (e) {
            const msg = (e?.message || String(e)).toLowerCase();
            // "nicht zugewiesen" behandeln wir idempotent als ok
            if (msg.includes('not found') || msg.includes('unknown') || msg.includes('no assignment')) {
              return res.status(204).end();
            }
            console.error('[rep/customers] repUnassign error:', e);
            return res.status(500).end(JSON.stringify({ error: 'server error', ...(WANT_DEBUG ? { where:'repUnassign', details: String(e) } : {}) }));
          }
        }

        // sollte wegen includes() nie erreicht werden
        return res.status(400).end(JSON.stringify({ error: 'invalid action' }));
      } catch (e) {
        console.error('[rep/customers] POST fatal:', e);
        return res.status(500).end(JSON.stringify({ error: 'server error', ...(WANT_DEBUG ? { where:'post-catch', details: String(e) } : {}) }));
      }
    }

    // 4) GET: Liste (Strings) ODER Details (?details=1)
    if (req.method === 'GET') {
      try {
        const details = (req.query?.details || '').toString() === '1';

        const emails = await repCustomers(auth.repId); // Array<string>
        if (!Array.isArray(emails) || emails.length === 0) {
          return res.status(200).end(JSON.stringify([]));
        }

        if (!details) {
          // abwärtskompatibel: nur E-Mail-Strings
          return res.status(200).end(JSON.stringify(emails));
        }

        // Details: Lazy-Import, damit Top-Level nicht crasht
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
              const fullName = S(`${first} ${last}`);

              // Firmenname priorisieren für "name"
              company    = S(u.companyName || u.company || u.org);
              name       = company || S(u.contactName || u.name || fullName || mail) || mail;
              address    = S(u.address || u.street || u.street1 || u.address1);
              zip        = S(u.zip || u.postcode || u.postalCode || u.plz);
              city       = S(u.city || u.town || u.ort);
              country    = S(u.country || u.countryCode || u.land);
              phone      = S(u.phone || u.tel || u.phoneNumber || u.telephone);
              customerNo = S(u.customerNo || u.customerId || u.kundennummer || u.kundenNr);
              vatId      = S(u.vat || u.vatId || u.vatid || u.ustId || u.ustid);
            }
          } catch (e) {
            // Einzelnen Datensatz-Fehler ignorieren, aber Liste weiter aufbauen
            console.warn('[rep/customers] userByEmail failed for', mail, e?.message || e);
          }

          out.push({
            email: mail,
            name,          // ← wird im UI als Titel genutzt (jetzt primär Firma)
            company,
            address,
            zip,
            city,
            country,
            phone,
            customerNo,
            vatId,
          });
        }

        return res.status(200).end(JSON.stringify(out));
      } catch (e) {
        console.error('[rep/customers] GET error:', e);
        // stabil bleiben, nie 500 an FE
        return res.status(200).end(JSON.stringify([]));
      }
    }

    // 5) Method not allowed
    return res.status(405).end(JSON.stringify({ error: 'method not allowed' }));
  } catch (e) {
    // Catch-All: CORS sicherstellen + sinnvolle Antwort
    console.error('[rep/customers] FATAL:', e);
    setCors(req, res, 'Content-Type, Authorization, X-Gate');
    return res.status(500).end(JSON.stringify({ error: 'fatal server error' }));
  }
}
