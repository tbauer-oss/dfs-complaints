// /api/admin/supplier-report-layout.js – Layout-Konfiguration für Lieferantenbriefe
export const config = { runtime: 'nodejs' };

import { ok, bad, methodNotAllowed, readJsonBody } from '../_lib/http.js';
import { applyCors } from '../_lib/cors.js';
import { requirePortalAccess } from './_guard.js';
import { layoutPayloadSize, MAX_LAYOUT_BYTES, validateSupplierReportLayout } from '../_lib/supplierReportLayout.js';
import { supplierReportLetterLayoutGet, supplierReportLetterLayoutSave } from '../_lib/store.js';

const SUPPLIER_TILE = 'supplierEvaluation';

export default async function handler(req, res) {
  if (applyCors(req, res, { allowCredentials: Boolean(req?.headers?.cookie) })) return;

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
      const body = await readJsonBody(req, { limitBytes: MAX_LAYOUT_BYTES });
      const payload = body && typeof body === 'object' ? body : {};
      if (layoutPayloadSize(payload) > MAX_LAYOUT_BYTES) {
        return bad(res, 'Layout-Daten sind zu groß.', 413);
      }
      const validationError = validateSupplierReportLayout(payload);
      if (validationError) {
        return bad(res, validationError, 400);
      }
      const updated = await supplierReportLetterLayoutSave(payload, { updatedBy: actor.email });
      return ok(res, { ok: true, layout: updated });
    }

    return methodNotAllowed(res, req.method, ['GET', 'POST']);
  } catch (err) {
    if (err?.statusCode === 413) {
      return bad(res, 'Layout-Daten sind zu groß.', 413);
    }
    if (err?.statusCode === 400) {
      return bad(res, 'Ungültiges JSON.', 400);
    }
    console.error('[admin/supplier-report-layout] failed', err);
    return bad(res, 'Layout-Konfiguration konnte nicht gespeichert werden.', 500);
  }
}
