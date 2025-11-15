// api/admin/customers.js
export const config = { runtime: 'nodejs' };

import bcrypt from 'bcryptjs';

import { setCors } from '../_lib/cors.js';
import { userSave } from '../_lib/store.js';
import { isStrongPassword } from '../_lib/passwords.js';

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

  const email       = String(body.email       || '').trim().toLowerCase();
  const company     = String(body.company     || '').trim();
  const contactRaw  = String(body.contact     || '').trim();
  const firstName   = String(body.firstName   || '').trim();
  const lastName    = String(body.lastName    || '').trim();
  const street      = String(body.street      || '').trim();
  const zip         = String(body.zip         || '').trim();
  const city        = String(body.city        || '').trim();
  const country     = String(body.country     || '').trim();
  const countryCode = String(body.countryCode || '').trim().toUpperCase().slice(0, 2);
  const phone       = String(body.phone       || '').trim();
  const lang        = String(body.lang        || 'de').trim() || 'de';
  
  // Wenn kein Passwort angegeben wurde, ADMIN_SECRET als Startpasswort
  const pwRaw = String(body.password || '').trim() || ADMIN_SECRET;

  if (!email || !company) {
    return res
      .status(400)
      .end(JSON.stringify({ error: 'company and email required' }));
  }

  if (!street || !zip || !city || !country) {
    return res
      .status(400)
      .end(JSON.stringify({ error: 'street, zip, city and country required' }));
  }

  const hasContact = contactRaw.length > 0;
  const hasNames = firstName.length > 0 && lastName.length > 0;
  if (!hasContact && !hasNames) {
    return res
      .status(400)
      .end(JSON.stringify({ error: 'contact or first/last name required' }));
  }

  const contact = hasContact ? contactRaw : `${firstName} ${lastName}`.trim();

  if (!isStrongPassword(pwRaw)) {
    return res
      .status(400)
      .end(
        JSON.stringify({ error: 'password requirements not met (min. 8 chars incl. letters, numbers & special characters)' })
      );
  }

  try {
    const passhash = await bcrypt.hash(pwRaw, 10);
    
    const user = {
      email,
      company,
      contact,
      firstName: firstName || undefined,
      lastName: lastName || undefined,
      street,
      zip,
      city,
      country,
      countryCode: countryCode || undefined,
      phone: phone || undefined,
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
        firstName: firstName || undefined,
        lastName: lastName || undefined,
        street,
        zip,
        city,
        country,
        countryCode: countryCode || undefined,
        phone: phone || undefined,
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
