// /api/admin/report.js
export const config = { runtime: 'nodejs' };

import {handlePreflight, setCors, noContent, ok, bad, methodNotAllowed, readJson,} from '../_lib/http.js';
import { complaintUpdate, complaintClearReportLink } from '../_lib/store.js';

const ADMIN_SECRET = process.env.ADMIN_SECRET || '';

function isAuthorizedAdmin(req) {
  const hdr = req.headers?.['x-admin-secret'] || req.headers?.['X-Admin-Secret'];
  return !!(hdr && ADMIN_SECRET && hdr === ADMIN_SECRET);
}

export default async function handler(req, res) {
  setCors(req, res);
  if (req.method === 'OPTIONS') return noContent(res);
  if (!isAuthorizedAdmin(req)) return bad(res, 'admin unauthorized', 401);

  const { ticket } = (req.method === 'GET' || req.method === 'DELETE')
    ? (req.query || {})
    : (typeof req.body === 'object' ? req.body : {});

  if (!ticket || typeof ticket !== 'string') {
    return bad(res, 'missing ticket', 400);
  }

  try {
    if (req.method === 'PATCH') {
      // Body: { ticket, reportUrl }
      const { reportUrl } = req.body || {};
      if (typeof reportUrl !== 'string' || !reportUrl.trim()) {
        return bad(res, 'missing reportUrl', 400);
      }
      const updated = await complaintUpdate(ticket, { reportUrl: reportUrl.trim() });
      if (!updated) return bad(res, 'ticket not found', 404);
      return ok(res, { ok: true, ticket, reportUrl: updated.reportUrl });
    }

    if (req.method === 'DELETE') {
      const updated = await complaintClearReportLink(ticket);
      if (!updated) return bad(res, 'ticket not found', 404);
      return ok(res, { ok: true, ticket, reportUrl: null });
    }

    return methodNotAllowed(res, ['PATCH', 'DELETE']);
  } catch (e) {
    return bad(res, String(e || 'error'), 500);
  }
}
