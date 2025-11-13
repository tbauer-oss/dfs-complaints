import type { VercelRequest, VercelResponse } from '@vercel/node';
import nodemailer from 'nodemailer';

export default async function handler(req: VercelRequest, res: VercelResponse) {
  if (req.method !== 'POST') {
    return res.status(405).json({ error: 'METHOD_NOT_ALLOWED' });
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
    } = (req.body ?? {}) as Record<string, any>;

    // 🟡 Testziel: alles an complaint@dfs-diamon.de
    // Später reicht es, diese Zeile auf repEmail zu ändern.
    const overrideTo = (process.env.REP_CONTACT_OVERRIDE_TO ?? '').trim();
    const to = overrideTo || 'complaint@dfs-diamon.de';

    if (!subject || !message || !to) {
      return res.status(400).json({
        error: 'MISSING_REQUIRED_FIELDS',
        detail: { subjectEmpty: !subject, messageEmpty: !message, toEmpty: !to },
      });
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
      lines.push(`Vertreter: ${(repFirstName ?? '')} ${(repLastName ?? '')}`.trim());
    }
    lines.push('');
    lines.push(message);

    const fullBody = lines.join('\n');

    // 📨 SMTP-Transporter – hier MÜSSEN deine ENV-Variablen stimmen!
    const transporter = nodemailer.createTransport({
      host: process.env.SMTP_HOST,
      port: Number(process.env.SMTP_PORT ?? 587),
      secure: false,
      auth: {
        user: process.env.SMTP_USER,
        pass: process.env.SMTP_PASS,
      },
    });

    // optional: kurz Loggen, ob ENV überhaupt da ist
    console.log('REP_CONTACT: sending mail', {
      to,
      host: process.env.SMTP_HOST,
      user: process.env.SMTP_USER,
    });

    await transporter.sendMail({
      from: process.env.MAIL_FROM ?? 'no-reply_dfs-complaints@gmx.net',
      to,
      subject,
      text: fullBody,
    });

    return res.status(200).json({ ok: true });
  } catch (err: any) {
    console.error('rep/contact error', err);
    return res.status(500).json({
      error: 'INTERNAL_MAIL_ERROR',
      detail: err?.message ?? String(err),
    });
  }
}
