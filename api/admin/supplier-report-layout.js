// /api/admin/supplier-report-layout.js – Layout-Konfiguration für Lieferantenbriefe
export const config = { runtime: 'nodejs' };

import { handlePreflight, setCors, ok, bad, methodNotAllowed, readJson } from '../_lib/http.js';
import { requirePortalAccess } from './_guard.js';
import { supplierReportLetterLayoutGet, supplierReportLetterLayoutSave } from '../_lib/store.js';

const SUPPLIER_TILE = 'supplierEvaluation';

export default async function handler(req, res) {
  if (handlePreflight(req, res)) return;
  setCors(req, res);

  const wantsWrite = ['POST'].includes(req.method);
  const actor = await requirePortalAccess(req, res, { tile: SUPPLIER_TILE, write: wantsWrite });
  if (!actor) return;

  try {
    const type = (req.query?.type || '').toString().toLowerCase();
    if (type && type !== 'letter') {
      return bad(res, 'Ungültiger Layout-Typ.', 400);
    }

    if (req.method === 'GET') {
      const layout = await supplierReportLetterLayoutGet();
      return ok(res, { ok: true, layout });
    }

    if (req.method === 'POST') {
      const body = readJson(req) || {};
      const payload = body?.layout && typeof body.layout === 'object' ? body.layout : body;
      const updated = await supplierReportLetterLayoutSave(payload, { updatedBy: actor.email });
      return ok(res, { ok: true, layout: updated });
    }

    return methodNotAllowed(res, req.method, ['GET', 'POST']);
  } catch (err) {
    console.error('[admin/supplier-report-layout] failed', err);
    return bad(res, 'Layout-Konfiguration konnte nicht gespeichert werden.', 500);
  }
}
