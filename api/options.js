// api/options.js
export const config = { runtime: 'nodejs' };

import { withCors } from './_lib/http.js';

export default function handler(req, res) {
  withCors(req, res);
  if (req.method === 'OPTIONS') {
    return res.status(204).end();
  }
  return res.status(404).end();
}
