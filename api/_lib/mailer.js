// api/_lib/mailer.js
import nodemailer from 'nodemailer';
import { mailConfigOk, resolveMailConfig } from './mail-config.js';
import { applyTestMailRouting, loadAppMeta } from './appMeta.js';

const MAIL = resolveMailConfig();
const { ok: mailOk, missing: missingMailEnv } = mailConfigOk(MAIL);

const FALLBACK_FROM = MAIL.from || 'DFS Complaints <noreply@dfs-diamon.com>';

function createTransporter() {
  return nodemailer.createTransport({
    host: MAIL.host,
    port: MAIL.port,
    secure: MAIL.port === 465,
    auth: MAIL.user && MAIL.pass ? { user: MAIL.user, pass: MAIL.pass } : undefined,
  });
}

let transporter = mailOk ? createTransporter() : null;
let transporterHealthy = true;

export async function sendMail({ to, subject, html, text, cc }) {
  try {
    const diagnosticsBase = {
      host: MAIL.host,
      port: MAIL.port,
      userPresent: !!MAIL.user,
    };
    if (!transporter) {
      return {
        ok: false,
        reason: 'missing-smtp-config',
        missing: missingMailEnv,
        diagnostics: { ...diagnosticsBase, missing: missingMailEnv },
        userMessage: 'Maildienst nicht konfiguriert – SMTP-Zugangsdaten prüfen.',
      };
    }

    let meta = null;
    try { meta = await loadAppMeta(); } catch (_) {}
    const routing = applyTestMailRouting(meta, { to, cc, subject });
    const diagnostics = {
      ...diagnosticsBase,
      testMode: !!meta?.testMode,
      testEmailConfigured: !!meta?.testEmail,
      suppressed: !!routing.suppressed,
    };
    const toList = routing.to && routing.to.length > 0 ? routing.to : to;
    const ccList = routing.cc && routing.cc.length > 0 ? routing.cc : undefined;
    const subjectOut = routing.subject || subject;

    if (routing.suppressed) {
      console.warn('[mail] test mode active – suppressing mail send', { to });
      return {
        ok: false,
        reason: 'test-mode-suppressed',
        skipped: true,
        diagnostics,
        userMessage: 'Testmodus aktiv – Mailversand wurde unterdrückt.',
      };
    }

    if (!transporterHealthy) {
      return {
        ok: false,
        reason: 'transporter-disabled',
        diagnostics,
        userMessage: 'Maildienst aktuell deaktiviert wegen eines früheren Fehlers.',
      };
    }

    const attemptSend = async ({ allowRebuild = false } = {}) => {
      try {
        const info = await transporter.sendMail({
          from: FALLBACK_FROM,
          to: toList,
          cc: ccList,
          subject: subjectOut,
          html,
          text,
        });
        transporterHealthy = true;
        return { ok: true, info, rebuilt: allowRebuild };
      } catch (err) {
        const isStackOverflow = err instanceof RangeError && /stack size/i.test(err.message || '');
        const message = err?.message || String(err);
        if (isStackOverflow) {
          transporterHealthy = false;
          if (allowRebuild && mailOk) {
            try {
              transporter = createTransporter();
              const retry = await attemptSend({ allowRebuild: false });
              return { ...retry, rebuilt: true };
            } catch (retryErr) {
              return { ok: false, err: retryErr, message: retryErr?.message || String(retryErr), stackOverflow: true };
            }
          }
        }

        return { ok: false, err, message, stackOverflow: isStackOverflow };
      }
    };

    const outcome = await attemptSend({ allowRebuild: true });
    if (outcome.ok) {
      const { info, rebuilt } = outcome;
      return { ok: true, id: info.messageId, diagnostics: { ...diagnostics, rebuiltTransport: rebuilt } };
    }

    const err = outcome.err;
    const isStackOverflow = outcome.stackOverflow;
    const message = outcome.message || err?.message || String(err);

    return {
      ok: false,
      reason: isStackOverflow ? 'stack-overflow' : err?.code || 'send-error',
      message,
      diagnostics: { ...diagnostics, rebuiltTransport: outcome.rebuilt === true },
      userMessage:
        err?.response?.code === 'EAUTH'
          ? 'SMTP-Authentifizierung fehlgeschlagen – Zugangsdaten prüfen.'
          : isStackOverflow
              ? 'Mailer stack overflow – bitte SMTP/Testmodus/Routing-Konfiguration prüfen (Host/Port/User).'
              : 'Maildienst nicht erreichbar – SMTP-Verbindung oder Quota prüfen.',
    };
  }
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
      diagnostics: {
        host: MAIL.host,
        port: MAIL.port,
        userPresent: !!MAIL.user,
      },
      userMessage: isStackOverflow
        ? 'Mailer stack overflow – bitte Maildienst-Konfiguration prüfen.'
        : 'Mailversand fehlgeschlagen – Bitte SMTP/Testmodus-Konfiguration prüfen.',
    };
  }
}
