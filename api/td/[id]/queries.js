export const config = { runtime: 'nodejs' };
import { handlePreflight, setCors, ok, bad } from '../../_lib/http.js';
import { requirePortalAccess } from '../../admin/_guard.js';
import { tdQueries } from '../../_lib/tdStore.js';

const TTL_MS = 30 * 1000;
const queriesCache = new Map();

export default async function handler(req, res) {
  if (handlePreflight(req, res)) return;
  setCors(req, res);
  const actor = await requirePortalAccess(req, res, { tile: 'td', write: false });
  if (!actor) return;
  if (req.method !== 'GET') return bad(res, 'method not allowed', 405);
  const id = String(req.query?.id || '').trim();
  if (!id) return bad(res, 'id is required', 400);
  const sectionId = req.query?.sectionId ? String(req.query.sectionId) : null;
  try {
    const cacheKey = `${id}:${sectionId || ''}`;
    const now = Date.now();
    const cached = queriesCache.get(cacheKey);
    if (cached && now - cached.ts <= TTL_MS) {
      return ok(res, { ok: true, cached: true, items: cached.items });
    }

    const items = await tdQueries(id, sectionId);
    queriesCache.set(cacheKey, { ts: now, items });
    return ok(res, { ok: true, cached: false, items });
  } catch (err) {
    return bad(res, err?.message || 'server error', 500);
  }
}
