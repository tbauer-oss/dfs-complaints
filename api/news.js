// api/news.js
export const config = { runtime: 'nodejs' };

import { setCors, handlePreflight, ok, bad, methodNotAllowed } from './_lib/http.js';
import { customerNewsList } from './_lib/store.js';

export default async function handler(req, res) {
  if (handlePreflight(req, res)) return;
  setCors(req, res);
  if (req.method !== 'GET') {
    return methodNotAllowed(res);
  }

  try {
    const limitRaw = req.query?.limit;
    const limit = limitRaw ? Math.max(0, Math.min(200, Number(limitRaw) || 0)) : 0;
    const items = await customerNewsList({ limit, includeDrafts: false });
    return ok(res, { items });
  } catch (e) {
    console.error('news endpoint failed', e);
    return bad(res, 'internal error', 500);
  }
}
