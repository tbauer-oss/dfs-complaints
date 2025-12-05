// /api/wiki/admin/articles/[id].js
export const config = { runtime: 'nodejs' };

import { handlePreflight, setCors, ok, bad, methodNotAllowed, readJson, noContent } from '../../../_lib/http.js';
import { wikiSaveArticle, wikiDeleteArticle, wikiGetArticle } from '../../../_lib/wikiStore.js';
import { validateArticlePayload } from '../../../_lib/wikiValidation.js';
import { normalizeRole, PORTAL_ROLES, portalUserFromRequest } from '../../../_lib/portalAuth.js';

async function requirePortalUser(req, res) {
  const actor = await portalUserFromRequest(req);
  if (!actor) {
    bad(res, 'unauthorized', 401);
    return null;
  }
  return actor;
}

function assertSuperuser(actor, res) {
  const isSuperuser = normalizeRole(actor?.role) === PORTAL_ROLES.superuser;
  if (!isSuperuser) {
    bad(res, 'forbidden', 403);
    return false;
  }
  return true;
}

export default async function handler(req, res) {
  if (handlePreflight(req, res)) return;
  setCors(req, res);
  const actor = await requirePortalUser(req, res);
  if (!actor) return;

  const id = (req.query?.id ?? '').toString().trim();
  if (!id) return bad(res, 'id required', 400);

  if (req.method === 'GET') {
    const item = await wikiGetArticle(id);
    if (!item) return bad(res, 'not found', 404);
    return ok(res, item);
  }

  if (req.method === 'PUT') {
    if (!assertSuperuser(actor, res)) return;
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
    if (!assertSuperuser(actor, res)) return;
    await wikiDeleteArticle(id);
    return noContent(res);
  }

  return methodNotAllowed(res);
}
