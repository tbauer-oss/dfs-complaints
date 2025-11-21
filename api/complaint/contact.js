// api/complaint/contact.js
export const config = { runtime: 'nodejs' };

import { setCors, noContent, ok, bad, methodNotAllowed, readJson } from '../_lib/http.js';
import { getAuthUser } from '../_lib/auth.js';
import { complaintGet, userByEmail } from '../_lib/store.js';
import { getRepOf } from '../_lib/repsStore.js';
import { send, tpl } from '../_lib/mail.js';
import { sendMail } from '../_lib/mailer.js';

const QM_MAIL = process.env.MAIL_QM || 'complaint@dfs-diamon.de';
const LANGS = new Set(['de', 'en', 'fr', 'it', 'es']);

const S = (v) => (v ?? '').toString().trim();
const lower = (v) => S(v).toLowerCase();

function firstNonEmpty(...values) {
  for (const value of values) {
    const s = S(value);
    if (s.length > 0) return s;
  }
  return '';
}

function normLang(value) {
  const raw = String(value || '').toLowerCase();
  const two = raw.split(/[-_]/)[0];
  return LANGS.has(two) ? two : 'de';
}

function sanitizeSubject(value) {
  return S(value).replace(/[\r\n]+/g, ' ').trim();
}

function normalizeMessage(value) {
  return S(value).replace(/\r\n/g, '\n');
}

export default async function handler(req, res) {
  setCors(req, res);
  if (req.method === 'OPTIONS') return noContent(res);
  if (req.method !== 'POST') return methodNotAllowed(res);

  const user = getAuthUser(req);
  if (!user?.email) return bad(res, 'unauthorized', 401);

  try {
    const body = readJson(req);
    const ticket = S(body?.ticket).toUpperCase();
    const subject = sanitizeSubject(body?.subject);
    const message = normalizeMessage(body?.message);

    if (!ticket) return bad(res, 'ticket required', 400);
    if (!subject || !message) return bad(res, 'subject and message required', 400);

    const comp = await complaintGet(ticket);
    if (!comp) return bad(res, 'not found', 404);

    const userMail = lower(user.email);
    const compMail = lower(comp.email);
    if (!userMail || userMail !== compMail) return bad(res, 'forbidden', 403);

    let rep = null;
    try {
      rep = await getRepOf(userMail);
    } catch (err) {
      console.warn('[complaint/contact] failed to load rep', err?.message || err);
    }
    const repEmail = S(rep?.email);
    const hasRep = repEmail.includes('@');

    const target = hasRep ? repEmail : QM_MAIL;
    if (!target) return bad(res, 'recipient missing', 500);
    const cc = hasRep && QM_MAIL ? [QM_MAIL] : [];

    let account = null;
    try {
      account = await userByEmail(userMail);
    } catch (err) {
      console.warn('[complaint/contact] failed to load account', err?.message || err);
    }
    const payload = (comp?.payload && typeof comp.payload === 'object') ? comp.payload : {};

    const company = firstNonEmpty(
      account?.company,
      comp?.company,
      payload?.company,
      payload?.customerName,
      payload?.firma,
    );

    const accountName = `${S(account?.firstName)} ${S(account?.lastName)}`.trim();
    const contactName = firstNonEmpty(
      account?.contact,
      account?.contactName,
      account?.name,
      accountName,
      payload?.contact,
      payload?.contactName,
    );

    const lang = normLang(user?.lang || account?.lang || payload?.lang || req.headers['accept-language']);

    const repDisplay = hasRep
      ? firstNonEmpty(
          [S(rep?.firstName), S(rep?.lastName)].filter(Boolean).join(' ').trim(),
          repEmail,
        )
      : '';

    const lines = [
      'Kontakt über das DFS Kundenportal – Reklamation',
      '',
      `Ticket: ${ticket}`,
      `Kunde: ${company || '(unbekannt)'}`,
      `Kunden-E-Mail: ${user.email}`,
    ];
    if (contactName) lines.push(`Kontaktperson: ${contactName}`);
    if (hasRep) {
      lines.push(`Zugewiesener Ansprechpartner: ${repDisplay}`);
    } else {
      lines.push('Kein Ansprechpartner zugeordnet – Nachricht wird an complaint@dfs-diamon.de gesendet.');
    }
    lines.push('');
    lines.push(`Betreff: ${subject}`);
    lines.push('');
    lines.push('--- Nachricht ---');
    lines.push('');
    lines.push(message);

    const mailSubject = `[DFS Complaint ${ticket}] ${subject}`;

    let delivered = false;
    const mailText = lines.join('\n');

    try {
      await send(target, {
        subject: mailSubject,
        text: mailText,
        lang: 'de',
        cc,
      });
      delivered = true;
    } catch (err) {
      console.error('[complaint/contact] primary mail failed', err?.message || err);
      try {
        await sendMail({
          to: target,
          subject: mailSubject,
          text: mailText,
          cc,
        });
        delivered = true;
      } catch (fallbackErr) {
        console.error('[complaint/contact] fallback mail failed', fallbackErr?.message || fallbackErr);
        return bad(res, 'message_send_failed', 500);
      }
    }

    if (user.email && delivered) {
      try {
        const confirmation = tpl.messageConfirmation(
          {
            name: contactName,
            subject,
            message,
            channel: hasRep ? 'rep' : 'support',
          },
          lang,
        );
        await send(user.email, { ...confirmation, lang });
      } catch (err) {
        console.error('[complaint/contact] confirmation mail failed', err);
      }
    }

    return ok(res, { ok: true, viaRep: hasRep });
  } catch (err) {
    console.error('[complaint/contact] error', err);
    return bad(res, 'server error', 500);
  }
}
