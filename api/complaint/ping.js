export const config = { runtime: 'nodejs' };
import { setCors, noContent, ok } from '../_lib/http.js';

export default function handler(req, res) {
  setCors(req, res);
  if (req.method === 'OPTIONS') return noContent(res);
  return ok(res, { ok: true, route: '/api/complaint/ping' });
}
