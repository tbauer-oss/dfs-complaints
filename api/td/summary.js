export const config = { runtime: 'nodejs' };

import { handlePreflight, setCors, ok, bad } from '../_lib/http.js';
import { requirePortalAccess } from '../admin/_guard.js';
import { tdSummaryFast } from '../_lib/tdStore.js';
import { getCachedJson, setCachedJson } from '../_lib/tdFastCache.js';
import { withTiming } from '../_lib/timing.js';

const SUMMARY_CACHE_KEY = 'dfs:td:summary:v1';
const FALLBACK_CACHE_TTL_SECONDS = 60;

function setSummaryServerTiming(res, { total, db, kv, cacheHit }) {
  const cacheDuration = cacheHit ? 1 : 0;
  res.setHeader('Server-Timing', `total;dur=${Math.max(0, total)}, db;dur=${Math.max(0, db)}, kv;dur=${Math.max(0, kv)}, cache;dur=${cacheDuration}`);
}

function toSummaryPayload(summary) {
  const items = Array.isArray(summary?.items) ? summary.items : [];
  return {
    items,
    data: items,
    tdCount: Number.isFinite(Number(summary?.tdCount)) ? Number(summary.tdCount) : items.length,
    lastUpdatedAt: summary?.lastUpdatedAt || null,
    generatedAt: new Date().toISOString(),
  };
}

export default async function handler(req, res) {
  if (handlePreflight(req, res)) return;
  setCors(req, res);

  const actor = await requirePortalAccess(req, res, { tile: 'td', write: false });
  if (!actor) return;
  if (req.method !== 'GET') return bad(res, 'method not allowed', 405);

  return withTiming('td.summary', async (timing) => {
    const route = '/api/td/summary';
    timing.stats.route = route;
    const startedAt = Date.now();

    try {
      const cached = await getCachedJson(SUMMARY_CACHE_KEY, timing);
      const summary = await tdSummaryFast(cached, { route });
      timing.setCacheHit(Boolean(summary?.cacheHit));

      const payload = toSummaryPayload(summary);
      timing.addRows(payload.items.length);

      if (!summary?.cacheHit) {
        const cacheTtl = summary?.cacheInvalid || summary?.recoveredFromError ? FALLBACK_CACHE_TTL_SECONDS : undefined;
        await setCachedJson(SUMMARY_CACHE_KEY, payload, timing, cacheTtl);
      }

      setSummaryServerTiming(res, {
        total: Date.now() - startedAt,
        db: timing.stats.ms_db,
        kv: timing.stats.ms_kv,
        cacheHit: Boolean(summary?.cacheHit),
      });
      return ok(res, { ok: true, ...payload, cached: Boolean(summary?.cacheHit) });
    } catch (err) {
      console.warn('[td.summary] cache+db failure', {
        route,
        message: err?.message || String(err),
        stack: err?.stack || null,
      });
      setSummaryServerTiming(res, {
        total: Date.now() - startedAt,
        db: timing.stats.ms_db,
        kv: timing.stats.ms_kv,
        cacheHit: false,
      });
      return ok(res, { ok: false, error: 'TD summary unavailable', data: [], items: [], tdCount: 0, lastUpdatedAt: null });
    }
  });
}
