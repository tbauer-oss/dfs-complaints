// api/admin/complaints.js
export const config = { runtime: 'nodejs' };

import {
  setCors,
  ok,
  bad,
  noContent,
  methodNotAllowed,
  readJson,
} from '../_lib/http.js';
import { sendMail } from '../_lib/mailer.js';
import { requirePortalAccess } from './_guard.js';
import { normalizeRole, PORTAL_ROLES } from '../_lib/portalAuth.js';
import {
  DEFAULT_INTERNAL_DEPARTMENTS,
  hasDepartmentOverlap,
  INTERNAL_EVALUATION_CAUSES,
  ALLOWED_EVALUATION_TRANSLATION_LANGS,
  normalizeDepartments,
  normalizeEvaluationText,
  normalizeInternalEvaluationCause,
  normalizeEvaluationTranslations,
  normalizeReportLinksMap,
} from '../_lib/departments.js';
import { translateTexts } from '../_lib/translate.js';
import { generateReportsForComplaint } from '../_lib/reporting.js';

// -------- Status-Mapping ----------
const STATUS_LABEL = {
  1: 'Eingegangen',
  2: 'In Bearbeitung',
  3: 'Rückfrage erforderlich',
  4: 'In Nacharbeit',
  5: 'Abgeschlossen',
};
const STATUS_CODE = Object.fromEntries(Object.entries(STATUS_LABEL).map(([k, v]) => [v, Number(k)]));

const STATUS_I18N = {
  de: {
    1: 'Eingegangen',
    2: 'In Bearbeitung',
    3: 'Rückfrage erforderlich',
    4: 'In Nacharbeit',
    5: 'Abgeschlossen',
  },
  en: {
    1: 'Received',
    2: 'In progress',
    3: 'Needs info',
    4: 'Rework',
    5: 'Closed',
  },
  fr: {
    1: 'Reçu',
    2: 'En cours',
    3: 'Informations requises',
    4: 'Reprise',
    5: 'Clôturé',
  },
  it: {
    1: 'Ricevuto',
    2: 'In lavorazione',
    3: 'Informazioni necessarie',
    4: 'Revisione',
    5: 'Chiuso',
  },
  es: {
    1: 'Recibido',
    2: 'En curso',
    3: 'Se requiere información',
    4: 'Revisión',
    5: 'Cerrado',
  },
};

const PUSH_TEXT = {
  de: {
    title: 'Status Ihrer Reklamation',
    body: (ticket, status) => `Der Status Ihrer Reklamation ${ticket} hat sich geändert: ${status}.`,
  },
  en: {
    title: 'Complaint status updated',
    body: (ticket, status) => `The status of your complaint ${ticket} has changed to ${status}.`,
  },
  fr: {
    title: 'Statut de réclamation mis à jour',
    body: (ticket, status) => `Le statut de votre réclamation ${ticket} a changé : ${status}.`,
  },
  it: {
    title: 'Aggiornamento stato reclamo',
    body: (ticket, status) => `Lo stato del reclamo ${ticket} è cambiato in: ${status}.`,
  },
  es: {
    title: 'Estado de reclamación actualizado',
    body: (ticket, status) => `El estado de su reclamación ${ticket} ha cambiado a: ${status}.`,
  },
};

const SUPPORTED_LANGS = new Set(['de', 'en', 'fr', 'it', 'es']);
const LANG_ALIASES = {
  german: 'de',
  deutsch: 'de',
  englisch: 'en',
  english: 'en',
  french: 'fr',
  français: 'fr',
  francais: 'fr',
  italienisch: 'it',
  italian: 'it',
  spanish: 'es',
  spanisch: 'es',
  español: 'es',
  espanol: 'es',
};

function normalizeLangValue(input) {
  const raw = (input || '').toString().trim().toLowerCase();
  if (!raw) return null;
  if (LANG_ALIASES[raw]) return LANG_ALIASES[raw];
  if (SUPPORTED_LANGS.has(raw)) return raw;
  const two = raw.split(/[-_]/)[0];
  if (SUPPORTED_LANGS.has(two)) return two;
  if (LANG_ALIASES[two]) return LANG_ALIASES[two];
  return null;
}

function resolveLang(input, fallback = 'en') {
  return normalizeLangValue(input) || fallback;
}

function normalizeRoleSafe(actor) {
  return normalizeRole(actor?.role || actor?.portalRole || '');
}

function actorDepartments(actor) {
  return normalizeDepartments(actor?.assignedDepartments || []);
}

function filterByDepartments(list = [], actor) {
  const role = normalizeRoleSafe(actor);
  if (role === PORTAL_ROLES.superuser || role === PORTAL_ROLES.readonly) return list;
  const deps = actorDepartments(actor);
  if (deps.length === 0) return [];
  return list.filter((c) => hasDepartmentOverlap(deps, c?.internalDepartments));
}

function detectCustomerLang(user, complaint) {
  const candidates = [
    user?.lang,
    user?.language,
    user?.preferredLanguage,
    user?.preferred_language,
    user?.preferred_lang,
    user?.langCode,
    user?.lang_code,
    user?.languageCode,
    user?.language_code,
    user?.locale,
    user?.customerLang,
    complaint?.lang,
  ];
  for (const candidate of candidates) {
    const normalized = normalizeLangValue(candidate);
    if (normalized) return normalized;
  }
  return null;
}

function buildPushMessage(lang, ticket, status) {
  const l = resolveLang(lang);
  const texts = PUSH_TEXT[l] || PUSH_TEXT.en;
  const labels = STATUS_I18N[l] || STATUS_I18N.en;
  const statusLabel = labels[status] || labels[1];
  return {
    title: texts.title,
    body: texts.body(ticket, statusLabel),
    statusLabel,
  };
}

function parseStatus(input) {
  if (input == null) return null;
  if (typeof input === 'number') return (input >= 1 && input <= 5) ? input : null;
  if (typeof input === 'string') {
    const s = input.trim();
    if (/^\d+$/.test(s)) {
      const n = Number(s);
      return (n >= 1 && n <= 5) ? n : null;
    }
    return STATUS_CODE[s] ?? null;
  }
  return null;
}

// -------- Helpers ----------
const normEmail = (v = '') => v.toString().trim().toLowerCase();
const sortDescByDate = (a, b) => {
  const ta = a?.updatedAt ?? a?.createdAt ?? 0;
  const tb = b?.updatedAt ?? b?.createdAt ?? 0;
  return (tb || 0) - (ta || 0);
};
function normalizeHistoryEntry(entry = {}) {
  const at = Number(entry?.at);
  const actor = (entry?.actor || 'system').toString().trim() || 'system';
  const type = (entry?.type || 'info').toString().trim() || 'info';
  const message = (entry?.message || '').toString();
  const data = (entry?.data && typeof entry.data === 'object') ? entry.data : undefined;
  return {
    at: Number.isFinite(at) && at > 0 ? at : Date.now(),
    actor,
    type,
    message,
    ...(data ? { data } : {}),
  };
}

function normalizeHistory(list) {
  if (!Array.isArray(list)) return [];
  const out = list.map((entry) => normalizeHistoryEntry(entry)).filter(Boolean);
  out.sort((a, b) => (a.at || 0) - (b.at || 0));
  return out;
}

function pushHistory(c, entry) {
  const existing = Array.isArray(c?.history) ? c.history.slice() : [];
  existing.push(normalizeHistoryEntry(entry));
  c.history = normalizeHistory(existing);
  return c.history;
}

const decorateForAdmin = (c) => ({
  ...c,
  history: normalizeHistory(c?.history),
  statusLabel: STATUS_LABEL[c.status] || STATUS_LABEL[1],
  internalDepartmentOptions: DEFAULT_INTERNAL_DEPARTMENTS,
  internalEvaluationCauseOptions: INTERNAL_EVALUATION_CAUSES,
});

const EDITABLE_PAYLOAD_FIELDS = {
  segment: { label: 'Produktbereich', keys: ['segment', 'customer_segment', 'segment_code'] },
  productType: { label: 'Produkttyp', keys: ['product_type', 'productType', 'type'] },
  article: { label: 'Artikelnummer', keys: ['article', 'article_no', 'articleNumber', 'artnr'] },
  batch: { label: 'Charge / Lot', keys: ['batch', 'batch_no', 'lot', 'lot_no'] },
  serial: { label: 'Seriennummer', keys: ['serial', 'serial_no', 'sn'] },
  qty: { label: 'Menge', keys: ['qty', 'quantity', 'amount', 'menge'] },
  expiry: { label: 'Ablaufdatum', keys: ['expiry', 'expiry_date', 'exp'] },
  desc: { label: 'Fehler / Beschreibung', keys: ['desc', 'description', 'comment', 'details', 'failure_desc'] },
  reason: { label: 'Grund / Ursache', keys: ['reason', 'failure_reason', 'cause'] },
  returned: { label: 'Produkte zurückgeschickt', keys: ['returned'] },
  handling: { label: 'Gewünschte Behandlung', keys: ['handling', 'customer_wish', 'customerWish', 'wish', 'treatment_wish'] },
  applied: { label: 'Am Patienten angewendet', keys: ['applied'] },
  injury: { label: 'Verletzung', keys: ['injury'] },
  injuryDesc: { label: 'Verletzungsbeschreibung', keys: ['injuryDesc'] },
};

function pickPayloadValue(payload = {}, keys = []) {
  for (const key of keys) {
    const raw = payload?.[key];
    if (raw === undefined || raw === null) continue;
    const str = raw.toString().trim();
    if (str) return str;
  }
  return '';
}

function chooseTargetKey(payload = {}, keys = []) {
  for (const key of keys) {
    if (Object.prototype.hasOwnProperty.call(payload, key)) return key;
  }
  return keys[0];
}

function normalizePayloadInput(input) {
  if (!input || typeof input !== 'object') return null;
  const out = {};
  for (const [k, v] of Object.entries(input)) {
    out[k] = (v ?? '').toString().trim();
  }
  return Object.keys(out).length > 0 ? out : null;
}

function diffAndMergePayload(current = {}, incoming = {}) {
  const updated = { ...current };
  const changes = [];

  for (const [canonical, cfg] of Object.entries(EDITABLE_PAYLOAD_FIELDS)) {
    if (!Object.prototype.hasOwnProperty.call(incoming, canonical)) continue;
    const newValue = (incoming[canonical] ?? '').toString().trim();
    const prevValue = pickPayloadValue(updated, cfg.keys);
    const targetKey = chooseTargetKey(updated, cfg.keys);

    if (newValue) updated[targetKey] = newValue; else delete updated[targetKey];

    if (prevValue !== newValue) {
      changes.push({
        label: cfg.label,
        before: prevValue || '—',
        after: newValue || '—',
      });
    }
  }

  return { updated, changes };
}

function escapeHtml(value = '') {
  return value
    .replace(/&/g, '&amp;')
    .replace(/</g, '&lt;')
    .replace(/>/g, '&gt;')
    .replace(/"/g, '&quot;')
    .replace(/'/g, '&#039;');
}

function buildStatusMail(lang, ticket, prevStatus, nextStatus) {
  const l = resolveLang(lang, 'de');
  const labels = STATUS_I18N[l] || STATUS_I18N.de;
  const before = labels[prevStatus] || labels[1];
  const after = labels[nextStatus] || labels[1];

  const SUBJECT = {
    de: `Aktualisierung Ihrer Reklamation ${ticket}`,
    en: `Update to your complaint ${ticket}`,
    fr: `Mise à jour de votre réclamation ${ticket}`,
    it: `Aggiornamento della sua segnalazione ${ticket}`,
    es: `Actualización de su reclamación ${ticket}`,
  };

  const INTRO = {
    de: `wir haben Ihre Reklamation ${ticket} aktualisiert. Der Status hat sich geändert:`,
    en: `we updated your complaint ${ticket}. The status has changed:`,
    fr: `nous avons mis à jour votre réclamation ${ticket}. Le statut a changé :`,
    it: `abbiamo aggiornato la sua segnalazione ${ticket}. Lo stato è cambiato:`,
    es: `hemos actualizado su reclamación ${ticket}. El estado ha cambiado:`,
  };

  const OUTRO = {
    de: 'Bei Rückfragen stehen wir gerne zur Verfügung.',
    en: 'If you have any questions, please let us know.',
    fr: 'Pour toute question, nous restons à votre disposition.',
    it: 'Per eventuali domande restiamo a disposizione.',
    es: 'Si tiene alguna pregunta, estamos a su disposición.',
  };

  const CLOSING = {
    de: 'Freundliche Grüße\nDFS-DIAMON GmbH – Quality Management',
    en: 'Kind regards\nDFS-DIAMON GmbH – Quality Management',
    fr: 'Cordialement\nDFS-DIAMON GmbH – Quality Management',
    it: 'Cordiali saluti\nDFS-DIAMON GmbH – Quality Management',
    es: 'Saludos cordiales\nDFS-DIAMON GmbH – Quality Management',
  };

  return {
    subject: SUBJECT[l] || SUBJECT.de,
    intro: INTRO[l] || INTRO.de,
    outro: OUTRO[l] || OUTRO.de,
    closing: CLOSING[l] || CLOSING.de,
    statusLine: `${before} → ${after}`,
  };
}

function buildPayloadMail(lang, ticket) {
  const l = resolveLang(lang, 'de');

  const SUBJECT = {
    de: `Korrektur Ihrer Reklamation ${ticket}`,
    en: `Correction of your complaint ${ticket}`,
    fr: `Correction de votre réclamation ${ticket}`,
    it: `Correzione del reclamo ${ticket}`,
    es: `Corrección de su reclamación ${ticket}`,
  };

  const INTRO = {
    de: `wir haben Ihre Reklamation ${ticket} korrigiert. Folgende Angaben wurden geändert:`,
    en: `we have corrected your complaint ${ticket}. The following details were changed:`,
    fr: `nous avons corrigé votre réclamation ${ticket}. Les informations suivantes ont été modifiées :`,
    it: `abbiamo corretto il Suo reclamo ${ticket}. Sono stati modificati i seguenti dati:`,
    es: `hemos corregido su reclamación ${ticket}. Se han modificado los siguientes datos:`,
  };

  const OUTRO = {
    de: 'Bei Rückfragen stehen wir gerne zur Verfügung.',
    en: 'If you have any questions, please let us know.',
    fr: 'Pour toute question, nous restons à votre disposition.',
    it: 'Per eventuali domande restiamo a disposizione.',
    es: 'Si tiene alguna pregunta, estamos a su disposición.',
  };

  const CLOSING = {
    de: 'Freundliche Grüße\nDFS-DIAMON GmbH – Quality Management',
    en: 'Kind regards\nDFS-DIAMON GmbH – Quality Management',
    fr: 'Cordialement\nDFS-DIAMON GmbH – Quality Management',
    it: 'Cordiali saluti\nDFS-DIAMON GmbH – Quality Management',
    es: 'Saludos cordiales\nDFS-DIAMON GmbH – Quality Management',
  };

  return {
    subject: SUBJECT[l] || SUBJECT.de,
    intro: INTRO[l] || INTRO.de,
    outro: OUTRO[l] || OUTRO.de,
    closing: CLOSING[l] || CLOSING.de,
    statusLine: null,
  };
}

// =======================================================
// Handler
// =======================================================
export default async function handler(req, res) {
  // 1) CORS IMMER zuerst
  setCors(req, res);

  // 2) Preflight IMMER minimal beantworten (keine weiteren Imports!)
  if (req.method === 'OPTIONS') return noContent(res);

  // 3) Admin-Auth prüfen (immer noch ohne schwere Imports)
  const actor = await requirePortalAccess(req, res, { write: req.method !== 'GET' });
  if (!actor) return;
  const role = normalizeRoleSafe(actor);
  const deps = actorDepartments(actor);
  const isSuperuser = role === PORTAL_ROLES.superuser;
  const isNormalUser = role === PORTAL_ROLES.user;

  // 4) Schwere Imports NACH Preflight/Admin laden (verhindert 500 bei OPTIONS)
  const {
    complaintsAll,
    complaintsOpen,
    complaintsByEmail,
    complaintByTicket,
    complaintSave,
    complaintDelete,
    userByEmail,
    pushTokensForEmail,
    pushTokenRemove,
    Status,
  } = await import('../_lib/store.js');
  const { sendPushToTokens } = await import('../_lib/fcm.js');
  
  try {
    // ----------------------------
    // GET
    // ----------------------------
    if (req.method === 'GET') {
      const q = req.query || {};
      const email   = normEmail(q.email || '');
      const ticket  = (q.ticket || '').toString().trim();
      const open    = (q.open || '').toString().trim();
      const details = (q.details || '').toString().trim();

      if (ticket) {
        const c = await complaintByTicket(ticket);
        if (!c) return bad(res, 'not found', 404);
        if (isNormalUser && !hasDepartmentOverlap(deps, c.internalDepartments)) {
          return bad(res, 'forbidden', 403);
        }
        if (isSuperuser && c.internalEvaluationNewForAdmin) {
          const cleared = await complaintSave({ ...c, internalEvaluationNewForAdmin: false });
          return ok(res, decorateForAdmin(cleared));
        }
        return ok(res, decorateForAdmin(c));
      }

      if (email) {
        const list = filterByDepartments(await complaintsByEmail(email), actor);
        list.sort(sortDescByDate);
        return ok(res, details === '1' ? list.map(decorateForAdmin) : list.map((c) => c.ticket));
      }

      if (open === '1') {
        const list = filterByDepartments(await complaintsOpen(), actor);
        return ok(res, list.map(decorateForAdmin));
      }

      const all = filterByDepartments(await complaintsAll(), actor);
      const out = (Array.isArray(all) ? all : []).sort(sortDescByDate).map(decorateForAdmin);
      return ok(res, out);
    }

    // ----------------------------
    // POST / PATCH – Status / Decision / Report
    // ----------------------------
    if (req.method === 'POST' || req.method === 'PATCH') {
      let body = readJson(req);
      if (typeof body === 'string') { try { body = JSON.parse(body); } catch {} }
      if (typeof body === 'string') body = { ticket: body };
      if (!body || typeof body !== 'object') body = {};

      const ticket      = (body?.ticket || '').toString().trim();
      const statusIn    = body?.status; // 1..6 | "1".."6" | Label
      const hasDecision = Object.prototype.hasOwnProperty.call(body, 'decision');
      const rawDecision = hasDecision ? body.decision : undefined; // 'accepted' | 'rejected' | "" | null | undefined
      const reportLink  = body?.reportLink; // string | "" | null | undefined
      const hasInternal = Object.prototype.hasOwnProperty.call(body, 'internalNo');
      const rawInternal = hasInternal ? body.internalNo : undefined;
      const hasNotes    = Object.prototype.hasOwnProperty.call(body, 'notes');
      const rawNotes    = hasNotes ? body.notes : undefined;
      const internalDepartmentsInput = body?.internalDepartments;
      const internalEvalText = body?.internalEvaluationText_de;
      const internalEvalCause = body?.internalEvaluationCause;
      const translateEval = body?.translateInternalEvaluation;
      const payloadInput = normalizePayloadInput(body?.payload);
      const sendPushFlag =
        body?.sendPush === true ||
        body?.sendPush === 'true' ||
        body?.sendPush === 1 ||
        body?.sendPush === '1';

      if (!ticket) return bad(res, 'missing ticket', 400);

      const c = await complaintByTicket(ticket);
      if (!c) return bad(res, 'not found', 404);

      if (isNormalUser && !hasDepartmentOverlap(deps, c.internalDepartments)) {
        return bad(res, 'forbidden', 403);
      }

      if (isNormalUser) {
        const allowedKeys = new Set(['ticket', 'internalEvaluationText_de', 'internalEvaluationCause']);
        const forbidden = Object.keys(body || {}).filter((key) => !allowedKeys.has(key));
        if (forbidden.length > 0) return bad(res, 'forbidden for role', 403);

        const prevEval = normalizeEvaluationText(c.internalEvaluationText_de);
        const prevCause = normalizeInternalEvaluationCause(c.internalEvaluationCause);
        const nextEval = normalizeEvaluationText(body.internalEvaluationText_de ?? prevEval);
        const nextCause = normalizeInternalEvaluationCause(body.internalEvaluationCause ?? prevCause);

        let changed = false;
        c.history = normalizeHistory(c.history);

        if (nextEval !== prevEval) {
          c.internalEvaluationText_de = nextEval;
          c.internalEvaluationNewForAdmin = Boolean(nextEval);
          changed = true;
        }

        if (nextCause !== prevCause) {
          c.internalEvaluationCause = nextCause;
          changed = true;
        }

        if (changed) {
          pushHistory(c, {
            actor: 'user',
            type: 'internal-eval',
            message: 'Interne Bewertung aktualisiert',
            data: { cause: c.internalEvaluationCause || null },
          });
          c.updatedAt = Date.now();
          await complaintSave(c);
        }

        return ok(res, decorateForAdmin(c));
      }

      let account = null;
      const normalizedEmail = normEmail(c.email || '');
      if (normalizedEmail) {
        try { account = await userByEmail(normalizedEmail); }
        catch (err) { console.error('admin/complaints user lookup failed', err?.message || err); }
      }

      const prevStatus = Number(c.status ?? 1);
      const prevDecision = (c.decision ?? null);
      const prevReportLink = (c.reportLink ?? '').toString().trim();
      const prevInternal = (c.internalNo ?? '').toString().trim();
      const prevNotes = (c.adminNotes ?? '').toString();
      const prevDepartments = normalizeDepartments(c.internalDepartments);
      const prevEvalText = normalizeEvaluationText(c.internalEvaluationText_de);
      const prevEvalCause = normalizeInternalEvaluationCause(c.internalEvaluationCause);
      const prevTranslations = normalizeEvaluationTranslations(c.internalEvaluationTranslations);
      let statusChanged = false;
      let payloadChanged = false;
      let payloadChanges = [];
      let decisionChanged = false;
      let reportChanged = false;
      let internalChanged = false;
      let notesChanged = false;
      let departmentsChanged = false;
      let evalTextChanged = false;
      let evalCauseChanged = false;
      let evalTranslationChanged = false;

      c.history = normalizeHistory(c.history);

      if (internalDepartmentsInput !== undefined) {
        const normalizedDeps = normalizeDepartments(internalDepartmentsInput);
        const prevKey = prevDepartments.map((d) => d.toLowerCase()).sort().join('|');
        const nextKey = normalizedDeps.map((d) => d.toLowerCase()).sort().join('|');
        if (prevKey !== nextKey) {
          c.internalDepartments = normalizedDeps;
          departmentsChanged = true;
          pushHistory(c, {
            actor: 'admin',
            type: 'departments',
            message: 'Interne Abteilungen aktualisiert',
            data: { departments: normalizedDeps },
          });
        }
      }

      if (internalEvalText !== undefined) {
        const nextText = normalizeEvaluationText(internalEvalText);
        if (nextText !== prevEvalText) {
          c.internalEvaluationText_de = nextText;
          evalTextChanged = true;
          c.internalEvaluationNewForAdmin = Boolean(nextText);
        }
      }

      if (internalEvalCause !== undefined) {
        const nextCause = normalizeInternalEvaluationCause(internalEvalCause);
        if (nextCause !== prevEvalCause) {
          c.internalEvaluationCause = nextCause;
          evalCauseChanged = true;
        }
      }

      if (translateEval) {
        const requested = normalizeLangValue(
          translateEval?.targetLang || translateEval?.lang || translateEval,
        ) || 'en';
        if (!ALLOWED_EVALUATION_TRANSLATION_LANGS.has(requested)) {
          return bad(res, 'unsupported translation target', 400);
        }
        const sourceText = normalizeEvaluationText(
          internalEvalText !== undefined ? internalEvalText : c.internalEvaluationText_de,
        );
        if (!sourceText) return bad(res, 'no internal evaluation to translate', 400);
        try {
          const result = await translateTexts({
            textByKey: { text: sourceText },
            sourceLang: 'de',
            targetLangs: [requested],
          });
          const translated = result?.translations?.[requested]?.text;
          if (translated) {
            const nextTranslations = {
              ...prevTranslations,
              ...normalizeEvaluationTranslations(c.internalEvaluationTranslations),
              [requested]: translated,
            };
            c.internalEvaluationTranslations = nextTranslations;
            evalTranslationChanged = true;
          }
        } catch (err) {
          return bad(res, err?.message || 'translation failed', 400);
        }
      }

      if (payloadInput) {
        const currentPayload = (c.payload && typeof c.payload === 'object') ? { ...c.payload } : {};
        const { updated, changes } = diffAndMergePayload(currentPayload, payloadInput);
        if (changes.length > 0) {
          c.payload = updated;
          payloadChanged = true;
          payloadChanges = changes;
          pushHistory(c, {
            actor: 'admin',
            type: 'payload',
            message: `Payload aktualisiert (${changes.length} Änderung${changes.length === 1 ? '' : 'en'})`,
            data: { changes },
          });
        }
      }

      // Status (optional)
      if (statusIn !== undefined) {
        const code = parseStatus(statusIn);
        if (code == null) return bad(res, 'invalid status', 400);
        if (code !== c.status) {
          c.status = code;
          statusChanged = true;
        }
      }

      // Decision (optional, separat, "" => null)
      if (hasDecision) {
        const decision = (rawDecision === '') ? null : rawDecision;
        if (decision !== null && decision !== 'accepted' && decision !== 'rejected') {
          return bad(res, 'invalid decision', 400);
        }
        c.decision = decision;
        if (decision !== prevDecision) decisionChanged = true;

        // Business-Logik: 'rejected' => schließen + Status "Entscheidung"
        if (c.decision === 'rejected') {
          c.closed = true;
          c.closedAt = Date.now();
          if (c.status !== Status.CLOSED) {
            c.status = Status.CLOSED;
            statusChanged = true;
          }
        }
      }

      // Report-Link (optional; "" => löschen)
      if (reportLink !== undefined) {
        const v = (reportLink ?? '').toString().trim();
        if (v) c.reportLink = v;
        else delete c.reportLink;
        const nextReport = (c.reportLink ?? '').toString().trim();
        if (nextReport !== prevReportLink) reportChanged = true;
      }

      // Interne Nummer (optional; "" => löschen)
      if (hasInternal) {
        const v = (rawInternal ?? '').toString().trim();
        if (v) c.internalNo = v;
        else delete c.internalNo;
        const nextInternal = (c.internalNo ?? '').toString().trim();
        if (nextInternal !== prevInternal) internalChanged = true;
      }

      // Admin-Notizen (optional; "" => löschen)
      if (hasNotes) {
        const v = (rawNotes ?? '').toString();
        if (v.trim()) c.adminNotes = v;
        else delete c.adminNotes;
        const nextNotes = (c.adminNotes ?? '').toString();
        if (nextNotes !== prevNotes) notesChanged = true;
      }

      if (!statusChanged && prevStatus !== c.status) statusChanged = true;

      if (statusChanged) {
        pushHistory(c, {
          actor: 'admin',
          type: 'status',
          message: `Status geändert: ${(STATUS_LABEL[prevStatus] || prevStatus)} → ${(STATUS_LABEL[c.status] || c.status)}`,
          data: { before: prevStatus, after: c.status },
        });
      }

      if (decisionChanged) {
        const decisionLabel = c.decision === 'accepted'
          ? 'Angenommen'
          : c.decision === 'rejected'
            ? 'Abgelehnt'
            : 'Zurückgesetzt';
        pushHistory(c, {
          actor: 'admin',
          type: 'decision',
          message: `Entscheidung aktualisiert: ${decisionLabel}`,
          data: { before: prevDecision, after: c.decision },
        });
      }

      if (reportChanged) {
        const label = (c.reportLink ?? '').toString().trim().isEmpty
          ? 'Report-Link entfernt'
          : 'Report-Link hinterlegt';
        pushHistory(c, {
          actor: 'admin',
          type: 'report',
          message: label,
          data: { link: c.reportLink || null },
        });
      }

      if (internalChanged) {
        const label = (c.internalNo ?? '').toString().trim().isEmpty
          ? 'Interne Nummer entfernt'
          : `Interne Nummer gesetzt: ${c.internalNo}`;
        pushHistory(c, {
          actor: 'admin',
          type: 'internal',
          message: label,
          data: { internalNo: c.internalNo || null },
        });
      }

      if (notesChanged) {
        const label = (c.adminNotes ?? '').toString().trim().isEmpty
          ? 'Admin-Notiz entfernt'
          : 'Admin-Notiz aktualisiert';
        pushHistory(c, {
          actor: 'admin',
          type: 'notes',
          message: label,
        });
      }

      if (evalTextChanged || evalCauseChanged) {
        pushHistory(c, {
          actor: 'admin',
          type: 'internal-eval',
          message: 'Interne Bewertung angepasst (Admin)',
          data: {
            cause: c.internalEvaluationCause || null,
            hasText: Boolean(c.internalEvaluationText_de),
          },
        });
      }

      if (evalTranslationChanged) {
        pushHistory(c, {
          actor: 'admin',
          type: 'internal-eval-translation',
          message: 'Übersetzung der internen Bewertung gespeichert',
          data: { translations: c.internalEvaluationTranslations || {} },
        });
      }

      if ((statusChanged || c.status === Status.CLOSED) && c.status === Status.CLOSED) {
        const preferredLang = detectCustomerLang(account, c) || 'de';
        const targetLangs = preferredLang === 'en' ? ['en'] : ['de'];
        if (!targetLangs.includes('de') && !targetLangs.includes('en')) targetLangs.push('de');
        try {
          const generated = await generateReportsForComplaint(c, { targetLangs });
          if (generated && Object.keys(generated).length > 0) {
            const merged = normalizeReportLinksMap({ ...(c.reportLinks || {}), ...generated });
            c.reportLinks = merged;
            const defaultLink = merged[preferredLang] || merged.en || merged.de;
            if (defaultLink) c.reportLink = defaultLink;
            reportChanged = true;
          }
        } catch (err) {
          console.error('admin/complaints report generation failed', err?.message || err);
        }
      }

      c.updatedAt = Date.now();
      if (statusChanged) c.statusUpdatedAt = Date.now();

      // robust persistieren
      try { await complaintSave(c); }
      catch { await complaintSave({ ...c }); }

      if ((payloadChanged && payloadChanges.length > 0) || statusChanged) {
        const recipient = (c.email || '').toString().trim();
        const normalized = normEmail(recipient);
        if (recipient && normalized) {
          const lang = detectCustomerLang(account, c) || 'de';
          const hasStatusChange = statusChanged;
          const hasPayloadChanges = payloadChanged && payloadChanges.length > 0;
          const mailText = hasStatusChange
            ? buildStatusMail(lang, c.ticket, prevStatus, c.status)
            : buildPayloadMail(lang, c.ticket);
          const changeLines = [];
          const htmlItems = [];

          if (hasStatusChange) {
            changeLines.push(`• ${mailText.statusLine}`);
            htmlItems.push(`<li><strong>${escapeHtml(mailText.statusLine)}</strong></li>`);
          }

          if (hasPayloadChanges) {
            payloadChanges.forEach((chg) => {
              changeLines.push(`• ${chg.label}: vorher "${chg.before}", jetzt "${chg.after}"`);
              htmlItems.push(
                `<li><strong>${escapeHtml(chg.label)}:</strong> vorher „${escapeHtml(chg.before)}”, jetzt „${escapeHtml(chg.after)}”</li>`,
              );
            });
          }

          const textBody =
            `Guten Tag,\n\n${mailText.intro}\n` +
            `${changeLines.join('\n')}\n\n` +
            `${mailText.outro}\n\n${mailText.closing}`;

          const htmlBody =
            `<p>Guten Tag,</p>` +
            `<p>${escapeHtml(mailText.intro)}</p>` +
            `<ul>${htmlItems.join('')}</ul>` +
            `<p>${escapeHtml(mailText.outro)}</p>` +
            `<p>${escapeHtml(mailText.closing).replace(/\n/g, '<br/>')}</p>`;

          sendMail({ to: recipient, subject: mailText.subject, text: textBody, html: htmlBody }).catch((err) => {
            console.error('admin/complaints mail failed', err);
          });
        }
      }

      if (statusChanged && sendPushFlag) {
        try {
          const email = normEmail(c.email || '');
          if (email) {
            const user = await userByEmail(email);
            const customerTokens = await pushTokensForEmail(email);
            const accountLang = detectCustomerLang(user, c);
            const tokensByLang = new Map();
            for (const entry of customerTokens) {
              const tok = (entry?.token || '').toString().trim();
              if (!tok) continue;
              const lang = resolveLang(entry?.lang || entry?.locale || accountLang || user?.lang || c.lang || '');
              if (!tokensByLang.has(lang)) tokensByLang.set(lang, []);
              tokensByLang.get(lang).push(tok);
            }

            const invalidTokens = new Set();
            for (const [lang, tokens] of tokensByLang.entries()) {
              if (tokens.length === 0) continue;
              const pushMsg = buildPushMessage(lang, c.ticket, c.status);
              const payloadData = {
                type: 'complaint-status',
                ticket: c.ticket,
                status: String(c.status ?? ''),
                statusLabel: pushMsg.statusLabel,
                lang,
                customerEmail: email,
              };

              const result = await sendPushToTokens(
                tokens,
                { title: pushMsg.title, body: pushMsg.body },
                payloadData,
              );

              if (Array.isArray(result?.invalidTokens)) {
                result.invalidTokens.forEach(t => invalidTokens.add(t));
              }
            }

            if (invalidTokens.size > 0) {
              for (const bad of invalidTokens) {
                try {
                  await pushTokenRemove(email, bad);
                } catch (err) {
                  console.error('push token cleanup failed', err);
                }
              }
            }
          }
        } catch (pushErr) {
          console.error('admin/complaints push notify failed:', pushErr);
        }
      }

      return ok(res, decorateForAdmin(c));
    }

    // ----------------------------
    // DELETE
    // ----------------------------
    if (req.method === 'DELETE') {
      let ticket = (req.query?.ticket || '').toString().trim();
      if (!ticket && req.body) {
        try {
          const b = typeof req.body === 'string' ? JSON.parse(req.body || '{}') : req.body;
          ticket = (b?.ticket || '').toString().trim();
        } catch {}
      }
      if (!ticket) return bad(res, 'missing ticket', 400);

      const c = await complaintByTicket(ticket);
      if (!c) return bad(res, 'not found', 404);

      await complaintDelete(ticket);
      return noContent(res);
    }

    return methodNotAllowed(res);
  } catch (e) {
    console.error('admin/complaints error:', e);
    return bad(res, e?.message || 'server error', 500);
  }
}
