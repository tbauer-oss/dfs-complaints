export const config = { runtime: 'nodejs' };

import { handlePreflight, setCors, ok, bad } from '../../_lib/http.js';
import { requirePortalAccess } from '../../admin/_guard.js';
import { getSectionsForCurrentVersion } from '../../_lib/regulatory/db.js';

export default async function handler(req, res) {
  if (handlePreflight(req, res)) return;
  setCors(req, res);
  const actor = await requirePortalAccess(req, res, { write: false, allowPrrc: true });
  if (!actor) return;
  if (req.method !== 'GET') return bad(res, 'method not allowed', 405);

  try {
    const slug = String(req.query?.slug || '').trim();
    const sections = await getSectionsForCurrentVersion(slug);
    return ok(res, { ok: true, sections });
  } catch (err) {
    console.error('[regulatory/sections] failed', err?.message || err);
    return ok(res, { ok: true, degraded: true, sections: [] });
  }
}
