// api/admin/news.js
export const config = { runtime: 'nodejs' };

import { setCors, handlePreflight, ok, bad, methodNotAllowed, readJson, noContent } from '../_lib/http.js';
import {
  customerNewsList,
  customerNewsUpsert,
  customerNewsDelete,
  CUSTOMER_NEWS_CATEGORY_CODES,
} from '../_lib/store.js';

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
      const items = await customerNewsList({ includeDrafts: true });
      return ok(res, { items, categories: CUSTOMER_NEWS_CATEGORY_CODES });
    }

    if (req.method === 'POST') {
      const body = readJson(req);
      try {
        const saved = await customerNewsUpsert(body);
        return ok(res, saved);
      } catch (e) {
        return bad(res, e?.message || 'invalid payload', 400);
      }
    }

    if (req.method === 'DELETE') {
      const body = readJson(req);
      const id = (body.id ?? req.query?.id ?? '').toString().trim();
      if (!id) return bad(res, 'id required', 400);
      await customerNewsDelete(id);
      return noContent(res);
    }

    return methodNotAllowed(res);
  } catch (e) {
    console.error('admin/news error', e);
    return bad(res, 'internal error', 500);
  }
}
