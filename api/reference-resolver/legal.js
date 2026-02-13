export const config = { runtime: 'nodejs' };
import { handlePreflight, setCors, ok, bad } from '../_lib/http.js';
import { requirePortalAccess } from '../admin/_guard.js';
import { legalReferenceResolver } from '../_lib/legalRefService.js';

export default async function handler(req, res) {
  if (handlePreflight(req, res)) return;
  setCors(req, res);
  const actor = await requirePortalAccess(req, res, { tile: 'td', write: false });
  if (!actor) return;
  if (req.method !== 'GET') return bad(res, 'method not allowed', 405);
  const type = String(req.query?.type || '').trim();
  const value = String(req.query?.value || '').trim();
  if (!type || !value) return bad(res, 'type and value are required', 400);
  const item = legalReferenceResolver(type, value);
  if (!item) return bad(res, 'reference not found', 404);
  return ok(res, { ok: true, item });
}
