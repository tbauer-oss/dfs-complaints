// api/_options.js
import { withCors } from './_lib/cors.js';

export const config = { runtime: 'nodejs' };

export default function handler(req, res) {
  // Nur Header setzen – egal was withCors zurückliefert
  try { withCors(req, res); } catch (e) { /* ignore */ }

  return res.status(204).end();
}
