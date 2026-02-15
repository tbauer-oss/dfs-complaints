export const config = { runtime: 'nodejs' };

import bcrypt from 'bcryptjs';
import jwt from 'jsonwebtoken';
import { methodNotAllowed, readJson } from '../_lib/http.js';
import { portalUserByEmail } from '../_lib/store.js';
import { normalizeRole } from '../_lib/portalAuth.js';
import { forbiddenEmailReason, logSecurityEvent } from '../_lib/forbiddenEmails.js';
import { normalizeEmail } from '../_lib/identity.js';

const JWT_SECRET = String(process.env.JWT_SECRET || '').trim() || 'devsecret';
const EXPIRES_IN = '12h';
const AUTH_DEBUG = String(process.env.AUTH_DEBUG || '').toLowerCase() === 'true';
const AUTH_DEBUG_KEY = String(process.env.AUTH_DEBUG_KEY || '').trim();
const BCRYPT_PREFIX_PATTERN = /^\$(2[aby])\$/;

function logOutcome(outcome, details = {}) {
  console.info('[portal/login]', { outcome, ...details });
}

function normalizeBcryptHash(passwordHash) {
  const hash = String(passwordHash || '').trim();
  if (!hash) return '';
  if (hash.startsWith('$2y$')) return `$2b$${hash.slice(4)}`;
  if (!BCRYPT_PREFIX_PATTERN.test(hash)) return '';
  return hash;
}

function shouldIncludeReason(req) {
  if (!AUTH_DEBUG) return false;
  if (!AUTH_DEBUG_KEY) return true;
  return String(req.headers?.['x-auth-debug'] || '').trim() === AUTH_DEBUG_KEY;
}

function respond(req, res, statusCode, payload, outcome = null) {
  if (!res.getHeader('Content-Type')) {
    res.setHeader('Content-Type', 'application/json; charset=utf-8');
  }
  const body = { ...payload };
  if (outcome && shouldIncludeReason(req)) body.reason = outcome;
  res.statusCode = statusCode;
  res.end(JSON.stringify(body));
}

export default async function handler(req, res) {
  if (req.method === 'OPTIONS') return res.status(204).end();
  if (req.method !== 'POST') return methodNotAllowed(res);

  let body;
  try {
    body = await readJson(req);
  } catch {
    logOutcome('BAD_REQUEST');
    return respond(req, res, 400, { code: 'BAD_REQUEST', message: 'Bitte alle Felder ausfüllen.' }, 'BAD_REQUEST');
  }

  const emailRaw = String(body?.email || '');
  const emailNorm = normalizeEmail(emailRaw);
  const password = String(body?.password || '');
  if (!emailNorm || !password) {
    logOutcome('BAD_REQUEST');
    return respond(req, res, 400, { code: 'BAD_REQUEST', message: 'Bitte alle Felder ausfüllen.' }, 'BAD_REQUEST');
  }

  const forbiddenReason = forbiddenEmailReason(emailNorm);
  if (forbiddenReason) {
    logSecurityEvent({ req, email: emailNorm, reason: forbiddenReason });
    return respond(req, res, 403, { code: 'FORBIDDEN_EMAIL', message: 'E-Mail nicht zulässig.' }, forbiddenReason);
  }

  let user;
  try {
    user = await portalUserByEmail(emailNorm);
  } catch {
    const outcome = 'STORE_UNAVAILABLE';
    logOutcome(outcome);
    return respond(
      req,
      res,
      503,
      { code: outcome, message: 'Service temporär nicht verfügbar. Bitte später erneut versuchen.' },
      outcome,
    );
  }

  if (!user) {
    const outcome = 'USER_NOT_FOUND';
    logOutcome(outcome, { email_norm: emailNorm });
    return respond(req, res, 401, { code: 'INVALID_CREDENTIALS', message: 'E-Mail/Passwort ungültig.' }, outcome);
  }

  if (user.portalStatus === 'inactive') {
    const outcome = 'ACCOUNT_DISABLED';
    logOutcome(outcome, { email_norm: emailNorm, user_id: user.id || null });
    return respond(req, res, 403, { code: 'ACCOUNT_DISABLED', message: 'Konto deaktiviert.' }, outcome);
  }

  const passwordHash = normalizeBcryptHash(user.passhash || user.passwordHash || '');
  if (!passwordHash) {
    const outcome = 'PASSWORD_NOT_SET';
    logOutcome(outcome, { email_norm: emailNorm, user_id: user.id || null });
    return respond(req, res, 409, { code: 'PASSWORD_NOT_SET', message: 'Für dieses Konto ist kein Passwort gesetzt.' }, outcome);
  }

  let passwordOk = false;
  try {
    passwordOk = await bcrypt.compare(password, passwordHash);
  } catch {
    passwordOk = false;
  }

  if (!passwordOk) {
    const outcome = 'PASSWORD_MISMATCH';
    logOutcome(outcome, { email_norm: emailNorm, user_id: user.id || null });
    return respond(req, res, 401, { code: 'INVALID_CREDENTIALS', message: 'E-Mail/Passwort ungültig.' }, outcome);
  }

  const role = normalizeRole(user.role);
  const token = jwt.sign(
    { sub: user.id || user.email, email: user.email, role, portalStatus: 'active' },
    JWT_SECRET,
    { expiresIn: EXPIRES_IN },
  );

  logOutcome('SUCCESS', { email_norm: emailNorm, user_id: user.id || null });
  return respond(req, res, 200, {
    token,
    user: { id: user.id, email: user.email, role },
    profile: { id: user.id, email: user.email, role, portalStatus: 'active', tourSeen: user.tourSeen === true },
    tourSeen: user.tourSeen === true,
    expiresIn: EXPIRES_IN,
  });
}
