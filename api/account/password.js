// api/account/password.js
export const config = { runtime: 'nodejs' };

import bcrypt from 'bcryptjs';
import { getAuthUser } from '../_lib/auth.js';
import { query } from '../_lib/db.js';
import { methodNotAllowed, setCors } from '../_lib/http.js';
import { invalidatePortalUserCaches } from '../_lib/portalUserCache.js';

const BCRYPT_PREFIX_PATTERN = /^\$(2[aby])\$/;
const UUID_V4_PATTERN = /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;

function sendJson(res, statusCode, payload) {
  res.statusCode = statusCode;
  res.setHeader('Content-Type', 'application/json; charset=utf-8');
  res.end(JSON.stringify(payload));
}

async function readJsonBody(req) {
  if (req.body && typeof req.body === 'object') return req.body;

  const parse = (value) => {
    if (typeof value === 'string') {
      const trimmed = value.trim();
      return JSON.parse(trimmed || '{}');
    }
    if (Buffer.isBuffer(value)) {
      const trimmed = value.toString('utf8').trim();
      return JSON.parse(trimmed || '{}');
    }
    return value && typeof value === 'object' ? value : {};
  };

  if (req.body != null) return parse(req.body);

  const raw = await new Promise((resolve, reject) => {
    if (!req || typeof req.on !== 'function') return resolve('');
    let chunks = '';
    req.on('data', (chunk) => {
      chunks += Buffer.isBuffer(chunk) ? chunk.toString('utf8') : String(chunk || '');
    });
    req.on('end', () => resolve(chunks));
    req.on('error', reject);
  });

  return parse(raw);
}

function isDbConnectivityError(err) {
  return String(err?.code || '').toUpperCase() === 'DB_UNAVAILABLE';
}

function normalizeBcryptHash(passwordHash) {
  const hash = String(passwordHash || '').trim();
  if (!hash) return '';
  if (hash.startsWith('$2y$')) return `$2b$${hash.slice(4)}`;
  if (!BCRYPT_PREFIX_PATTERN.test(hash)) return '';
  return hash;
}

export default async function handler(req, res) {
  setCors(req, res);
  if (req.method === 'OPTIONS') return res.status(204).end();
  if (req.method !== 'POST') return methodNotAllowed(res);

  const auth = getAuthUser(req);
  if (!auth) {
    return sendJson(res, 401, { code: 'UNAUTHORIZED', message: 'Missing or invalid authorization token.' });
  }

  const authSubject = String(auth.sub || '').trim();
  const authEmail = String(auth.email || '').trim().toLowerCase();

  if (!authSubject && !authEmail) {
    return sendJson(res, 401, { code: 'UNAUTHORIZED', message: 'Token subject is missing.' });
  }

  let body;
  try {
    body = await readJsonBody(req);
  } catch {
    return sendJson(res, 400, { code: 'VALIDATION_ERROR', message: 'Request body must be valid JSON.' });
  }

  const presentKeys = body && typeof body === 'object' ? Object.keys(body).sort() : [];
  if (process.env.NODE_ENV !== 'production') {
    console.debug('[account/password] payload keys', presentKeys);
  }

  const currentPassword = body?.currentPassword
    ?? body?.current_password
    ?? body?.oldPassword
    ?? body?.old_password
    ?? body?.password;

  const newPassword = body?.newPassword
    ?? body?.new_password
    ?? body?.newPass
    ?? body?.new_pass;

  const confirmPassword = body?.confirmPassword
    ?? body?.confirm_password
    ?? body?.newPasswordRepeat
    ?? body?.new_password_repeat;

  if (!currentPassword || !newPassword) {
    return sendJson(res, 400, {
      code: 'VALIDATION_ERROR',
      message: 'Both currentPassword and newPassword are required.',
    });
  }

  if (String(newPassword).length < 8) {
    return sendJson(res, 400, {
      code: 'WEAK_PASSWORD',
      message: 'newPassword must be at least 8 characters long.',
    });
  }

  if (confirmPassword != null && String(confirmPassword) !== String(newPassword)) {
    return sendJson(res, 400, {
      code: 'PASSWORD_CONFIRM_MISMATCH',
      message: 'confirmPassword must match newPassword.',
    });
  }

  try {
    const subjectLooksLikeUuid = UUID_V4_PATTERN.test(authSubject);
    const userLookupKey = authEmail || authSubject;

    const userResult = await query(
      `SELECT id, email_norm, password_hash
       FROM portal_users
       WHERE id::text = $1
          OR email_norm = $2
       LIMIT 1`,
      [authSubject || userLookupKey, userLookupKey],
    );

    const user = userResult?.rows?.[0] || null;
    if (!user) {
      return sendJson(res, 404, { code: 'USER_NOT_FOUND', message: 'User account not found.' });
    }

    if (subjectLooksLikeUuid && authSubject && String(user.id) !== authSubject && process.env.NODE_ENV !== 'production') {
      console.warn('[account/password] auth subject does not match resolved user id', {
        authSubject,
        resolvedUserId: user.id,
      });
    }

    const currentHash = normalizeBcryptHash(user.password_hash || '');
    if (!currentHash) {
      return sendJson(res, 400, {
        code: 'INVALID_CURRENT_PASSWORD',
        message: 'The current password is incorrect.',
      });
    }

    let ok = false;
    try {
      ok = await bcrypt.compare(currentPassword, currentHash);
    } catch {
      ok = false;
    }

    if (!ok) {
      return sendJson(res, 400, {
        code: 'INVALID_CURRENT_PASSWORD',
        message: 'The current password is incorrect.',
      });
    }

    const hash = await bcrypt.hash(newPassword, 10);

    await query(
      `UPDATE portal_users
       SET password_hash = $1,
           updated_at = NOW()
       WHERE id = $2`,
      [hash, user.id],
    );

    const cacheInfo = await invalidatePortalUserCaches(user.email_norm || auth.email, { logPrefix: 'account/password' });

    return sendJson(res, 200, { ok: true, cacheInvalidated: cacheInfo.cacheInvalidated });
  } catch (err) {
    if (isDbConnectivityError(err)) {
      return sendJson(res, 503, { code: 'DB_UNAVAILABLE', message: 'Database unavailable.' });
    }

    if (String(err?.code || '').toUpperCase() === '22P02') {
      return sendJson(res, 401, { code: 'UNAUTHORIZED', message: 'Invalid authorization subject.' });
    }

    console.error('[account/password] unexpected error', err);
    return sendJson(res, 500, { code: 'INTERNAL_ERROR', message: 'Internal server error.' });
  }
}
