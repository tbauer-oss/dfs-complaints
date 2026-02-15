export const config = { runtime: 'nodejs' };

import { methodNotAllowed, withCors } from '../_lib/http.js';
import { getSanitizedDbTarget, query } from '../_lib/db.js';

function unauthorized(res) {
  res.statusCode = 401;
  res.end(JSON.stringify({ code: 'UNAUTHORIZED', message: 'Unauthorized' }));
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

  const target = getSanitizedDbTarget();
  const startedAt = Date.now();

  try {
    await query('select 1');
    res.statusCode = 200;
    return res.end(JSON.stringify({ ok: true, target, ms: Date.now() - startedAt }));
  } catch (err) {
    const message = err?.message || 'Database unavailable';
    const code = err?.code === 'DB_UNAVAILABLE' ? 'DB_UNAVAILABLE' : 'DB_UNAVAILABLE';
    console.warn('[admin/db-ping] failed', { target, code, message });
    res.statusCode = 503;
    return res.end(JSON.stringify({ ok: false, error: message, code, target }));
  }
}
