export const config = { runtime: 'nodejs' };

import { handlePreflight, setCors, ok, bad } from '../../_lib/http.js';
import { requirePortalAccess } from '../../admin/_guard.js';
import { tdOverviewFast } from '../../_lib/tdStore.js';

export default async function handler(req, res) {
  if (handlePreflight(req, res)) return;
  setCors(req, res);

  const actor = await requirePortalAccess(req, res, { tile: 'td', write: false });
  if (!actor) return;
  if (req.method !== 'GET') return bad(res, 'method not allowed', 405);

  const tdKey = String(req.query?.tdKey || '').trim();
  if (!tdKey) return bad(res, 'tdKey is required', 400);

  const started = Date.now();
  try {
    const overview = await tdOverviewFast(tdKey);
    if (!overview) return bad(res, 'not found', 404);
    console.info('[td/overview]', { td_key: tdKey, total_ms: Date.now() - started, section_count: overview.section_count });
    return ok(res, { ok: true, ...overview });
  } catch (err) {
    return bad(res, err?.message || 'server error', 500);
  }
}
