export const config = { runtime: 'nodejs' };

import bcrypt from 'bcryptjs';
import { logStoreError, methodNotAllowed, storeUnavailablePayload } from '../_lib/http.js';
import { createPortalUser } from '../_lib/store.js';
import { query } from '../_lib/db.js';
import { forbiddenEmailReason, logSecurityEvent } from '../_lib/forbiddenEmails.js';
import { normalizeEmail } from '../_lib/identity.js';

function respond(res, statusCode, payload) {
  if (!res.getHeader('Content-Type')) {
    res.setHeader('Content-Type', 'application/json; charset=utf-8');
  }
  res.statusCode = statusCode;
  res.end(JSON.stringify(payload));
}

export default async function handler(req, res) {
  if (req.method === 'OPTIONS') return res.status(204).end();
  if (req.method !== 'POST') return methodNotAllowed(res);

  const setupSecret = String(process.env.SETUP_SECRET || '').trim();
  if (setupSecret) {
    const headerSecret = String(req.headers?.['x-setup-secret'] || '').trim();
    if (!headerSecret || headerSecret !== setupSecret) {
      return respond(res, 401, { code: 'INVALID_SETUP_SECRET', message: 'Nicht autorisiert.' });
    }
  }

  try {
    const existing = await query(
      "SELECT id FROM portal_users WHERE role IN ('admin','superuser') AND is_active = true LIMIT 1",
      [],
    );
    if ((existing.rows || []).length > 0) {
      return respond(res, 200, { ok: true, status: 'already_initialized' });
    }

    const email = normalizeEmail(process.env.INITIAL_ADMIN_EMAIL || '');

    const forbiddenReason = forbiddenEmailReason(email);
    if (forbiddenReason) {
      logSecurityEvent({ req, email, reason: forbiddenReason });
      return respond(res, 403, { code: 'FORBIDDEN_EMAIL', message: 'E-Mail nicht zulässig.' });
    }
    const password = String(process.env.INITIAL_ADMIN_PASSWORD || '');
    if (!email || !password) {
      return respond(res, 503, storeUnavailablePayload('Service temporär nicht verfügbar. Bitte später erneut versuchen.'));
    }

    const passwordHash = await bcrypt.hash(password, 10);
    await createPortalUser({
      email,
      passwordHash,
      role: 'admin',
      portalStatus: 'active',
    });

    return respond(res, 200, { ok: true, status: 'initialized' });
  } catch (err) {
    const payload = storeUnavailablePayload('Service temporär nicht verfügbar. Bitte später erneut versuchen.');
    logStoreError(err, payload.debugId);
    return respond(res, 503, payload);
  }
}
