// /api/admin/audits/plan.js – alias endpoint using ?id=... for plan CRUD
export const config = { runtime: 'nodejs.x' };

import handlerById from './[id]/plan.js';

export default async function handler(req, res) {
  // Mirror the dynamic route but allow id via query to support rewrites.
  req.query = req.query || {};
  if (!req.query.id && req.url) {
    // attempt to pick up id from body for PUT edge cases
    try {
      const parsedUrl = new URL(req.url, 'http://localhost');
      req.query.id = parsedUrl.searchParams.get('id') || req.query.id;
    } catch (_) {
      /* ignore */
    }
  }
  return handlerById(req, res);
}
