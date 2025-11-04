// api/rep/customers.js
import { setCors } from '../_lib/cors.js';
import { getRepFromAuthHeader } from '../_lib/repAuth.js';
import { repCustomers, assignCustomer, unassignCustomer } from '../_lib/repsStore.js';

export default async function handler(req, res) {
  setCors(req, res);
  if (req.method === 'OPTIONS') return res.status(204).end();

  const auth = getRepFromAuthHeader(req);
  if (!auth) return res.status(401).end(JSON.stringify({ error: 'unauthorized' }));

  if (req.method === 'GET') {
    const customers = await repCustomers(auth.repId);
    return res.status(200).end(JSON.stringify(customers || []));
  }

  if (req.method === 'POST') {
    const body = (typeof req.body === 'string') ? JSON.parse(req.body||'{}') : (req.body || {});
    const action = (body.action || '').toString().toLowerCase();
    const email  = (body.email  || '').toString().toLowerCase();
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

  res.status(405).end(JSON.stringify({ error: 'method not allowed' }));
}
