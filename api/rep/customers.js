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

    // 3) POST: assign / unassign  (→ nur hier minimal gehärtet)
    if (req.method === 'POST') {
      try {
        let body = {};
        try {
          body = typeof req.body === 'string'
            ? JSON.parse(req.body || '{}')
            : (req.body || {});
        } catch {}

        // NEU: action/op + email/customerEmail akzeptieren
        const action = (S(body.action || body.op)).toLowerCase();
        const email  = S(body.email || body.customerEmail).toLowerCase();

        if (!action) {
          return res.status(400).end(JSON.stringify({ error: 'invalid action' }));
        }
        if (!email || !isEmail(email)) {
          return res.status(400).end(JSON.stringify({ error: 'invalid email' }));
        }

        // NEU: Kunde muss existieren – sonst 404 statt 500
        try {
          const { userByEmail } = await import('../_lib/store.js');
          const u = await userByEmail(email);
          if (!u) {
            return res.status(404).end(JSON.stringify({ error: 'customer not found' }));
          }
        } catch (e) {
          // Wenn store nicht verfügbar → nicht hart abbrechen, aber loggen
          console.warn('[rep/customers] userByEmail check skipped:', e?.message || e);
        }

        const { repAssign, repUnassign } = await import('../_lib/repsStore.js');

        if (action === 'assign') {
          try {
            await repAssign(auth.repId, email);
            return res.status(204).end();
          } catch (e) {
            // typische Konflikte sauber mappen
            const msg = (e?.message || '').toString().toLowerCase();
            if (msg.includes('already') || msg.includes('assigned')) {
              return res.status(409).end(JSON.stringify({ error: 'already assigned' }));
            }
            if (msg.includes('not found') || msg.includes('unknown')) {
              return res.status(404).end(JSON.stringify({ error: 'customer not found' }));
            }
            console.error('[rep/customers] repAssign error:', e);
            return res.status(500).end(JSON.stringify({ error: 'server error' }));
          }
        }

        if (action === 'unassign') {
          try {
            await repUnassign(auth.repId, email);
            return res.status(204).end();
          } catch (e) {
            const msg = (e?.message || '').toString().toLowerCase();
            if (msg.includes('not found') || msg.includes('unknown')) {
              // unassign von „nicht zugewiesen“ ist idempotent
              return res.status(204).end();
            }
            console.error('[rep/customers] repUnassign error:', e);
            return res.status(500).end(JSON.stringify({ error: 'server error' }));
          }
        }

        return res.status(400).end(JSON.stringify({ error: 'invalid action' }));
      } catch (e) {
        console.error('[rep/customers] POST error:', e);
        return res.status(500).end(JSON.stringify({ error: 'server error' }));
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
