// /api/wiki/admin/articles.js
export const config = { runtime: 'nodejs' };

import { handlePreflight, setCors, ok, bad, methodNotAllowed, readJson } from '../../_lib/http.js';
import { wikiAdminList, wikiSaveArticle } from '../../_lib/wikiStore.js';
import { validateArticlePayload } from '../../_lib/wikiValidation.js';
import { normalizeRole, PORTAL_ROLES, portalUserFromRequest } from '../../_lib/portalAuth.js';

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

  if (req.method === 'GET') {
    const { category, productGroup, type, status, search } = req.query || {};
    const includeInactive = (status || '').toString().toLowerCase() !== 'active';
    const data = await wikiAdminList({ category, productGroup, type, search, includeInactive });
    return ok(res, data);
  }

  if (req.method === 'POST') {
    if (!assertSuperuser(actor, res)) return;
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
