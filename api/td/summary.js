export const config = { runtime: 'nodejs' };

import { handlePreflight, setCors, ok } from '../_lib/http.js';
import { requirePortalAccess } from '../admin/_guard.js';
import { tdSummaryFast, tdListFromDb } from '../_lib/tdStore.js';
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

function toMinimalSummaryRow(td) {
  return {
    id: td?.id || null,
    code: td?.code || null,
    title: td?.title || td?.name || '',
    status: td?.status || 'Draft',
    lifecycleState: td?.lifecycleState || 'Development',
    productGroup: td?.productGroup || null,
    classification: td?.classification || null,
    rule: td?.rule || null,
    progress: 0,
    updated_at: td?.updatedAt || td?.updated_at || td?.createdAt || null,
  };
}

function logSummaryFormat(format, count, cacheHit) {
  console.info(`[tdSummary] format=${format} count=${count} cacheHit=${cacheHit ? '1' : '0'}`);
}

function warnEmptySummary(reason, details = {}) {
  console.warn('[tdSummary] empty', { reason, ...details });
}

export default async function handler(req, res) {
  if (handlePreflight(req, res)) return;
  setCors(req, res);

  const actor = await requirePortalAccess(req, res, { tile: 'td', write: false });
  if (!actor) return;
  if (req.method !== 'GET') {
    res.setHeader('Content-Type', 'application/json; charset=utf-8');
    return ok(res, String(req.query?.v || '') === '2' ? { ok: false, data: [], error: { code: 'METHOD_NOT_ALLOWED', message: 'Only GET is supported.' }, meta: { tdCount: 0, lastUpdatedAt: null } } : []);
  }

  return withTiming('td.summary', async (timing) => {
    const route = '/api/td/summary';
    timing.stats.route = route;
    const startedAt = Date.now();

    try {
      const cached = await getCachedJson(SUMMARY_CACHE_KEY, timing);
      const summary = await tdSummaryFast(cached, { route });
      timing.setCacheHit(Boolean(summary?.cacheHit));

      let payload = toSummaryPayload(summary);

      if (!Array.isArray(payload.items)) {
        warnEmptySummary('parse mismatch', { itemsType: typeof payload.items });
        const dbItems = await tdListFromDb();
        payload = toSummaryPayload({ items: dbItems.map(toMinimalSummaryRow) });
      }

      if (payload.items.length === 0) {
        const dbItems = await tdListFromDb();
        if (dbItems.length > 0) {
          warnEmptySummary('cache empty', { dbCount: dbItems.length });
          payload = toSummaryPayload({ items: dbItems.map(toMinimalSummaryRow) });
        } else {
          warnEmptySummary('db empty', { dbCount: 0 });
        }
      }

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
      const format = String(req.query?.v || '') === '2' ? 'v2' : 'legacy';
      res.setHeader('Content-Type', 'application/json; charset=utf-8');
      res.setHeader('X-TD-Summary-Format', format);
      logSummaryFormat(format, payload.items.length, Boolean(summary?.cacheHit));
      if (format === 'v2') {
        return ok(res, {
          ok: true,
          data: payload.items,
          meta: {
            tdCount: payload.tdCount,
            lastUpdatedAt: payload.lastUpdatedAt,
            generatedAt: payload.generatedAt,
            cached: Boolean(summary?.cacheHit),
          },
        });
      }
      return ok(res, payload.items);
    } catch (err) {
      console.warn('[tdSummary] cache+db failure', {
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
      const format = String(req.query?.v || '') === '2' ? 'v2' : 'legacy';
      res.setHeader('Content-Type', 'application/json; charset=utf-8');
      res.setHeader('X-TD-Summary-Format', format);
      logSummaryFormat(format, 0, false);
      if (format === 'v2') {
        return ok(res, { ok: false, data: [], error: { code: 'TD_SUMMARY_UNAVAILABLE', message: 'TD summary unavailable' }, meta: { tdCount: 0, lastUpdatedAt: null } });
      }
      return ok(res, []);
    }
  });
}
