// api/rep/my.js
import { getAllRepsWithCustomers } from '../_lib/repsStore.js';

function norm(s) {
  return (s || '').toString().trim().toLowerCase();
}

function tryExtractEmailFromJwt(req) {
  const h = req.headers.authorization || '';
  const m = /^Bearer\s+(.+)$/i.exec(h);
  if (!m) return null;
  try {
    const parts = m[1].split('.');
    if (parts.length < 2) return null;
    const payload = JSON.parse(Buffer.from(parts[1], 'base64').toString('utf8'));

    let email =
      payload.email ||
      payload.mail ||
      payload?.user?.email ||
      payload?.claims?.email ||
      (/@/.test(payload.sub || '') ? payload.sub : '');

    return norm(email);
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

  const email = tryExtractEmailFromJwt(req);
  if (!email) return res.status(401).json({ error: 'unauthorized' });

  // reps: [{ firstName, lastName, email, region, customers: [ ...emails... ] }]
  const reps = await getAllRepsWithCustomers();

  // Normiere Kundenlisten
  const rep = reps.find(r => Array.isArray(r.customers) && r.customers
    .map(norm)
    .some(c => c === email));

  // DEBUG: ?debug=1 zeigt dir, was verglichen wurde
  if (req.query?.debug === '1') {
    return res.status(rep ? 200 : 204).json({
      debug: {
        tokenEmail: email,
        repsCount: Array.isArray(reps) ? reps.length : -1,
        sample: (reps || []).slice(0, 3).map(r => ({
          repEmail: norm(r.email),
          customersCount: Array.isArray(r.customers) ? r.customers.length : 0,
          first3Customers: Array.isArray(r.customers)
            ? r.customers.slice(0, 3).map(norm)
            : [],
        })),
      },
      ...(rep && {
        firstName: rep.firstName || '',
        lastName : rep.lastName  || '',
        email    : rep.email     || '',
        region   : rep.region    || '',
      }),
    });
  }

  if (!rep) return res.status(204).end();

  return res.status(200).json({
    firstName: rep.firstName || '',
    lastName : rep.lastName  || '',
    email    : rep.email     || '',
    region   : rep.region    || '',
  });
}
