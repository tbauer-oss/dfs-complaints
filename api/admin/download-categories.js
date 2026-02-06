// api/admin/download-categories.js
export const config = { runtime: 'nodejs' };

import { handlePreflight, setCors, ok, bad, methodNotAllowed, readJson } from '../_lib/http.js';
import { addDownloadCategory, deleteDownloadCategory, downloadCategoriesWithCounts } from '../_lib/store.js';
import { requirePortalAccess } from './_guard.js';

export default async function handler(req, res) {
  if (handlePreflight(req, res)) return;
  setCors(req, res);

  const actor = await requirePortalAccess(req, res, { write: req.method !== 'GET', tile: 'downloads' });
  if (!actor) return;

  try {
    if (req.method === 'GET') {
      const items = await downloadCategoriesWithCounts();
      return ok(res, { items });
    }

    if (req.method === 'POST' || req.method === 'PUT') {
      const body = readJson(req) || {};
      const name = (body.name ?? body.category ?? '').toString().trim();
      if (!name) return bad(res, 'name required', 400);
      await addDownloadCategory(name);
      const items = await downloadCategoriesWithCounts();
      return ok(res, { items });
    }

    if (req.method === 'DELETE') {
      const body = readJson(req) || {};
      const name = (body.name ?? body.category ?? req.query?.name ?? req.query?.category ?? '').toString().trim();
      if (!name) return bad(res, 'name required', 400);
      const force = body.force === true || body.force === 'true' || req.query?.force === 'true';

      try {
        const result = await deleteDownloadCategory(name, { force });
        const items = await downloadCategoriesWithCounts();
        return ok(res, { ...result, items });
      } catch (err) {
        if (err?.code === 'HAS_DOWNLOADS') {
          return bad(res, err?.message || 'category has downloads', 409, err?.details);
        }
        throw err;
      }
    }

    return methodNotAllowed(res);
  } catch (e) {
    console.error('[admin/download-categories] error', e);
    return bad(res, e?.message || 'internal error', 500);
  }
}
