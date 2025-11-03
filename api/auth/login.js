// api/auth/login.js
export const config = { runtime: 'nodejs' };

import * as bcrypt from 'bcryptjs';               // robust in ESM
import jwt from 'jsonwebtoken';
import {
  handlePreflight, setCors, ok, bad, methodNotAllowed, readJson
} from '../_lib/http.js';
import { userByEmail } from '../_lib/store.js';

const JWT_SECRET = process.env.JWT_SECRET || 'devsecret';

// Prüft, ob ein valider BCrypt-Hash vorliegt
function isBcryptHash(s) {
  return typeof s === 'string' && /^\$2[aby]\$\d{2}\$[./A-Za-z0-9]{53}$/.test(s);
}

export default async function handler(req, res) {
  // CORS / Preflight zuerst
  if (handlePreflight(req, res)) return;
  // CORS auch beim echten Request setzen
  setCors(req, res);

  if (req.method !== 'POST') return methodNotAllowed(res);

  try {
    const body  = readJson(req);
    const email = String(body?.email || '').trim().toLowerCase();
    const pw    = String(body?.password || '');

    if (!email || !pw) return bad(res, 'missing credentials', 400);

    let u;
    try {
      u = await userByEmail(email);
    } catch (e) {
      console.error('auth/login -> userByEmail threw:', e);
      return bad(res, 'server error', 500);       // Datenzugriffsfehler
    }

    if (!u || typeof u !== 'object') {
      // Nutzer nicht gefunden
      return bad(res, 'invalid credentials', 401);
    }

    // Hash-Felder robust bestimmen (verschiedene Namensvarianten zulassen)
    const hash = u.passhash || u.passwordHash || u.hash || '';

    let okPw = false;

    if (isBcryptHash(hash)) {
      try {
        okPw = await bcrypt.compare(pw, hash);
      } catch (e) {
        console.error('auth/login -> bcrypt.compare error:', e);
        // Wenn der Hash formal valide aussieht, compare aber scheitert: 401 statt 500
        return bad(res, 'invalid credentials', 401);
      }
    } else {
      // Legacy/Test-Fallback: Klartext-Passwortfeld (nur vorübergehend!)
      // Falls du das nicht willst, kommentiere die 3 Zeilen aus und lass strikt 401 zurückgeben.
      const legacy = (u.password || u.pass || '').toString();
      if (legacy) {
        okPw = (legacy === pw);
      }
    }

    if (!okPw) return bad(res, 'invalid credentials', 401);
    if (u.revoked) return bad(res, 'revoked', 403);

    const token = jwt.sign({ sub: u.email, email: u.email }, JWT_SECRET, { expiresIn: '12h' });

    return ok(res, {
      ok: true,
      token,
      profile: {
        email: u.email || '',
        company: u.company || '',
        contact: u.contact || '',
        street: u.street || '',
        zip: u.zip || '',
        city: u.city || '',
        country: u.country || '',
        phone: u.phone || ''
      }
    });
  } catch (e) {
    console.error('auth/login fatal error:', e);
    return bad(res, 'server error', 500);
  }
}
