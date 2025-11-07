// /api/rep/assignable-customers.js


export const config = { runtime: 'nodejs' };
import { setCors } from '../_lib/cors.js';
import { getRepFromAuthHeader } from '../_lib/repAuth.js';
import { repCustomers } from '../_lib/repsStore.js'; // leichtgewichtig belassen

function S(v) { return (v ?? '').toString().trim(); }

export default async function handler(req, res) {
  // 1) CORS IMMER zuerst
  setCors(req, res, 'Content-Type, Authorization, X-Gate');
  if (req.method === 'OPTIONS') return res.status(204).end();

    const allCustomers = await loadAllCustomersWithAssignee(); 

  // Minimalvalidierung + sortieren nach Label
  const norm = (x) => ({
    email: String(x.email || '').toLowerCase(),
    company: String(x.company || ''),
    name: String(x.name || ''),
    assigneeEmail: x.assigneeEmail ? String(x.assigneeEmail).toLowerCase() : null,
    assigneeName: x.assigneeName || null,
  });
  const list = allCustomers.map(norm).filter(c => c.email);
  list.sort((a,b) => (a.company||a.name||a.email).localeCompare(b.company||b.name||b.email, 'de', {sensitivity:'base'}));

  res.status(200).json(list);
}
