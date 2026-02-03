// api/ping.js – diagnostic route to confirm /api deployment
export const config = { runtime: 'nodejs' };

import { withCors, ok, methodNotAllowed } from './_lib/http.js';

export default async function handler(req, res) {
  withCors(req, res);
  if (req.method === 'OPTIONS') {
    return res.status(204).end();
  }
  if (req.method !== 'GET') return methodNotAllowed(res);
  return ok(res, { ok: true, service: 'dfs-complaints-backend' });
}
