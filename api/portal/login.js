// api/portal/login.js – DFS Portal (vormals Adminbereich)
export const config = { runtime: 'nodejs' };

import bcrypt from 'bcryptjs';
import jwt from 'jsonwebtoken';
import { ok, bad, methodNotAllowed, readJson } from '../_lib/http.js';
import { portalUserByEmail, portalUserSave, sanitizeTilePermissions } from '../_lib/store.js';
import {
  ADMIN_EMAILS,
  ensureInitialAdmins,
  normalizeRole,
  normalizeStatus,
  PORTAL_ROLES,
} from '../_lib/portalAuth.js';

const JWT_SECRET = process.env.JWT_SECRET || 'devsecret';
const ADMIN_SECRET = process.env.ADMIN_SECRET || '';

function passwordCandidates(user) {
  if (!user || typeof user !== 'object') return [];
  return [user.passhash, user.passwordHash, user.passHash, user.password]
    .map((v) => String(v || '').trim())
    .filter(Boolean);
}


export default async function handler(req, res) {
  if (req.method === 'OPTIONS') {
    return res.status(204).end();
  }

  try {
    if (req.method !== 'POST') return methodNotAllowed(res);

    await ensureInitialAdmins();

    const body = await readJson(req);
    const email = String(body?.email || '').trim().toLowerCase();
    const pw = String(body?.password || '');
    if (!email || !pw) return bad(res, 'missing credentials', 400);

    let u = await portalUserByEmail(email);
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
    }

    if (!u) return bad(res, 'invalid credentials', 401);

    let hash = '';
    let usedPlaintextFallback = false;
    const candidates = passwordCandidates(u);
    if (!candidates.length && ADMIN_EMAILS.has(email) && ADMIN_SECRET) {
      hash = await bcrypt.hash(ADMIN_SECRET, 10);
      u = { ...u, passhash: hash };
      await portalUserSave(u);
      candidates.push(hash);
    }
    if (!candidates.length) return bad(res, 'invalid credentials', 401);

    let okPw = false;
    for (const candidate of candidates) {
      if (!candidate) continue;
      if (candidate.startsWith('$2a$') || candidate.startsWith('$2b$') || candidate.startsWith('$2y$')) {
        try {
          if (await bcrypt.compare(pw, candidate)) {
            okPw = true;
            hash = candidate;
            break;
          }
        } catch (err) {
          console.warn('[portal/login] password hash invalid for', email, err?.message || err);
        }
      } else if (pw === candidate) {
        okPw = true;
        usedPlaintextFallback = true;
        break;
      }
    }

    if (!okPw) return bad(res, 'invalid credentials', 401);

    if (usedPlaintextFallback) {
      const upgraded = await bcrypt.hash(pw, 10);
      u = { ...u, passhash: upgraded, passwordHash: upgraded };
      await portalUserSave(u);
      hash = upgraded;
    }

    const role = normalizeRole(u.role);
    const portalStatus = normalizeStatus(u.portalStatus, u.revoked);
    if (portalStatus !== 'active') return bad(res, 'inactive', 403);
    const tilePermissions = sanitizeTilePermissions(u.tilePermissions);
    const isPRRC = u.isPRRC === true;

    const token = jwt.sign({
      sub: u.email,
      email: u.email,
      role,
      portalStatus,
      isSales: u.isSales === true,
      prrc: isPRRC,
    }, JWT_SECRET, { expiresIn: '12h' });

    return ok(res, {
      ok: true,
      token,
      profile: {
        email: u.email,
        displayName: u.displayName || u.contact || u.company,
        role,
        portalStatus,
        tilePermissions,
        isSales: u.isSales === true,
        isPRRC,
      },
    });
  } catch (err) {
    return bad(res, err?.message || 'server error', 500);
  }
}
