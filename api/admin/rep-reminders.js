// api/admin/rep-reminders.js
export const config = { runtime: 'nodejs' };

import {
  setCors,
  ok,
  bad,
  noContent,
  methodNotAllowed,
} from '../_lib/http.js';
import {
  complaintsAll,
  complaintUpdate,
  Status,
} from '../_lib/store.js';
import {
  loadRepById,
  getRepOf,
} from '../_lib/repsStore.js';
import { send } from '../_lib/mail.js';

const ADMIN_SECRET = process.env.ADMIN_SECRET || '';
const PORTAL_URL = process.env.REP_PORTAL_URL || 'https://dfs-complaints-web.vercel.app/rep';
const DAY_MS = 24 * 60 * 60 * 1000;
const REMINDER_DELAY_DAYS = Number(process.env.REP_DECISION_REMINDER_DAYS || 4) || 4;
const REMINDER_DELAY_MS = Math.max(1, REMINDER_DELAY_DAYS) * DAY_MS;
const REMINDER_CC = process.env.REP_DECISION_REMINDER_CC || 'complaint@dfs-diamon.de';

const SUPPORTED_LANGS = new Set(['de', 'en', 'fr', 'it', 'es']);
const S = (value) => (value ?? '').toString().trim();
const lower = (value) => S(value).toLowerCase();

const SUBJECTS = {
  de: (ticket) => `[DFS Complaint ${ticket}] Erinnerung: Entscheidung offen`,
  en: (ticket) => `[DFS Complaint ${ticket}] Reminder: decision pending`,
  fr: (ticket) => `[DFS Complaint ${ticket}] Rappel : décision en attente`,
  it: (ticket) => `[DFS Complaint ${ticket}] Promemoria: decisione in sospeso`,
  es: (ticket) => `[DFS Complaint ${ticket}] Recordatorio: decisión pendiente`,
};

const TEXTS = {
  de: ({ name, ticket, customer, days }) => `Hallo ${name || 'Team'},\n\n` +
    `für die Reklamation ${ticket} des Kunden ${customer} liegt seit ${days} Tagen ` +
    'noch keine Entscheidung vor.\n\n' +
    `Bitte melden Sie sich im DFS Kundenportal (${PORTAL_URL}) an und markieren Sie ` +
    'die Reklamation als angenommen oder abgelehnt.\n\n' +
    'Vielen Dank und viele Grüße\nIhr DFS Complaints Team',
  en: ({ name, ticket, customer, days }) => `Hello ${name || 'team'},\n\n` +
    `The complaint ${ticket} from customer ${customer} has been waiting for your ` +
    `decision for ${days} days.\n\n` +
    `Please sign in to the DFS complaints portal (${PORTAL_URL}) and mark the ` +
    'complaint as accepted or rejected.\n\n' +
    'Thank you!\nYour DFS complaints team',
  fr: ({ name, ticket, customer, days }) => `Bonjour ${name || 'équipe'},\n\n` +
    `La réclamation ${ticket} du client ${customer} attend votre décision depuis ` +
    `${days} jours.\n\n` +
    `Merci de vous connecter au portail clients DFS (${PORTAL_URL}) et d’indiquer ` +
    'si la réclamation est acceptée ou refusée.\n\n' +
    'Merci beaucoup !\nVotre équipe DFS Complaints',
  it: ({ name, ticket, customer, days }) => `Gentile ${name || 'team'},\n\n` +
    `la reclamazione ${ticket} del cliente ${customer} è in attesa della sua ` +
    `decisione da ${days} giorni.\n\n` +
    `Acceda al portale clienti DFS (${PORTAL_URL}) e contrassegni la pratica come ` +
    'accettata o rifiutata.\n\n' +
    'Grazie mille e cordiali saluti\nIl team DFS Complaints',
  es: ({ name, ticket, customer, days }) => `Hola ${name || 'equipo'},\n\n` +
    `La reclamación ${ticket} del cliente ${customer} lleva ${days} días esperando ` +
    'su decisión.\n\n' +
    `Inicie sesión en el portal de clientes DFS (${PORTAL_URL}) e indique si ` +
    'acepta o rechaza la reclamación.\n\n' +
    'Muchas gracias.\nSu equipo DFS Complaints',
};

function isAdmin(req) {
  const hdr = req.headers?.['x-admin-secret'];
  return typeof hdr === 'string' && !!ADMIN_SECRET && hdr === ADMIN_SECRET;
}

function normalizeLang(lang) {
  const lc = lower(lang).split(/[-_]/)[0];
  return SUPPORTED_LANGS.has(lc) ? lc : 'de';
}

function firstNonEmpty(...values) {
  for (const value of values) {
    const s = S(value);
    if (s.length > 0) return s;
  }
  return '';
}

function extractCompany(complaint) {
  const payload = complaint?.payload && typeof complaint.payload === 'object'
    ? complaint.payload
    : {};
  return firstNonEmpty(
    complaint?.company,
    complaint?.customer?.company,
    complaint?.account?.company,
    payload?.company,
    payload?.companyName,
    payload?.customerName,
    payload?.firma,
  );
}

function formatRepName(rep) {
  const name = [S(rep?.firstName), S(rep?.lastName)].filter(Boolean).join(' ').trim();
  return name || S(rep?.email) || S(rep?.id) || 'Team';
}

function baselineTimestamp(complaint) {
  const candidates = [
    complaint?.repReminderBaselineAt,
    complaint?.repAssignedAt,
    complaint?.repDecisionRequestedAt,
    complaint?.updatedAt,
    complaint?.createdAt,
  ];
  for (const candidate of candidates) {
    const ts = Number(candidate);
    if (Number.isFinite(ts) && ts > 0) return ts;
  }
  return null;
}

function shouldRemind(complaint, now) {
  if (!complaint || typeof complaint !== 'object') return false;
  if (!S(complaint.ticket)) return false;
  if (!S(complaint.email)) return false;
  if (Number(complaint.status) === Status.CLOSED) return false;
  if (S(complaint.decision)) return false;
  if (S(complaint.repDecision)) return false;
  const baseline = baselineTimestamp(complaint);
  if (!baseline) return false;
  if (now - baseline < REMINDER_DELAY_MS) return false;
  const alreadySent = Number(complaint.repReminderSentAt || 0);
  if (Number.isFinite(alreadySent) && alreadySent > 0) return false;
  return true;
}

async function resolveRep(complaint) {
  const repId = S(complaint?.repId);
  if (repId) {
    try {
      const rep = await loadRepById(repId);
      if (rep?.email) return rep;
    } catch (err) {
      console.warn('[rep-reminders] loadRepById failed', err?.message || err);
    }
  }
  const email = lower(complaint?.email);
  if (email) {
    try {
      const rep = await getRepOf(email);
      if (rep?.email) return rep;
    } catch (err) {
      console.warn('[rep-reminders] getRepOf failed', err?.message || err);
    }
  }
  return null;
}

function buildMessage(lang, data) {
  const normalizedLang = normalizeLang(lang);
  const subject = SUBJECTS[normalizedLang](data.ticket);
  const text = TEXTS[normalizedLang](data);
  return { subject, text, lang: normalizedLang };
}

export default async function handler(req, res) {
  setCors(req, res);
  if (req.method === 'OPTIONS') return noContent(res);
  if (!['GET', 'POST'].includes(req.method || '')) return methodNotAllowed(res);
  if (!isAdmin(req)) return bad(res, 'admin unauthorized', 401);

  try {
    const now = Date.now();
    const complaints = await complaintsAll();
    const reminders = [];
    let eligible = 0;

    for (const complaint of complaints || []) {
      if (!shouldRemind(complaint, now)) continue;
      eligible += 1;
      const rep = await resolveRep(complaint);
      if (!rep) continue;
      const customer = extractCompany(complaint) || S(complaint.email);
      const daysWaiting = Math.max(4, Math.floor((now - (baselineTimestamp(complaint) || now)) / DAY_MS));
      const message = buildMessage(rep.lang, {
        name: formatRepName(rep),
        ticket: complaint.ticket,
        customer,
        days: daysWaiting,
      });

      try {
        await send(rep.email, { ...message, cc: REMINDER_CC });
        await complaintUpdate(complaint.ticket, {
          repReminderSentAt: now,
          repReminderSentCount: Number(complaint.repReminderSentCount || 0) + 1,
        });
        reminders.push({
          ticket: complaint.ticket,
          repId: rep.id,
          repEmail: rep.email,
          lang: message.lang,
        });
      } catch (err) {
        console.error('[rep-reminders] send failed', err?.message || err);
      }
    }

    return ok(res, {
      ok: true,
      remindersSent: reminders.length,
      eligible,
      reminders,
      delayDays: REMINDER_DELAY_MS / DAY_MS,
    });
  } catch (err) {
    console.error('[rep-reminders] error', err);
    return bad(res, 'server error', 500);
  }
}
