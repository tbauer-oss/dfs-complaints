// api/rep/my.js
import { getAllRepsWithCustomers } from '../_lib/repsStore.js';

function tryExtractEmailFromJwt(req) {
  const h = req.headers.authorization || '';
  const m = /^Bearer\s+(.+)$/i.exec(h);
  if (!m) return null;
  try {
    const token = m[1];
    const parts = token.split('.');
    if (parts.length < 2) return null;
    const payloadJson = Buffer.from(parts[1], 'base64').toString('utf8');
    const p = JSON.parse(payloadJson);

    // 1) direkte Felder
    let email =
      (p.email?.toString()) ||
      (p.mail?.toString()) ||
      // 2) verschachtelt
      (p.user?.email?.toString()) ||
      (p.claims?.email?.toString()) ||
      // 3) sub als Fallback, falls es eine E-Mail ist
      (/@/.test(p.sub || '') ? p.sub.toString() : '');

    email = (email || '').trim().toLowerCase();
    return email || null;
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

  // Reps mit Kundenlisten laden: [{ firstName,lastName,email,region,customers:[...]}]
  const reps = await getAllRepsWithCustomers();

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
