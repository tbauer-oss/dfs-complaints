// /api/wiki/admin/articles/[id].js
export const config = { runtime: 'nodejs' };

import { z } from 'zod';
import { handlePreflight, setCors, ok, bad, methodNotAllowed, readJson, noContent } from '../../../_lib/http.js';
import { wikiSaveArticle, wikiDeleteArticle, wikiGetArticle } from '../../../_lib/wikiStore.js';

function requireAdmin(req, res) {
  const sec = (req.headers?.['x-admin-secret'] || '').toString().trim();
  const expected = (process.env.ADMIN_SECRET || '').toString().trim();
  if (!sec || !expected || sec !== expected) {
    bad(res, 'unauthorized', 401);
    return false;
  }
  return true;
}

const articleSchema = z.object({
  categoryId: z.string().trim().min(1),
  productGroups: z.array(z.string().trim()).optional(),
  type: z.enum(['faq', 'safety', 'error', 'prevention']),
  title: z.string().trim().min(1),
  teaser: z.string().trim().default(''),
  importance: z.enum(['normal', 'high', 'critical']).default('normal'),
  contentMarkdown: z.string().trim().default(''),
  tags: z.array(z.string().trim()).optional(),
  isActive: z.boolean().optional(),
  createdAt: z.coerce.date().optional(),
  updatedAt: z.coerce.date().optional(),
});

export default async function handler(req, res) {
  if (handlePreflight(req, res)) return;
  setCors(req, res);
  if (!requireAdmin(req, res)) return;

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
      const payload = articleSchema.parse(body || {});
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
