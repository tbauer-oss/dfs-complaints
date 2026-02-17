export const config = { runtime: 'nodejs' };

import { handlePreflight, setCors, ok, bad } from '../_lib/http.js';
import { requirePortalAccess } from '../admin/_guard.js';
import { tdSummaryFast } from '../_lib/tdStore.js';

export default async function handler(req, res) {
  if (handlePreflight(req, res)) return;
  setCors(req, res);

  const actor = await requirePortalAccess(req, res, { tile: 'td', write: false });
  if (!actor) return;
  if (req.method !== 'GET') return bad(res, 'method not allowed', 405);

  const started = Date.now();
  try {
    const items = await tdSummaryFast();
    const totalMs = Date.now() - started;
    console.info('[td/summary]', { total_ms: totalMs, item_count: items.length, payload_bytes: Buffer.byteLength(JSON.stringify(items)) });
    return ok(res, { ok: true, items, warnings: [] });
  } catch (err) {
    return bad(res, err?.message || 'server error', 500);
  }
}
