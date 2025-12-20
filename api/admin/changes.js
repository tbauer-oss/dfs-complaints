// /api/admin/changes.js – Verwaltung Change Management
export const config = { runtime: 'nodejs' };

import { handlePreflight, setCors, ok, bad, methodNotAllowed, readJson } from '../_lib/http.js';
import { requirePortalAccess } from './_guard.js';
import { changeAll, changeSave, changeUpdate, changeDelete, changeGet, nextChangeNumber } from '../_lib/store.js';

const CHANGE_TILE = 'changeManagement';

const REQUIRED_FIELDS = ['title', 'description', 'justification', 'changeType'];
const ASSESSMENT_FIELDS = [
  'productImpact',
  'documentationImpact',
  'processImpact',
  'regulatoryImpact',
  'safetyRelevance',
  'riskChange',
  'furtherAnalysis',
];
const DECISION_FIELDS = ['decision', 'followUps', 'followUpLink', 'decisionNote'];
const IMPLEMENTATION_FIELDS = ['implementationOwner', 'plannedDate', 'implementedAt', 'implemented', 'documentsUpdated', 'status'];

function isFilled(value) {
  if (value == null) return false;
  if (Array.isArray(value)) return value.length > 0;
  return String(value).trim().length > 0;
}

function validateChange(record) {
  const missing = REQUIRED_FIELDS.filter((field) => !isFilled(record?.[field]));
  if (missing.length > 0) return `missing fields: ${missing.join(', ')}`;

  if (record?.furtherAnalysis === 'yes') {
    if (record?.decision !== 'furtherEvaluation') {
      return 'decision must be furtherEvaluation when furtherAnalysis is yes';
    }
    if (!Array.isArray(record?.followUps) || record.followUps.length === 0) {
      return 'followUps required when furtherAnalysis is yes';
    }
  }

  if (record?.decision === 'furtherEvaluation') {
    if (!Array.isArray(record?.followUps) || record.followUps.length === 0) {
      return 'followUps required when decision is furtherEvaluation';
    }
  }

  if (record?.status && record.status !== 'open') {
    if (!isFilled(record?.implementationOwner) || !isFilled(record?.plannedDate)) {
      return 'implementationOwner and plannedDate required for in-progress changes';
    }
  }

  if (record?.status === 'closed') {
    if (!record?.implementedAt || record?.implemented !== true) {
      return 'implementedAt and implemented required for closed changes';
    }
  }

  return null;
}

function detectChangedFields(current, next, fields) {
  return fields.filter((field) => {
    const prev = current?.[field];
    const value = next?.[field];
    if (Array.isArray(prev) || Array.isArray(value)) {
      return JSON.stringify(prev || []) !== JSON.stringify(value || []);
    }
    return prev !== value;
  });
}

export default async function handler(req, res) {
  if (handlePreflight(req, res)) return;
  setCors(req, res);

  const wantsWrite = ['POST', 'PATCH', 'DELETE'].includes(req.method);
  const actor = await requirePortalAccess(req, res, { tile: CHANGE_TILE, write: wantsWrite });
  if (!actor) return;

  try {
    if (req.method === 'GET') {
      const { id, changeId, summary } = req.query || {};
      if (id || changeId) {
        const record = await changeGet(id || changeId);
        if (!record) return bad(res, 'not found', 404);
        return ok(res, { ok: true, record });
      }
      const list = await changeAll();
      if (summary) {
        const open = list.filter((c) => c.status === 'open').length;
        const closed = list.filter((c) => c.status === 'closed').length;
        const escalated = list.filter((c) => c.furtherAnalysis === 'yes' || c.decision === 'furtherEvaluation').length;
        return ok(res, { ok: true, summary: { open, closed, escalated, total: list.length } });
      }
      return ok(res, { ok: true, list });
    }

    if (req.method === 'POST') {
      const body = readJson(req) || {};
      const payload = {
        ...body,
        createdBy: actor.email,
        updatedBy: actor.email,
        initiator: body?.initiator || actor.displayName || actor.email,
        createdAt: body?.createdAt || Date.now(),
      };
      if (!payload.changeId) payload.changeId = await nextChangeNumber();
      payload.history = [
        ...(Array.isArray(body?.history) ? body.history : []),
        { action: 'created', actor: actor.email, at: Date.now(), note: 'Change erstellt' },
      ];
      const err = validateChange(payload);
      if (err) return bad(res, err, 400);
      const saved = await changeSave(payload);
      return ok(res, { ok: true, record: saved });
    }

    if (req.method === 'PATCH') {
      const body = readJson(req) || {};
      const id = body.id || body.changeId || req.query?.id || req.query?.changeId;
      if (!id) return bad(res, 'id missing', 400);
      const current = await changeGet(id);
      if (!current) return bad(res, 'not found', 404);
      const now = Date.now();
      const patch = { ...body, updatedBy: actor.email, updatedAt: now };
      const next = { ...current, ...patch };

      const assessmentChanged = detectChangedFields(current, next, ASSESSMENT_FIELDS);
      if (assessmentChanged.length > 0) {
        if (!patch.evaluator) patch.evaluator = current.evaluator || actor.email;
        if (!patch.evaluatedAt) patch.evaluatedAt = now;
      }

      const decisionChanged = detectChangedFields(current, next, DECISION_FIELDS);
      if (decisionChanged.length > 0) {
        if (!patch.decisionBy) patch.decisionBy = current.decisionBy || actor.email;
        if (next.decision && !patch.decisionAt) patch.decisionAt = now;
      }

      const implementationChanged = detectChangedFields(current, next, IMPLEMENTATION_FIELDS);
      if (implementationChanged.length > 0) {
        if (!patch.implementationBy) patch.implementationBy = current.implementationBy || actor.email;
        if (next.implemented === true && !patch.implementedAt) patch.implementedAt = now;
      }

      const updated = { ...current, ...patch };
      const err = validateChange(updated);
      if (err) return bad(res, err, 400);

      const history = [
        ...(current.history || []),
      ];
      if (assessmentChanged.length > 0) {
        history.push({ action: 'assessment', actor: actor.email, at: now, fields: assessmentChanged });
      }
      if (decisionChanged.length > 0) {
        history.push({ action: 'decision', actor: actor.email, at: now, fields: decisionChanged });
      }
      if (implementationChanged.length > 0) {
        history.push({ action: 'implementation', actor: actor.email, at: now, fields: implementationChanged });
      }
      if (current.status !== updated.status) {
        history.push({ action: 'status', actor: actor.email, at: now, fields: ['status'] });
      }
      updated.history = history;

      const saved = await changeUpdate(id, updated);
      return ok(res, { ok: true, record: saved });
    }

    if (req.method === 'DELETE') {
      const body = readJson(req) || {};
      const id = body.id || req.query?.id;
      if (!id) return bad(res, 'id missing', 400);
      await changeDelete(id);
      return ok(res, { ok: true });
    }

    return methodNotAllowed(res);
  } catch (err) {
    console.error('[admin/changes] error', err);
    return bad(res, 'server error', 500);
  }
}
