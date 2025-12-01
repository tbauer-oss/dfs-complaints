// api/_lib/mailer.js
import nodemailer from 'nodemailer';
import { mailConfigOk, resolveMailConfig } from './mail-config.js';
import { applyTestMailRouting, loadAppMeta } from './appMeta.js';

const MAIL = resolveMailConfig();
const { ok: mailOk, missing: missingMailEnv } = mailConfigOk(MAIL);

const FALLBACK_FROM = MAIL.from || 'DFS Complaints <no-reply_dfs-complaints@gmx.net>';

let transporter = null;
let transporterHealthy = true;
if (mailOk) {
  transporter = nodemailer.createTransport({
    host: MAIL.host,
    port: MAIL.port,
    secure: MAIL.port === 465,
    auth: MAIL.user && MAIL.pass ? { user: MAIL.user, pass: MAIL.pass } : undefined,
  });
}

export async function sendMail({ to, subject, html, text, cc }) {
  if (!transporter) {
    return {
      ok: false,
      reason: 'missing-smtp-config',
      missing: missingMailEnv,
      userMessage: 'Maildienst nicht konfiguriert – SMTP-Zugangsdaten prüfen.',
    };
  }
  let meta = null;
  try { meta = await loadAppMeta(); } catch (_) {}
  const routing = applyTestMailRouting(meta, { to, cc, subject });
  const toList = routing.to && routing.to.length > 0 ? routing.to : to;
  const ccList = routing.cc && routing.cc.length > 0 ? routing.cc : undefined;
  const subjectOut = routing.subject || subject;

  if (routing.suppressed) {
    console.warn('[mail] test mode active – suppressing mail send', { to });
    return {
      ok: false,
      reason: 'test-mode-suppressed',
      skipped: true,
      userMessage: 'Testmodus aktiv – Mailversand wurde unterdrückt.',
    };
  }

  if (!transporterHealthy) {
    return {
      ok: false,
      reason: 'transporter-disabled',
      userMessage: 'Maildienst aktuell deaktiviert wegen eines früheren Fehlers.',
    };
  }

  try {
    const info = await transporter.sendMail({
      from: FALLBACK_FROM,
      to: toList,
      cc: ccList,
      subject: subjectOut,
      html,
      text,
    });
    return { ok: true, id: info.messageId };
  } catch (err) {
    const isStackOverflow = err instanceof RangeError && /stack size/i.test(err.message || '');
    const message = err?.message || String(err);
    if (isStackOverflow) {
      transporterHealthy = false;
    }
    return {
      ok: false,
      reason: isStackOverflow ? 'stack-overflow' : err?.code || 'send-error',
      message,
      userMessage:
        err?.response?.code === 'EAUTH'
          ? 'SMTP-Authentifizierung fehlgeschlagen – Zugangsdaten prüfen.'
          : isStackOverflow
              ? 'Mailer stack overflow – please check SMTP/test-mode routing configuration.'
              : 'Maildienst nicht erreichbar – SMTP-Verbindung oder Quota prüfen.',
    };
  }
}
