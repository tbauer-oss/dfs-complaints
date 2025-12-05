// /api/wiki/admin/categories.js
export const config = { runtime: 'nodejs' };

import { handlePreflight, setCors, ok, bad, methodNotAllowed, readJson, noContent } from '../../_lib/http.js';
import { wikiCategories, wikiSaveCategory } from '../../_lib/wikiStore.js';
import { validateCategoryPayload } from '../../_lib/wikiValidation.js';
import { normalizeRole, PORTAL_ROLES, portalUserFromRequest } from '../../_lib/portalAuth.js';

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

  try {
    if (req.method === 'GET') {
      const status = (req.query?.status ?? '').toString().trim().toLowerCase();
      const data = await wikiCategories({ includeInactive: true });
      const filtered = status === 'active'
          ? data.filter((c) => c.isActive)
          : status === 'inactive'
              ? data.filter((c) => !c.isActive)
              : data;
      return ok(res, filtered);
    }

    if (req.method === 'POST') {
      const body = readJson(req);
      try {
        const payload = validateCategoryPayload(body || {});
        const saved = await wikiSaveCategory(payload);
        return ok(res, saved);
      } catch (e) {
        return bad(res, e?.message || 'invalid payload', 400);
      }
    }

    return methodNotAllowed(res);
  } catch (err) {
    console.error('[api/wiki/admin/categories] failed', err);
    return bad(res, 'internal server error', 500);
  }
}
