export const config = { runtime: 'nodejs' };

import { handlePreflight, setCors, ok, bad } from '../_lib/http.js';
import { requirePortalAccess } from '../admin/_guard.js';

export default async function handler(req, res) {
  if (handlePreflight(req, res)) return;
  setCors(req, res);
  const actor = await requirePortalAccess(req, res, { tile: 'gspr', write: true, allowPrrc: true });
  if (!actor) return;
  if (req.method !== 'POST' && req.method !== 'GET') return bad(res, 'method not allowed', 405);
  return ok(res, {
    ok: false,
    code: 'DEPRECATED_ENDPOINT',
    message: 'GSPR source sync moved to /api/regulatory/:slug/diff and /api/regulatory/:slug/apply.',
  });
}
