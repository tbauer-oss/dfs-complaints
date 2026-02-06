// /api/admin/changes.js – Verwaltung Change Management
export const config = { runtime: 'nodejs' };

import { handlePreflight, setCors, ok, bad, methodNotAllowed, readJson } from '../_lib/http.js';
import { requirePortalAccess } from './_guard.js';
import { changeAll, changeSave, changeUpdate, changeDelete, changeGet, nextChangeNumber, portalUsersList } from '../_lib/store.js';
import { sendMail } from '../_lib/mailer.js';
import { normalizeStatus } from '../_lib/portalAuth.js';

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
const PRRC_FIELDS = ['prrcDecision', 'prrcNote'];
const ESCALATION_FIELDS = ['followUps', 'fmeaId', 'fmeaStatus', 'capaId', 'capaStatus', 'affectedProcessOther'];
const APP_ORIGIN = (process.env.APP_ORIGIN || process.env.APP_BASE_URL || 'https://dfs-complaints-web.vercel.app').replace(
  /\/$/,
  ''
);

function isFilled(value) {
  if (value == null) return false;
  if (Array.isArray(value)) return value.length > 0;
  return String(value).trim().length > 0;
}

function validateChange(record) {
  const missing = REQUIRED_FIELDS.filter((field) => !isFilled(record?.[field]));
  if (missing.length > 0) return `missing fields: ${missing.join(', ')}`;

  if (Array.isArray(record?.affectedProcesses) && record.affectedProcesses.includes('Sonstiges')) {
    if (!isFilled(record?.affectedProcessOther)) {
      return 'affectedProcessOther required when affectedProcesses includes Sonstiges';
    }
  }

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

  const prrcRequired = Array.isArray(record?.followUps) && record.followUps.includes('prrc');
  if (prrcRequired && !isFilled(record?.prrcDecision)) {
    if (record?.status !== 'waitingPrrc') {
      return 'status must be waitingPrrc when PRRC decision is pending';
    }
  }
  if (record?.prrcDecision === 'rejected') {
    const hasEscalation = Array.isArray(record?.followUps)
      && record.followUps.some((f) => f === 'fmea' || f === 'capa');
    if (!hasEscalation) {
      return 'PRRC rejection requires escalation (fmea/capa)';
    }
  }

  const fmeaBlocked = Array.isArray(record?.followUps)
    && record.followUps.includes('fmea')
    && record?.fmeaStatus !== 'closed';
  const capaBlocked = Array.isArray(record?.followUps)
    && record.followUps.includes('capa')
    && record?.capaStatus !== 'closed';
  if ((fmeaBlocked || capaBlocked) && ['inProgress', 'closed'].includes(record?.status)) {
    return 'cannot continue or close while escalations are open';
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

async function resolvePrrcRecipients() {
  const fallback = 'tobias.bauer@dfs-diamon.de';
  try {
    const users = await portalUsersList();
    const prrcUsers = users.filter((u) => {
      const status = normalizeStatus(u.portalStatus, u.revoked);
      return status === 'active' && (u.isPRRC === true || u.isPrrc === true);
    });
    const recipients = prrcUsers.map((u) => String(u.email || '').toLowerCase()).filter(Boolean);
    return recipients.length > 0 ? recipients : [fallback];
  } catch (err) {
    console.warn('[admin/changes] PRRC lookup failed', err?.message || err);
    return [fallback];
  }
}

async function sendPrrcMail(record) {
  const to = await resolvePrrcRecipients();
  const changeId = record?.changeId || record?.id || '';
  const link = `${APP_ORIGIN}/admin`;
  const subject = `PRRC-Bewertung erforderlich: ${changeId}`;
  const bodyLines = [
    `Change-ID: ${changeId}`,
    `Titel: ${record?.title || '—'}`,
    `Begründung: ${record?.justification || '—'}`,
    `Link: ${link}`,
  ];
  const text = bodyLines.join('\n');
  const html = bodyLines.map((line) => `<p>${line}</p>`).join('');
  try {
    await sendMail({ to, subject, text, html });
  } catch (err) {
    console.error('[admin/changes] PRRC mail failed', err);
  }
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
      const followUps = Array.isArray(payload.followUps) ? payload.followUps : [];
      if (followUps.includes('prrc') && !payload.prrcDecision) {
        payload.status = 'waitingPrrc';
      }
      if (followUps.includes('fmea') && !payload.fmeaStatus) {
        payload.fmeaStatus = 'open';
      }
      if (followUps.includes('capa') && !payload.capaStatus) {
        payload.capaStatus = 'open';
      }
      payload.history = [
        ...(Array.isArray(body?.history) ? body.history : []),
        { action: 'created', actor: actor.email, at: Date.now(), note: 'Change erstellt' },
      ];
      const err = validateChange(payload);
      if (err) return bad(res, err, 400);
      const saved = await changeSave(payload);
      if (followUps.includes('prrc') && !payload.prrcDecision) {
        await sendPrrcMail(saved);
      }
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

      const prrcChanged = detectChangedFields(current, next, PRRC_FIELDS);
      if (prrcChanged.length > 0) {
        if (!patch.prrcBy) patch.prrcBy = current.prrcBy || actor.email;
        if (next.prrcDecision && !patch.prrcAt) patch.prrcAt = now;
      }

      const implementationChanged = detectChangedFields(current, next, IMPLEMENTATION_FIELDS);
      if (implementationChanged.length > 0) {
        if (!patch.implementationBy) patch.implementationBy = current.implementationBy || actor.email;
        if (next.implemented === true && !patch.implementedAt) patch.implementedAt = now;
      }

      const updated = { ...current, ...patch };
      const followUps = Array.isArray(updated.followUps) ? updated.followUps : [];
      const prrcRequired = followUps.includes('prrc');
      if (prrcRequired && !updated.prrcDecision) {
        updated.status = 'waitingPrrc';
      }
      if (!prrcRequired) {
        updated.prrcDecision = '';
        updated.prrcNote = '';
        updated.prrcBy = '';
        updated.prrcAt = null;
      }
      if (prrcRequired && updated.prrcDecision === 'approved' && updated.status === 'waitingPrrc') {
        updated.status = 'open';
      }
      if (followUps.includes('fmea') && !updated.fmeaStatus) {
        updated.fmeaStatus = 'open';
      }
      if (!followUps.includes('fmea')) {
        updated.fmeaStatus = '';
        updated.fmeaId = '';
      }
      if (followUps.includes('capa') && !updated.capaStatus) {
        updated.capaStatus = 'open';
      }
      if (!followUps.includes('capa')) {
        updated.capaStatus = '';
        updated.capaId = '';
      }
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
      if (prrcChanged.length > 0) {
        history.push({ action: 'prrc', actor: actor.email, at: now, fields: prrcChanged });
      }
      if (implementationChanged.length > 0) {
        history.push({ action: 'implementation', actor: actor.email, at: now, fields: implementationChanged });
      }
      const escalationChanged = detectChangedFields(current, updated, ESCALATION_FIELDS);
      if (escalationChanged.length > 0) {
        history.push({ action: 'escalation', actor: actor.email, at: now, fields: escalationChanged });
      }
      if (current.status !== updated.status) {
        history.push({ action: 'status', actor: actor.email, at: now, fields: ['status'] });
      }
      updated.history = history;

      const followUpsBefore = Array.isArray(current.followUps) ? current.followUps : [];
      if (!followUpsBefore.includes('prrc') && followUps.includes('prrc') && !updated.prrcDecision) {
        await sendPrrcMail(updated);
      }

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
