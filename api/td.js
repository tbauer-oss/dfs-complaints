export const config = { runtime: 'nodejs' };

import { handlePreflight, setCors, ok, bad, readJson } from './_lib/http.js';
import { requirePortalAccess } from './admin/_guard.js';
import { tdList, tdCreate, tdComputedSummary } from './_lib/tdStore.js';

const TD_TILE = 'td';

export default async function handler(req, res) {
  if (handlePreflight(req, res)) return;
  setCors(req, res);

  const wantsWrite = req.method === 'POST';
  const actor = await requirePortalAccess(req, res, { tile: TD_TILE, write: wantsWrite });
  if (!actor) return;

  try {
    if (req.method === 'GET') {
      const list = await tdList();
      const withSummary = await Promise.all(
        list.map(async (td) => ({ ...td, summary: await tdComputedSummary(td) })),
      );
      return ok(res, { ok: true, items: withSummary });
    }

    if (req.method === 'POST') {
      const body = readJson(req);
      const created = await tdCreate(body, actor.email || actor.id || null);
      return ok(res, { ok: true, item: created });
    }

    return bad(res, 'method not allowed', 405);
  } catch (err) {
    return bad(res, err?.message || 'server error', 500);
  }
}
