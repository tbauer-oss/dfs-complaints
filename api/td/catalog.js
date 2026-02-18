export const config = { runtime: 'nodejs' };

import { requirePortalAccess } from '../admin/_guard.js';
import { bad, handlePreflight, ok, setCors } from '../_lib/http.js';
import { getTdCatalogCached } from '../_lib/tdCatalog.js';

export default async function handler(req, res) {
  if (handlePreflight(req, res)) return;
  setCors(req, res);

  const actor = await requirePortalAccess(req, res, { tile: 'td', write: false });
  if (!actor) return;

  if (req.method !== 'GET') return bad(res, 'method not allowed', 405);

  const startedAt = Date.now();
  const debugId = `td_catalog_${Date.now().toString(36)}`;

  try {
    const payload = await getTdCatalogCached();
    const totalMs = Date.now() - startedAt;
    console.info('[td/catalog] ok', {
      debugId,
      totalMs,
      cacheHit: payload.cacheHit === true,
      count: payload.items?.length || 0,
      cacheMs: payload.timings?.cacheMs || 0,
      dbMs: payload.timings?.dbMs || 0,
    });
    res.setHeader('Server-Timing', `total;dur=${totalMs}, db;dur=${payload.timings?.dbMs || 0}, kv;dur=${payload.timings?.cacheMs || 0}`);
    return ok(res, {
      ok: true,
      items: payload.items || [],
      meta: {
        ...(payload.meta || {}),
        cacheHit: payload.cacheHit === true,
        totalMs,
      },
      debugId,
    });
  } catch (err) {
    const totalMs = Date.now() - startedAt;
    console.error('[td/catalog] failed', {
      debugId,
      totalMs,
      message: err?.message || String(err),
    });
    return bad(res, 'td catalog unavailable', 500, { debugId });
  }
}
