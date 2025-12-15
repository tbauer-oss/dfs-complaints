// /api/wiki/admin/articles.js
export const config = { runtime: 'nodejs' };

import { handlePreflight, setCors, ok, bad, methodNotAllowed, readJson } from '../../_lib/http.js';
import { wikiAdminList, wikiSaveArticle } from '../../_lib/wikiStore.js';
import { validateArticlePayload } from '../../_lib/wikiValidation.js';
import { requirePortalAccess } from '../../admin/_guard.js';

const WIKI_TILE = 'wiki';

export default async function handler(req, res) {
  if (handlePreflight(req, res)) return;
  setCors(req, res);
  const wantsWrite = req.method !== 'GET';
  const actor = await requirePortalAccess(req, res, { write: wantsWrite, tile: WIKI_TILE });
  if (!actor) return;

  if (req.method === 'GET') {
    const { category, productGroup, type, status, search } = req.query || {};
    const includeInactive = (status || '').toString().toLowerCase() !== 'active';
    const data = await wikiAdminList({ category, productGroup, type, search, includeInactive });
    return ok(res, data);
  }

  if (req.method === 'POST') {
    const body = readJson(req);
    try {
      const payload = validateArticlePayload(body || {});
      const saved = await wikiSaveArticle(payload);
      return ok(res, saved);
    } catch (e) {
      return bad(res, e?.message || 'invalid payload', 400);
    }
  }

  return methodNotAllowed(res);
}
