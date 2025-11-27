// /api/wiki/admin/categories.js
export const config = { runtime: 'nodejs' };

import { z } from 'zod';
import { handlePreflight, setCors, ok, bad, methodNotAllowed, readJson, noContent } from '../../_lib/http.js';
import { wikiCategories, wikiSaveCategory } from '../../_lib/wikiStore.js';

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
  id: z.string().trim().optional(),
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

  if (req.method === 'GET') {
    const data = await wikiCategories({ includeInactive: true });
    return ok(res, data);
  }

  if (req.method === 'POST') {
    const body = readJson(req);
    try {
      const payload = categorySchema.parse(body || {});
      const saved = await wikiSaveCategory(payload);
      return ok(res, saved);
    } catch (e) {
      return bad(res, e?.message || 'invalid payload', 400);
    }
  }

  return methodNotAllowed(res);
}
