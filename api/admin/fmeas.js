// /api/admin/fmeas.js – Verwaltung von FMEAs (Stammdaten ohne Risiko-Tabellen)
export const config = { runtime: 'nodejs' };

import { handlePreflight, setCors, ok, bad, methodNotAllowed, readJson } from '../_lib/http.js';
import { requirePortalAccess } from './_guard.js';
import { fmeaAll, fmeaSave, fmeaUpdate, fmeaDelete, fmeaGet } from '../_lib/store.js';

const FMEA_TILE = 'fmea';

export default async function handler(req, res) {
  if (handlePreflight(req, res)) return;
  setCors(req, res);

  const wantsWrite = ['POST', 'PATCH', 'DELETE'].includes(req.method);
  const actor = await requirePortalAccess(req, res, { tile: FMEA_TILE, write: wantsWrite });
  if (!actor) return;

  try {
    // ===== GET: Liste oder einzelne FMEA laden =====
    if (req.method === 'GET') {
      const id = req.query?.id;
      if (id) {
        const fmea = await fmeaGet(id);
        if (!fmea) return bad(res, 'not found', 404);
        return ok(res, { ok: true, fmea });
      }
      const list = await fmeaAll();
      return ok(res, { ok: true, list });
    }

    // ===== POST: Neue FMEA anlegen =====
    if (req.method === 'POST') {
      const body = readJson(req) || {};
      const payload = { ...body, createdBy: actor.email, updatedBy: actor.email };
      const saved = await fmeaSave(payload);
      return ok(res, { ok: true, fmea: saved });
    }

    // ===== PATCH: FMEA-Kopf aktualisieren =====
    if (req.method === 'PATCH') {
      const body = readJson(req) || {};
      const id = body.id || req.query?.id;
      if (!id) return bad(res, 'id missing', 400);
      const updated = await fmeaUpdate(id, { ...body, updatedBy: actor.email });
      if (!updated) return bad(res, 'not found', 404);
      return ok(res, { ok: true, fmea: updated });
    }

    // ===== DELETE: FMEA entfernen =====
    if (req.method === 'DELETE') {
      const body = readJson(req) || {};
      const id = body.id || req.query?.id;
      if (!id) return bad(res, 'id missing', 400);
      await fmeaDelete(id);
      return ok(res, { ok: true });
    }

    return methodNotAllowed(res);
  } catch (err) {
    console.error('[admin/fmeas] error', err);
    return bad(res, 'server error', 500);
  }
}
