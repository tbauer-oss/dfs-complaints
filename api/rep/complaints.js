// api/rep/complaints.js
export const config = { runtime: 'nodejs' };

import { setCors } from '../_lib/cors.js';
import { getRepFromAuthHeader } from '../_lib/repAuth.js';
import { repCustomers } from '../_lib/repsStore.js';

export default async function handler(req, res) {
  // Einheitliche CORS-Header
  setCors(req, res);
  if (req.method === 'OPTIONS') return res.status(204).end();
  if (req.method !== 'GET') {
    return res
      .status(405)
      .end(JSON.stringify({ error: 'method not allowed' }));
  }

  // ---- Auth aus Authorization: Bearer <repToken> ----
  const auth = getRepFromAuthHeader(req);
  if (!auth) {
    return res
      .status(401)
      .end(JSON.stringify({ error: 'unauthorized' }));
  }

  // ---- Kundenliste (E-Mails) für diesen Rep holen ----
  let emails = [];
  try {
    emails = await repCustomers(auth.repId);
  } catch (e) {
    console.error('[rep/complaints] repCustomers failed:', e);
    // Lieber "leere Liste" liefern als 500, damit das Frontend nicht bricht
    return res.status(200).end(JSON.stringify([]));
  }
  if (!Array.isArray(emails) || emails.length === 0) {
    return res.status(200).end(JSON.stringify([]));
  }

  // Optionaler Filter ?status=...
  const status = (req.query?.status || '').toString().trim();

  // ---- Complaints laden (dynamisch importieren, um Build/Runtime robust zu halten) ----
  let items = [];
  try {
    const store = await import('../_lib/complaintsStore.js').catch(() => null);

    if (store && typeof store.getComplaintsByEmails === 'function') {
      items = await store.getComplaintsByEmails(emails, { status });
    } else if (store && typeof store.listComplaintsForRepEmails === 'function') {
      // Falls dein Store anders heißt – kleiner Kompatibilitätsfallback
      items = await store.listComplaintsForRepEmails(emails, { status });
    } else {
      // Kein kompatibler Export vorhanden → Frontend-freundlicher Fallback
      console.warn(
        '[rep/complaints] complaintsStore has no getComplaintsByEmails/listComplaintsForRepEmails – returning empty list.'
      );
      items = [];
    }
  } catch (e) {
    console.error('[rep/complaints] loading complaints failed:', e);
    // Frontend-freundlich bleiben
    items = [];
  }

  if (!Array.isArray(items)) items = [];
  return res.status(200).end(JSON.stringify(items));
}