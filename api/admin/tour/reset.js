export const config = { runtime: 'nodejs' };

import { logStoreError, methodNotAllowed, storeUnavailablePayload, withCors } from '../../_lib/http.js';
import { markPortalTourSeen } from '../../_lib/store.js';

export default async function handler(req, res) {
  withCors(req, res);
  if (req.method === 'OPTIONS') return res.status(204).end();
  if (req.method !== 'POST') return methodNotAllowed(res);

  const adminSecret = String(process.env.ADMIN_SECRET || '').trim();
  const providedSecret = String(req.headers?.['x-admin-secret'] || '').trim();
  if (!adminSecret || providedSecret !== adminSecret) {
    res.statusCode = 401;
    return res.end(JSON.stringify({ code: 'UNAUTHORIZED', message: 'Unauthorized' }));
  }

  const emailRaw = Array.isArray(req.query?.email) ? req.query.email[0] : req.query?.email;
  const email = String(emailRaw || '').trim().toLowerCase();
  if (!email) {
    res.statusCode = 400;
    return res.end(JSON.stringify({ code: 'BAD_REQUEST', message: 'email is required' }));
  }

  try {
    const updated = await markPortalTourSeen(email, { seen: false });
    res.statusCode = 200;
    return res.end(JSON.stringify({ ok: true, tourSeen: updated?.tourSeen === true }));
  } catch (error) {
    const code = String(error?.code || '').toUpperCase();
    if (code === 'STORE_UNAVAILABLE' || code === 'DB_UNAVAILABLE') {
      const payload = storeUnavailablePayload('Service temporär nicht verfügbar.');
      logStoreError(error, payload.debugId);
      res.statusCode = 503;
      return res.end(JSON.stringify(payload));
    }
    res.statusCode = 500;
    return res.end(JSON.stringify({ code: 'INTERNAL_ERROR', message: 'internal error' }));
  }
}
