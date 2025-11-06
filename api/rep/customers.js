// api/rep/customers.js
export const config = { runtime: 'nodejs' };

import { setCors } from '../_lib/cors.js';
import { getRepFromAuthHeader } from '../_lib/repAuth.js';
import { repCustomers, repAssign, repUnassign } from '../_lib/repsStore.js';
import { userByEmail } from '../_lib/store.js';

export default async function handler(req, res) {
  setCors(req, res, 'Content-Type, Authorization, X-Gate');
  if (req.method === 'OPTIONS') return res.status(204).end();

  const auth = getRepFromAuthHeader(req);
  if (!auth) return res.status(401).end(JSON.stringify({ error: 'unauthorized' }));

  // Zuweisen/Entfernen bleibt wie gehabt (POST)
  if (req.method === 'POST') {
    try {
      let body = {};
      try { body = typeof req.body === 'string' ? JSON.parse(req.body || '{}') : (req.body || {}); } catch {}
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

  // GET – zurückliefern: Strings (abwärtskompatibel) ODER detailiert, je nach Query
  if (req.method === 'GET') {
    try {
      const details = (req.query?.details || '').toString() === '1';
      const emails = await repCustomers(auth.repId); // Array<string>
      if (!Array.isArray(emails) || emails.length === 0) {
        return res.status(200).end(JSON.stringify([]));
      }

      if (!details) {
        // klassischer Modus (kompatibel): Liste von Strings
        return res.status(200).end(JSON.stringify(emails));
      }

      // Details anreichern (best effort)
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
            name = (u.companyName || u.contactName || u.name || `${(u.firstName||'')} ${(u.lastName||'')}` || mail).trim() || mail;
            company = (u.companyName || '').toString();
            address = (u.address || '').toString();
            zip     = (u.zip || '').toString();
            city    = (u.city || '').toString();
            country = (u.country || '').toString();
          }
        } catch {}
        out.push({ email: mail, name, company, address, zip, city, country });
      }
      return res.status(200).end(JSON.stringify(out));
    } catch (e) {
      console.error('[rep/customers] GET error:', e);
      return res.status(200).end(JSON.stringify([]));
    }
  }

  return res.status(405).end(JSON.stringify({ error: 'method not allowed' }));
}
