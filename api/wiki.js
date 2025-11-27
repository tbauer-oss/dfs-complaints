// /api/wiki.js
export const config = { runtime: 'nodejs' };

import { handlePreflight, setCors, ok, bad, methodNotAllowed } from './_lib/http.js';
import { normalizeLangValue } from './_lib/store.js';
import { wikiPublicList } from './_lib/wikiStore.js';

export default async function handler(req, res) {
  if (handlePreflight(req, res)) return;
  setCors(req, res);

  try {
    if (req.method !== 'GET') return methodNotAllowed(res);

    const { category, productGroup, type, search } = req.query || {};
    const lang = normalizeLangValue(
      req.query?.lang || (req.headers?.['accept-language'] || '').split(',')[0],
    );
    const data = await wikiPublicList({ category, productGroup, type, search, lang });
    return ok(res, data);
  } catch (err) {
    console.error('[api/wiki] failed', err);
    return bad(res, 'internal server error', 500);
  }
}
