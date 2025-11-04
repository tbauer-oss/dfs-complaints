// api/rep/complaints.js
import { setCors } from '../_lib/cors.js';
import { getRepFromAuthHeader } from '../_lib/repAuth.js';
import { repCustomers } from '../_lib/repsStore.js';
import { getComplaintsByEmails } from '../_lib/complaintsStore.js'; // Du hast bereits ähnliche Query-Helfer; sonst kurz implementieren.

export default async function handler(req, res) {
  setCors(req, res);
  if (req.method === 'OPTIONS') return res.status(204).end();
  if (req.method !== 'GET')     return res.status(405).end(JSON.stringify({ error: 'method not allowed' }));

  const auth = getRepFromAuthHeader(req);
  if (!auth) return res.status(401).end(JSON.stringify({ error: 'unauthorized' }));

  const list = await repCustomers(auth.repId);
  if (!list?.length) return res.status(200).end(JSON.stringify([]));

  const status = (req.query?.status || '').toString(); // optional: filtern
  const data = await getComplaintsByEmails(list, { status }); // implementiere in deinem Complaint-Store
  res.status(200).end(JSON.stringify(data || []));
}
