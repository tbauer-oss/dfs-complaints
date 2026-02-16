// api/account/password.js
export const config = { runtime: 'nodejs' };

import bcrypt from 'bcryptjs';
import { getAuthUser } from '../_lib/auth.js';
import { query } from '../_lib/db.js';
import { methodNotAllowed, setCors } from '../_lib/http.js';
import { normalizeEmail } from '../_lib/identity.js';
import { redis } from '../_lib/redis.js';

function sendJson(res, statusCode, payload) {
  res.statusCode = statusCode;
  res.setHeader('Content-Type', 'application/json; charset=utf-8');
  res.end(JSON.stringify(payload));
}

function parseBody(req) {
  if (req.body && typeof req.body === 'object') return req.body;
  if (typeof req.body === 'string') {
    const trimmed = req.body.trim();
    return JSON.parse(trimmed || '{}');
  }
  return {};
}

function isDbConnectivityError(err) {
  return String(err?.code || '').toUpperCase() === 'DB_UNAVAILABLE';
}

export default async function handler(req, res) {
  setCors(req, res);
  if (req.method === 'OPTIONS') return res.status(204).end();
  if (req.method !== 'POST') return methodNotAllowed(res);

  const auth = getAuthUser(req);
  if (!auth) {
    return sendJson(res, 401, { code: 'UNAUTHORIZED', message: 'Missing or invalid authorization token.' });
  }

  if (!auth.sub) {
    return sendJson(res, 401, { code: 'UNAUTHORIZED', message: 'Token subject is missing.' });
  }

  let body;
  try {
    body = parseBody(req);
  } catch {
    return sendJson(res, 400, { code: 'VALIDATION_ERROR', message: 'Request body must be valid JSON.' });
  }

  const { currentPassword, newPassword } = body || {};

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

  try {
    const userResult = await query(
      `SELECT id, email_norm, password_hash
       FROM portal_users
       WHERE id = $1
       LIMIT 1`,
      [auth.sub],
    );

    const user = userResult?.rows?.[0] || null;
    if (!user) {
      return sendJson(res, 404, { code: 'USER_NOT_FOUND', message: 'User account not found.' });
    }

    const ok = await bcrypt.compare(currentPassword, String(user.password_hash || ''));
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

    const emailNorm = normalizeEmail(user.email_norm || auth.email || '');
    if (emailNorm) {
      await redis.del(`dfs:portal:user:${emailNorm}`);
      await redis.del(`dfs:portal:user_safe:${emailNorm}`);
    }

    return sendJson(res, 200, { ok: true });
  } catch (err) {
    if (isDbConnectivityError(err)) {
      return sendJson(res, 503, { code: 'DB_UNAVAILABLE', message: 'Database unavailable.' });
    }

    console.error('[account/password] unexpected error', err);
    return sendJson(res, 500, { code: 'INTERNAL_ERROR', message: 'Internal server error.' });
  }
}
