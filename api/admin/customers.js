// api/admin/customers.js
export const config = { runtime: 'nodejs' };

import { setCors, ok, bad, noContent, methodNotAllowed } from '../_lib/http.js';
import { userByEmail, userSave } from '../_lib/store.js';
import { hashPassword } from '../_lib/auth.js';

const ADMIN_SECRET = process.env.ADMIN_SECRET || '';

function adminAuthorized(req) {
  const hdr = req.headers?.['x-admin-secret'];
  return !!(hdr && ADMIN_SECRET && hdr === ADMIN_SECRET);
}

export default async function handler(req, res) {
  setCors(req, res);
  if (req.method === 'OPTIONS') return noContent(res);

  if (!adminAuthorized(req)) {
    return bad(res, 'admin unauthorized', 401);
  }

  if (req.method !== 'POST') {
    return methodNotAllowed(res);
  }

  let body = {};
  try {
    body = typeof req.body === 'object' ? req.body : JSON.parse(req.body ?? '{}');
  } catch (e) {
    return bad(res, 'invalid json', 400);
  }

  const email = (body.email ?? '').toString().trim().toLowerCase();
  const company = (body.company ?? '').toString().trim();
  const contact = (body.contact ?? '').toString().trim();
  const country = (body.country ?? '').toString().trim();
  const langRaw = (body.lang ?? '').toString().trim().toLowerCase();
  const plainPassword = (body.password ?? '').toString().trim();

  if (!email || !company) {
    return bad(res, 'email and company required', 400);
  }

  // Prüfen, ob es den Nutzer schon gibt
  const existing = await userByEmail(email);
  if (existing) {
    return bad(res, 'user already exists', 409);
  }

  // Startpasswort:
  // - wenn Admin eins eingibt -> das nehmen
  // - sonst -> ADMIN_SECRET
  const passwordToUse = plainPassword || ADMIN_SECRET;
  if (!passwordToUse) {
    return bad(res, 'no password configured (ADMIN_SECRET missing)', 500);
  }

  const passwordHash = await hashPassword(passwordToUse);

  // Sprache grob normalisieren (Backend normiert in userSave nochmal)
  const supported = ['de', 'en', 'fr', 'it', 'es'];
  const lang = supported.includes(langRaw) ? langRaw : 'de';

  const now = Date.now();

  const user = {
    email,
    company,
    contact,
    country,
    lang,
    passwordHash,
    createdAt: now,
    updatedAt: now,
    // optional:
    // createdByAdmin: true,
  };

  await userSave(user);

  return ok(res, {
    ok: true,
    user: {
      email,
      company,
      contact,
      country,
      lang,
      createdAt: now,
    },
  });
}
