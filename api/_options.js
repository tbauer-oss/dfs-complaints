// api/_options.js
export const config = { runtime: 'nodejs' };

import { setCors, handlePreflight } from './_lib/cors.js';

export default function handler(req, res) {
  setCors(req, res);
  if (handlePreflight(req, res)) return;
  return res.status(204).end();
}
