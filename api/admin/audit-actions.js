// /api/admin/audit-actions.js – Maßnahmenplan & Wirksamkeitsprüfung
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
  auditActionAll,
  auditActionSave,
  auditActionUpdate,
  auditActionDelete,
  runWithAuditRedisContext,
} from '../_lib/store.js';

const TILE = AUDIT_TILE_ID;

function handleError(res, err) {
  console.error('[admin/audit-actions] error', err);
  return bad(res, err.message || 'server error', err.code === 'VALIDATION_ERROR' ? 400 : 500);
}

export default async function handler(req, res) {
  if (handlePreflight(req, res)) return;
  setCors(req, res);

  const wantsWrite = ['POST', 'PATCH', 'DELETE'].includes(req.method);
  const actor = await requirePortalAccess(req, res, { tile: TILE, write: wantsWrite, allowPrrc: true });
  if (!actor) return;

  const redisLogContext = { route: '/api/admin/audit-actions', method: req.method };

  return await runWithAuditRedisContext(redisLogContext, async () => {
    try {
      if (req.method === 'GET') {
        const filter = { auditId: req.query?.auditId, findingId: req.query?.findingId };
        const list = await auditActionAll(filter);
        const id = req.query?.id;
        if (id) {
          redisLogContext.auditId = redisLogContext.auditId || filter.auditId;
          const found = list.find((a) => a.id === id);
          if (!found) return bad(res, 'not found', 404);
          return ok(res, { ok: true, action: found });
        }
        return ok(res, { ok: true, list });
      }

      if (req.method === 'POST') {
        const body = readJson(req) || {};
        redisLogContext.auditId = redisLogContext.auditId || body.auditId;
        const saved = await auditActionSave({ ...body, updatedBy: actor.email });
        redisLogContext.auditId = redisLogContext.auditId || saved?.auditId;
        return ok(res, { ok: true, action: saved });
      }

      if (req.method === 'PATCH') {
        const body = readJson(req) || {};
        const id = body.id || req.query?.id;
        redisLogContext.auditId = redisLogContext.auditId || body.auditId;
        if (!id) return bad(res, 'id missing', 400);
        const updated = await auditActionUpdate(id, { ...body, updatedBy: actor.email });
        redisLogContext.auditId = redisLogContext.auditId || updated?.auditId;
        if (!updated) return bad(res, 'not found', 404);
        return ok(res, { ok: true, action: updated });
      }

      if (req.method === 'DELETE') {
        const id = req.query?.id;
        if (!id) return bad(res, 'id missing', 400);
        await auditActionDelete(id);
        return ok(res, { ok: true });
      }

      return methodNotAllowed(res);
    } catch (err) {
      return handleError(res, err);
    }
  });
}
