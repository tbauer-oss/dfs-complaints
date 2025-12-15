// /api/admin/audits.js – Auditplanung & Durchführung
export const config = { runtime: 'nodejs22.x' };

import crypto from 'node:crypto';

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

function handleError(res, err, { requestId } = {}) {
  const status = err.code === 'VALIDATION_ERROR' ? 400 : err.statusCode || 500;
  const details = Array.isArray(err.details) ? err.details : undefined;
  const payload = { ...(requestId ? { requestId } : {}), ...(details ? { details } : {}) };
  console.error('[admin/audits] error', {
    status,
    requestId,
    message: err?.message,
    details: details?.map?.(d => d?.issue || d?.message || d),
  });
  return bad(res, err.message || 'server error', status, payload);
}

export default async function handler(req, res) {
  if (handlePreflight(req, res)) return;
  setCors(req, res);

  const requestId = req.headers?.['x-request-id'] || req.headers?.['x-vercel-id'] || crypto.randomUUID();

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
        if (!found) return bad(res, 'not found', 404, { requestId });
        return ok(res, { ok: true, audit: found });
      }
      return ok(res, { ok: true, list });
    }

    if (req.method === 'POST') {
      const body = readJson(req) || {};
      console.log('[admin/audits] create', { actor: actor.email, requestId, fields: Object.keys(body || {}) });
      const saved = await auditSave({ ...body, updatedBy: actor.email });
      return ok(res, { ok: true, audit: saved, requestId });
    }

    if (req.method === 'PATCH') {
      const body = readJson(req) || {};
      const id = body.id || req.query?.id;
      if (!id)
        return bad(res, 'id missing', 400, { requestId, details: [{ field: 'id', issue: 'required' }] });
      console.log('[admin/audits] update', { actor: actor.email, id, requestId, fields: Object.keys(body || {}) });
      const updated = await auditUpdate(id, { ...body, updatedBy: actor.email });
      if (!updated) return bad(res, 'not found', 404, { requestId });
      return ok(res, { ok: true, audit: updated, requestId });
    }

    if (req.method === 'DELETE') {
      const id = req.query?.id;
      if (!id)
        return bad(res, 'id missing', 400, { requestId, details: [{ field: 'id', issue: 'required' }] });
      await auditDelete(id);
      return ok(res, { ok: true, requestId });
    }

    return methodNotAllowed(res);
  } catch (err) {
    return handleError(res, err, { requestId });
  }
}
