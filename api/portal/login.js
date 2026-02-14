// api/portal/login.js – DFS Portal (vormals Adminbereich)
export const config = { runtime: 'nodejs' };

import bcrypt from 'bcryptjs';
import crypto from 'crypto';
import jwt from 'jsonwebtoken';
import { ok, methodNotAllowed, readJson } from '../_lib/http.js';
import { portalUserByEmail, portalUserSave, sanitizeTilePermissions, userByEmail } from '../_lib/store.js';
import {
  ADMIN_EMAILS,
  ensureInitialAdmins,
  normalizeRole,
  normalizeStatus,
  PORTAL_ROLES,
} from '../_lib/portalAuth.js';

const AUTH_DEBUG = String(process.env.AUTH_DEBUG || '').trim().toLowerCase() === 'true';
const AUTH_DEBUG_KEY = String(process.env.AUTH_DEBUG_KEY || '');
const JWT_SECRET = String(process.env.JWT_SECRET || '').trim() || 'devsecret';

function hashEmailForLogs(email) {
  return crypto.createHash('sha256').update(String(email || '').toLowerCase()).digest('hex').slice(0, 12);
}

function authLog(outcome, payload = {}) {
  console.info('[portal/login]', {
    event: 'login_attempt',
    outcome,
    ...payload,
  });
}

function isAuthDebugRequest(req) {
  if (!AUTH_DEBUG || !AUTH_DEBUG_KEY) return false;
  const headerValue = req?.headers?.['x-auth-debug'];
  return typeof headerValue === 'string' && headerValue === AUTH_DEBUG_KEY;
}

function authError(req, res, statusCode, code, message, reason = '') {
  const body = { code, message };
  if (reason && isAuthDebugRequest(req)) body.reason = reason;
  if (!res.getHeader('Content-Type')) {
    res.setHeader('Content-Type', 'application/json; charset=utf-8');
  }
  res.statusCode = statusCode;
  res.end(JSON.stringify(body));
  return;
}

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
    const rawEmail = String(body?.email || '').trim();
    const email = rawEmail.toLowerCase();
    const passwordRaw = String(body?.password || '');
    const emailHash = hashEmailForLogs(email);
    if (!email || !passwordRaw) {
      authLog('MISSING_FIELDS', {
        emailHash,
        hasEmail: Boolean(email),
        hasPassword: Boolean(passwordRaw),
      });
      return authError(req, res, 400, 'BAD_REQUEST', 'Bitte alle Felder ausfüllen.', 'MISSING_FIELDS');
    }
    const passwordOptions = passwordInputCandidates(passwordRaw);
    authLog('START', { emailHash, normalizedEmailPresent: true });

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
      authLog('OK_ADMIN_SECRET', { emailHash });
      return ok(res, {
        ok: true,
        token: auth.token,
        user: auth.profile,
        profile: auth.profile,
        expiresIn: '12h',
      });
    }

    let u = null;
    let legacyUser = null;
    try {
      u = await portalUserByEmail(email);
      if (!u && rawEmail && rawEmail !== email) u = await portalUserByEmail(rawEmail);
      legacyUser = await userByEmail(email).catch(() => null);
    } catch (err) {
      authLog('DB_ERROR', {
        emailHash,
        step: 'lookup_user',
        error: err?.message || 'db error',
      });
      return authError(req, res, 500, 'SERVER_ERROR', 'server error', 'DB_ERROR');
    }
    let legacyAdminUser = null;
    if (ADMIN_EMAILS.has(email)) {
      legacyAdminUser = legacyUser;
    }

    if (!u && legacyUser && looksPortalLikeLegacyUser(email, legacyUser)) {
      const migratedLegacy = buildPortalUserFromLegacy(email, legacyUser);
      try {
        await portalUserSave(migratedLegacy);
      } catch (err) {
        authLog('DB_ERROR', {
          emailHash,
          step: 'save_migrated_legacy',
          error: err?.message || 'db error',
        });
        return authError(req, res, 500, 'SERVER_ERROR', 'server error', 'DB_ERROR');
      }
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
      try {
        await portalUserSave(u);
      } catch (err) {
        authLog('DB_ERROR', {
          emailHash,
          step: 'save_initial_admin',
          error: err?.message || 'db error',
        });
        return authError(req, res, 500, 'SERVER_ERROR', 'server error', 'DB_ERROR');
      }
    }

    if (!u) {
      authLog('USER_NOT_FOUND', {
        emailHash,
        legacyUserFound: Boolean(legacyUser),
      });
      return authError(req, res, 401, 'INVALID_CREDENTIALS', 'E-Mail/Passwort ungültig.', 'USER_NOT_FOUND');
    }

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
        try {
          await portalUserSave(u);
        } catch (err) {
          authLog('DB_ERROR', {
            emailHash,
            step: 'save_after_legacy_password_match',
            error: err?.message || 'db error',
          });
          return authError(req, res, 500, 'SERVER_ERROR', 'server error', 'DB_ERROR');
        }
        verification = legacyVerification;
      }
    }

    if (!verification.okPw) {
      authLog('PASSWORD_MISMATCH', {
        emailHash,
        legacyUserFound: Boolean(legacyUser),
      });
      return authError(req, res, 401, 'INVALID_CREDENTIALS', 'E-Mail/Passwort ungültig.', 'PASSWORD_MISMATCH');
    }

    if (verification.usedPlaintextFallback) {
      const upgraded = await bcrypt.hash(matchedPassword, 10);
      u = { ...u, passhash: upgraded, passwordHash: upgraded };
      try {
        await portalUserSave(u);
      } catch (err) {
        authLog('DB_ERROR', {
          emailHash,
          step: 'save_upgraded_plaintext',
          error: err?.message || 'db error',
        });
        return authError(req, res, 500, 'SERVER_ERROR', 'server error', 'DB_ERROR');
      }
    } else if (verification.comparableFromPassHashOnly) {
      u = { ...u, passhash: verification.comparableHash, passwordHash: verification.comparableHash };
      delete u.passHash;
      try {
        await portalUserSave(u);
      } catch (err) {
        authLog('DB_ERROR', {
          emailHash,
          step: 'save_canonicalized_hash_fields',
          error: err?.message || 'db error',
        });
        return authError(req, res, 500, 'SERVER_ERROR', 'server error', 'DB_ERROR');
      }
    }

    const role = normalizeRole(u.role);
    const portalStatus = normalizeStatus(u.portalStatus, u.revoked);
    if (portalStatus !== 'active') {
      authLog('USER_DISABLED', { emailHash });
      return authError(req, res, 403, 'ACCOUNT_INACTIVE', 'Konto ist deaktiviert.', 'USER_DISABLED');
    }

    const auth = buildTokenAndProfile(u);
    authLog('OK', { emailHash, role });
    return ok(res, {
      ok: true,
      token: auth.token,
      user: auth.profile,
      profile: auth.profile,
      expiresIn: '12h',
    });
  } catch (err) {
    authLog('DB_ERROR', {
      message: err?.message || 'server error',
    });
    return authError(req, res, 500, 'SERVER_ERROR', 'server error', 'DB_ERROR');
  }
}
