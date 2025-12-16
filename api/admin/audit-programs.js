// /api/admin/audit-programs.js – Auditprogramme (Jahresplanung)
export const config = { runtime: 'nodejs' };

import { setCors, ok, bad, methodNotAllowed, readJson } from '../_lib/http.js';
import { requirePortalAccess } from './_guard.js';
import {
  AUDIT_TILE_ID,
  auditProgramAll,
  auditProgramSave,
  auditProgramUpdate,
  auditProgramDelete,
  runWithAuditRedisContext,
} from '../_lib/store.js';

const TILE = AUDIT_TILE_ID;

function handleError(res, err) {
  console.error('[admin/audit-programs] error', err);
  return bad(res, err.message || 'server error', err.code === 'VALIDATION_ERROR' ? 400 : 500);
}

export default async function handler(req, res) {
  if (setCors(req, res)) return;

  const wantsWrite = ['POST', 'PATCH', 'DELETE'].includes(req.method);
  const actor = await requirePortalAccess(req, res, { tile: TILE, write: wantsWrite, allowPrrc: true });
  if (!actor) return;

  const redisLogContext = { route: '/api/admin/audit-programs', method: req.method };

  return await runWithAuditRedisContext(redisLogContext, async () => {
    try {
      if (req.method === 'GET') {
        const list = await auditProgramAll();
        const id = req.query?.id;
        if (id) {
          redisLogContext.auditId = id;
          const found = list.find((p) => p.id === id);
          if (!found) return bad(res, 'not found', 404);
          return ok(res, { ok: true, program: found });
        }
        return ok(res, { ok: true, list });
      }

      if (req.method === 'POST') {
        const body = readJson(req) || {};
        const saved = await auditProgramSave({ ...body, updatedBy: actor.email });
        redisLogContext.auditId = saved?.id;
        return ok(res, { ok: true, program: saved });
      }

      if (req.method === 'PATCH') {
        const body = readJson(req) || {};
        const id = body.id || req.query?.id;
        redisLogContext.auditId = id;
        if (!id) return bad(res, 'id missing', 400);
        const updated = await auditProgramUpdate(id, { ...body, updatedBy: actor.email });
        if (!updated) return bad(res, 'not found', 404);
        return ok(res, { ok: true, program: updated });
      }

      if (req.method === 'DELETE') {
        const id = req.query?.id;
        redisLogContext.auditId = id;
        if (!id) return bad(res, 'id missing', 400);
        await auditProgramDelete(id);
        return ok(res, { ok: true });
      }

      return methodNotAllowed(res);
    } catch (err) {
      return handleError(res, err);
    }
  });
}
