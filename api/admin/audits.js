// /api/admin/audits.js – Auditplanung & Durchführung
export const config = { runtime: 'nodejs' };

import {
  handlePreflight,
  setCors,
  ok,
  bad,
  methodNotAllowed,
  readJson,
} from '../_lib/http.js';
import { requirePortalAccess } from './_guard.js';
import {
  AUDIT_TILE_ID,
  auditAll,
  auditGet,
  auditSave,
  auditUpdate,
  auditDelete,
} from '../_lib/store.js';

const TILE = AUDIT_TILE_ID;

function handleError(res, err) {
  console.error('[admin/audits] error', err);
  return bad(res, err.message || 'server error', err.code === 'VALIDATION_ERROR' ? 400 : 500);
}

export default async function handler(req, res) {
  if (handlePreflight(req, res)) return;
  setCors(req, res);

  const wantsWrite = ['POST', 'PATCH', 'DELETE'].includes(req.method);
  const actor = await requirePortalAccess(req, res, { tile: TILE, write: wantsWrite, allowPrrc: true });
  if (!actor) return;

  try {
    if (req.method === 'GET') {
      const filter = {
        year: req.query?.year,
        quarter: req.query?.quarter,
        status: req.query?.status,
        orgUnit: req.query?.orgUnit,
        leadAuditorId: req.query?.leadAuditorId,
        from: req.query?.from,
        to: req.query?.to,
      };
      const list = await auditAll(filter);
      const id = req.query?.id;
      if (id) {
        const found = list.find((p) => p.id === id) || (await auditGet(id));
        if (!found) return bad(res, 'not found', 404);
        return ok(res, { ok: true, audit: found });
      }
      return ok(res, { ok: true, list });
    }

    if (req.method === 'POST') {
      const body = readJson(req) || {};
      console.log('[admin/audits] create', { actor: actor.email, body });
      const saved = await auditSave({ ...body, updatedBy: actor.email });
      return ok(res, { ok: true, audit: saved });
    }

    if (req.method === 'PATCH') {
      const body = readJson(req) || {};
      const id = body.id || req.query?.id;
      if (!id) return bad(res, 'id missing', 400);
      console.log('[admin/audits] update', { actor: actor.email, id, body });
      const updated = await auditUpdate(id, { ...body, updatedBy: actor.email });
      if (!updated) return bad(res, 'not found', 404);
      return ok(res, { ok: true, audit: updated });
    }

    if (req.method === 'DELETE') {
      const id = req.query?.id;
      if (!id) return bad(res, 'id missing', 400);
      await auditDelete(id);
      return ok(res, { ok: true });
    }

    return methodNotAllowed(res);
  } catch (err) {
    return handleError(res, err);
  }
}
