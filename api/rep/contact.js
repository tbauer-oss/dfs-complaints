// api/rep/contact.js
import { setCors } from '../_lib/cors.js';
import { send, tpl } from '../_lib/mail.js'; // Pfad wie bei deinen anderen Routen
import { mailConfigOk, resolveMailConfig } from '../_lib/mail-config.js';

function asString(v) {
  return (typeof v === 'string' ? v : '').trim();
}

const LANGS = new Set(['de', 'en', 'fr', 'it', 'es']);
function normLang(x) {
  const lc = String(x || '').toLowerCase();
  const two = lc.split(/[-_]/)[0];
  return LANGS.has(two) ? two : 'de';
}

const MAIL = resolveMailConfig();
const { ok: mailOk, missing: missingMailEnv } = mailConfigOk(MAIL);

export default async function handler(req, res) {
  setCors(req, res, 'Content-Type, Authorization, X-Gate');
  if (req.method === 'OPTIONS') {
    return res.status(204).end();
  }
  if (req.method !== 'POST') {
    return res.status(405).json({ error: 'Method not allowed' });
  }

  try {
    if (!mailOk) {
      return res.status(503).json({ error: 'smtp_config_missing', missing: missingMailEnv });
    }

    const body = req.body || {};

    const repEmail        = asString(body.repEmail);
    const repFirstName    = asString(body.repFirstName);
    const repLastName     = asString(body.repLastName);
    const company         = asString(body.company);
    const companyEmail    = asString(body.companyEmail);
    const contactFirst    = asString(body.contactFirstName);
    const contactLast     = asString(body.contactLastName);
    const subjectRaw      = asString(body.subject);
    const messageRaw      = asString(body.message);
    const lang            = normLang(body.lang || req.headers['accept-language']);

    if (!subjectRaw || !messageRaw) {
      return res.status(400).json({ error: 'Missing subject or message' });
    }

    const contactName = [contactFirst, contactLast]
      .filter((s) => s.length > 0)
      .join(' ')
      .trim();

    const lines = [];

    lines.push('Kontakt über das DFS Kundenportal – Vertreterkontakt');
    lines.push('');
    if (company)      lines.push(`Firma: ${company}`);
    if (companyEmail) lines.push(`Firmen-E-Mail: ${companyEmail}`);
    if (contactName)  lines.push(`Kontaktperson: ${contactName}`);
    if (repFirstName || repLastName || repEmail) {
      lines.push(
        `Zugewiesener Vertreter: ${
          [repFirstName, repLastName].filter(Boolean).join(' ') || repEmail || '–'
        }`
      );
    }
    lines.push('');
    lines.push('--- Nachricht des Kunden ---');
    lines.push('');
    lines.push(messageRaw);

    const fullText = lines.join('\n');

    // -------------------------------------------------
    // 1) Test-Override (für dich zum Spielen)
    // -------------------------------------------------
    // Wenn REP_CONTACT_OVERRIDE_TO gesetzt ist, geht ALLES dorthin.
    // Beispiel in Vercel:
    //   REP_CONTACT_OVERRIDE_TO=complaint@dfs-diamon.de
    //
    const overrideTo = asString(process.env.REP_CONTACT_OVERRIDE_TO);

    // -------------------------------------------------
    // 2) Normales Verhalten (wenn kein Override)
    // -------------------------------------------------
    const fallbackQM = asString(process.env.MAIL_QM) || 'complaint@dfs-diamon.de';
    const repValid   = repEmail && repEmail.includes('@');

    const normalTo = repValid ? repEmail : fallbackQM;

    // -------------------------------------------------
    // 3) Finale Zieladresse: Override schlägt alles
    // -------------------------------------------------
    const toAddress = overrideTo
      ? overrideTo
      : normalTo;

    await send(toAddress, {
      subject: `[Rep-Kontakt] ${subjectRaw}`,
      text: fullText,
      lang: 'de',
    });

    const hasCompanyEmail = companyEmail && companyEmail.includes('@');
    if (hasCompanyEmail) {
      const confirmation = tpl.messageConfirmation(
        {
          name: contactName,
          subject: subjectRaw,
          message: messageRaw,
          channel: 'rep',
        },
        lang,
      );

      await send(companyEmail, {
        ...confirmation,
        lang,
      });
    }

    return res.status(200).json({ ok: true });
  } catch (err) {
    console.error('rep/contact error', err);
    const msg = err && err.message ? err.message : String(err);
    return res.status(500).json({
      error: 'rep_contact_failed',
      message: msg,
    });
  }
}
