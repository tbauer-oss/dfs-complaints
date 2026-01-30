// api/_options.js
import { withCors } from './_lib/cors.js';

export const config = { runtime: 'nodejs' };

export default function handler(req, res) {
  const handled = withCors(req, res);
  if (handled) return;

  res.statusCode = 204;
  res.end();
}
