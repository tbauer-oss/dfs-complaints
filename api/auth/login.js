// api/auth/login.js
export const config = { runtime: 'nodejs' };

import bcrypt from 'bcryptjs';
import jwt from 'jsonwebtoken';
import {
  handlePreflight, ok, bad, methodNotAllowed, readJson
} from '../_lib/http.js';
import { recordUserLogin, userByEmail } from '../_lib/store.js';
import {
  DFS_PORTAL_EMAIL_FORBIDDEN_MSG,
  ensureInitialAdmins,
  isPortalEmail,
  normalizeRole,
  normalizeStatus,
} from '../_lib/portalAuth.js';

const JWT_SECRET = process.env.JWT_SECRET || 'devsecret';
export default async function handler(req, res) {
  // CORS-Header setzen + OPTIONS direkt beantworten (204)
  if (handlePreflight(req, res)) return;

  if (req.method !== 'POST') return methodNotAllowed(res);

  try {
    const body = readJson(req);
    const email = String(body?.email || '').trim().toLowerCase();
    const pw    = String(body?.password || '');

    if (!email || !pw) return bad(res, 'missing credentials', 400);

    await ensureInitialAdmins();

    if (await isPortalEmail(email)) {
      return bad(res, DFS_PORTAL_EMAIL_FORBIDDEN_MSG, 403);
    }

    const u = await userByEmail(email);
    if (!u) return bad(res, 'invalid credentials', 401);

    // Achtung: Feldname muss zu deinem Store passen (passhash vs passwordHash)
    const hash = u.passhash || u.passwordHash || '';
    const okPw = await bcrypt.compare(pw, hash);
    if (!okPw) return bad(res, 'invalid credentials', 401);

    if (u.revoked) return bad(res, 'revoked', 403);

    const role = normalizeRole(u.role);
    const portalStatus = normalizeStatus(u.portalStatus, u.revoked);
    if (portalStatus !== 'active') return bad(res, 'inactive', 403);

    const token = jwt.sign({
      sub: u.email,
      email: u.email,
      role,
      portalStatus,
      isSales: u.isSales === true,
    }, JWT_SECRET, { expiresIn: '12h' });

    // Meta protokollieren (letzter Login + evtl. App-Version)
    try {
      await recordUserLogin(email, { appVersion: body?.appVersion, appBuild: body?.appBuild });
    } catch (e) {
      console.warn('[auth/login] recordUserLogin failed:', e?.message || e);
    }

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
        phone: u.phone || '',
        role,
        portalStatus,
        isSales: u.isSales === true,
      }
    });
  } catch (e) {
    return bad(res, 'server error', 500);
  }
}
