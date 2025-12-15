// /api/wiki/admin/articles/[id].js
export const config = { runtime: 'nodejs' };

import { handlePreflight, setCors, ok, bad, methodNotAllowed, readJson, noContent } from '../../../_lib/http.js';
import { wikiSaveArticle, wikiDeleteArticle, wikiGetArticle } from '../../../_lib/wikiStore.js';
import { validateArticlePayload } from '../../../_lib/wikiValidation.js';
import { requirePortalAccess } from '../../../admin/_guard.js';

const WIKI_TILE = 'wiki';

export default async function handler(req, res) {
  if (handlePreflight(req, res)) return;
  setCors(req, res);
  const write = req.method !== 'GET';
  const actor = await requirePortalAccess(req, res, { write, tile: WIKI_TILE });
  if (!actor) return;

  const id = (req.query?.id ?? '').toString().trim();
  if (!id) return bad(res, 'id required', 400);

  if (req.method === 'GET') {
    const item = await wikiGetArticle(id);
    if (!item) return bad(res, 'not found', 404);
    return ok(res, item);
  }

  if (req.method === 'PUT') {
    const body = readJson(req);
    try {
      const payload = validateArticlePayload(body || {});
      const saved = await wikiSaveArticle({ ...payload, id });
      return ok(res, saved);
    } catch (e) {
      return bad(res, e?.message || 'invalid payload', 400);
    }
  }

  if (req.method === 'DELETE') {
    await wikiDeleteArticle(id);
    return noContent(res);
  }

  return methodNotAllowed(res);
}
