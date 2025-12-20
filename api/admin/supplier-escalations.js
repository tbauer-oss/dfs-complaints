// /api/admin/supplier-escalations.js – Eskalationen Lieferanten
export const config = { runtime: 'nodejs' };

import { handlePreflight, setCors, ok, bad, methodNotAllowed, readJson } from '../_lib/http.js';
import { requirePortalAccess } from './_guard.js';
import {
  supplierEscalationAll,
  supplierEscalationGet,
  supplierEscalationSave,
  supplierEscalationUpdate,
  supplierEscalationDelete,
  supplierEvalConfigGet,
} from '../_lib/store.js';
import { sendMail } from '../_lib/mailer.js';

const SUPPLIER_TILE = 'supplierEvaluation';

function isFilled(value) {
  if (value == null) return false;
  if (Array.isArray(value)) return value.length > 0;
  return String(value).trim().length > 0;
}

function validateEscalation(record) {
  if (!isFilled(record?.supplierId)) return 'Bitte einen Lieferanten auswählen.';
  if (!isFilled(record?.trigger)) return 'Bitte einen Trigger angeben.';
  if (!isFilled(record?.reason)) return 'Bitte einen Grund angeben.';
  if (!isFilled(record?.severity)) return 'Bitte einen Schweregrad auswählen.';
  if (!isFilled(record?.status)) return 'Bitte einen Status auswählen.';
  return null;
}

function resolveNotificationRecipients(config) {
  const emails = Array.isArray(config?.notifications?.emails) ? config.notifications.emails : [];
  return emails.map((e) => String(e || '').toLowerCase()).filter(Boolean);
}

async function sendEscalationNotification(escalation) {
  const config = await supplierEvalConfigGet();
  const recipients = await resolveNotificationRecipients(config);
  if (recipients.length === 0) return;
  const subject = `Lieferanten-Eskalation: ${escalation.supplierId}`;
  const bodyLines = [
    `Lieferant: ${escalation.supplierId}`,
    `Trigger: ${escalation.trigger}`,
    `Grund: ${escalation.reason}`,
    `Status: ${escalation.status}`,
    `Schweregrad: ${escalation.severity}`,
  ];
  const text = bodyLines.join('\n');
  const html = bodyLines.map((line) => `<p>${line}</p>`).join('');
  try {
    await sendMail({ to: recipients, subject, text, html });
  } catch (err) {
    console.error('[admin/supplier-escalations] mail failed', err);
  }
}

export default async function handler(req, res) {
  if (handlePreflight(req, res)) return;
  setCors(req, res);

  const wantsWrite = ['POST', 'PATCH', 'DELETE'].includes(req.method);
  const actor = await requirePortalAccess(req, res, { tile: SUPPLIER_TILE, write: wantsWrite });
  if (!actor) return;

  try {
    if (req.method === 'GET') {
      const { id, supplierId } = req.query || {};
      if (id) {
        const escalation = await supplierEscalationGet(id);
        if (!escalation) return bad(res, 'Eskalation nicht gefunden.', 404);
        return ok(res, { ok: true, escalation });
      }
      const list = await supplierEscalationAll({ supplierId });
      return ok(res, { ok: true, list });
    }

    if (req.method === 'POST') {
      const body = readJson(req) || {};
      const payload = {
        ...body,
        createdAt: body?.createdAt || Date.now(),
        createdBy: actor.email,
        updatedBy: actor.email,
        history: [
          ...(Array.isArray(body?.history) ? body.history : []),
          { action: 'created', actor: actor.email, at: Date.now(), note: 'Eskalation erstellt' },
        ],
      };
      const err = validateEscalation(payload);
      if (err) return bad(res, err, 400);
      const saved = await supplierEscalationSave(payload);
      await sendEscalationNotification(saved);
      return ok(res, { ok: true, escalation: saved });
    }

    if (req.method === 'PATCH') {
      const { id } = req.query || {};
      if (!id) return bad(res, 'Eskalations-ID fehlt.', 400);
      const current = await supplierEscalationGet(id);
      if (!current) return bad(res, 'Eskalation nicht gefunden.', 404);
      const body = readJson(req) || {};
      const historyEntry = {
        action: 'updated',
        actor: actor.email,
        at: Date.now(),
        note: isFilled(body.changeReason) ? String(body.changeReason).trim() : 'Eskalation aktualisiert',
      };
      const merged = {
        ...current,
        ...body,
        updatedBy: actor.email,
        updatedAt: Date.now(),
        history: [...(current.history || []), historyEntry],
      };
      const err = validateEscalation(merged);
      if (err) return bad(res, err, 400);
      const saved = await supplierEscalationUpdate(id, merged);
      return ok(res, { ok: true, escalation: saved });
    }

    if (req.method === 'DELETE') {
      const { id } = req.query || {};
      if (!id) return bad(res, 'Eskalations-ID fehlt.', 400);
      await supplierEscalationDelete(id);
      return ok(res, { ok: true });
    }

    return methodNotAllowed(res, req.method, ['GET', 'POST', 'PATCH', 'DELETE']);
  } catch (err) {
    console.error('[admin/supplier-escalations] failed', err);
    return bad(res, 'Eskalation konnte nicht verarbeitet werden.', 500);
  }
}
