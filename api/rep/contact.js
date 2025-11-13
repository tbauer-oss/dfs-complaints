import type { VercelRequest, VercelResponse } from '@vercel/node';
import nodemailer from 'nodemailer';

export default async function handler(req: VercelRequest, res: VercelResponse) {
  if (req.method !== 'POST') {
    return res.status(405).json({ error: 'Method not allowed' });
  }

  try {
    const {
      repEmail,
      repFirstName,
      repLastName,
      company,
      companyEmail,
      contactFirstName,
      contactLastName,
      subject,
      message,
    } = req.body || {};

    if (!repEmail || !subject || !message) {
      return res.status(400).json({ error: 'Missing required fields' });
    }

    const contactName = [contactFirstName, contactLastName]
      .filter((s) => typeof s === 'string' && s.trim().length > 0)
      .join(' ')
      .trim();

    const lines: string[] = [];

    if (company)      lines.push(`Firma: ${company}`);
    if (companyEmail) lines.push(`Firmen-E-Mail: ${companyEmail}`);
    if (contactName)  lines.push(`Kontaktperson: ${contactName}`);
    lines.push('');
    lines.push(message);

    const fullBody = lines.join('\n');

    // Mail-Transporter (Beispiel – hier deine SMTP-Daten einsetzen)
    const transporter = nodemailer.createTransport({
      host: process.env.SMTP_HOST,
      port: Number(process.env.SMTP_PORT ?? 587),
      secure: false,
      auth: {
        user: process.env.SMTP_USER,
        pass: process.env.SMTP_PASS,
      },
    });

    await transporter.sendMail({
      from: process.env.MAIL_FROM ?? 'no-reply@dfs-diamon.de',
      to: repEmail,
      subject: subject,
      text: fullBody,
    });

    return res.status(200).json({ ok: true });
  } catch (err) {
    console.error('rep/contact error', err);
    return res.status(500).json({ error: 'Internal server error' });
  }
}
