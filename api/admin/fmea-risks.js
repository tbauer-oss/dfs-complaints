// /api/admin/fmea-risks.js – CRUD für Risikozeilen innerhalb einer FMEA
export const config = { runtime: 'nodejs' };

import { handlePreflight, setCors, ok, bad, methodNotAllowed, readJson } from '../_lib/http.js';
import { requirePortalAccess } from './_guard.js';
import { fmeaAddRisk, fmeaUpdateRisk, fmeaDeleteRisk, fmeaDuplicateRisk, fmeaGet } from '../_lib/store.js';

const FMEA_TILE = 'fmea';

export default async function handler(req, res) {
  if (handlePreflight(req, res)) return;
  setCors(req, res);

  const wantsWrite = ['POST', 'PATCH', 'DELETE'].includes(req.method);
  const actor = await requirePortalAccess(req, res, { tile: FMEA_TILE, write: wantsWrite });
  if (!actor) return;

  try {
    // ===== GET: Risiken einer FMEA laden =====
    if (req.method === 'GET') {
      const fmeaId = req.query?.fmeaId;
      if (!fmeaId) return bad(res, 'fmeaId missing', 400);
      const fmea = await fmeaGet(fmeaId);
      if (!fmea) return bad(res, 'not found', 404);
      return ok(res, { ok: true, risks: fmea.risks || [] });
    }

    // ===== POST: Neue Risikozeile anlegen =====
    if (req.method === 'POST') {
      const body = readJson(req) || {};
      const fmeaId = body.fmeaId || req.query?.fmeaId;
      if (!fmeaId) return bad(res, 'fmeaId missing', 400);
      const result = await fmeaAddRisk(fmeaId, { ...body.risk, updatedBy: actor.email });
      if (!result) return bad(res, 'not found', 404);
      return ok(res, { ok: true, risk: result.risk, fmea: result.fmea });
    }

    // ===== PATCH: Risikozeile aktualisieren oder duplizieren =====
    if (req.method === 'PATCH') {
      const body = readJson(req) || {};
      const fmeaId = body.fmeaId || req.query?.fmeaId;
      const riskId = body.riskId || req.query?.riskId;
      if (!fmeaId || !riskId) return bad(res, 'fmeaId or riskId missing', 400);

      if (body.duplicate === true || body.action === 'duplicate') {
        const cloned = await fmeaDuplicateRisk(fmeaId, riskId);
        if (!cloned) return bad(res, 'not found', 404);
        return ok(res, { ok: true, risk: cloned.risk, fmea: cloned.fmea });
      }

      const patch = body.patch ?? body.risk ?? {};
      const result = await fmeaUpdateRisk(fmeaId, riskId, { ...patch, updatedBy: actor.email });
      if (!result) return bad(res, 'not found', 404);
      return ok(res, { ok: true, risk: result.risk, fmea: result.fmea });
    }

    // ===== DELETE: Risikozeile löschen =====
    if (req.method === 'DELETE') {
      const body = readJson(req) || {};
      const fmeaId = body.fmeaId || req.query?.fmeaId;
      const riskId = body.riskId || req.query?.riskId;
      if (!fmeaId || !riskId) return bad(res, 'fmeaId or riskId missing', 400);
      const updated = await fmeaDeleteRisk(fmeaId, riskId);
      if (!updated) return bad(res, 'not found', 404);
      return ok(res, { ok: true, fmea: updated });
    }

    return methodNotAllowed(res);
  } catch (err) {
    console.error('[admin/fmea-risks] error', err);
    return bad(res, 'server error', 500);
  }
}
