// api/rep/customers.js
export const config = { runtime: 'nodejs' };

import { setCors } from '../_lib/cors.js';
import { getRepFromAuthHeader } from '../_lib/repAuth.js';
import { repCustomers, repAssign, repUnassign } from '../_lib/repsStore.js';
import { userByEmail } from '../_lib/store.js';

export default async function handler(req, res) {
  // CORS exakt wie in /api/rep/complaints.js
  setCors(req, res, 'Content-Type, Authorization, X-Gate');
  if (req.method === 'OPTIONS') return res.status(204).end();

  const auth = getRepFromAuthHeader(req);
  if (!auth) {
    return res.status(401).end(JSON.stringify({ error: 'unauthorized' }));
  }

  // POST – assign/unassign (unverändert, nur CORS oben zentral gesetzt)
  if (req.method === 'POST') {
    try {
      let body = {};
      try {
        body = typeof req.body === 'string'
          ? JSON.parse(req.body || '{}')
          : (req.body || {});
      } catch (_) {}

      const action = (body.action || '').toString();
      const email  = (body.email  || '').toString().trim().toLowerCase();

      if (!email || !email.includes('@')) {
        return res.status(400).end(JSON.stringify({ error: 'invalid email' }));
      }

      if (action === 'assign') {
        await repAssign(auth.repId, email);
        return res.status(204).end();
      }
      if (action === 'unassign') {
        await repUnassign(auth.repId, email);
        return res.status(204).end();
      }

      return res.status(400).end(JSON.stringify({ error: 'invalid action' }));
    } catch (e) {
      console.error('[rep/customers] POST error:', e);
      return res.status(500).end(JSON.stringify({ error: 'server error' }));
    }
  }

  // GET – Strings (kompatibel) oder Details mit ?details=1
  if (req.method === 'GET') {
    try {
      const details = (req.query?.details || '').toString() === '1';
      const emails = await repCustomers(auth.repId); // Array<string>

      if (!Array.isArray(emails) || emails.length === 0) {
        return res.status(200).end(JSON.stringify([]));
      }

      if (!details) {
        // klassischer Modus: Liste von E-Mail-Strings
        return res.status(200).end(JSON.stringify(emails));
      }

      // Detailanreicherung (best effort)
      const out = [];
      for (const mail of emails) {
        let name = mail;
        let company = '';
        let address = '';
        let zip = '';
        let city = '';
        let country = '';
        try {
          const u = await userByEmail(mail);
          if (u && typeof u === 'object') {
            const fullName = `${(u.firstName || '').toString()} ${(u.lastName || '').toString()}`.trim();
            name = (u.companyName || u.contactName || u.name || fullName || mail).toString().trim() || mail;
            company = (u.companyName || '').toString();
            address = (u.address || '').toString();
            zip     = (u.zip || '').toString();
            city    = (u.city || '').toString();
            country = (u.country || '').toString();
          }
        } catch (_) {}
        out.push({ email: mail, name, company, address, zip, city, country });
      }

      return res.status(200).end(JSON.stringify(out));
    } catch (e) {
      console.error('[rep/customers] GET error:', e);
      // wie gehabt: bei Fehlern leere Liste zurück
      return res.status(200).end(JSON.stringify([]));
    }
  }

  return res.status(405).end(JSON.stringify({ error: 'method not allowed' }));
}
