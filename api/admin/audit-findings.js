// /api/admin/audit-findings.js – Auditfeststellungen & Verknüpfungen
export const config = { runtime: 'nodejs' };

import { setCors, ok, bad, methodNotAllowed, readJson } from '../_lib/http.js';
import { requirePortalAccess } from './_guard.js';
import {
  AUDIT_TILE_ID,
  auditFindingAll,
  auditFindingSave,
  auditFindingUpdate,
  auditFindingDelete,
  runWithAuditRedisContext,
} from '../_lib/store.js';

const TILE = AUDIT_TILE_ID;

function handleError(res, err) {
  console.error('[admin/audit-findings] error', err);
  return bad(res, err.message || 'server error', err.code === 'VALIDATION_ERROR' ? 400 : 500);
}

export default async function handler(req, res) {
  if (setCors(req, res)) return;

  const wantsWrite = ['POST', 'PATCH', 'DELETE'].includes(req.method);
  const actor = await requirePortalAccess(req, res, { tile: TILE, write: wantsWrite, allowPrrc: true });
  if (!actor) return;

  const redisLogContext = { route: '/api/admin/audit-findings', method: req.method };

  return await runWithAuditRedisContext(redisLogContext, async () => {
    try {
      if (req.method === 'GET') {
        const filter = { auditId: req.query?.auditId };
        const list = await auditFindingAll(filter);
        const id = req.query?.id;
        if (id) {
          redisLogContext.auditId = redisLogContext.auditId || filter.auditId;
          const found = list.find((f) => f.id === id);
          if (!found) return bad(res, 'not found', 404);
          return ok(res, { ok: true, finding: found });
        }
        return ok(res, { ok: true, list });
      }

      if (req.method === 'POST') {
        const body = readJson(req) || {};
        redisLogContext.auditId = redisLogContext.auditId || body.auditId;
        const saved = await auditFindingSave({ ...body, updatedBy: actor.email });
        redisLogContext.auditId = redisLogContext.auditId || saved?.auditId;
        return ok(res, { ok: true, finding: saved });
      }

      if (req.method === 'PATCH') {
        const body = readJson(req) || {};
        const id = body.id || req.query?.id;
        redisLogContext.auditId = redisLogContext.auditId || body.auditId;
        if (!id) return bad(res, 'id missing', 400);
        const updated = await auditFindingUpdate(id, { ...body, updatedBy: actor.email });
        redisLogContext.auditId = redisLogContext.auditId || updated?.auditId;
        if (!updated) return bad(res, 'not found', 404);
        return ok(res, { ok: true, finding: updated });
      }

      if (req.method === 'DELETE') {
        const id = req.query?.id;
        if (!id) return bad(res, 'id missing', 400);
        await auditFindingDelete(id);
        return ok(res, { ok: true });
      }

      return methodNotAllowed(res);
    } catch (err) {
      return handleError(res, err);
    }
  });
}
