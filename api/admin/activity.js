// /api/admin/activity.js
export const config = { runtime: 'nodejs' };

import { handlePreflight, setCors, ok, bad, methodNotAllowed } from '../_lib/http.js';
import { activityForRep, activityForUser, isPushTokenFresh } from '../_lib/store.js';

const ADMIN_SECRET = process.env.ADMIN_SECRET || '';

function isAdmin(req) {
  const hdr = req.headers?.['x-admin-secret'];
  return typeof hdr === 'string' && !!ADMIN_SECRET && hdr === ADMIN_SECRET;
}

export default async function handler(req, res) {
  if (handlePreflight(req, res)) return;
  setCors(req, res);

  if (!isAdmin(req)) return bad(res, 'admin unauthorized', 401);
  if (req.method !== 'GET') return methodNotAllowed(res);

  const email = (req.query?.email || '').toString().trim().toLowerCase();
  const kind = (req.query?.kind || '').toString().trim().toLowerCase();
  if (!email) return bad(res, 'missing email', 400);

  let result = null;

  if (!kind || kind === 'customer') {
    result = await activityForUser(email).catch((e) => {
      console.error('[admin/activity] activityForUser failed', e);
      return null;
    });
  }

  if ((!result && !kind) || kind === 'rep') {
    result = await activityForRep({ email }).catch((e) => {
      console.error('[admin/activity] activityForRep failed', e);
      return null;
    });
  }

  if (!result) return ok(res, { found: false });

  return ok(res, {
    found: true,
    freshnessMs: Number(process.env.PUSH_TOKEN_FRESH_MS || 1000 * 60 * 60 * 24 * 45),
    ...result,
    pushValid: result.pushValid && isPushTokenFresh({ updatedAt: result.pushUpdatedAt }),
  });
}
