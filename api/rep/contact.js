import type { VercelRequest, VercelResponse } from '@vercel/node';
import nodemailer from 'nodemailer';

export default async function handler(req: VercelRequest, res: VercelResponse) {
  if (req.method !== 'POST') {
    return res.status(405).json({ error: 'METHOD_NOT_ALLOWED' });
  }

  try {
    console.log('rep/contact body:', req.body);

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

    // Test-Override: complaint@dfs-diamon.de
    const overrideTo = (process.env.REP_CONTACT_OVERRIDE_TO ?? '').trim();

    const to = overrideTo || (repEmail || '').trim();

    if (!subject || !message || !to) {
      return res.status(400).json({ error: 'MISSING_REQUIRED_FIELDS' });
    }

    // 🔍 WICHTIG: SMTP-Konfiguration prüfen, bevor wir nodemailer verwenden
    const host = (process.env.SMTP_HOST ?? '').trim();
    const user = (process.env.SMTP_USER ?? '').trim();
    const pass = (process.env.SMTP_PASS ?? '').trim();
    const port = Number(process.env.SMTP_PORT ?? 587);

    if (!host || !user || !pass) {
      console.error('SMTP config missing', {
        hasHost: !!host,
        hasUser: !!user,
        hasPass: !!pass,
      });
      return res.status(500).json({ error: 'SMTP_NOT_CONFIGURED' });
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

    if (overrideTo && repEmail) {
      // hilfreich, um zu sehen, wohin es ursprünglich gegangen wäre
      lines.push(`(Ursprünglicher Empfänger: ${repEmail})`);
    }

    lines.push('');
    lines.push(message);

    const fullBody = lines.join('\n');

    const transporter = nodemailer.createTransport({
      host,
      port,
      secure: false,
      auth: {
        user,
        pass,
      },
    });

    // optional: Transport verifizieren (hilft beim Debuggen)
    // await transporter.verify();

    await transporter.sendMail({
      from: (process.env.MAIL_FROM ?? 'no-reply_dfs-complaints@gmx.net').trim(),
      to,
      bcc: (process.env.REP_CONTACT_BCC ?? '').trim() || undefined,
      subject: subject,
      text: fullBody,
    });

    return res.status(200).json({ ok: true });
  } catch (err: any) {
    console.error('rep/contact error', err);
    const msg =
      typeof err?.message === 'string'
        ? err.message
        : 'Internal server error';
    return res.status(500).json({ error: msg });
  }
}
