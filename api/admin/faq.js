// api/admin/faq.js
export const config = { runtime: 'nodejs' };

import { setCors, handlePreflight, ok, bad, methodNotAllowed, readJson, noContent } from '../_lib/http.js';
import {
  faqList,
  faqUpsertCategory,
  faqUpsertEntry,
  faqDeleteCategory,
  faqDeleteEntry,
  FAQ_AUDIENCE_CODES,
} from '../_lib/store.js';
import { requirePortalAccess } from './_guard.js';

function normalizeType(raw) {
  const t = (raw ?? '').toString().trim().toLowerCase();
  if (t === 'category' || t === 'categories') return 'category';
  if (t === 'entry' || t === 'item' || t === 'faq') return 'entry';
  return '';
}

export default async function handler(req, res) {
  if (handlePreflight(req, res)) return;
  setCors(req, res);
  const actor = await requirePortalAccess(req, res, { write: req.method !== 'GET' });
  if (!actor) return;

  try {
    if (req.method === 'GET') {
      const data = await faqList({ audience: 'both', includeInactive: true });
      return ok(res, { ...data, audiences: FAQ_AUDIENCE_CODES });
    }

    if (req.method === 'POST') {
      const body = readJson(req);
      const type = normalizeType(body?.type || body?.entity || 'entry');
      if (!type) return bad(res, 'type must be category or entry', 400);

      try {
        if (type === 'category') {
          const savedCat = await faqUpsertCategory(body);
          return ok(res, savedCat);
        }

        const savedEntry = await faqUpsertEntry(body);
        return ok(res, savedEntry);
      } catch (e) {
        return bad(res, e?.message || 'invalid payload', 400);
      }
    }

    if (req.method === 'DELETE') {
      const body = readJson(req);
      const type = normalizeType(body?.type || body?.entity || req.query?.type);
      const id = (body?.id ?? req.query?.id ?? '').toString().trim();
      if (!type) return bad(res, 'type must be category or entry', 400);
      if (!id) return bad(res, 'id required', 400);

      if (type === 'category') {
        await faqDeleteCategory(id);
        return noContent(res);
      }

      await faqDeleteEntry(id);
      return noContent(res);
    }

    return methodNotAllowed(res);
  } catch (e) {
    console.error('admin/faq error', e);
    return bad(res, 'internal error', 500);
  }
}
