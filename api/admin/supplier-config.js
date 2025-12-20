// /api/admin/supplier-config.js – Konfiguration Lieferantenbewertung
export const config = { runtime: 'nodejs' };

import { handlePreflight, setCors, ok, bad, methodNotAllowed, readJson } from '../_lib/http.js';
import { requirePortalAccess } from './_guard.js';
import { supplierEvalConfigGet, supplierEvalConfigSave } from '../_lib/store.js';

const SUPPLIER_TILE = 'supplierEvaluation';

export default async function handler(req, res) {
  if (handlePreflight(req, res)) return;
  setCors(req, res);

  const wantsWrite = ['POST', 'PATCH'].includes(req.method);
  const actor = await requirePortalAccess(req, res, { tile: SUPPLIER_TILE, write: wantsWrite });
  if (!actor) return;

  try {
    if (req.method === 'GET') {
      const config = await supplierEvalConfigGet();
      return ok(res, { ok: true, config });
    }

    if (req.method === 'POST' || req.method === 'PATCH') {
      const body = readJson(req) || {};
      const updated = await supplierEvalConfigSave(body, { updatedBy: actor.email });
      return ok(res, { ok: true, config: updated });
    }

    return methodNotAllowed(res, req.method, ['GET', 'POST', 'PATCH']);
  } catch (err) {
    console.error('[admin/supplier-config] failed', err);
    return bad(res, 'Konfiguration konnte nicht gespeichert werden.', 500);
  }
}
