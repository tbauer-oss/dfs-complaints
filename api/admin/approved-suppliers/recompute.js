// /api/admin/approved-suppliers/recompute.js – Status neu berechnen
export const config = { runtime: 'nodejs' };

import { handlePreflight, setCors, ok, bad, methodNotAllowed, readJson } from '../../_lib/http.js';
import { requirePortalAccess } from '../_guard.js';
import {
  supplierAll,
  supplierPerformanceAll,
  supplierEvaluationAll,
  supplierEscalationAll,
  supplierApprovedSnapshotGet,
  supplierApprovedSnapshotSave,
} from '../../_lib/store.js';
import { buildApprovedSupplier, normalizeYear, pickEvaluation } from '../_approved_suppliers_utils.js';

const APPROVED_SUPPLIERS_TILE = 'approvedSuppliers';

export default async function handler(req, res) {
  if (handlePreflight(req, res)) return;
  setCors(req, res);

  const actor = await requirePortalAccess(req, res, { tile: APPROVED_SUPPLIERS_TILE, write: true });
  if (!actor) return;

  try {
    if (req.method !== 'POST') {
      return methodNotAllowed(res, req.method, ['POST']);
    }

    const body = readJson(req) || {};
    const supplierId = String(body?.supplierId || '').trim();
    const year = normalizeYear(body?.year);
    if (!supplierId || !year) return bad(res, 'Lieferanten-ID oder Jahr fehlt.', 400);

    const [suppliers, evaluations, entries, escalations] = await Promise.all([
      supplierAll(),
      supplierEvaluationAll({ supplierId }),
      supplierPerformanceAll({ supplierId, includeDeleted: false }),
      supplierEscalationAll({ supplierId }),
    ]);

    const supplier = suppliers.find((s) => s.id === supplierId);
    if (!supplier) return bad(res, 'Lieferant nicht gefunden.', 404);

    const existingSnapshot = await supplierApprovedSnapshotGet({ supplierId, year });
    const updatedSnapshot = await supplierApprovedSnapshotSave({
      supplierId,
      year,
      adminNote: body?.adminNote ?? existingSnapshot?.adminNote ?? '',
      reviewedBy: body?.reviewedByPurchasing ? actor.email : existingSnapshot?.reviewedBy ?? '',
      reviewedAt: body?.reviewedByPurchasing ? Date.now() : existingSnapshot?.reviewedAt ?? null,
      updatedAt: Date.now(),
      updatedBy: actor.email,
    });

    const evaluation = pickEvaluation(evaluations, year);
    const previous = evaluation?.evalYear
      ? evaluations.find((e) => e.evalYear === evaluation.evalYear - 1 && !e.archivedAt)
      : null;

    const entry = buildApprovedSupplier({
      supplier,
      evaluations,
      entries,
      escalations,
      year,
      snapshot: updatedSnapshot,
      previousEvaluation: previous,
    });

    return ok(res, { ok: true, supplier: entry });
  } catch (err) {
    console.error('[admin/approved-suppliers/recompute] failed', err);
    return bad(res, 'Status konnte nicht neu berechnet werden.', 500);
  }
}
