// api/_options.js
export const config = { runtime: 'nodejs22.x' };

import { handlePreflight, setCors } from './_lib/http.js';

export default function handler(req, res) {
  if (handlePreflight(req, res)) return;
  // Fallback for runtimes that skip OPTIONS short-circuiting
  setCors(req, res);
  return res.status(204).end();
}
