// api/news.js
export const config = { runtime: 'nodejs' };

import { setCors, handlePreflight, ok, bad, methodNotAllowed, readJson, noContent } from './_lib/http.js';
import {
  customerNewsDelete,
  customerNewsList,
  customerNewsUpsert,
  CUSTOMER_NEWS_CATEGORY_CODES,
} from './_lib/store.js';
import { requirePortalAccess } from './admin/_guard.js';

export default async function handler(req, res) {
  if (handlePreflight(req, res)) return;
  setCors(req, res);
  res.setHeader('Cache-Control', 'no-store');
  try {
    const includeDraftsRaw = req.query?.includeDrafts ?? req.query?.drafts ?? '';
    const includeDrafts = ['1', 'true', 'yes', 'y', 'on'].includes(
      includeDraftsRaw.toString().trim().toLowerCase(),
    );

    const requiresAuth = req.method !== 'GET' || includeDrafts;
    if (requiresAuth) {
      const actor = await requirePortalAccess(req, res, { write: req.method !== 'GET', tile: 'news' });
      if (!actor) return;
    }

    if (req.method === 'GET') {
      const limitRaw = req.query?.limit;
      const limit = limitRaw ? Math.max(0, Math.min(200, Number(limitRaw) || 0)) : 0;
      const items = await customerNewsList({ limit, includeDrafts });
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
    console.error('news endpoint failed', e);
    return bad(res, 'internal error', 500);
  }
}
