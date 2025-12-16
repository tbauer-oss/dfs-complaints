// /api/admin/audit-annual-reports.js – Jahresberichte & Exporte
export const config = { runtime: 'nodejs' };

import { setCors, ok, bad, methodNotAllowed, readJson } from '../_lib/http.js';
import { requirePortalAccess } from './_guard.js';
import {
  AUDIT_TILE_ID,
  auditAnnualReportAll,
  auditAnnualReportSave,
  runWithAuditRedisContext,
} from '../_lib/store.js';

const TILE = AUDIT_TILE_ID;

function handleError(res, err) {
  console.error('[admin/audit-annual-reports] error', err);
  return bad(res, err.message || 'server error', err.code === 'VALIDATION_ERROR' ? 400 : 500);
}

export default async function handler(req, res) {
  if (setCors(req, res)) return;

  const wantsWrite = ['POST'].includes(req.method);
  const actor = await requirePortalAccess(req, res, { tile: TILE, write: wantsWrite, allowPrrc: true });
  if (!actor) return;

  return await runWithAuditRedisContext(
    { route: '/api/admin/audit-annual-reports', method: req.method },
    async () => {
      try {
        if (req.method === 'GET') {
          const filter = { year: req.query?.year };
          const list = await auditAnnualReportAll(filter);
          const id = req.query?.id;
          if (id) {
            const found = list.find((r) => r.id === id);
            if (!found) return bad(res, 'not found', 404);
            return ok(res, { ok: true, report: found });
          }
          return ok(res, { ok: true, list });
        }

        if (req.method === 'POST') {
          const body = readJson(req) || {};
          const saved = await auditAnnualReportSave({ ...body, updatedBy: actor.email });
          return ok(res, { ok: true, report: saved });
        }

        return methodNotAllowed(res);
      } catch (err) {
        return handleError(res, err);
      }
    },
  );
}
