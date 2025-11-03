// api/auth/login.js
export const config = { runtime: 'nodejs' };

import bcrypt from 'bcryptjs';
import jwt from 'jsonwebtoken';
import { handlePreflight, setCors, ok, bad, methodNotAllowed, readJson } from '../_lib/http.js';
import { userByEmail } from '../_lib/store.js';

const JWT_SECRET = process.env.JWT_SECRET || 'devsecret';

// kleiner Helper: prüft, ob ein valider BCrypt-Hash vorliegt
function isBcryptHash(s) {
  return typeof s === 'string' && /^\$2[aby]\$\d{2}\$[./A-Za-z0-9]{53}$/.test(s);
}

export default async function handler(req, res) {
  // Preflight zuerst
  if (handlePreflight(req, res)) return;
  // CORS auch beim echten Request setzen
  setCors(req, res);

  if (req.method !== 'POST') return methodNotAllowed(res);

  try {
    const body  = readJson(req);
    const email = String(body?.email || '').trim().toLowerCase();
    const pw    = String(body?.password || '');

    if (!email || !pw) return bad(res, 'missing credentials', 400);

    // User lesen
    let u;
    try {
      u = await userByEmail(email);
    } catch (e) {
      console.error('auth/login userByEmail threw:', e);
      return bad(res, 'server error', 500);
    }

    if (!u || typeof u !== 'object') {
      return bad(res, 'invalid credentials', 401);
    }

    // Hash-Feld robust ermitteln
    const hash = u.passhash || u.passwordHash || u.hash || '';

    // Wenn kein valider BCrypt-Hash → keine 500 riskieren, sauber 401
    if (!isBcryptHash(hash)) {
      return bad(res, 'invalid credentials', 401);
    }

    // Passwort prüfen
    let okPw = false;
    try {
      okPw = await bcrypt.compare(pw, hash);
    } catch (e) {
      console.error('auth/login bcrypt.compare error:', e);
      // wenn compare scheitert, antworte mit 401 (nicht 500), um keine Interna zu leaken
      return bad(res, 'invalid credentials', 401);
    }

    if (!okPw) return bad(res, 'invalid credentials', 401);
    if (u.revoked) return bad(res, 'revoked', 403);

    // Token
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
    console.error('auth/login fatal error:', e);
    return bad(res, 'server error', 500);
  }
}
