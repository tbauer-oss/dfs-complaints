// /api/admin/supplier-performance.js – Laufende Lieferanten-Performance
export const config = { runtime: 'nodejs' };

import { handlePreflight, setCors, ok, bad, methodNotAllowed, readJson } from '../_lib/http.js';
import { requirePortalAccess } from './_guard.js';
import {
  supplierPerformanceAll,
  supplierPerformanceGet,
  supplierPerformanceSave,
  supplierPerformanceUpdate,
  supplierEvalConfigGet,
  supplierEscalationAll,
  supplierEscalationSave,
} from '../_lib/store.js';

const SUPPLIER_TILE = 'supplierEvaluation';

function isFilled(value) {
  if (value == null) return false;
  if (Array.isArray(value)) return value.length > 0;
  return String(value).trim().length > 0;
}

function validateEntry(record) {
  if (!isFilled(record?.supplierId)) return 'Bitte einen Lieferanten auswählen.';
  if (!isFilled(record?.date)) return 'Bitte ein Datum angeben.';
  if (!isFilled(record?.description)) return 'Bitte eine Kurzbeschreibung hinterlegen.';
  if (!isFilled(record?.referenceType)) return 'Bitte eine Bezugsart auswählen.';
  if (!isFilled(record?.referenceNumber)) return 'Bitte eine Bezugsnummer hinterlegen.';
  const ratings = record?.ratings || {};
  const ratingValues = Object.values(ratings);
  if (ratingValues.some((value) => value != null && (!Number.isFinite(value) || value < 1 || value > 6))) {
    return 'Bewertungen müssen zwischen 1 und 6 liegen oder leer bleiben.';
  }
  return null;
}

function normalizeRatings(input, ratingSchemaVersion = 3) {
  const ratings = {
    communication: null,
    quality: null,
    delivery: null,
    price: null,
    quantity: null,
    backorders: null,
  };
  const mapLegacyScore = (value, maxValue) => {
    if (!Number.isFinite(value)) return null;
    if (maxValue <= 4) {
      if (value <= 1) return 1;
      if (value === 2) return 2;
      if (value === 3) return 4;
      return 6;
    }
    if (maxValue === 5) {
      if (value <= 1) return 1;
      if (value === 2) return 2;
      if (value === 3) return 3;
      if (value === 4) return 5;
      return 6;
    }
    if (value < 1) return 1;
    if (value > 6) return 6;
    return value;
  };
  const mapScore = (value, maxValue) => {
    if (!Number.isFinite(value)) return null;
    if (ratingSchemaVersion < 3) {
      return mapLegacyScore(value, maxValue);
    }
    if (value < 1) return 1;
    if (value > 6) return 6;
    return value;
  };
  const rawValues = [];
  if (input && typeof input === 'object') {
    Object.entries(input).forEach(([key, value]) => {
      if (!key) return;
      if (!(key in ratings)) return;
      if (value == null || value === '') {
        ratings[key] = null;
        return;
      }
      const parsed = Number(value);
      if (Number.isFinite(parsed)) rawValues.push(parsed);
      ratings[key] = parsed;
    });
  }
  const maxValue = rawValues.length ? Math.max(...rawValues) : 0;
  Object.keys(ratings).forEach((key) => {
    if (!Number.isFinite(ratings[key])) return;
    ratings[key] = mapScore(ratings[key], maxValue);
  });
  return ratings;
}

function mapCategoryKey(name = '') {
  const value = String(name).toLowerCase();
  if (value.includes('kommunik')) return 'communication';
  if (value.includes('qualität') || value.includes('qualitaet')) return 'quality';
  if (value.includes('lieferfrist') || value.includes('termin') || value.includes('liefer')) return 'delivery';
  if (value.includes('preis')) return 'price';
  if (value.includes('menge') || value.includes('produkt')) return 'quantity';
  if (value.includes('nachliefer')) return 'backorders';
  return 'communication';
}

function normalizeRatingsNa(ratingsNa = {}, communicationNa = false) {
  const normalized = {
    communication: false,
    quality: false,
    delivery: false,
    price: false,
    quantity: false,
    backorders: false,
  };
  if (ratingsNa && typeof ratingsNa === 'object') {
    Object.entries(ratingsNa).forEach(([key, value]) => {
      if (!(key in normalized)) return;
      normalized[key] = value === true;
    });
  }
  if (communicationNa === true) {
    normalized.communication = true;
  }
  return normalized;
}

function entryPoints(entry, config) {
  const weights = {
    communication: 0.1,
    quality: 0.3,
    delivery: 0.15,
    price: 0.15,
    quantity: 0.2,
    backorders: 0.1,
  };
  const ratings = normalizeRatings(entry?.ratings, entry?.ratingSchemaVersion || 3);
  const ratingsNa = normalizeRatingsNa(entry?.ratingsNa, entry?.communicationNa === true);
  let total = 0;
  let weightTotal = 0;
  for (const [key, weight] of Object.entries(weights)) {
    const value = ratings[key];
    if (ratingsNa?.[key] === true) {
      continue;
    }
    if (!Number.isFinite(value)) return null;
    total += value * weight;
    weightTotal += weight;
  }
  if (!weightTotal) return null;
  return Number((total / weightTotal).toFixed(2));
}

function computeStatus(ratings = {}, ratingsNa = {}, ratingSchemaVersion = 3) {
  const normalized = normalizeRatings(ratings, ratingSchemaVersion);
  const values = Object.entries(normalized).filter(([key, value]) => {
    if (ratingsNa?.[key] === true) return true;
    return Number.isFinite(value);
  });
  if (values.length === 0) return 'OFFEN';
  if (values.length === Object.keys(normalized).length) return 'ABGESCHLOSSEN';
  return 'IN_BEARBEITUNG';
}

function applyReferenceFields(record = {}) {
  const reference = record.reference && typeof record.reference === 'object' ? record.reference : {};
  return {
    ...record,
    referenceType: record.referenceType != null ? record.referenceType : reference.referenceType || '',
    referenceNumber:
      record.referenceNumber != null ? record.referenceNumber : reference.referenceNumber || record.reference || '',
  };
}

async function maybeCreateTrendEscalation(entry, actor) {
  const config = await supplierEvalConfigGet();
  const windowDays = Number(config?.trend?.windowDays || 90);
  const minEntries = Number(config?.trend?.minEntries || 3);
  const threshold = Number(config?.thresholds?.escalationScore || 0);
  if (!threshold || windowDays <= 0) return;

  const since = Date.now() - windowDays * 24 * 60 * 60 * 1000;
  const allEntries = await supplierPerformanceAll({ supplierId: entry.supplierId });
  const relevant = allEntries.filter((e) => e.includeInAnnual && e.date >= since && e.status !== 'cancelled');
  if (relevant.length < minEntries) return;

  const scored = relevant
    .map((e) => entryPoints(e, config))
    .filter((p) => Number.isFinite(p));
  if (scored.length < minEntries) return;

  const avg = scored.reduce((sum, value) => sum + value, 0) / scored.length;
  if (avg >= threshold) return;

  const existing = await supplierEscalationAll({ supplierId: entry.supplierId });
  const recentOpen = existing.find(
    (e) => e.trigger === 'trend' && e.status !== 'abgeschlossen' && (Date.now() - e.createdAt) < 14 * 24 * 60 * 60 * 1000
  );
  if (recentOpen) return;

  await supplierEscalationSave({
    supplierId: entry.supplierId,
    trigger: 'trend',
    reason: `Trend unter Schwelle (${avg.toFixed(2)}) in den letzten ${windowDays} Tagen.`,
    severity: 'mittel',
    status: 'offen',
    createdAt: Date.now(),
    createdBy: actor.email,
    updatedBy: actor.email,
    history: [
      { action: 'created', actor: actor.email, at: Date.now(), note: 'Automatische Eskalation (Trend)' },
    ],
  });
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
      const includeDeleted = req.query?.includeDeleted === 'true';
      if (id) {
        const entry = await supplierPerformanceGet(id);
        if (!entry) return bad(res, 'Eintrag nicht gefunden.', 404);
        return ok(res, { ok: true, entry });
      }
      const list = await supplierPerformanceAll({ supplierId, includeDeleted });
      return ok(res, { ok: true, list });
    }

    if (req.method === 'POST') {
      const body = readJson(req) || {};
      const ratingSchemaVersion = Number(body?.ratingSchemaVersion || 3);
      const ratingsNa = normalizeRatingsNa(body?.ratingsNa, body?.communicationNa === true);
      const ratings = normalizeRatings(body.ratings, ratingSchemaVersion);
      const computedScore = entryPoints({ ratings, ratingsNa, ratingSchemaVersion }, {});
      const payload = {
        ...applyReferenceFields(body),
        ratings,
        ratingsNa,
        communicationNa: ratingsNa.communication,
        ratingSchemaVersion: ratingSchemaVersion >= 3 ? 3 : ratingSchemaVersion >= 2 ? 2 : 1,
        computedGrade: computedScore,
        computedScore,
        computedAt: computedScore != null ? Date.now() : null,
        status: computeStatus(ratings, ratingsNa, ratingSchemaVersion),
        createdAt: body?.createdAt || Date.now(),
        createdBy: actor.email,
        updatedBy: actor.email,
        history: [
          ...(Array.isArray(body?.history) ? body.history : []),
          { action: 'created', actor: actor.email, at: Date.now(), note: 'Performance-Eintrag erstellt' },
        ],
      };
      const err = validateEntry(payload);
      if (err) return bad(res, err, 400);
      const saved = await supplierPerformanceSave(payload);
      console.info('[supplier-performance] created', { entryId: saved.id, supplierId: saved.supplierId });
      await maybeCreateTrendEscalation(saved, actor);
      return ok(res, { ok: true, entry: saved });
    }

    if (req.method === 'PATCH') {
      const { id } = req.query || {};
      if (!id) return bad(res, 'Entry-ID fehlt.', 400);
      const current = await supplierPerformanceGet(id);
      if (!current) return bad(res, 'Eintrag nicht gefunden.', 404);
      const body = readJson(req) || {};
      const config = await supplierEvalConfigGet();
      const editDays = Number(config?.editRules?.entryEditDays || 0);
      const ageDays = (Date.now() - current.date) / (24 * 60 * 60 * 1000);
      if (editDays > 0 && ageDays > editDays && !isFilled(body.changeReason)) {
        return bad(res, `Bitte einen Änderungsgrund angeben (Eintrag älter als ${editDays} Tage).`, 400);
      }
      const historyEntry = {
        action: 'updated',
        actor: actor.email,
        at: Date.now(),
        note: isFilled(body.changeReason) ? String(body.changeReason).trim() : 'Performance-Eintrag aktualisiert',
      };
      const draft = {
        ...current,
        ...body,
      };
      const withReference = applyReferenceFields(draft);
      const ratingSchemaVersion = Number(draft?.ratingSchemaVersion || current.ratingSchemaVersion || 3);
      const ratingsNa = normalizeRatingsNa(draft?.ratingsNa, draft?.communicationNa === true);
      const nextRatings = normalizeRatings(draft.ratings ?? current.ratings, ratingSchemaVersion);
      const computedScore = entryPoints({ ratings: nextRatings, ratingsNa, ratingSchemaVersion }, {});
      const merged = {
        ...withReference,
        ratings: nextRatings,
        ratingsNa,
        communicationNa: ratingsNa.communication,
        ratingSchemaVersion: ratingSchemaVersion >= 3 ? 3 : ratingSchemaVersion >= 2 ? 2 : 1,
        computedGrade: computedScore,
        computedScore,
        computedAt: computedScore != null ? Date.now() : null,
        status: computeStatus(nextRatings, ratingsNa, ratingSchemaVersion),
        updatedBy: actor.email,
        updatedAt: Date.now(),
        history: [...(current.history || []), historyEntry],
      };
      const err = validateEntry(merged);
      if (err) return bad(res, err, 400);
      const saved = await supplierPerformanceUpdate(id, merged);
      console.info('[supplier-performance] updated', { entryId: saved.id, supplierId: saved.supplierId });
      await maybeCreateTrendEscalation(saved, actor);
      return ok(res, { ok: true, entry: saved });
    }

    if (req.method === 'DELETE') {
      const { id } = req.query || {};
      if (!id) return bad(res, 'Entry-ID fehlt.', 400);
      const current = await supplierPerformanceGet(id);
      if (!current) return bad(res, 'Eintrag nicht gefunden.', 404);
      const body = readJson(req) || {};
      if (!isFilled(body.deleteReason)) {
        return bad(res, 'Bitte eine Löschbegründung angeben.', 400);
      }
      const updated = await supplierPerformanceUpdate(id, {
        deletedAt: Date.now(),
        deletedBy: actor.email,
        deletedReason: body.deleteReason,
        updatedBy: actor.email,
        updatedAt: Date.now(),
        history: [...(current.history || []), { action: 'deleted', actor: actor.email, at: Date.now(), note: body.deleteReason }],
      });
      console.info('[supplier-performance] deleted', { entryId: updated.id, supplierId: updated.supplierId });
      return ok(res, { ok: true, entry: updated });
    }

    return methodNotAllowed(res, req.method, ['GET', 'POST', 'PATCH', 'DELETE']);
  } catch (err) {
    console.error('[admin/supplier-performance] failed', err);
    return bad(res, 'Performance-Eintrag konnte nicht verarbeitet werden.', 500);
  }
}
