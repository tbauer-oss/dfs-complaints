export const config = { runtime: 'nodejs' };

import bcrypt from 'bcryptjs';
import jwt from 'jsonwebtoken';
import { logStoreError, methodNotAllowed, readJson, storeUnavailablePayload } from '../_lib/http.js';
import { query } from '../_lib/db.js';
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

function isSchemaMismatchError(err) {
  const code = String(err?.code || '').toUpperCase();
  const message = String(err?.message || '').toLowerCase();
  if (code === '42703' || code === '42P01' || code === '3F000') return true;
  return (
    message.includes('column')
    || message.includes('relation')
    || message.includes('does not exist')
    || message.includes('schema')
  );
}

function isConnectivityError(err) {
  const code = String(err?.code || '').toUpperCase();
  const message = String(err?.message || '').toLowerCase();
  const connectivityCodes = new Set([
    'STORE_UNAVAILABLE',
    'DB_UNAVAILABLE',
    'REDIS_TIMEOUT',
    'ETIMEDOUT',
    'ECONNREFUSED',
    'ECONNRESET',
    'ENOTFOUND',
    'EAI_AGAIN',
    '57P01',
  ]);
  if (connectivityCodes.has(code)) return true;
  return message.includes('timeout') || message.includes('connect') || message.includes('connection');
}

function normalizeBcryptHash(passwordHash) {
  const hash = String(passwordHash || '').trim();
  if (!hash) return '';
  if (hash.startsWith('$2y$')) return `$2b$${hash.slice(4)}`;
  if (!BCRYPT_PREFIX_PATTERN.test(hash)) return '';
  return hash;
}

function mapAuthUserRow(row) {
  if (!row) return null;
  return {
    id: row.id,
    email: row.email_norm,
    emailNorm: row.email_norm,
    passhash: row.password_hash,
    role: row.role,
    authSource: 'db',
    tourSeen: row.tour_seen === true,
    portalStatus: String(row.portal_status || '').toLowerCase() === 'inactive'
      || row.is_active === false
      ? 'inactive'
      : 'active',
    createdAt: row.created_at || null,
    updatedAt: row.updated_at || null,
  };
}

async function loadPortalAuthUser(emailNorm) {
  const result = await query(
    `SELECT id,
            email_norm,
            password_hash,
            role,
            is_active
     FROM public.portal_users
     WHERE email_norm = $1
     LIMIT 1`,
    [emailNorm],
  );
  return mapAuthUserRow(result?.rows?.[0] || null);
}


function assertDbOnlyAuthSource(user) {
  if (!user) return;
  const source = String(user.authSource || '').toLowerCase();
  const hasKvMarker = user.fromKv === true
    || user.kv === true
    || String(user.source || '').toLowerCase() === 'kv'
    || String(user.cacheSource || '').toLowerCase() === 'kv';
  if (source && source !== 'db') {
    const err = new Error('auth user source is not db');
    err.code = 'SECURITY_GUARD_KV_AUTH_FORBIDDEN';
    throw err;
  }
  if (hasKvMarker) {
    const err = new Error('auth user has kv marker');
    err.code = 'SECURITY_GUARD_KV_AUTH_FORBIDDEN';
    throw err;
  }
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
    user = await loadPortalAuthUser(emailNorm);
  } catch (err) {
    if (isSchemaMismatchError(err)) {
      const outcome = 'SCHEMA_MISMATCH';
      logOutcome(outcome, {
        errorCode: err?.code || null,
        errorMessage: err?.message || String(err),
      });
      return respond(req, res, 500, { code: outcome, message: 'Database migration missing' }, outcome);
    }

    const outcome = 'STORE_UNAVAILABLE';
    const unavailablePayload = storeUnavailablePayload('Service temporär nicht verfügbar. Bitte später erneut versuchen.');
    logStoreError(err, unavailablePayload.debugId);
    logOutcome(outcome, {
      errorCode: err?.code || null,
      errorMessage: err?.message || String(err),
      debugId: unavailablePayload.debugId,
    });
    if (isConnectivityError(err)) {
      return respond(
        req,
        res,
        503,
        unavailablePayload,
        outcome,
      );
    }

    return respond(req, res, 500, { code: 'INTERNAL_ERROR', message: 'Internal server error' }, 'INTERNAL_ERROR');
  }

  if (!user) {
    const outcome = 'USER_NOT_FOUND';
    logOutcome(outcome, { email_norm: emailNorm });
    return respond(req, res, 401, { code: 'INVALID_CREDENTIALS', message: 'E-Mail/Passwort ungültig.' }, outcome);
  }

  try {
    assertDbOnlyAuthSource(user);
  } catch (err) {
    const outcome = 'SECURITY_GUARD_KV_AUTH_FORBIDDEN';
    logOutcome(outcome, {
      email_norm: emailNorm,
      user_id: user.id || null,
      errorCode: err?.code || null,
      errorMessage: err?.message || String(err),
    });
    return respond(req, res, 500, { code: outcome, message: 'Auth source violation.' }, outcome);
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
