// /api/rep/customers.js
export const config = { runtime: 'nodejs' };

import { setCors } from '../_lib/cors.js';
import { getRepFromAuthHeader } from '../_lib/repAuth.js';
import { repCustomers, assignCustomer, unassignCustomer } from '../_lib/repsStore.js';

export default async function handler(req, res) {
  setCors(req, res, 'Content-Type, Authorization, X-Gate');
  if (req.method === 'OPTIONS') return res.status(204).end();

  const auth = getRepFromAuthHeader(req);
  if (!auth) return res.status(401).end(JSON.stringify({ error: 'unauthorized' }));

  if (req.method === 'GET') {
    const customers = await repCustomers(auth.repId);
    return res.status(200).end(JSON.stringify(customers || []));
  }

  if (req.method === 'POST') {
    const raw = (typeof req.body === 'string') ? req.body : JSON.stringify(req.body || {});
    let body = {};
    try { body = JSON.parse(raw || '{}'); } catch { body = {}; }

    const action = String(body.action || '').toLowerCase();
    const email  = String(body.email  || '').toLowerCase().trim();
    if (!email) return res.status(400).end(JSON.stringify({ error: 'missing email' }));

    if (action === 'assign') {
      const list = await assignCustomer(auth.repId, email);
      return res.status(200).end(JSON.stringify({ ok: true, customers: list || [] }));
    }
    if (action === 'unassign') {
      const list = await unassignCustomer(auth.repId, email);
      return res.status(200).end(JSON.stringify({ ok: true, customers: list || [] }));
    }
    return res.status(400).end(JSON.stringify({ error: 'invalid action' }));
  }

  return res.status(405).end(JSON.stringify({ error: 'method not allowed' }));
}
