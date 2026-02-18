export const config = { runtime: 'nodejs' };

import { handlePreflight, setCors, ok, bad } from '../_lib/http.js';
import { requirePortalAccess } from '../admin/_guard.js';
import { tdSummaryFast } from '../_lib/tdStore.js';
import { withTiming } from '../_lib/timing.js';

export default async function handler(req, res) {
  if (handlePreflight(req, res)) return;
  setCors(req, res);

  const actor = await requirePortalAccess(req, res, { tile: 'td', write: false });
  if (!actor) return;
  if (req.method !== 'GET') return bad(res, 'method not allowed', 405);

  return withTiming('tdk.summary', async (timing) => {
    timing.stats.route = '/api/tdk/summary';
    const summary = await tdSummaryFast();
    timing.addRows(summary.items.length);
    timing.setServerTiming(res);
    return ok(res, { ok: true, ...summary, warnings: [] });
  });
}
