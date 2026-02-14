export const config = { runtime: 'nodejs' };

import { methodNotAllowed, withCors } from '../_lib/http.js';
import { portalUserByEmail } from '../_lib/store.js';

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

  const emailNorm = getQueryEmail(req).trim().toLowerCase();
  if (!emailNorm) {
    res.statusCode = 400;
    return res.end(JSON.stringify({ code: 'BAD_REQUEST', message: 'email is required' }));
  }

  let user;
  try {
    user = await portalUserByEmail(emailNorm);
  } catch (err) {
    console.warn('[admin/diag-portal-user]', { outcome: 'STORE_UNAVAILABLE', message: err?.message || String(err) });
    res.statusCode = 503;
    return res.end(JSON.stringify({ code: 'STORE_UNAVAILABLE', message: 'Service temporär nicht verfügbar.' }));
  }

  const hash = String(user?.passhash || user?.passwordHash || '').trim();
  const hashPrefix = hash ? hash.slice(0, 4) : '';
  const body = {
    found: Boolean(user),
    role: user?.role || null,
    is_active: user ? user.portalStatus !== 'inactive' : null,
    hash_prefix: hashPrefix,
    hash_len: hash.length,
  };

  res.statusCode = 200;
  return res.end(JSON.stringify(body));
}
