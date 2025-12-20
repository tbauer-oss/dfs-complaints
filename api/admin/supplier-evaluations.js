// /api/admin/supplier-evaluations.js – Jahresbewertung Lieferanten
export const config = { runtime: 'nodejs' };

import { handlePreflight, setCors, ok, bad, methodNotAllowed, readJson } from '../_lib/http.js';
import { requirePortalAccess } from './_guard.js';
import {
  supplierEvaluationAll,
  supplierEvaluationGet,
  supplierEvaluationSave,
  supplierEvaluationUpdate,
  supplierEvaluationDelete,
  supplierPerformanceAll,
  supplierEvalConfigGet,
  supplierEscalationSave,
} from '../_lib/store.js';

const SUPPLIER_TILE = 'supplierEvaluation';

function isFilled(value) {
  if (value == null) return false;
  if (Array.isArray(value)) return value.length > 0;
  return String(value).trim().length > 0;
}

const PERFORMANCE_CRITERIA = [
  { key: 'communication', label: 'Zusammenarbeit / Kommunikation', weight: 0.1 },
  { key: 'quality', label: 'Produktqualität', weight: 0.3 },
  { key: 'delivery', label: 'Einhaltung der Lieferfrist', weight: 0.15 },
  { key: 'price', label: 'Preis / Rechnungsstellung', weight: 0.15 },
  { key: 'quantity', label: 'Fehllieferungen / Falschlieferungen (Richtige Mengen / richtige Produkte)', weight: 0.2 },
  { key: 'backorders', label: 'Nachlieferungen', weight: 0.1 },
];

function entryGrade(entry) {
  const ratings = entry?.ratings || {};
  const communicationNa = entry?.communicationNa === true;
  let total = 0;
  let weightTotal = 0;
  for (const { key, weight } of PERFORMANCE_CRITERIA) {
    const value = ratings[key];
    if (key === 'communication' && communicationNa && value == null) {
      continue;
    }
    if (!Number.isFinite(value)) return null;
    total += value * weight;
    weightTotal += weight;
  }
  if (!weightTotal) return null;
  return Number((total / weightTotal).toFixed(2));
}

function classify(avg) {
  if (!Number.isFinite(avg)) return '';
  if (avg <= 1.5) return 'A';
  if (avg <= 2.0) return 'B';
  if (avg <= 2.5) return 'C';
  return 'D';
}

function decisionFor(classification) {
  if (classification === 'A' || classification === 'B') return 'weiterhin zugelassen';
  if (classification === 'C') return 'in Beobachtung';
  if (classification === 'D') return 'gesperrt / nicht zugelassen';
  return '';
}

function isEntryComplete(entry) {
  const ratings = entry?.ratings || {};
  const communicationNa = entry?.communicationNa === true;
  for (const { key } of PERFORMANCE_CRITERIA) {
    if (key === 'communication' && communicationNa && ratings[key] == null) continue;
    if (!Number.isFinite(ratings[key])) return false;
  }
  return true;
}

function computeAggregates(entries, allEntries = entries) {
  const gradedEntries = entries
    .map((entry) => ({
      entry,
      grade: entry.computedScore ?? entry.computedGrade ?? entryGrade(entry),
    }))
    .filter((item) => Number.isFinite(item.grade));

  const avgGrade = gradedEntries.length
    ? gradedEntries.reduce((sum, item) => sum + item.grade, 0) / gradedEntries.length
    : null;
  const classification = classify(avgGrade);
  const decision = decisionFor(classification);

  const criterionAverages = PERFORMANCE_CRITERIA.map((criterion) => {
    const values = gradedEntries
      .filter(
        (item) => !(criterion.key === 'communication' && item.entry?.communicationNa === true)
      )
      .map((item) => item.entry?.ratings?.[criterion.key])
      .filter((value) => Number.isFinite(value));
    const avg = values.length ? values.reduce((sum, value) => sum + value, 0) / values.length : null;
    return {
      key: criterion.key,
      label: criterion.label,
      weight: criterion.weight,
      average: avg == null ? null : Number(avg.toFixed(2)),
    };
  });

  const sortedDrivers = [...criterionAverages]
    .filter((item) => Number.isFinite(item.average))
    .sort((a, b) => (b.average ?? 0) - (a.average ?? 0));
  const topNegativeDrivers = sortedDrivers.slice(0, 2);

  const evidence = entries.map((entry) => ({
    id: entry.id,
    date: entry.date,
    referenceType: entry.referenceType,
    referenceNumber: entry.referenceNumber,
    description: entry.description,
    includeInAnnual: entry.includeInAnnual,
    status: entry.status,
    grade: entry.computedScore ?? entry.computedGrade ?? entryGrade(entry),
    communicationNa: entry.communicationNa === true,
  }));

  const deletedEntries = allEntries.filter((entry) => entry.deletedAt).length;
  const openEntries = allEntries.filter((entry) => {
    if (entry.deletedAt) return false;
    return !entry.includeInAnnual || !isEntryComplete(entry);
  }).length;

  return {
    totalEntries: allEntries.length,
    deletedEntries,
    openEntries,
    includedEntries: gradedEntries.length,
    averageGrade: avgGrade == null ? null : Number(avgGrade.toFixed(2)),
    classification,
    decision,
    criterionAverages,
    topNegativeDrivers,
    evidence,
  };
}

function validateEvaluation(record) {
  if (!isFilled(record?.supplierId)) return 'Bitte einen Lieferanten auswählen.';
  if (!isFilled(record?.evalYear)) return 'Bitte ein Bewertungsjahr angeben.';
  if (!isFilled(record?.periodFrom) || !isFilled(record?.periodTo)) return 'Bitte den Zeitraum angeben.';
  if (!isFilled(record?.decision)) return 'Bitte eine Entscheidung auswählen.';
  if (record?.decision && record.decision.toLowerCase().includes('sperr')) {
    if (!isFilled(record?.decisionReason)) return 'Bitte eine Begründung zur Sperrung angeben.';
  }
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
      const { id, supplierId } = req.query || {};
      if (id) {
        const evaluation = await supplierEvaluationGet(id);
        if (!evaluation) return bad(res, 'Bewertung nicht gefunden.', 404);
        return ok(res, { ok: true, evaluation });
      }
      const list = await supplierEvaluationAll({ supplierId });
      return ok(res, { ok: true, list });
    }

    if (req.method === 'POST') {
      const body = readJson(req) || {};
      const config = await supplierEvalConfigGet();
      const entries = await supplierPerformanceAll({ supplierId: body?.supplierId, includeDeleted: true });
      const relevant = entries.filter((e) => {
        if (!e.includeInAnnual || e.status !== 'ABGESCHLOSSEN') return false;
        if (e.deletedAt) return false;
        if (body?.periodFrom && e.date < Number(body.periodFrom)) return false;
        if (body?.periodTo && e.date > Number(body.periodTo)) return false;
        return true;
      });
      const aggregates = computeAggregates(relevant, entries);
      const payload = {
        ...body,
        aggregates,
        decision: body?.decision || aggregates.decision,
        configVersion: config.version,
        configSnapshot: {
          version: config.version,
          categories: config.categories,
          thresholds: config.thresholds,
        },
        status: body?.status || 'draft',
        createdAt: body?.createdAt || Date.now(),
        createdBy: actor.email,
        updatedBy: actor.email,
        history: [
          ...(Array.isArray(body?.history) ? body.history : []),
          { action: 'created', actor: actor.email, at: Date.now(), note: 'Jahresbewertung gestartet' },
        ],
      };
      const err = validateEvaluation(payload);
      if (err) return bad(res, err, 400);
      if (payload.status === 'final' && !isFilled(payload.approvedBy)) {
        return bad(res, 'Bitte die Freigabe dokumentieren.', 400);
      }
      const saved = await supplierEvaluationSave(payload);
      console.info('[supplier-evaluations] created', { evaluationId: saved.id, supplierId: saved.supplierId, year: saved.evalYear });
      if (payload.decision && payload.decision.toLowerCase().includes('sperr')) {
        await supplierEscalationSave({
          supplierId: payload.supplierId,
          trigger: 'annual',
          reason: payload.decisionReason || 'Sperrung aus Jahresbewertung',
          severity: 'hoch',
          status: 'offen',
          createdAt: Date.now(),
          createdBy: actor.email,
          updatedBy: actor.email,
          history: [
            { action: 'created', actor: actor.email, at: Date.now(), note: 'Eskalation aus Jahresbewertung' },
          ],
        });
      }
      return ok(res, { ok: true, evaluation: saved });
    }

    if (req.method === 'PATCH') {
      const { id } = req.query || {};
      if (!id) return bad(res, 'Bewertungs-ID fehlt.', 400);
      const current = await supplierEvaluationGet(id);
      if (!current) return bad(res, 'Bewertung nicht gefunden.', 404);
      if (current.status === 'final') {
        return bad(res, 'Finalisierte Bewertungen können nicht geändert werden.', 400);
      }
      const body = readJson(req) || {};
      const historyEntry = {
        action: 'updated',
        actor: actor.email,
        at: Date.now(),
        note: isFilled(body.changeReason) ? String(body.changeReason).trim() : 'Bewertung aktualisiert',
      };
      const merged = {
        ...current,
        ...body,
        updatedBy: actor.email,
        updatedAt: Date.now(),
        history: [...(current.history || []), historyEntry],
      };
      const err = validateEvaluation(merged);
      if (err) return bad(res, err, 400);
      if (merged.status === 'final' && !isFilled(merged.approvedBy)) {
        return bad(res, 'Bitte die Freigabe dokumentieren.', 400);
      }
      const saved = await supplierEvaluationUpdate(id, merged);
      return ok(res, { ok: true, evaluation: saved });
    }

    if (req.method === 'DELETE') {
      const { id } = req.query || {};
      if (!id) return bad(res, 'Bewertungs-ID fehlt.', 400);
      const current = await supplierEvaluationGet(id);
      if (!current) return bad(res, 'Bewertung nicht gefunden.', 404);
      if (current.status === 'final') {
        const body = readJson(req) || {};
        if (!isFilled(body.cancelReason)) {
          return bad(res, 'Bitte eine Stornierungsbegründung angeben.', 400);
        }
        const saved = await supplierEvaluationUpdate(id, {
          status: 'cancelled',
          cancelReason: body.cancelReason,
          updatedBy: actor.email,
          updatedAt: Date.now(),
          history: [...(current.history || []), { action: 'cancelled', actor: actor.email, at: Date.now(), note: body.cancelReason }],
        });
        return ok(res, { ok: true, evaluation: saved });
      }
      await supplierEvaluationDelete(id);
      return ok(res, { ok: true });
    }

    return methodNotAllowed(res, req.method, ['GET', 'POST', 'PATCH', 'DELETE']);
  } catch (err) {
    console.error('[admin/supplier-evaluations] failed', err);
    return bad(res, 'Bewertung konnte nicht verarbeitet werden.', 500);
  }
}
