// api/auth/login.js
export const config = { runtime: 'nodejs' };

import bcrypt from 'bcryptjs';
import jwt from 'jsonwebtoken';
import {
  handlePreflight, ok, bad, methodNotAllowed, readJson
} from '../_lib/http.js';
import { portalUserByEmail, portalUserSave, recordUserLogin, userByEmail } from '../_lib/store.js';
import {
  ADMIN_EMAILS,
  ensureInitialAdmins,
  normalizeRole,
  normalizeStatus,
  PORTAL_ROLES,
} from '../_lib/portalAuth.js';

const JWT_SECRET = process.env.JWT_SECRET || 'devsecret';
const ADMIN_SECRET = process.env.ADMIN_SECRET || '';

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

    const preferPortal = ADMIN_EMAILS.has(email);
    let u = preferPortal ? await portalUserByEmail(email) : null;
    let isPortalAccount = preferPortal && !!u;

    if (!u && !preferPortal) {
      u = await userByEmail(email);
    }

    if (!u) {
      const portal = await portalUserByEmail(email);
      if (portal) {
        u = portal;
        isPortalAccount = true;
      }
    }

    // Auto-Provision der hinterlegten Admin-E-Mails (Passwort = ADMIN_SECRET)
    if (!u && ADMIN_EMAILS.has(email)) {
      const passhash = ADMIN_SECRET ? await bcrypt.hash(ADMIN_SECRET, 10) : '';
      u = {
        email,
        passhash,
        role: PORTAL_ROLES.superuser,
        portalStatus: 'active',
        displayName: email.split('@')[0],
        createdAt: Date.now(),
      };
      await portalUserSave(u);
      isPortalAccount = true;
    }

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
      if (!isPortalAccount) {
        await recordUserLogin(email, { appVersion: body?.appVersion, appBuild: body?.appBuild });
      }
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
