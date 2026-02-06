// /api/admin/approved-suppliers.js – Zugelassene Lieferanten (abgeleitet)
export const config = { runtime: 'nodejs' };

import { handlePreflight, setCors, ok, bad, methodNotAllowed } from '../_lib/http.js';
import { requirePortalAccess } from './_guard.js';
import {
  supplierAll,
  supplierPerformanceAll,
  supplierEvaluationAll,
  supplierEscalationAll,
  supplierApprovedSnapshotGet,
} from '../_lib/store.js';
import { buildApprovedSupplier, normalizeYear, pickEvaluation } from './_approved_suppliers_utils.js';

const APPROVED_SUPPLIERS_TILE = 'approvedSuppliers';

async function loadSnapshotsForSuppliers(suppliers, yearBySupplier) {
  const snapshots = new Map();
  for (const supplier of suppliers) {
    const year = yearBySupplier.get(supplier.id);
    if (!year) continue;
    const snapshot = await supplierApprovedSnapshotGet({ supplierId: supplier.id, year });
    if (snapshot) snapshots.set(`${supplier.id}:${year}`, snapshot);
  }
  return snapshots;
}

export default async function handler(req, res) {
  if (handlePreflight(req, res)) return;
  setCors(req, res);

  const actor = await requirePortalAccess(req, res, { tile: APPROVED_SUPPLIERS_TILE });
  if (!actor) return;

  try {
    if (req.method === 'GET') {
      const yearParam = normalizeYear(req.query?.year);
      const [suppliers, evaluations, entries, escalations] = await Promise.all([
        supplierAll(),
        supplierEvaluationAll(),
        supplierPerformanceAll({ includeDeleted: false }),
        supplierEscalationAll(),
      ]);

      const evaluationsBySupplier = new Map();
      for (const evaluation of evaluations) {
        if (!evaluation?.supplierId) continue;
        const list = evaluationsBySupplier.get(evaluation.supplierId) || [];
        list.push(evaluation);
        evaluationsBySupplier.set(evaluation.supplierId, list);
      }

      const entriesBySupplier = new Map();
      for (const entry of entries) {
        if (!entry?.supplierId) continue;
        const list = entriesBySupplier.get(entry.supplierId) || [];
        list.push(entry);
        entriesBySupplier.set(entry.supplierId, list);
      }

      const escalationsBySupplier = new Map();
      for (const escalation of escalations) {
        if (!escalation?.supplierId) continue;
        const list = escalationsBySupplier.get(escalation.supplierId) || [];
        list.push(escalation);
        escalationsBySupplier.set(escalation.supplierId, list);
      }

      const yearBySupplier = new Map();
      for (const supplier of suppliers) {
        const evals = evaluationsBySupplier.get(supplier.id) || [];
        const picked = pickEvaluation(evals, yearParam);
        if (picked?.evalYear) yearBySupplier.set(supplier.id, picked.evalYear);
        else if (yearParam) yearBySupplier.set(supplier.id, yearParam);
      }

      const snapshots = await loadSnapshotsForSuppliers(suppliers, yearBySupplier);

      const list = suppliers.map((supplier) => {
        const evals = evaluationsBySupplier.get(supplier.id) || [];
        const selected = pickEvaluation(evals, yearParam);
        const previous = selected?.evalYear
          ? evals.find((e) => e.evalYear === selected.evalYear - 1 && !e.archivedAt)
          : null;
        const entriesForSupplier = entriesBySupplier.get(supplier.id) || [];
        const escalationsForSupplier = escalationsBySupplier.get(supplier.id) || [];
        const yearUsed = selected?.evalYear || yearParam || null;
        const snapshot = yearUsed ? snapshots.get(`${supplier.id}:${yearUsed}`) : null;
        return buildApprovedSupplier({
          supplier,
          evaluations: evals,
          entries: entriesForSupplier,
          escalations: escalationsForSupplier,
          year: yearParam,
          snapshot,
          previousEvaluation: previous,
        });
      });

      return ok(res, { ok: true, list });
    }

    return methodNotAllowed(res, req.method, ['GET']);
  } catch (err) {
    console.error('[admin/approved-suppliers] failed', err);
    return bad(res, 'Zugelassene Lieferanten konnten nicht geladen werden.', 500);
  }
}
