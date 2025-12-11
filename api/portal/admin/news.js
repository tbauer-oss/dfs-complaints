// api/portal/admin/news.js – Verwaltung für Mitarbeiter-News
export const config = { runtime: 'nodejs' };

import {
  bad,
  handlePreflight,
  methodNotAllowed,
  noContent,
  ok,
  readJson,
  setCors,
} from '../../_lib/http.js';
import {
  CUSTOMER_NEWS_CATEGORY_CODES,
  portalNewsDelete,
  portalNewsList,
  portalNewsUpsert,
} from '../../_lib/store.js';
import { requirePortalAccess } from '../../admin/_guard.js';

export default async function handler(req, res) {
  if (handlePreflight(req, res)) return;
  setCors(req, res);
  const actor = await requirePortalAccess(req, res, { write: req.method !== 'GET', tile: 'news' });
  if (!actor) return;

  try {
    if (req.method === 'GET') {
      const items = await portalNewsList({ includeDrafts: true });
      return ok(res, { items, categories: CUSTOMER_NEWS_CATEGORY_CODES });
    }

    if (req.method === 'POST') {
      const body = readJson(req);
      try {
        const saved = await portalNewsUpsert(body);
        return ok(res, saved);
      } catch (e) {
        return bad(res, e?.message || 'invalid payload', 400);
      }
    }

    if (req.method === 'DELETE') {
      const body = readJson(req);
      const id = (body.id ?? req.query?.id ?? '').toString().trim();
      if (!id) return bad(res, 'id required', 400);
      await portalNewsDelete(id);
      return noContent(res);
    }

    return methodNotAllowed(res);
  } catch (e) {
    console.error('portal/admin/news error', e);
    return bad(res, 'internal error', 500);
  }
}

