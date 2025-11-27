// /api/wiki/admin/categories/[id].js
export const config = { runtime: 'nodejs' };

import { z } from 'zod';
import { handlePreflight, setCors, ok, bad, methodNotAllowed, readJson, noContent } from '../../../_lib/http.js';
import { wikiSaveCategory, wikiDeleteCategory } from '../../../_lib/wikiStore.js';

function requireAdmin(req, res) {
  const sec = (req.headers?.['x-admin-secret'] || '').toString().trim();
  const expected = (process.env.ADMIN_SECRET || '').toString().trim();
  if (!sec || !expected || sec !== expected) {
    bad(res, 'unauthorized', 401);
    return false;
  }
  return true;
}

const categorySchema = z.object({
  name: z.string().trim().min(1),
  description: z.string().trim().default(''),
  icon: z.string().trim().default(''),
  sortOrder: z.coerce.number().optional(),
  isActive: z.boolean().optional(),
});

export default async function handler(req, res) {
  if (handlePreflight(req, res)) return;
  setCors(req, res);
  if (!requireAdmin(req, res)) return;

  const id = (req.query?.id ?? '').toString().trim();
  if (!id) return bad(res, 'id required', 400);

  if (req.method === 'PUT') {
    const body = readJson(req);
    try {
      const payload = categorySchema.parse(body || {});
      const saved = await wikiSaveCategory({ ...payload, id });
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
