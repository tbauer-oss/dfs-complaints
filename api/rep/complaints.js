// /api/rep/complaints.js
export const config = { runtime: 'nodejs' };

import { setCors } from '../_lib/cors.js';
import { getRepFromAuthHeader } from '../_lib/repAuth.js';
import { repCustomers } from '../_lib/repsStore.js';
import { complaintsByEmails } from '../_lib/store.js';

export default async function handler(req, res) {
  setCors(req, res, 'Content-Type, Authorization, X-Gate');
  if (req.method === 'OPTIONS') return res.status(204).end();
  if (req.method !== 'GET') {
    return res.status(405).end(JSON.stringify({ error: 'method not allowed' }));
  }

  const auth = getRepFromAuthHeader(req);
  if (!auth) return res.status(401).end(JSON.stringify({ error: 'unauthorized' }));

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

    try {
    const items = await complaintsByEmails(emails, { status });
    return res.status(200).end(JSON.stringify(items));
  } catch (e) {
    console.error('[rep/complaints] complaintsByEmails failed:', e);
    return res.status(200).end(JSON.stringify([]));
  }
}
