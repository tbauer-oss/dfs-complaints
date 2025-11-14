// api/admin/customers.js
export const config = { runtime: 'nodejs' };

import bcrypt from 'bcryptjs';

import { setCors } from '../_lib/cors.js';
import { userSave } from '../_lib/store.js';

const ADMIN_SECRET = process.env.ADMIN_SECRET || '';

function adminAuthorized(req) {
  const hdr = req.headers?.['x-admin-secret'] || req.headers?.['X-Admin-Secret'];
  return !!(ADMIN_SECRET && hdr && hdr === ADMIN_SECRET);
}

export default async function handler(req, res) {
  // CORS – exakt wie bei /api/rep/complaints.js, nur mit X-Admin-Secret
  setCors(req, res, 'Content-Type, Authorization, X-Admin-Secret, X-Gate');

  // Preflight
  if (req.method === 'OPTIONS') {
    return res.status(204).end();
  }

  // Nur POST zulassen
  if (req.method !== 'POST') {
    return res
      .status(405)
      .end(JSON.stringify({ error: 'method not allowed' }));
  }

  // Admin-Auth (Header X-Admin-Secret muss mit ENV übereinstimmen)
  if (!adminAuthorized(req)) {
    return res
      .status(401)
      .end(JSON.stringify({ error: 'admin unauthorized' }));
  }

  // Body lesen
  let body;
  try {
    body =
      typeof req.body === 'object'
        ? req.body
        : JSON.parse(req.body ?? '{}');
  } catch (e) {
    return res
      .status(400)
      .end(JSON.stringify({ error: 'invalid json' }));
  }

  const email   = String(body.email   || '').trim().toLowerCase();
  const company = String(body.company || '').trim();
  const contact = String(body.contact || '').trim();
  const country = String(body.country || '').trim();
  const lang    = String(body.lang    || 'de').trim() || 'de';

  // Wenn kein Passwort angegeben wurde, ADMIN_SECRET als Startpasswort
  const pwRaw = String(body.password || '').trim() || ADMIN_SECRET;

  if (!email || !company) {
    return res
      .status(400)
      .end(JSON.stringify({ error: 'company and email required' }));
  }

  try {
    const passhash = await bcrypt.hash(pwRaw, 10);
    
    const user = {
      email,
      company,
      contact,
      country,
      lang,
      passhash,
      createdAt: Date.now(),
      adminCreated: true, // Flag: vom Admin angelegt
    };

    await userSave(user);

    // Antwort im gleichen Stil wie deine anderen Admin-Endpoints
    return res.status(200).end(
      JSON.stringify({
        ok: true,
        email,
        company,
        contact,
        country,
        lang,
      }),
    );
  } catch (e) {
    console.error('[admin/customers] error:', e);
    return res
      .status(500)
      .end(JSON.stringify({ error: e?.message || 'internal error' }));
  }
}
