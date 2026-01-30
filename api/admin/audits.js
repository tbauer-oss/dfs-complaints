// /api/admin/audits.js – Legacy endpoint disabled in favor of Internal Audits V2
export const config = { runtime: 'nodejs' };

import { handlePreflight, methodNotAllowed, setCors } from '../_lib/http.js';

export default async function handler(req, res) {
  if (handlePreflight(req, res)) return;
  setCors(req, res);
  // Prevent accidental use of the legacy internal audits implementation.
  if (['GET', 'POST', 'PUT', 'PATCH', 'DELETE'].includes(req.method)) {
    res.statusCode = 410;
    res.end(
      JSON.stringify({
        error: 'internal audits legacy API disabled',
        details: ['Use /api/internal-audits for V2 internal audits.'],
      }),
    );
    return;
  }

  return methodNotAllowed(res);
}
