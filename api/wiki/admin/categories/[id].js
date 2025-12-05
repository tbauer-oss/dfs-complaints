// /api/wiki/admin/categories/[id].js
export const config = { runtime: 'nodejs' };

import { handlePreflight, setCors, ok, bad, methodNotAllowed, readJson, noContent } from '../../../_lib/http.js';
import { wikiSaveCategory, wikiDeleteCategory, wikiSetCategoryStatus } from '../../../_lib/wikiStore.js';
import { validateCategoryPayload, validateCategoryStatusPayload } from '../../../_lib/wikiValidation.js';
import { normalizeRole, PORTAL_ROLES, portalUserFromRequest } from '../../../_lib/portalAuth.js';

async function requireSuperuser(req, res) {
  const actor = await portalUserFromRequest(req);
  if (!actor) {
    bad(res, 'unauthorized', 401);
    return null;
  }
  if (normalizeRole(actor.role) !== PORTAL_ROLES.superuser) {
    bad(res, 'forbidden', 403);
    return null;
  }
  return actor;
}

export default async function handler(req, res) {
  if (handlePreflight(req, res)) return;
  setCors(req, res);
  const actor = await requireSuperuser(req, res);
  if (!actor) return;

  const id = (req.query?.id ?? '').toString().trim();
  if (!id) return bad(res, 'id required', 400);

  if (req.method === 'PUT') {
    const body = readJson(req);
    try {
      const payload = validateCategoryPayload(body || {});
      const saved = await wikiSaveCategory({ ...payload, id });
      return ok(res, saved);
    } catch (e) {
      return bad(res, e?.message || 'invalid payload', 400);
    }
  }

  if (req.method === 'PATCH') {
    const body = readJson(req);
    try {
      const payload = validateCategoryStatusPayload(body || {});
      const saved = await wikiSetCategoryStatus(id, payload.isActive);
      return ok(res, saved);
    } catch (e) {
      return bad(res, e?.message || 'invalid payload', 400);
    }
  }

  if (req.method === 'DELETE') {
    await wikiDeleteCategory(id);
    return noContent(res);
  }

  return methodNotAllowed(res);
}
