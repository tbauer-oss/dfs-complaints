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

    // 🔧 Test-/Override-Adresse aus ENV (z. B. complaint@dfs-diamon.de)
    const overrideTo = (process.env.REP_CONTACT_OVERRIDE_TO ?? 'complaint@dfs-diamon.de').trim();

    // Empfängerlogik:
    // - Wenn Override gesetzt -> immer dahin
    // - sonst normal: Vertreteradresse aus dem Payload
    const to = overrideTo || (repEmail || '').trim();

    if (!subject || !message || !to) {
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
    if (repFirstName || repLastName) {
      const repName = [repFirstName, repLastName]
        .filter((s) => typeof s === 'string' && s.trim().length > 0)
        .join(' ')
        .trim();
      if (repName) lines.push(`Vertreter: ${repName}`);
    }
    if (overrideTo) {
      // Hilfreich im Body zu sehen, an wen es ursprünglich gegangen wäre
      if (repEmail) lines.push(`(Ursprünglicher Empfänger: ${repEmail})`);
    }

    lines.push('');
    lines.push(message);

    const fullBody = lines.join('\n');

    // Mail-Transporter (deine SMTP-Daten)
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
      from: process.env.MAIL_FROM ?? 'no-reply_dfs-complaints@gmx.net',
      to,
      // Optional: später BCC einschalten
      bcc: (process.env.REP_CONTACT_BCC ?? '').trim() || undefined,
      subject: subject,
      text: fullBody,
    });

    return res.status(200).json({ ok: true });
  } catch (err) {
    console.error('rep/contact error', err);
    return res.status(500).json({ error: 'Internal server error' });
  }
}
