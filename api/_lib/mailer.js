// api/_lib/mailer.js
import nodemailer from 'nodemailer';

const env = {
  host: process.env.SMTP_HOST || process.env.MAIL_HOST || process.env.MAIL_SERVER,
  port: Number(process.env.SMTP_PORT || process.env.MAIL_PORT || 587),
  user: process.env.SMTP_USER || process.env.MAIL_USER,
  pass: process.env.SMTP_PASS || process.env.MAIL_PASS,
  from: process.env.SMTP_FROM || process.env.MAIL_FROM,
};

const FALLBACK_FROM =
  (env.from && env.from.trim()) ||
  (env.user && env.user.trim()) ||
  'DFS Complaints <no-reply_dfs-complaints@gmx.net>';

let transporter = null;

function ensureTransporter() {
  if (transporter) return transporter;
  if (!env.host || !env.user || !env.pass) {
    throw new Error('SMTP env missing (SMTP_HOST, SMTP_USER, SMTP_PASS)');
  }

  const secure = env.port === 465;
  transporter = nodemailer.createTransport({
    host: env.host,
    port: env.port,
    secure,
    auth: { user: env.user, pass: env.pass },
    tls: { minVersion: 'TLSv1.2', servername: env.host },
  });

  return transporter;
}

function normalizeText(html, text) {
  if (text && typeof text === 'string' && text.trim()) return text;
  if (!html || typeof html !== 'string') return '';
  return html
    .replace(/\r\n/g, '\n')
    .replace(/<\/?p>/gi, '\n')
    .replace(/<br\s*\/?>(?=\s*<)/gi, '\n')
    .replace(/<br\s*\/?>(?!\n)/gi, '\n')
    .replace(/<[^>]+>/g, ' ')
    .replace(/\s{2,}/g, ' ')
    .trim();
}

export async function sendMail({ to, subject, html, text, cc }) {
  const tx = ensureTransporter();
  const info = await tx.sendMail({
    from: FALLBACK_FROM,
    to,
    cc,
    subject,
    html,
    text: normalizeText(html, text),
  });
  return { ok: true, id: info.messageId };
}
