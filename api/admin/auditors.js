// /api/admin/auditors.js – Auditorenverwaltung & Matrix
export const config = { runtime: 'nodejs' };

import {
  handlePreflight,
  setCors,
  ok,
  bad,
  methodNotAllowed,
  readJson,
} from '../_lib/http.js';
export default async function handler(req, res) {
  if (handlePreflight(req, res)) return;
  setCors(req, res);

  // Legacy auditors API is disabled to stop all unintended Redis writes.
  res.statusCode = 410;
  res.end(
    JSON.stringify({
      error: 'legacy auditors API disabled',
      details: ['Use /api/internal-auditors instead.'],
    }),
  );
}
