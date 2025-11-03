// api/admin/health.js
export const config = { runtime: 'nodejs' };

import { handlePreflight, setCors, ok, bad } from '../_lib/http.js';
import { isAdmin } from '../_lib/auth.js';

export default async function handler(req, res) {
  if (handlePreflight(req, res)) return;
  setCors(req, res);
  if (!isAdmin(req, { debug: true })) return bad(res, 'admin unauthorized', 401);
  return ok(res, { ok: true, ts: Date.now() });
}
