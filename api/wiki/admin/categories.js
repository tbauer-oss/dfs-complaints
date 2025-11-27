// /api/wiki/admin/categories.js
export const config = { runtime: 'nodejs' };

import { handlePreflight, setCors, ok, bad, methodNotAllowed, readJson, noContent } from '../../_lib/http.js';
import { wikiCategories, wikiSaveCategory } from '../../_lib/wikiStore.js';
import { validateCategoryPayload } from '../../_lib/wikiValidation.js';

function requireAdmin(req, res) {
  const sec = (req.headers?.['x-admin-secret'] || '').toString().trim();
  const expected = (process.env.ADMIN_SECRET || '').toString().trim();
  if (!sec || !expected || sec !== expected) {
    bad(res, 'unauthorized', 401);
    return false;
  }
  return true;
}

export default async function handler(req, res) {
  if (handlePreflight(req, res)) return;
  setCors(req, res);
  if (!requireAdmin(req, res)) return;

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
