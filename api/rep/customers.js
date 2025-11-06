// api/rep/customers.js
export const config = { runtime: 'nodejs' };

import { setCors } from '../_lib/cors.js';
import { getRepFromAuthHeader } from '../_lib/repAuth.js';
import { repCustomers } from '../_lib/repsStore.js'; // leichtgewichtig belassen

export default async function handler(req, res) {
  // 1) CORS IMMER zuerst – wie bei /rep/complaints
  setCors(req, res, 'Content-Type, Authorization, X-Gate');
  if (req.method === 'OPTIONS') return res.status(204).end();

  // 2) Auth sicher parsen (falls repAuth intern mal wirft -> sauber 401 liefern)
  let auth = null;
  try {
    auth = getRepFromAuthHeader(req);
  } catch (e) {
    console.error('[rep/customers] auth parse failed:', e);
    return res.status(401).end(JSON.stringify({ error: 'unauthorized' }));
  }
  if (!auth) {
    return res.status(401).end(JSON.stringify({ error: 'unauthorized' }));
  }

  // 3) POST: assign/unassign (lazy import, damit OPTIONS/GET nicht am Import sterben)
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

      // Lazy import genau hier:
      const { repAssign, repUnassign } = await import('../_lib/repsStore.js');

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

  // 4) GET: Liste (Strings) ODER Details (?details=1)
  if (req.method === 'GET') {
    try {
      const details = (req.query?.details || '').toString() === '1';

      const emails = await repCustomers(auth.repId); // Array<string>
      if (!Array.isArray(emails) || emails.length === 0) {
        return res.status(200).end(JSON.stringify([]));
      }

      if (!details) {
        // abwärtskompatibel (nur Strings)
        return res.status(200).end(JSON.stringify(emails));
      }

      // Details: Lazy import hier – damit TOP-LEVEL nicht crasht
      const { userByEmail } = await import('../_lib/store.js');

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
            name    = (u.companyName || u.contactName || u.name || fullName || mail).toString().trim() || mail;
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
      // Bei Fehlern weiterhin leere Liste zurückgeben
      return res.status(200).end(JSON.stringify([]));
    }
  }

  // 5) Method not allowed
  return res.status(405).end(JSON.stringify({ error: 'method not allowed' }));
}
