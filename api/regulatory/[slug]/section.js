export const config = { runtime: 'nodejs' };

import { handlePreflight, setCors, ok, bad } from '../../_lib/http.js';
import { requirePortalAccess } from '../../admin/_guard.js';
import { getSectionsForCurrentVersion } from '../../_lib/regulatory/db.js';
import { verifySyncToken } from '../../_lib/regulatory/token.js';

export default async function handler(req, res) {
  if (handlePreflight(req, res)) return;
  setCors(req, res);
  const actor = await requirePortalAccess(req, res, { write: false, allowPrrc: true });
  if (!actor) return;
  if (req.method !== 'GET') return bad(res, 'method not allowed', 405);

  const slug = String(req.query?.slug || '').trim();
  const key = String(req.query?.key || '').trim();
  const side = String(req.query?.side || 'new').trim();
  if (!key) return bad(res, 'key missing', 400);

  if (side === 'old' || side === 'new') {
    const token = verifySyncToken(req.query?.token);
    const row = (token.sections || []).find((entry) => entry.section_key === key);
    return ok(res, { ok: true, section: row || null });
  }

  const sections = await getSectionsForCurrentVersion(slug);
  const row = sections.find((entry) => entry.section_key === key) || null;
  return ok(res, { ok: true, section: row });
}
