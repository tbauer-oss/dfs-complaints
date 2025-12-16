import crypto from 'node:crypto';

import { handlePreflight, setCors, ok, bad, methodNotAllowed, readJson } from '../_lib/http.js';
import { requirePortalAccess } from './_guard.js';
import {
  AUDIT_TILE_ID,
  auditDeleteUnindexed,
  auditFindUnindexed,
  runWithAuditRedisContext,
} from '../_lib/store.js';

const TILE = AUDIT_TILE_ID;

function handleError(res, err, { requestId } = {}) {
  const status = err.code === 'VALIDATION_ERROR' ? 400 : err.statusCode || 500;
  console.error('[admin/audits-cleanup] error', { requestId, status, message: err?.message });
  return bad(res, err.message || 'server error', status, requestId ? { requestId } : undefined);
}

export default async function handler(req, res) {
  if (handlePreflight(req, res)) return;
  setCors(req, res);

  const requestId = req.headers?.['x-request-id'] || req.headers?.['x-vercel-id'] || crypto.randomUUID();
  const wantsWrite = req.method === 'POST';
  const actor = await requirePortalAccess(req, res, { tile: TILE, write: wantsWrite, allowPrrc: true });
  if (!actor) return;

  const redisLogContext = { route: '/api/admin/audits-cleanup', method: req.method };

  return await runWithAuditRedisContext(redisLogContext, async () => {
    try {
      if (req.method === 'GET') {
        const unindexedIds = await auditFindUnindexed();
        return ok(res, { ok: true, unindexedIds, count: unindexedIds.length, requestId });
      }

      if (req.method === 'POST') {
        const body = readJson(req) || {};
        const dryRun = body.dryRun !== false;
        const result = await auditDeleteUnindexed({ dryRun });
        console.info('[admin/audits-cleanup] delete', { requestId, dryRun, removed: result.removed?.length });
        return ok(res, { ok: true, ...result, requestId });
      }

      return methodNotAllowed(res);
    } catch (err) {
      return handleError(res, err, { requestId });
    }
  });
}
