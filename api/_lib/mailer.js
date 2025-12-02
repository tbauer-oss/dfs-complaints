// api/_lib/mailer.js
import nodemailer from 'nodemailer';
import { mailConfigOk, resolveMailConfig } from './mail-config.js';
import { applyTestMailRouting, loadAppMeta } from './appMeta.js';

const MAIL = resolveMailConfig();
const { ok: mailOk, missing: missingMailEnv } = mailConfigOk(MAIL);

const FALLBACK_FROM = MAIL.from || 'DFS Complaints <noreply@dfs-diamon.com>';
const primaryPort = MAIL.port;
const isSecure = primaryPort === 465;
const fallbackPort = isSecure ? 587 : null;

let transporter = null;
if (mailOk) {
  transporter = buildTransport(primaryPort);
}

function buildTransport(port) {
  const secure = port === 465;
  return nodemailer.createTransport({
    host: MAIL.host,
    port,
    secure,
    requireTLS: !secure,
    name: MAIL.host,
    auth: MAIL.user && MAIL.pass ? { user: MAIL.user, pass: MAIL.pass } : undefined,
    tls: {
      servername: MAIL.host,
      minVersion: 'TLSv1.2',
      rejectUnauthorized: true,
    },
    connectionTimeout: 15000,
    greetingTimeout: 8000,
  });
}

function shouldFallback(err) {
  const code = (err?.code || '').toString();
  return ['ESOCKET', 'ECONNECTION', 'ETIMEDOUT', 'ECONNRESET', 'EPROTO'].includes(code);
}

export async function sendMail({ to, subject, html, text, cc }) {
  if (!transporter) {
    return {
      ok: false,
      reason: 'missing-smtp-config',
      missing: missingMailEnv,
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
    return { ok: false, reason: 'test-mode-suppressed', skipped: true };
  }

  const sendOptions = {
    from: FALLBACK_FROM,
    envelope: MAIL.user ? { from: MAIL.user, to: toList, cc: ccList } : undefined,
    to: toList,
    cc: ccList,
    subject: subjectOut,
    html,
    text,
  };

  try {
    const info = await transporter.sendMail(sendOptions);
    return { ok: true, id: info.messageId };
  } catch (err) {
    if (fallbackPort && shouldFallback(err)) {
      console.warn('[mail] primary SMTP port failed, retrying with STARTTLS', {
        port: primaryPort,
        fallbackPort,
        code: err?.code,
        responseCode: err?.responseCode,
        command: err?.command,
      });
      transporter = buildTransport(fallbackPort);
      const info = await transporter.sendMail(sendOptions);
      return { ok: true, id: info.messageId, fallback: true };
    }

    console.error('[mail] send failed', {
      code: err?.code,
      responseCode: err?.responseCode,
      command: err?.command,
      message: err?.message,
    });
    throw err;
  }
}
