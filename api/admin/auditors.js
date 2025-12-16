// /api/admin/auditors.js – Auditorenverwaltung & Matrix
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
  auditorAll,
  auditorSave,
  auditorUpdate,
  auditorDelete,
  runWithAuditRedisContext,
} from '../_lib/store.js';

const TILE = AUDIT_TILE_ID;

function handleError(res, err) {
  console.error('[admin/auditors] error', err);
  const status =
    err.code === 'VALIDATION_ERROR'
      ? 400
      : err.code === 'REFERENCED'
          ? 409
          : 500;
  return bad(res, err.message || 'server error', status);
}

export default async function handler(req, res) {
  if (handlePreflight(req, res)) return;
  setCors(req, res);

  const wantsWrite = ['POST', 'PATCH', 'DELETE'].includes(req.method);
  const actor = await requirePortalAccess(req, res, { tile: TILE, write: wantsWrite, allowPrrc: true });
  if (!actor) return;

  const redisLogContext = { route: '/api/admin/auditors', method: req.method };

  return await runWithAuditRedisContext(redisLogContext, async () => {
    try {
      if (req.method === 'GET') {
        const list = await auditorAll();
        const id = req.query?.id;
        if (id) {
          const found = list.find((p) => p.id === id);
          if (!found) return bad(res, 'not found', 404);
          return ok(res, { ok: true, auditor: found });
        }
        return ok(res, { ok: true, list });
      }

      if (req.method === 'POST') {
        const body = readJson(req) || {};
        console.log('[admin/auditors] create', { actor: actor.email, body });
        const saved = await auditorSave({ ...body, updatedBy: actor.email }, { persist: true });
        redisLogContext.auditId = saved?.id;
        return ok(res, { ok: true, auditor: saved });
      }

      if (req.method === 'PATCH') {
        const body = readJson(req) || {};
        const id = body.id || req.query?.id;
        redisLogContext.auditId = id;
        if (!id) return bad(res, 'id missing', 400);
        console.log('[admin/auditors] update', { actor: actor.email, id, body });
        const updated = await auditorUpdate(id, { ...body, updatedBy: actor.email }, { persist: true });
        if (!updated) return bad(res, 'not found', 404);
        return ok(res, { ok: true, auditor: updated });
      }

      if (req.method === 'DELETE') {
        const id = req.query?.id;
        redisLogContext.auditId = id;
        if (!id) return bad(res, 'id missing', 400);
        await auditorDelete(id, { persist: true });
        return ok(res, { ok: true });
      }

      return methodNotAllowed(res);
    } catch (err) {
      return handleError(res, err);
    }
  });
}
