// api/_lib/mailer.js
import nodemailer from 'nodemailer';
import { mailConfigOk, resolveMailConfig } from './mail-config.js';

const MAIL = resolveMailConfig();
const { ok: mailOk, missing: missingMailEnv } = mailConfigOk(MAIL);

const FALLBACK_FROM = MAIL.from || 'DFS Complaints <no-reply_dfs-complaints@gmx.net>';

let transporter = null;
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
    };
  }
  const info = await transporter.sendMail({
    from: FALLBACK_FROM,
    to,
    cc,
    subject,
    html,
    text,
  });
  return { ok: true, id: info.messageId };
}
