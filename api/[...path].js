// api/[...path].js - catch-all OPTIONS handler for Vercel
export const config = { runtime: 'nodejs' };

import { bad } from './_lib/http.js';

export default function handler(req, res) {
  if (req.method === 'OPTIONS') {
    return res.status(204).end();
  }

  return bad(res, 'not found', 404);
}
