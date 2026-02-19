export const config = { runtime: 'nodejs' };

import { handlePreflight, setCors, bad, ok } from '../_lib/http.js';
import { requirePortalAccess } from '../admin/_guard.js';
import { loadOrRebuildCatalog } from '../_lib/tdCatalog.js';

export default async function handler(req, res) {
  if (handlePreflight(req, res)) return;
  setCors(req, res);

  const actor = await requirePortalAccess(req, res, { tile: 'td', write: false });
  if (!actor) return;

  if (req.method !== 'GET') return bad(res, 'method not allowed', 405, { code: 'METHOD_NOT_ALLOWED' });

  try {
    const result = await loadOrRebuildCatalog();
    const items = Array.isArray(result.items) ? result.items : [];

    console.info('[td/catalog] outcome:', result.outcome, {
      itemCount: items.length,
      ms_total: result.timings.ms_total,
      ms_db: result.timings.ms_db,
      ms_fs: result.timings.ms_fs,
      ms_parse: result.timings.ms_parse,
    });

    if (items.length === 0) {
      console.warn('[td/catalog] CSV parsed but contains no MDR-TD rows');
    }

    res.setHeader('Cache-Control', 'private, max-age=60');
    return ok(res, {
      ok: true,
      items,
      meta: {
        outcome: result.outcome,
        sourceHash: result.sourceHash,
        generatedAt: result.generatedAt,
      },
    });
  } catch (err) {
    const message = String(err?.message || err || '');
    if (String(err?.code || '').toUpperCase() === 'DB_UNAVAILABLE') {
      return bad(res, 'Database unavailable', 503, { code: 'DB_UNAVAILABLE' });
    }
    if (err?.code === 'ENOENT' || message.includes('no such file')) {
      return bad(res, 'CSV source file unavailable at api/_data/dfs_products.csv', 503, {
        code: 'TD_CATALOG_SOURCE_UNAVAILABLE',
      });
    }
    console.error('[td/catalog] failed', { message });
    return bad(res, 'td catalog unavailable', 503, { code: 'TD_CATALOG_UNAVAILABLE' });
  }
}
