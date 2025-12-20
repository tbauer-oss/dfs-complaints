// /api/admin/supplier-performance.js – Laufende Lieferanten-Performance
export const config = { runtime: 'nodejs' };

import { handlePreflight, setCors, ok, bad, methodNotAllowed, readJson } from '../_lib/http.js';
import { requirePortalAccess } from './_guard.js';
import {
  supplierPerformanceAll,
  supplierPerformanceGet,
  supplierPerformanceSave,
  supplierPerformanceUpdate,
  supplierPerformanceDelete,
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
  if (!isFilled(record?.type)) return 'Bitte einen Typ auswählen.';
  if (!isFilled(record?.rating)) return 'Bitte eine Bewertung auswählen.';
  if (!isFilled(record?.description)) return 'Bitte eine Kurzbeschreibung hinterlegen.';
  return null;
}

function entryPoints(entry, config) {
  const categories = Array.isArray(config?.categories) ? config.categories : [];
  const category = categories.find((c) => c.name === entry.type) || categories[0];
  const scoreMap = category?.scoreMap || {};
  const numeric = Number(scoreMap[entry.rating]);
  return Number.isFinite(numeric) ? numeric : null;
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
      if (id) {
        const entry = await supplierPerformanceGet(id);
        if (!entry) return bad(res, 'Eintrag nicht gefunden.', 404);
        return ok(res, { ok: true, entry });
      }
      const list = await supplierPerformanceAll({ supplierId });
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
          { action: 'created', actor: actor.email, at: Date.now(), note: 'Performance-Eintrag erstellt' },
        ],
      };
      const err = validateEntry(payload);
      if (err) return bad(res, err, 400);
      const saved = await supplierPerformanceSave(payload);
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
      const merged = {
        ...current,
        ...body,
        updatedBy: actor.email,
        updatedAt: Date.now(),
        history: [...(current.history || []), historyEntry],
      };
      const err = validateEntry(merged);
      if (err) return bad(res, err, 400);
      const saved = await supplierPerformanceUpdate(id, merged);
      await maybeCreateTrendEscalation(saved, actor);
      return ok(res, { ok: true, entry: saved });
    }

    if (req.method === 'DELETE') {
      const { id } = req.query || {};
      if (!id) return bad(res, 'Entry-ID fehlt.', 400);
      const current = await supplierPerformanceGet(id);
      if (!current) return bad(res, 'Eintrag nicht gefunden.', 404);
      if (current.status === 'final') {
        const body = readJson(req) || {};
        if (!isFilled(body.cancelReason)) {
          return bad(res, 'Bitte eine Stornierungsbegründung angeben.', 400);
        }
        const updated = await supplierPerformanceUpdate(id, {
          status: 'cancelled',
          cancelReason: body.cancelReason,
          updatedBy: actor.email,
          updatedAt: Date.now(),
          history: [...(current.history || []), { action: 'cancelled', actor: actor.email, at: Date.now(), note: body.cancelReason }],
        });
        return ok(res, { ok: true, entry: updated });
      }
      await supplierPerformanceDelete(id);
      return ok(res, { ok: true });
    }

    return methodNotAllowed(res, req.method, ['GET', 'POST', 'PATCH', 'DELETE']);
  } catch (err) {
    console.error('[admin/supplier-performance] failed', err);
    return bad(res, 'Performance-Eintrag konnte nicht verarbeitet werden.', 500);
  }
}
