// api/_lib/mailer.js
import nodemailer from 'nodemailer';

const {
  SMTP_HOST,
  SMTP_PORT,
  SMTP_USER,
  SMTP_PASS,
  SMTP_FROM,
  MAIL_FROM,
} = process.env;

const FALLBACK_FROM =
  (SMTP_FROM && SMTP_FROM.trim()) ||
  (MAIL_FROM && MAIL_FROM.trim()) ||
  (SMTP_USER && SMTP_USER.trim()) ||
  'DFS Complaints <no-reply_dfs-complaints@gmx.net>';

let transporter = null;
if (SMTP_HOST && (SMTP_USER ? SMTP_PASS : true)) {
  const port = Number(SMTP_PORT || 587);
  transporter = nodemailer.createTransport({
    host: SMTP_HOST,
    port,
    secure: port === 465,
    auth: SMTP_USER && SMTP_PASS ? { user: SMTP_USER, pass: SMTP_PASS } : undefined,
  });
}

export async function sendMail({ to, subject, html, cc }) {
  if (!transporter) return { ok: false, reason: 'no-transporter' };
  const info = await transporter.sendMail({
    from: FALLBACK_FROM,
    to,
    cc,
    subject,
    html
  });
  return { ok: true, id: info.messageId };
}
