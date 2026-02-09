// /api/gspr/td-options.js – GSPR TD options from Artikelliste
export const config = { runtime: 'nodejs' };

import { handlePreflight, setCors, ok, bad } from '../_lib/http.js';
import { requirePortalAccess } from '../admin/_guard.js';
import { gsprTdOptions } from '../_lib/gsprTdOptions.js';

const GSPR_TILE = 'gspr';

export default async function handler(req, res) {
  if (handlePreflight(req, res)) return;
  setCors(req, res);

  const actor = await requirePortalAccess(req, res, { tile: GSPR_TILE, write: false, allowPrrc: true });
  if (!actor) return;

  try {
    if (req.method !== 'GET') return bad(res, 'method not allowed', 405);
    res.setHeader('Cache-Control', 'public, max-age=300');
    const options = await gsprTdOptions();
    return ok(res, { ok: true, options });
  } catch (err) {
    console.error('[gspr/td-options] error', err);
    return bad(res, err?.message || 'server error', 500);
  }
}
