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

function entryPoints(entry, config) {
  const categories = Array.isArray(config?.categories) ? config.categories : [];
  const category = categories.find((c) => c.name === entry.type) || categories[0];
  const scoreMap = category?.scoreMap || {};
  const numeric = Number(scoreMap[entry.rating]);
  return Number.isFinite(numeric) ? numeric : null;
}

function computeAggregates(entries, config) {
  const categories = Array.isArray(config?.categories) ? config.categories : [];
  const byCategory = new Map();
  for (const cat of categories) {
    byCategory.set(cat.name, []);
  }
  for (const entry of entries) {
    const points = entryPoints(entry, config);
    if (!Number.isFinite(points)) continue;
    if (!byCategory.has(entry.type)) byCategory.set(entry.type, []);
    byCategory.get(entry.type).push(points);
  }

  const categoryScores = {};
  let totalScore = 0;
  let weightSum = 0;
  for (const category of categories) {
    const points = byCategory.get(category.name) || [];
    const avg = points.length ? points.reduce((sum, v) => sum + v, 0) / points.length : 0;
    const weight = Number(category.weight || 0);
    const weighted = weight > 0 ? avg * (weight / 100) : 0;
    categoryScores[category.name] = {
      avgPoints: Number(avg.toFixed(2)),
      weightedScore: Number(weighted.toFixed(2)),
      entries: points.length,
    };
    totalScore += weighted;
    weightSum += weight;
  }

  const threshold = Number(config?.thresholds?.red || 0);
  const negativeEntries = entries.filter((e) => {
    const points = entryPoints(e, config);
    return Number.isFinite(points) && threshold > 0 && points <= threshold;
  }).length;

  return {
    totalEntries: entries.length,
    negativeEntries,
    categoryScores,
    totalScore: Number(totalScore.toFixed(2)),
    weightSum,
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
      const entries = await supplierPerformanceAll({ supplierId: body?.supplierId });
      const relevant = entries.filter((e) => {
        if (!e.includeInAnnual || e.status === 'cancelled') return false;
        if (body?.periodFrom && e.date < Number(body.periodFrom)) return false;
        if (body?.periodTo && e.date > Number(body.periodTo)) return false;
        return true;
      });
      const aggregates = computeAggregates(relevant, config);
      const payload = {
        ...body,
        aggregates,
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
