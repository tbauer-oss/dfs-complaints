// /api/wiki/[id].js
export const config = { runtime: 'nodejs' };

import { handlePreflight, setCors, ok, bad, methodNotAllowed } from '../_lib/http.js';
import { normalizeLangValue } from '../_lib/store.js';
import { wikiGetPublic } from '../_lib/wikiStore.js';

export default async function handler(req, res) {
  if (handlePreflight(req, res)) return;
  setCors(req, res);

  try {
    if (req.method !== 'GET') return methodNotAllowed(res);

    const id = (req.query?.id ?? '').toString();
    const lang = normalizeLangValue(
      req.query?.lang || (req.headers?.['accept-language'] || '').split(',')[0],
    );
    const item = await wikiGetPublic(id, { lang });
    if (!item) return bad(res, 'not found', 404);
    return ok(res, item);
  } catch (err) {
    console.error('[api/wiki/[id]] failed', err);
    return bad(res, 'internal server error', 500);
  }
}
