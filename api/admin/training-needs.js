// /api/admin/training-needs.js – Schulungsbedarfe (FB620)
export const config = { runtime: 'nodejs' };

import { handlePreflight, setCors, ok, bad, methodNotAllowed, readJson } from '../_lib/http.js';
import { requireTrainingNeedAccess } from './_guard.js';
import { PORTAL_ROLES, normalizeRole } from '../_lib/portalAuth.js';
import {
  trainingNeedsAll,
  trainingNeedGet,
  trainingNeedSave,
  trainingNeedUpdate,
  trainingNeedDelete,
} from '../_lib/store.js';
import { sendMail } from '../_lib/mailer.js';
import { normalizePeriodValue, periodYear, trim, validateTrainingNeed } from '../_lib/trainingValidation.js';

function plannedPeriodLabel(type, value) {
  if (!value) return '';
  if (type === 'date') return `Datum: ${value}`;
  if (type === 'month') return `Monat: ${value}`;
  if (type === 'quarter') {
    const [year, quarter] = value.split('-');
    return `Quartal: ${quarter} ${year}`;
  }
  if (type === 'halfYear') {
    const [year, half] = value.split('-');
    return `Halbjahr: ${half} ${year}`;
  }
  return value;
}

function escapeHtml(value) {
  return String(value || '')
    .replace(/&/g, '&amp;')
    .replace(/</g, '&lt;')
    .replace(/>/g, '&gt;')
    .replace(/"/g, '&quot;')
    .replace(/'/g, '&#39;');
}

function buildNeedEmailHtml({ need, resolvedDepartment, plannedPeriodLabelText, submittedBy, submittedAt }) {
  const rows = [];
  const addRow = (label, value) => {
    if (value === null || value === undefined || value === '') return;
    rows.push(
      `<tr><td style="padding:8px 12px;border:1px solid #2c2f3a;font-weight:600;color:#f5f5f5;background:#1f222b;">${escapeHtml(label)}</td>` +
        `<td style="padding:8px 12px;border:1px solid #2c2f3a;color:#e4e8f0;">${escapeHtml(value)}</td></tr>`
    );
  };

  const primaryItem = Array.isArray(need.items) && need.items.length > 0 ? need.items[0] : {};

  addRow('Schulungsjahr', need.year);
  addRow('Ansprechpartner', need.contactName);
  addRow('Abteilung/Team', resolvedDepartment);
  addRow('Schulungsthema', primaryItem?.topic || '');
  addRow('Geplanter Zeitraum', plannedPeriodLabelText);
  addRow('Geplanter Zeitraum (normalisiert)', need.plannedPeriodValue || '');
  addRow('Format', need.trainingFormat === 'praesenz' ? 'Präsenz' : need.trainingFormat === 'online' ? 'Online' : '');
  addRow('Schulungsintervall', need.intervalType === 'recurring' ? 'wiederkehrend' : 'einmalig');
  if (need.intervalType === 'recurring') {
    addRow('Intervall', need.intervalValue === 'Sonstiges...' ? need.intervalValueFreeText || '' : need.intervalValue || '');
  }
  addRow('Teilnehmer', primaryItem?.participants ?? '');
  addRow('Geplantes Budget', need.plannedBudget !== null && need.plannedBudget !== undefined ? `${need.plannedBudget} €` : '');
  addRow('Zusätzliche Hinweise / Kommentare', need.additionalNotes || '');
  addRow('Wichtige Themen / Fachgebiete', need.topicPriorities || '');
  addRow('Bevorzugte Trainer / Anbieter', need.preferredTrainers || '');
  addRow('Besondere Anforderungen', need.specialRequirements || '');
  addRow('Eingereicht von', submittedBy || '');
  addRow('Zeitpunkt', submittedAt || '');

  return `
    <div style="font-family:Arial, sans-serif;background:#0f1116;padding:24px;color:#e4e8f0;">
      <h2 style="margin:0 0 12px 0;color:#ffffff;">Neuer Schulungsbedarf (FB620)</h2>
      <p style="margin:0 0 20px 0;color:#b6bcc8;">Eine neue Anforderung wurde über DFS Connect+ eingereicht.</p>
      <table style="border-collapse:collapse;width:100%;font-size:14px;">${rows.join('')}</table>
      <p style="margin-top:20px;color:#8d96a6;font-size:12px;">Diese Nachricht wurde automatisch erstellt.</p>
    </div>`;
}


export default async function handler(req, res) {
  if (handlePreflight(req, res)) return;
  setCors(req, res);

  const wantsWrite = ['POST', 'PATCH', 'DELETE'].includes(req.method);
  const actor = await requireTrainingNeedAccess(req, res, { write: wantsWrite });
  if (!actor) return;

  try {
    if (req.method === 'GET') {
      const list = await trainingNeedsAll();
      const year = Number(req.query?.year || 0);
      const filtered = year ? list.filter((entry) => entry.year === year) : list;
      return ok(res, { ok: true, list: filtered });
    }

    if (req.method === 'POST') {
      const body = readJson(req) || {};
      const { errors, normalizedPeriod } = validateTrainingNeed(body);
      if (Object.keys(errors).length > 0) {
        return bad(res, 'Validierung fehlgeschlagen.', 400, { errors });
      }
      const payload = {
        ...body,
        plannedPeriodValue: normalizedPeriod || body.plannedPeriodValue,
        createdBy: actor.email,
        updatedBy: actor.email,
      };
      const saved = await trainingNeedSave(payload);
      console.info('[training-needs] created', { id: saved.id, by: actor.email });
      let warning = null;
      try {
        const resolvedDepartment =
          saved.departmentTeamSelected === 'Sonstiges...' && saved.departmentTeamFreeText
            ? saved.departmentTeamFreeText
            : saved.departmentTeamSelected;
        const plannedPeriodLabelText = plannedPeriodLabel(saved.plannedPeriodType, saved.plannedPeriodValue);
        const subject = `Schulungsbedarf ${saved.year} – ${resolvedDepartment || 'Abteilung'} – ${saved.items?.[0]?.topic || ''}`.trim();
        const html = buildNeedEmailHtml({
          need: saved,
          resolvedDepartment,
          plannedPeriodLabelText,
          submittedBy: actor?.email || '',
          submittedAt: new Date().toLocaleString('de-DE'),
        });
        const info = await sendMail({
          to: 'qualitymanagement@dfs-diamon.de',
          subject,
          html,
          text: 'Ein neuer Schulungsbedarf wurde erfasst. Bitte öffnen Sie die HTML-Version dieser E-Mail.',
        });
        if (!info?.ok) {
          warning = 'Gespeichert, aber E-Mail konnte nicht versendet werden.';
        }
      } catch (err) {
        console.error('[admin/training-needs] email error', err);
        warning = 'Gespeichert, aber E-Mail konnte nicht versendet werden.';
      }
      return ok(res, { ok: true, need: saved, warning });
    }

    if (req.method === 'PATCH') {
      const body = readJson(req) || {};
      const id = body.id || req.query?.id;
      if (!id) return bad(res, 'id missing', 400);
      const patchYear = String(body.year || '').trim();
      const patchPeriodType = trim(body.plannedPeriodType || '');
      const patchPeriodValue = normalizePeriodValue(patchPeriodType, body.plannedPeriodValue);
      if (patchYear && patchPeriodValue && periodYear(patchPeriodValue) !== patchYear) {
        return bad(res, 'Der geplante Zeitraum muss im Schulungsjahr liegen.', 400);
      }
      const { errors, normalizedPeriod } = validateTrainingNeed(body);
      if (Object.keys(errors).length > 0) {
        return bad(res, 'Validierung fehlgeschlagen.', 400, { errors });
      }
      const current = await trainingNeedGet(id);
      if (!current) return bad(res, 'not found', 404);
      if (body.updatedAt && Number(body.updatedAt) !== Number(current.updatedAt)) {
        return bad(res, 'conflict', 409, { message: 'Datensatz wurde zwischenzeitlich geändert.' });
      }
      const updated = await trainingNeedUpdate(id, {
        ...body,
        plannedPeriodValue: normalizedPeriod || body.plannedPeriodValue,
        updatedBy: actor.email,
      });
      if (!updated) return bad(res, 'not found', 404);
      console.info('[training-needs] updated', { id, by: actor.email });
      return ok(res, { ok: true, need: updated });
    }

    if (req.method === 'DELETE') {
      if (normalizeRole(actor.role) !== PORTAL_ROLES.superuser) {
        console.warn('[training-needs] delete denied', { id: req.query?.id, by: actor.email });
        return bad(res, 'forbidden', 403);
      }
      const id = req.query?.id || readJson(req)?.id;
      if (!id) return bad(res, 'id missing', 400);
      await trainingNeedDelete(id);
      console.info('[training-needs] deleted', { id, by: actor.email, scope: 'single' });
      return ok(res, { ok: true });
    }

    return methodNotAllowed(res);
  } catch (err) {
    console.error('[admin/training-needs] error', err);
    return bad(res, 'server error', 500);
  }
}
