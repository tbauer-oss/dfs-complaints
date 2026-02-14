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

const BCRYPT_PATTERN = /^\$2[ab]\$\d{2}\$[./A-Za-z0-9]{53}$/;

function normalizeBcryptHash(value) {
  const raw = String(value || '').trim();
  if (!raw) return '';
  if (/^\$2y\$\d{2}\$[./A-Za-z0-9]{53}$/.test(raw)) return `$2b$${raw.slice(4)}`;
  if (BCRYPT_PATTERN.test(raw)) return raw;
  return '';
}

function toPlain(value) {
  return String(value || '');
}



function passwordInputCandidates(value) {
  const raw = String(value ?? '');
  const trimmed = raw.trim();
  if (trimmed && trimmed != raw) return [raw, trimmed];
  return [raw];
}

function isLikelyPortalEmail(email) {
  return /@dfs-diamon\.(de|com)$/i.test(String(email || '').trim());
}



function looksPortalLikeLegacyUser(email, legacyUser) {
  if (!legacyUser || typeof legacyUser !== 'object') return false;
  if (ADMIN_EMAILS.has(email) || isLikelyPortalEmail(email)) return true;

  const normalizedType = String(legacyUser.type || legacyUser.kind || '').trim().toLowerCase();
  if (normalizedType === 'portal' || normalizedType === 'staff') return true;

  const hasExplicitRole = Object.prototype.hasOwnProperty.call(legacyUser, 'role');
  const normalizedRole = normalizeRole(legacyUser.role || '');
  if (normalizedRole !== PORTAL_ROLES.user) return true;
  if (hasExplicitRole) return true;

  if (Object.prototype.hasOwnProperty.call(legacyUser, 'portalStatus')) return true;
  if (legacyUser.isSales === true || legacyUser.isPRRC === true) return true;
  if (legacyUser.tilePermissions && typeof legacyUser.tilePermissions === 'object') return true;

  return false;
}

async function verifyPasswordForUser(user, password) {
  const storedPasshash = toPlain(user?.passhash);
  const storedPasswordHash = toPlain(user?.passwordHash);
  const storedPassHash = toPlain(user?.passHash);
  const hashCandidates = passwordCandidates(user).map(normalizeBcryptHash).filter(Boolean);
  const comparableHash = hashCandidates[0] || '';

  let okPw = false;
  if (comparableHash) {
    try {
      okPw = await bcrypt.compare(password, comparableHash);
    } catch {
      okPw = false;
    }
  }

  const legacyCandidates = [
    toPlain(user?.password),
    storedPasshash && !normalizeBcryptHash(storedPasshash) ? storedPasshash : '',
    storedPasswordHash && !normalizeBcryptHash(storedPasswordHash) ? storedPasswordHash : '',
    storedPassHash && !normalizeBcryptHash(storedPassHash) ? storedPassHash : '',
  ];
  const usedPlaintextFallback = !okPw && legacyCandidates.some((candidate) => candidate && candidate === password);

  return {
    okPw: okPw || usedPlaintextFallback,
    usedPlaintextFallback,
    comparableHash,
    comparableFromPassHashOnly: Boolean(
      comparableHash
      && !normalizeBcryptHash(storedPasshash)
      && !normalizeBcryptHash(storedPasswordHash)
      && normalizeBcryptHash(storedPassHash),
    ),
  };
}

function buildPortalUserFromLegacy(email, legacyUser = {}) {
  const role = normalizeRole(legacyUser.role || PORTAL_ROLES.user);
  return {
    email,
    passhash: toPlain(legacyUser.passhash),
    passwordHash: toPlain(legacyUser.passwordHash),
    passHash: toPlain(legacyUser.passHash),
    password: toPlain(legacyUser.password),
    role,
    portalStatus: normalizeStatus(legacyUser.portalStatus || 'active', legacyUser.revoked),
    displayName: legacyUser.displayName || legacyUser.contact || legacyUser.company || email.split('@')[0],
    isSales: legacyUser.isSales === true,
    isPRRC: legacyUser.isPRRC === true,
    tilePermissions: legacyUser.tilePermissions,
    createdAt: legacyUser.createdAt || Date.now(),
  };
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
    const passwordRaw = String(body?.password || '');
    if (!email || !passwordRaw) return bad(res, 'missing credentials', 400);
    const passwordOptions = passwordInputCandidates(passwordRaw);

    // Hard recovery path for internal admin accounts.
    // If ADMIN_SECRET matches, always allow and self-heal the stored hash.
    if (ADMIN_EMAILS.has(email) && adminSecret && passwordOptions.includes(adminSecret)) {
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
    const legacyUser = await userByEmail(email).catch(() => null);
    let legacyAdminUser = null;
    if (ADMIN_EMAILS.has(email)) {
      legacyAdminUser = legacyUser;
    }

    if (!u && legacyUser && looksPortalLikeLegacyUser(email, legacyUser)) {
      const migratedLegacy = buildPortalUserFromLegacy(email, legacyUser);
      await portalUserSave(migratedLegacy);
      u = migratedLegacy;
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

    let verification = { okPw: false, usedPlaintextFallback: false, comparableHash: '', comparableFromPassHashOnly: false };
    let matchedPassword = passwordRaw;
    for (const candidatePassword of passwordOptions) {
      verification = await verifyPasswordForUser(u, candidatePassword);
      if (verification.okPw) {
        matchedPassword = candidatePassword;
        break;
      }
    }

    if (!verification.okPw && legacyUser) {
      let legacyVerification = { okPw: false, usedPlaintextFallback: false, comparableHash: '', comparableFromPassHashOnly: false };
      for (const candidatePassword of passwordOptions) {
        legacyVerification = await verifyPasswordForUser(legacyUser, candidatePassword);
        if (legacyVerification.okPw) {
          matchedPassword = candidatePassword;
          break;
        }
      }
      if (legacyVerification.okPw) {
        u = buildPortalUserFromLegacy(email, legacyUser);
        await portalUserSave(u);
        verification = legacyVerification;
      }
    }

    if (!verification.okPw) return bad(res, 'invalid credentials', 401);

    if (verification.usedPlaintextFallback) {
      const upgraded = await bcrypt.hash(matchedPassword, 10);
      u = { ...u, passhash: upgraded, passwordHash: upgraded };
      await portalUserSave(u);
    } else if (verification.comparableFromPassHashOnly) {
      u = { ...u, passhash: verification.comparableHash, passwordHash: verification.comparableHash };
      delete u.passHash;
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
