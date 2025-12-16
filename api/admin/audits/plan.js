// /api/admin/audits/plan.js – Auditplan lesen & speichern via ?id=...

import { handlePreflight, setCors, ok, bad, methodNotAllowed, readJson } from '../../_lib/http.js';
import { requirePortalAccess } from '../_guard.js';
import {
  AUDIT_TILE_ID,
  auditGet,
  auditPlanGet,
  auditPlanSave,
  runWithAuditRedisContext,
} from '../../_lib/store.js';

const TILE = AUDIT_TILE_ID;

function requestIdFrom(req) {
  return (
    req?.headers?.['x-vercel-id'] ||
    req?.headers?.['x-request-id'] ||
    req?.headers?.['x-amzn-trace-id'] ||
    req?.headers?.['x-cf-ray'] ||
    undefined
  );
}

function handleError(res, err, { status = 500 } = {}) {
  console.error('[admin/audits/plan] error', err);
  return bad(res, err.message || 'server error', status);
}

function resolveAuditId(req) {
  if (!req.query) req.query = {};
  if (req.query.auditId) {
    req.query.id = req.query.auditId;
    return req.query.auditId;
  }
  if (req.query.id) return req.query.id;

  if (req.url) {
    try {
      const fromPathMatch = req.url.match(/\/audits\/([^/]+)\/plan/i);
      if (fromPathMatch?.[1]) {
        req.query.id = fromPathMatch[1];
        return fromPathMatch[1];
      }

      const parsedUrl = new URL(req.url, 'http://localhost');
      const fromSearch = parsedUrl.searchParams.get('id');
      if (fromSearch) {
        req.query.id = fromSearch;
        return fromSearch;
      }
    } catch (_) {}
  }
  return undefined;
}

export default async function handler(req, res) {
  if (handlePreflight(req, res)) return;

  const wantsWrite = req.method === 'PUT' || req.method === 'PATCH';
  const actor = await requirePortalAccess(req, res, {
    tile: TILE,
    write: wantsWrite,
    allowPrrc: true,
  });
  if (!actor) return;

  const auditId = resolveAuditId(req);
  const reqId = requestIdFrom(req);
  console.info('[audit-plan] route hit', { requestId: reqId, auditId });
  if (!auditId) {
    return bad(res, 'id missing', 400, {
      details: [{ field: 'id', issue: 'required' }],
    });
  }

  return await runWithAuditRedisContext(
    { route: '/api/admin/audits/plan', method: req.method, auditId },
    async () => {
      try {
        const audit = await auditGet(auditId);
        if (!audit) return handleError(res, new Error('Audit not found'), { status: 404 });

        if (req.method === 'GET') {
          const planResult = await auditPlanGet(auditId);
          console.info('[audit-plan] read', {
            requestId: reqId,
            auditId,
            planKey: planResult.planKey,
            found: planResult.found,
          });
          if (!planResult.found) {
            res.statusCode = 404;
            return res.end(JSON.stringify({ message: 'Plan not found' }));
          }
          return ok(res, { ok: true, planEntries: planResult.planEntries });
        }

        if (req.method === 'PUT' || req.method === 'PATCH') {
          const body = readJson(req) || {};
          const entries = Array.isArray(body.planEntries || body.plan)
            ? body.planEntries || body.plan
            : [];
          const saved = await auditPlanSave(auditId, entries, {
            updatedBy: actor.email,
          });
          console.info('[audit-plan] saved', {
            requestId: reqId,
            auditId,
            planKey: saved.planKey,
            entries: Array.isArray(saved.planEntries) ? saved.planEntries.length : 0,
          });
          if (!saved.planEntries) return handleError(res, new Error('Audit not found'), { status: 404 });
          return ok(res, { ok: true, planEntries: saved.planEntries });
        }

        return methodNotAllowed(res);
      } catch (err) {
        return handleError(res, err);
      }
    }
  );
}
