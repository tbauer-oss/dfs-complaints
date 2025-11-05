// /api/rep/complaints.js
export const config = { runtime: 'nodejs' };

import { setCors } from '../_lib/cors.js';
import { getRepFromAuthHeader } from '../_lib/repAuth.js';
import { repCustomers } from '../_lib/repsStore.js';

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

  let items = [];
  try {
    const store = await import('../_lib/complaintsStore.js').catch(() => null);
    if (store && typeof store.getComplaintsByEmails === 'function') {
      items = await store.getComplaintsByEmails(emails, { status });
    } else if (store && typeof store.listComplaintsForRepEmails === 'function') {
      items = await store.listComplaintsForRepEmails(emails, { status });
    } else {
      console.warn('[rep/complaints] complaintsStore has no compatible export – returning empty list.');
      items = [];
    }
  } catch (e) {
    console.error('[rep/complaints] loading complaints failed:', e);
    items = [];
  }

  if (!Array.isArray(items)) items = [];
  return res.status(200).end(JSON.stringify(items));
}
