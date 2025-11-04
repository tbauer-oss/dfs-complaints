// api/rep/my.js
import { getAllRepsWithCustomers } from '../_lib/repsStore.js';

function getEmailFromJwt(req) {
  const h = req.headers.authorization || '';
  const m = /^Bearer\s+(.+)$/i.exec(h);
  if (!m) return null;
  try {
    const payload = JSON.parse(Buffer.from(m[1].split('.')[1], 'base64').toString('utf8'));
    return (payload.email || '').trim().toLowerCase();
  } catch {
    return null;
  }
}

function setCors(res) {
  res.setHeader('Access-Control-Allow-Origin', process.env.WEB_ORIGIN || '*');
  res.setHeader('Access-Control-Allow-Credentials', 'true');
  res.setHeader('Access-Control-Allow-Headers', 'Content-Type, Authorization, X-Gate');
  res.setHeader('Access-Control-Allow-Methods', 'GET,OPTIONS');
}

export default async function handler(req, res) {
  setCors(res);

  if (req.method === 'OPTIONS') return res.status(204).end();
  if (req.method !== 'GET') return res.status(405).end();

  const email = getEmailFromJwt(req);
  if (!email) return res.status(401).json({ error: 'unauthorized' });

  const reps = await getAllRepsWithCustomers(); // [{firstName,lastName,email,region,customers:[...]}]
  const rep = reps.find(r =>
    Array.isArray(r.customers) &&
    r.customers.some(c => (c || '').trim().toLowerCase() === email)
  );

  if (!rep) return res.status(204).end();

  return res.status(200).json({
    firstName: rep.firstName || '',
    lastName : rep.lastName  || '',
    email    : rep.email     || '',
    region   : rep.region    || '',
  });
}
