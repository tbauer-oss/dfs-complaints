// /api/admin/capas.js – Verwaltung eigenständiger CAPA / 8D-Reports
export const config = { runtime: 'nodejs' };

import { handlePreflight, setCors, ok, bad, methodNotAllowed, readJson } from '../_lib/http.js';
import { requirePortalAccess } from './_guard.js';
import { capaAll, capaSave, capaUpdate, capaDelete, capaGet, nextCapaNumber } from '../_lib/store.js';

const CAPA_TILE = 'capaReports';

export default async function handler(req, res) {
  if (handlePreflight(req, res)) return;
  setCors(req, res);

  const wantsWrite = ['POST', 'PATCH', 'DELETE'].includes(req.method);
  const actor = await requirePortalAccess(req, res, { tile: CAPA_TILE, write: wantsWrite });
  if (!actor) return;

  try {
    if (req.method === 'GET') {
      const list = await capaAll();
      return ok(res, { ok: true, list });
    }

    if (req.method === 'POST') {
      const body = readJson(req) || {};
      const payload = { ...body, createdBy: actor.email, updatedBy: actor.email };
      if (!payload.capaNumber) payload.capaNumber = await nextCapaNumber();
      const saved = await capaSave(payload);
      return ok(res, { ok: true, report: saved });
    }

    if (req.method === 'PATCH') {
      const body = readJson(req) || {};
      if (!body.id && !body.capaNumber) return bad(res, 'id missing', 400);
      const updated = await capaUpdate(body.id || body.capaNumber, { ...body, updatedBy: actor.email });
      if (!updated) return bad(res, 'not found', 404);
      return ok(res, { ok: true, report: updated });
    }

    if (req.method === 'DELETE') {
      const body = readJson(req) || {};
      const id = body.id || req.query?.id;
      if (!id) return bad(res, 'id missing', 400);
      await capaDelete(id);
      return ok(res, { ok: true });
    }

    return methodNotAllowed(res);
  } catch (err) {
    console.error('[admin/capas] error', err);
    return bad(res, 'server error', 500);
  }
}
