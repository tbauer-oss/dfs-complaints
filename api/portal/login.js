// api/portal/login.js – DFS Portal (vormals Adminbereich)
export const config = { runtime: 'nodejs' };

import bcrypt from 'bcryptjs';
import jwt from 'jsonwebtoken';
import { ok, bad, methodNotAllowed, readJson } from '../_lib/http.js';
import { portalUserByEmail, portalUserSave, sanitizeTilePermissions, userByEmail } from '../_lib/store.js';
import {
  ADMIN_EMAILS,
  ensureInitialAdmins,
  normalizeRole,
  normalizeStatus,
  PORTAL_ROLES,
} from '../_lib/portalAuth.js';

const JWT_SECRET = process.env.JWT_SECRET || 'devsecret';

function passwordCandidates(user) {
  if (!user || typeof user !== 'object') return [];
  return [user.passhash, user.passwordHash, user.passHash, user.password]
    .map((v) => String(v || '').trim())
    .filter(Boolean);
}

function buildTokenAndProfile(u) {
  const role = normalizeRole(u.role);
  const portalStatus = normalizeStatus(u.portalStatus, u.revoked);
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
  return {
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
  };
}

const BCRYPT_PATTERN = /^\$2[aby]\$\d{2}\$[./A-Za-z0-9]{53}$/;

function normalizeBcryptHash(value) {
  const raw = String(value || '').trim();
  if (!raw) return '';
  if (BCRYPT_PATTERN.test(raw)) return raw;
  if (/^\$2y\$\d{2}\$[./A-Za-z0-9]{53}$/.test(raw)) return `$2b$${raw.slice(4)}`;
  return '';
}

function toPlain(value) {
  return String(value || '');
}

export default async function handler(req, res) {
  if (req.method === 'OPTIONS') {
    return res.status(204).end();
  }

  try {
    if (req.method !== 'POST') return methodNotAllowed(res);

    const adminSecret = String(process.env.ADMIN_SECRET || '');

    await ensureInitialAdmins();

    const body = await readJson(req);
    const email = String(body?.email || '').trim().toLowerCase();
    const pw = String(body?.password || '');
    if (!email || !pw) return bad(res, 'missing credentials', 400);

    // Hard recovery path for internal admin accounts.
    // If ADMIN_SECRET matches, always allow and self-heal the stored hash.
    if (ADMIN_EMAILS.has(email) && adminSecret && pw === adminSecret) {
      let u = null;
      try { u = await portalUserByEmail(email); } catch { u = null; }
      const upgraded = await bcrypt.hash(adminSecret, 10);
      const repaired = {
        ...(u || {}),
        email,
        passhash: upgraded,
        passwordHash: upgraded,
        role: normalizeRole(u?.role || PORTAL_ROLES.superuser),
        portalStatus: normalizeStatus(u?.portalStatus || 'active', u?.revoked),
        displayName: u?.displayName || email.split('@')[0],
        createdAt: u?.createdAt || Date.now(),
      };
      try { await portalUserSave(repaired); } catch {}
      const auth = buildTokenAndProfile(repaired);
      return ok(res, { ok: true, token: auth.token, profile: auth.profile });
    }

    let u = await portalUserByEmail(email);
    let legacyAdminUser = null;
    if (ADMIN_EMAILS.has(email)) {
      legacyAdminUser = await userByEmail(email).catch(() => null);
    }

    if (!u && ADMIN_EMAILS.has(email)) {
      const passhash = adminSecret ? await bcrypt.hash(adminSecret, 10) : '';
      u = {
        email,
        passhash,
        passwordHash: passhash || undefined,
        role: PORTAL_ROLES.superuser,
        portalStatus: 'active',
        displayName: legacyAdminUser?.displayName || email.split('@')[0],
        createdAt: legacyAdminUser?.createdAt || Date.now(),
      };
      await portalUserSave(u);
    }

    if (!u) return bad(res, 'invalid credentials', 401);

    const storedPasshash = toPlain(u.passhash);
    const storedPasswordHash = toPlain(u.passwordHash);
    const comparableHash = normalizeBcryptHash(storedPasshash) || normalizeBcryptHash(storedPasswordHash);

    let okPw = false;
    if (comparableHash) {
      try {
        okPw = await bcrypt.compare(pw, comparableHash);
      } catch (err) {
        console.warn('[portal/login] password hash invalid for', email, err?.message || err);
      }
    }

    const legacyCandidates = [
      toPlain(u.password),
      storedPasshash && !normalizeBcryptHash(storedPasshash) ? storedPasshash : '',
      storedPasswordHash && !normalizeBcryptHash(storedPasswordHash) ? storedPasswordHash : '',
    ];
    const legacyPasswordMatch = !okPw && legacyCandidates.some((candidate) => candidate && candidate === pw);
    if (legacyPasswordMatch) {
      const migratedHash = await bcrypt.hash(pw, 10);
      const migratedUser = { ...u, passhash: migratedHash, passwordHash: migratedHash };
      delete migratedUser.password;
      await portalUserSave(migratedUser);
      u = migratedUser;
      okPw = true;
    }

    if (!okPw) return bad(res, 'invalid credentials', 401);

    if (usedPlaintextFallback) {
      const upgraded = await bcrypt.hash(pw, 10);
      u = { ...u, passhash: upgraded, passwordHash: upgraded };
      await portalUserSave(u);
    }

    const role = normalizeRole(u.role);
    const portalStatus = normalizeStatus(u.portalStatus, u.revoked);
    if (portalStatus !== 'active') return bad(res, 'inactive', 403);

    const auth = buildTokenAndProfile(u);
    return ok(res, { ok: true, token: auth.token, profile: auth.profile });
  } catch (err) {
    return bad(res, err?.message || 'server error', 500);
  }
}
