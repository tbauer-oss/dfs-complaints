export const config = { runtime: 'nodejs' };
import { handlePreflight, setCors, ok, bad, readJson } from '../../_lib/http.js';
import { requirePortalAccess } from '../../admin/_guard.js';
import { tdLinkCreate, tdLinksBySection } from '../../_lib/tdStore.js';

export default async function handler(req, res) {
  if (handlePreflight(req, res)) return;
  setCors(req, res);
  const id = String(req.query?.id || '').trim();
  if (!id) return bad(res, 'id is required', 400);
  const wantsWrite = req.method === 'POST';
  const actor = await requirePortalAccess(req, res, { tile: 'td', write: wantsWrite });
  if (!actor) return;
  try {
    if (req.method === 'GET') {
      const sectionId = req.query?.sectionId ? String(req.query.sectionId) : null;
      return ok(res, { ok: true, items: await tdLinksBySection(id, sectionId) });
    }
    if (req.method === 'POST') {
      return ok(res, { ok: true, item: await tdLinkCreate(id, readJson(req)) });
    }
    return bad(res, 'method not allowed', 405);
  } catch (err) {
    return bad(res, err?.message || 'server error', 500);
  }
}
