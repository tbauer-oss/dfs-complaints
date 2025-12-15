// api/portal/news.js – Mitarbeiter-Newsfeed (DFS Portal)
export const config = { runtime: 'nodejs' };

import { bad, handlePreflight, methodNotAllowed, ok, setCors } from '../_lib/http.js';
import { portalUserFromRequest } from '../_lib/portalAuth.js';
import { portalNewsForUser } from '../_lib/store.js';

export default async function handler(req, res) {
  if (handlePreflight(req, res)) return;
  setCors(req, res);
  res.setHeader('Cache-Control', 'no-store');
  if (req.method !== 'GET') return methodNotAllowed(res);

  const actor = await portalUserFromRequest(req);
  if (!actor) return bad(res, 'unauthorized', 401);

  try {
    const limitRaw = req.query?.limit;
    const limit = limitRaw ? Math.max(0, Math.min(200, Number(limitRaw) || 0)) : 0;
    const items = await portalNewsForUser(actor, { limit, includeDrafts: false });
    return ok(res, { items });
  } catch (err) {
    console.error('portal/news endpoint failed', err);
    return bad(res, 'internal error', 500);
  }
}

