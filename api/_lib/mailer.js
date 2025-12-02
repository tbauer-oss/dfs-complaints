// api/_lib/mailer.js
import nodemailer from 'nodemailer';
import { mailConfigOk, resolveMailConfig } from './mail-config.js';
import { applyTestMailRouting, loadAppMeta } from './appMeta.js';

const MAIL = resolveMailConfig();
const { ok: mailOk, missing: missingMailEnv } = mailConfigOk(MAIL);

const FALLBACK_FROM = MAIL.from || 'DFS Complaints <noreply@dfs-diamon.com>';
const isSecure = MAIL.port === 465;

let transporter = null;
if (mailOk) {
  transporter = nodemailer.createTransport({
    host: MAIL.host,
    port: MAIL.port,
    secure: isSecure,
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

  const info = await transporter.sendMail({
    from: FALLBACK_FROM,
    envelope: MAIL.user ? { from: MAIL.user, to: toList, cc: ccList } : undefined,
    to: toList,
    cc: ccList,
    subject: subjectOut,
    html,
    text,
  });
  return { ok: true, id: info.messageId };
}
