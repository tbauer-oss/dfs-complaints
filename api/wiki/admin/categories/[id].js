// /api/wiki/admin/categories/[id].js
export const config = { runtime: 'nodejs' };

import { handlePreflight, setCors, ok, bad, methodNotAllowed, readJson, noContent } from '../../../_lib/http.js';
import { wikiSaveCategory, wikiDeleteCategory, wikiSetCategoryStatus } from '../../../_lib/wikiStore.js';
import { validateCategoryPayload, validateCategoryStatusPayload } from '../../../_lib/wikiValidation.js';

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
