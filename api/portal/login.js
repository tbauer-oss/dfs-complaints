// api/portal/login.js – DFS Portal (vormals Adminbereich)
export const config = { runtime: 'nodejs' };

import bcrypt from 'bcryptjs';
import jwt from 'jsonwebtoken';
import { handlePreflight, ok, bad, methodNotAllowed, readJson } from '../_lib/http.js';
import { userByEmail, userSave } from '../_lib/store.js';
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
  if (handlePreflight(req, res)) return;
  if (req.method !== 'POST') return methodNotAllowed(res);

  try {
    await ensureInitialAdmins();

    const body = readJson(req);
    const email = String(body?.email || '').trim().toLowerCase();
    const pw = String(body?.password || '');
    if (!email || !pw) return bad(res, 'missing credentials', 400);

    let u = await userByEmail(email);
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
      await userSave(u);
    }

    if (!u) return bad(res, 'invalid credentials', 401);

    const hash = u.passhash || u.passwordHash || '';
    const okPw = await bcrypt.compare(pw, hash);
    if (!okPw) return bad(res, 'invalid credentials', 401);

    const role = normalizeRole(u.role);
    const portalStatus = normalizeStatus(u.portalStatus, u.revoked);
    if (portalStatus !== 'active') return bad(res, 'inactive', 403);

    const token = jwt.sign({
      sub: u.email,
      email: u.email,
      role,
      portalStatus,
    }, JWT_SECRET, { expiresIn: '12h' });

    return ok(res, {
      ok: true,
      token,
      profile: {
        email: u.email,
        displayName: u.displayName || u.contact || u.company,
        role,
        portalStatus,
      },
    });
  } catch (err) {
    return bad(res, err?.message || 'server error', 500);
  }
}

