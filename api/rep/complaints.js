// /api/rep/complaints.js
export const config = { runtime: 'nodejs' };

import { setCors } from '../_lib/cors.js';
import { getRepFromAuthHeader } from '../_lib/repAuth.js';
import { repCustomers } from '../_lib/repsStore.js';
import { complaintsForRepEmails } from '../_lib/store.js'; // KORREKT

export default async function handler(req, res) {
  setCors(req, res, 'Content-Type, Authorization, X-Gate');
  if (req.method === 'OPTIONS') return res.status(204).end();
  if (req.method !== 'GET') {
    return res.status(405).end(JSON.stringify({ error: 'method not allowed' }));
  }

  const auth = getRepFromAuthHeader(req);
  if (!auth) {
    return res.status(401).end(JSON.stringify({ error: 'unauthorized' }));
  }

  let emails = [];
  try {
    emails = await repCustomers(auth.repId);
  } catch (e) {
    console.error('[rep/complaints] repCustomers failed:', e);
    return res.status(200).end(JSON.stringify([]));
  }

  if (!Array.isArray(emails) || emails.length === 0) {
    return res.status(200).end(JSON.stringify([]));
  }

  const status = String((req.query?.status || '')).trim();
  const debug  = req.query?.debug === '1';

  try {
    // KORRIGIERT: nutzt jetzt complaintsForRepEmails() statt complaintsByEmails()
    const items = await complaintsForRepEmails(emails, { status });

    if (debug) {
      // Nur zu Diagnosezwecken – KEINE sensiblen Daten loggen!
      const sample = items.slice(0, 5).map(c => ({
        ticket: c.ticket,
        email:
          c.email ||
          c.customerEmail ||
          c?.payload?.email ||
          c?.payload?.customerEmail ||
          '',
        status: c.status,
        decision: c.decision ?? null,
      }));

      return res.status(200).end(
        JSON.stringify({
          repId: auth.repId,
          emails,              // zugewiesene Kundenmails
          count: items.length, // Trefferzahl
          sample,              // kleine Stichprobe
        })
      );
    }

    return res.status(200).end(JSON.stringify(items));
  } catch (e) {
    console.error('[rep/complaints] complaintsForRepEmails failed:', e);
    return res.status(200).end(JSON.stringify([]));
  }
}
