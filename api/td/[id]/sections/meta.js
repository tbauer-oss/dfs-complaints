export const config = { runtime: 'nodejs' };

import { handlePreflight, setCors, ok, bad } from '../../../_lib/http.js';
import { requirePortalAccess } from '../../../admin/_guard.js';
import { withTiming } from '../../../_lib/timing.js';
import { getCachedJson, refreshInBackground, sectionsMetaCacheKey, setCachedJson } from '../../../_lib/tdFastCache.js';
import { loadSectionsMetaFallback, loadSectionsMetaFromDb } from '../../../_lib/tdFastQueries.js';
import { queryWithStatementTimeout } from '../../../_lib/db.js';

function parsePaging(req) {
  const limitRaw = Number(req.query?.limit || 50);
  const limit = Math.max(1, Math.min(100, Number.isFinite(limitRaw) ? limitRaw : 50));
  const cursorRaw = Number(req.query?.cursor || 0);
  const offset = Math.max(0, Number.isFinite(cursorRaw) ? cursorRaw : 0);
  return { limit, offset };
}

async function buildSections(tdId, limit, offset, timing) {
  try {
    const dbResult = await loadSectionsMetaFromDb(tdId, limit, offset, 4000, (sql, params) => timing.db(() => queryWithStatementTimeout(sql, params, 4000)));
    if (dbResult) return dbResult;
  } catch (err) {
    timing.setColdStartSuspected(true);
    console.warn('[td/sections/meta] db failed, using fallback', { tdId, message: err?.message || String(err) });
  }
  return loadSectionsMetaFallback(tdId, limit, offset);
}

function mapMetaRow(row) {
  const completenessPercent = row.completeness_percent ?? row.query_completion_percent ?? row.completion_percent ?? null;
  return {
    id: row.section_id,
    title: row.title,
    order_index: row.order,
    status: row.status || 'NotStarted',
    completeness_percent: typeof completenessPercent === 'number' ? completenessPercent : (row.query_total > 0 ? Math.round(((row.completed_queries || 0) / row.query_total) * 100) : 0),
  };
}

export default async function handler(req, res) {
  if (handlePreflight(req, res)) return;
  setCors(req, res);

  const actor = await requirePortalAccess(req, res, { tile: 'td', write: false });
  if (!actor) return;
  if (req.method !== 'GET') return bad(res, 'method not allowed', 405);

  const tdId = String(req.query?.id || '').trim();
  if (!tdId) return bad(res, 'id is required', 400);

  const { limit, offset } = parsePaging(req);
  const pageKey = `${limit}:${offset}`;

  return withTiming('td.sections.meta', async (timing) => {
    timing.stats.route = '/api/td/:id/sections/meta';
    timing.stats.tdId = tdId;

    const cacheKey = sectionsMetaCacheKey(tdId, pageKey);
    const cached = await getCachedJson(cacheKey, timing);
    if (cached) {
      timing.setCacheHit(true);
      timing.addRows(Array.isArray(cached.items) ? cached.items.length : 0);
      timing.setServerTiming(res);
      ok(res, { ok: true, ...cached, cacheHit: true });
      refreshInBackground(async () => {
        const fresh = await buildSections(tdId, limit, offset, timing);
        const freshItems = fresh.items.map(mapMetaRow);
        const payload = {
          items: freshItems,
          page: { limit, cursor: offset, nextCursor: offset + freshItems.length < fresh.total ? offset + freshItems.length : null, total: fresh.total },
        };
        await setCachedJson(cacheKey, payload);
      });
      return;
    }

    const data = await buildSections(tdId, limit, offset, timing);
    const items = data.items.map(mapMetaRow);

    timing.addRows(items.length);
    const payload = {
      items,
      page: {
        limit,
        cursor: offset,
        nextCursor: offset + items.length < data.total ? offset + items.length : null,
        total: data.total,
      },
    };
    await setCachedJson(cacheKey, payload, timing);
    timing.setServerTiming(res);
    return ok(res, { ok: true, ...payload, cacheHit: false });
  });
}
