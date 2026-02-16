export const config = { runtime: 'nodejs' };

import { logStoreError, methodNotAllowed, storeUnavailablePayload, withCors } from '../_lib/http.js';
import { portalUserByEmail } from '../_lib/store.js';
import { query } from '../_lib/db.js';
import { normalizeEmail } from '../_lib/identity.js';

function unauthorized(res) {
  res.statusCode = 401;
  res.end(JSON.stringify({ code: 'UNAUTHORIZED', message: 'Unauthorized' }));
}

function getQueryEmail(req) {
  const raw = req?.query?.email;
  if (Array.isArray(raw)) return String(raw[0] || '');
  return String(raw || '');
}

export default async function handler(req, res) {
  withCors(req, res);
  if (req.method === 'OPTIONS') return res.status(204).end();
  if (req.method !== 'GET') return methodNotAllowed(res);

  const adminSecret = String(process.env.ADMIN_SECRET || '').trim();
  const providedSecret = String(req.headers?.['x-admin-secret'] || '').trim();
  if (!adminSecret || providedSecret !== adminSecret) {
    return unauthorized(res);
  }

  const emailNorm = normalizeEmail(getQueryEmail(req));
  if (!emailNorm) {
    res.statusCode = 400;
    return res.end(JSON.stringify({ code: 'BAD_REQUEST', message: 'email is required' }));
  }

  let user;
  try {
    user = await portalUserByEmail(emailNorm);
  } catch (err) {
    const payload = storeUnavailablePayload('Service temporär nicht verfügbar.');
    logStoreError(err, payload.debugId);
    console.warn('[admin/auth-diagnose]', {
      outcome: 'STORE_UNAVAILABLE',
      message: err?.message || String(err),
      debugId: payload.debugId,
    });
    res.statusCode = 503;
    return res.end(JSON.stringify(payload));
  }


  let legacyKvExists = null;
  try {
    const kvCheck = await query(
      `SELECT COUNT(*)::int AS cnt FROM kv_store WHERE k = $1`,
      [`dfs:portal:user:${emailNorm}`],
    );
    legacyKvExists = Number(kvCheck?.rows?.[0]?.cnt || 0) > 0;
  } catch {
    legacyKvExists = null;
  }

  const hash = String(user?.passhash || user?.passwordHash || '').trim();
  const body = {
    email_norm: emailNorm,
    existsInPortalUsers: Boolean(user),
    is_active: user ? user.portalStatus !== 'inactive' : null,
    hasPasswordHash: hash.length > 0,
    passwordHashPrefix: hash ? hash.slice(0, 7) : null,
    updated_at: user?.updatedAt || null,
    legacyKvExists,
  };

  res.statusCode = 200;
  return res.end(JSON.stringify(body));
}
