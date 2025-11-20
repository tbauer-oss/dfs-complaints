// api/_options.js
export const config = { runtime: 'nodejs' };

import { setCors } from './_lib/cors.js';

export default function handler(req, res) {
  setCors(req, res);
  return res.status(204).end();
}
