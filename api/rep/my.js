// api/rep/my.js
import { getAllRepsWithCustomers } from '../_lib/repsStore.js';

const norm = s => (s || '').toString().trim().toLowerCase();

function tryExtractEmailFromJwt(req) {
  const h = req.headers.authorization || '';
  const m = /^Bearer\s+(.+)$/i.exec(h);
  if (!m) return null;
  try {
    const [h64, p64] = m[1].split('.'); // header.payload.signature
    if (!p64) return null;
    const payload = JSON.parse(Buffer.from(p64, 'base64').toString('utf8'));
    const email =
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

  const reps = await getAllRepsWithCustomers();
  const found = (reps || []).find(r =>
    Array.isArray(r.customers) && r.customers.map(norm).some(c => c === email)
  );

  // DEBUG-Pfad: IMMER 200 + JSON zurückgeben (auch wenn kein Match)
  if (req.query?.debug === '1') {
    return res.status(200).json({
      debug: {
        tokenEmail: email,
        repsCount: Array.isArray(reps) ? reps.length : 0,
        // kleine Stichprobe zum Prüfen
        sample: (reps || []).slice(0, 3).map(r => ({
          repEmail: norm(r.email),
          customersCount: Array.isArray(r.customers) ? r.customers.length : 0,
          first3Customers: Array.isArray(r.customers)
            ? r.customers.slice(0, 3).map(norm)
            : [],
        })),
      },
      matched: !!found,
      rep: found
        ? {
            firstName: found.firstName || '',
            lastName:  found.lastName  || '',
            email:     found.email     || '',
            region:    found.region    || '',
          }
        : null,
    });
  }

  if (!found) return res.status(204).end(); // kein Body!

  return res.status(200).json({
    firstName: found.firstName || '',
    lastName:  found.lastName  || '',
    email:     found.email     || '',
    region:    found.region    || '',
  });
}
