export const config = { runtime: 'nodejs' };

import { handlePreflight, setCors, ok, bad } from '../_lib/http.js';
import { requirePortalAccess } from '../admin/_guard.js';
import { gsprAssessmentsPage } from '../_lib/store.js';

const GSPR_TILE = 'gspr';

function parseLimit(value) {
  const n = Number(value);
  if (!Number.isFinite(n)) return 100;
  return Math.max(1, Math.min(200, Math.trunc(n)));
}

export default async function handler(req, res) {
  if (handlePreflight(req, res)) return;
  setCors(req, res);

  const actor = await requirePortalAccess(req, res, { tile: GSPR_TILE, write: false, allowPrrc: true });
  if (!actor) return;

  try {
    if (req.method !== 'GET') return bad(res, 'method not allowed', 405);

    const cursor = (req.query?.cursor || '').toString().trim();
    const tdId = (req.query?.tdId || '').toString().trim();
    const limit = parseLimit(req.query?.limit);

    const page = await gsprAssessmentsPage({ cursor, limit, tdId });

    return ok(res, {
      ok: true,
      items: page.items,
      cursor,
      nextCursor: page.nextCursor,
      hasMore: page.hasMore,
      limit,
      total: page.total,
      tdId: tdId || null,
    });
  } catch (err) {
    console.error('[gspr/assessments] error', err);
    return bad(res, err?.message || 'server error', 500);
  }
}
