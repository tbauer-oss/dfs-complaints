// api/[...path].js - catch-all OPTIONS handler for Vercel
export const config = { runtime: 'nodejs' };

import { withCors, bad } from './_lib/http.js';

export default function handler(req, res) {
  if (withCors(req, res)) return;

  return bad(res, 'not found', 404);
}
