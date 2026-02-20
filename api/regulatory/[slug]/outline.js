export const config = { runtime: 'nodejs' };

import { handlePreflight, setCors, ok, bad } from '../../_lib/http.js';
import { requirePortalAccess } from '../../admin/_guard.js';
import { getOutlineForCurrentVersion } from '../../_lib/regulatory/db.js';

export default async function handler(req, res) {
  if (handlePreflight(req, res)) return;
  setCors(req, res);
  const actor = await requirePortalAccess(req, res, { write: false, allowPrrc: true });
  if (!actor) return;
  if (req.method !== 'GET') return bad(res, 'method not allowed', 405);

  try {
    const slug = String(req.query?.slug || '').trim();
    if (!slug) return bad(res, 'slug missing', 400);
    const outline = await getOutlineForCurrentVersion(slug);
    return ok(res, { ok: true, outline });
  } catch (err) {
    console.error('[regulatory/outline] failed', err?.message || err);
    return bad(res, err?.message || 'outline lookup failed', 500);
  }
}
