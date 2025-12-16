// /api/admin/audits/plan.js – Auditplan lesen & speichern via ?id=...
export const config = { runtime: 'nodejs' };

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

function handleError(res, err, { status = 500 } = {}) {
  console.error('[admin/audits/plan] error', err);
  return bad(res, err.message || 'server error', status);
}

function resolveAuditId(req) {
  if (!req.query) req.query = {};
  if (req.query.id) return req.query.id;

  if (req.url) {
    try {
      const parsedUrl = new URL(req.url, 'http://localhost');
      const fromSearch = parsedUrl.searchParams.get('id');
      if (fromSearch) {
        req.query.id = fromSearch;
        return fromSearch;
      }
    } catch (_) {
      /* ignore */
    }
  }

  return undefined;
}

export default async function handler(req, res) {
  if (handlePreflight(req, res)) return;
  setCors(req, res);

  const wantsWrite = req.method === 'PUT';
  const actor = await requirePortalAccess(req, res, { tile: TILE, write: wantsWrite, allowPrrc: true });
  if (!actor) return;

  const auditId = resolveAuditId(req);
  console.log('[audit-plan] route hit', auditId);
  if (!auditId) return bad(res, 'id missing', 400, { details: [{ field: 'id', issue: 'required' }] });

  return await runWithAuditRedisContext({ route: '/api/admin/audits/plan', method: req.method, auditId }, async () => {
    try {
      const audit = await auditGet(auditId);
      if (process.env.NODE_ENV !== 'production') {
        console.log('[admin/audits/plan] hit', {
          auditId,
          hasAudit: !!audit,
          hasPlan: Array.isArray(audit?.planEntries) && audit.planEntries.length > 0,
        });
      }

      if (!audit) return handleError(res, new Error('Audit not found'), { status: 404 });

      if (req.method === 'GET') {
        const planEntries = Array.isArray(audit?.planEntries) && audit.planEntries.length > 0
          ? audit.planEntries
          : await auditPlanGet(auditId);
        return ok(res, { ok: true, planEntries });
      }

      if (req.method === 'PUT') {
        const body = readJson(req) || {};
        const entries = Array.isArray(body.planEntries || body.plan) ? body.planEntries || body.plan : [];
        const saved = await auditPlanSave(auditId, entries, { updatedBy: actor.email });
        return ok(res, { ok: true, planEntries: saved });
      }

      return methodNotAllowed(res);
    } catch (err) {
      return handleError(res, err);
    }
  });
}
