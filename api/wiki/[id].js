// /api/wiki/[id].js
export const config = { runtime: 'nodejs' };

import { handlePreflight, setCors, ok, bad, methodNotAllowed } from '../_lib/http.js';
import { wikiGetPublic } from '../_lib/wikiStore.js';

export default async function handler(req, res) {
  if (handlePreflight(req, res)) return;
  setCors(req, res);

  if (req.method !== 'GET') return methodNotAllowed(res);

  const id = (req.query?.id ?? '').toString();
  const item = await wikiGetPublic(id);
  if (!item) return bad(res, 'not found', 404);
  return ok(res, item);
}
