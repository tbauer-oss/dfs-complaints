export const config = { runtime: 'nodejs' };
import { handlePreflight, setCors, ok, bad } from '../../_lib/http.js';
import { requirePortalAccess } from '../../admin/_guard.js';
import { tdReadiness } from '../../_lib/tdStore.js';

const TTL_MS = 60 * 1000;
const readinessCache = new Map();

export default async function handler(req, res) {
  if (handlePreflight(req, res)) return;
  setCors(req, res);
  const actor = await requirePortalAccess(req, res, { tile: 'td', write: false });
  if (!actor) return;
  if (req.method !== 'GET') return bad(res, 'method not allowed', 405);
  try {
    const id = String(req.query?.id || '').trim();
    if (!id) return bad(res, 'id is required', 400);

    const now = Date.now();
    const cached = readinessCache.get(id);
    if (cached && now - cached.ts <= TTL_MS) {
      return ok(res, { ok: true, cached: true, ...cached.data });
    }

    const data = await tdReadiness(id);
    readinessCache.set(id, { ts: now, data });
    return ok(res, { ok: true, cached: false, ...data });
  } catch (err) {
    return bad(res, err?.message || 'server error', 500);
  }
}
