// api/rep/me.js
import { setCors } from '../_lib/cors.js';
import { getRepFromAuthHeader } from '../_lib/repAuth.js';
import { loadRepById, repCustomers } from '../_lib/repsStore.js';

export default async function handler(req, res) {
  setCors(req, res);
  if (req.method === 'OPTIONS') return res.status(204).end();
  if (req.method !== 'GET')     return res.status(405).end(JSON.stringify({ error: 'method not allowed' }));

  const auth = getRepFromAuthHeader(req);
  if (!auth) return res.status(401).end(JSON.stringify({ error: 'unauthorized' }));

  const rep = await loadRepById(auth.repId);
  if (!rep) return res.status(404).end(JSON.stringify({ error: 'not found' }));

  const customers = await repCustomers(rep.id);
  res.status(200).end(JSON.stringify({
    id: rep.id,
    firstName: rep.firstName,
    lastName:  rep.lastName,
    email:     rep.email,
    region:    rep.region,
    customers: customers || [],
  }));
}
