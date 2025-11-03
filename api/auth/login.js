// api/auth/login.js
export const config = { runtime: 'nodejs' };

import bcrypt from 'bcryptjs';
import jwt from 'jsonwebtoken';
import { handlePreflight, setCors, ok, bad, methodNotAllowed, readJson } from '../_lib/http.js';
import { userByEmail } from '../_lib/store.js';

const JWT_SECRET = process.env.JWT_SECRET || 'devsecret';

export default async function handler(req, res) {
  // 1) OPTIONS beantworten
  if (handlePreflight(req, res)) return;
  // 2) Für den echten Request CORS-Header setzen!
  setCors(req, res);

  if (req.method !== 'POST') return methodNotAllowed(res);

  try {
    const body  = readJson(req);
    const email = String(body?.email || '').trim().toLowerCase();
    const pw    = String(body?.password || '');

    if (!email || !pw) return bad(res, 'missing credentials', 400);

    const u = await userByEmail(email);
    if (!u) return bad(res, 'invalid credentials', 401);

    const hash = u.passhash || u.passwordHash || '';
    const okPw = await bcrypt.compare(pw, hash);
    if (!okPw) return bad(res, 'invalid credentials', 401);
    if (u.revoked) return bad(res, 'revoked', 403);

    const token = jwt.sign({ sub: u.email, email: u.email }, JWT_SECRET, { expiresIn: '12h' });

    return ok(res, {
      ok: true,
      token,
      profile: {
        email: u.email,
        company: u.company,
        contact: u.contact,
        street: u.street,
        zip: u.zip,
        city: u.city,
        country: u.country,
        phone: u.phone || ''
      }
    });
  } catch (e) {
    console.error('auth/login error:', e);
    return bad(res, 'server error', 500);
  }
}
