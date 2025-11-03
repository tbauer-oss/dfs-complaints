// api/_lib/mailer.js
import nodemailer from 'nodemailer';

const {
  SMTP_HOST, SMTP_PORT, SMTP_USER, SMTP_PASS, SMTP_FROM
} = process.env;

let transporter = null;
if (SMTP_HOST && SMTP_PORT && SMTP_FROM) {
  transporter = nodemailer.createTransport({
    host: SMTP_HOST,
    port: Number(SMTP_PORT || 587),
    secure: Number(SMTP_PORT || 587) === 465,
    auth: (SMTP_USER && SMTP_PASS) ? { user: SMTP_USER, pass: SMTP_PASS } : undefined
  });
}

export async function sendMail({ to, subject, html, cc }) {
  if (!transporter) return { ok: false, reason: 'no-transporter' };
  const info = await transporter.sendMail({
    from: SMTP_FROM,
    to,
    cc,
    subject,
    html
  });
  return { ok: true, id: info.messageId };
}
