// /api/admin/suppliers.js – Lieferantenstamm
export const config = { runtime: 'nodejs' };

import { handlePreflight, setCors, ok, bad, methodNotAllowed, readJson } from '../_lib/http.js';
import { requirePortalAccess } from './_guard.js';
import {
  supplierAll,
  supplierGet,
  supplierSave,
  supplierUpdate,
  supplierDelete,
  supplierPerformanceAll,
  supplierEvaluationAll,
  supplierEscalationAll,
} from '../_lib/store.js';

const SUPPLIER_TILE = 'supplierEvaluation';

function isFilled(value) {
  if (value == null) return false;
  if (Array.isArray(value)) return value.length > 0;
  return String(value).trim().length > 0;
}

function validateSupplier(record) {
  if (!isFilled(record?.name)) return 'Bitte einen Lieferantennamen angeben.';
  if (!isFilled(record?.status)) return 'Bitte einen Status auswählen.';
  return null;
}

export default async function handler(req, res) {
  if (handlePreflight(req, res)) return;
  setCors(req, res);

  const wantsWrite = ['POST', 'PATCH', 'DELETE'].includes(req.method);
  const actor = await requirePortalAccess(req, res, { tile: SUPPLIER_TILE, write: wantsWrite });
  if (!actor) return;

  try {
    if (req.method === 'GET') {
      const { id } = req.query || {};
      if (id) {
        const supplier = await supplierGet(id);
        if (!supplier) return bad(res, 'Lieferant nicht gefunden.', 404);
        return ok(res, { ok: true, supplier });
      }
      const list = await supplierAll();
      return ok(res, { ok: true, list });
    }

    if (req.method === 'POST') {
      const body = readJson(req) || {};
      const payload = {
        ...body,
        createdAt: body?.createdAt || Date.now(),
        createdBy: actor.email,
        updatedBy: actor.email,
        history: [
          ...(Array.isArray(body?.history) ? body.history : []),
          { action: 'created', actor: actor.email, at: Date.now(), note: 'Lieferant angelegt' },
        ],
      };
      const err = validateSupplier(payload);
      if (err) return bad(res, err, 400);
      const saved = await supplierSave(payload);
      return ok(res, { ok: true, supplier: saved });
    }

    if (req.method === 'PATCH') {
      const { id } = req.query || {};
      if (!id) return bad(res, 'Lieferanten-ID fehlt.', 400);
      const current = await supplierGet(id);
      if (!current) return bad(res, 'Lieferant nicht gefunden.', 404);
      const body = readJson(req) || {};
      if (body.status === 'gesperrt' && !isFilled(body.blockedReason)) {
        return bad(res, 'Bitte einen Sperrgrund angeben.', 400);
      }
      const historyEntry = {
        action: 'updated',
        actor: actor.email,
        at: Date.now(),
        note: isFilled(body.changeReason) ? String(body.changeReason).trim() : 'Lieferant aktualisiert',
      };
      const merged = {
        ...current,
        ...body,
        updatedBy: actor.email,
        updatedAt: Date.now(),
        history: [...(current.history || []), historyEntry],
      };
      const err = validateSupplier(merged);
      if (err) return bad(res, err, 400);
      const saved = await supplierUpdate(id, merged);
      return ok(res, { ok: true, supplier: saved });
    }

    if (req.method === 'DELETE') {
      const { id } = req.query || {};
      if (!id) return bad(res, 'Lieferanten-ID fehlt.', 400);
      const [perf, evals, escs] = await Promise.all([
        supplierPerformanceAll({ supplierId: id }),
        supplierEvaluationAll({ supplierId: id }),
        supplierEscalationAll({ supplierId: id }),
      ]);
      if (perf.length || evals.length || escs.length) {
        const body = readJson(req) || {};
        const archived = await supplierUpdate(id, {
          status: 'inaktiv',
          archivedAt: Date.now(),
          archivedBy: actor.email,
          archivedReason: String(body?.archivedReason || 'Archiviert durch Löschversuch').trim(),
          updatedBy: actor.email,
          updatedAt: Date.now(),
          history: [
            ...(Array.isArray(body?.history) ? body.history : []),
            { action: 'archived', actor: actor.email, at: Date.now(), note: 'Lieferant archiviert (verknüpfte Daten vorhanden)' },
          ],
        });
        return ok(res, { ok: true, supplier: archived, archived: true });
      }
      await supplierDelete(id);
      return ok(res, { ok: true });
    }

    return methodNotAllowed(res, req.method, ['GET', 'POST', 'PATCH', 'DELETE']);
  } catch (err) {
    console.error('[admin/suppliers] failed', err);
    return bad(res, 'Lieferant konnte nicht verarbeitet werden.', 500);
  }
}
