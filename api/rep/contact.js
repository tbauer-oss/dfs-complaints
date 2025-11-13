// api/rep/contact.ts
import type { VercelRequest, VercelResponse } from '@vercel/node';
import { send } from '../_lib/mail';  // <--- nutzt deinen bestehenden Mail-Layer

export default async function handler(req: VercelRequest, res: VercelResponse) {
  if (req.method !== 'POST') {
    return res.status(405).json({ error: 'METHOD_NOT_ALLOWED' });
  }

  try {
    const {
      // wir nehmen alles an, was dein Frontend schickt
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

    // 🔴 Minimal: subject + message müssen da sein
    if (!subject || !message) {
      return res.status(400).json({
        error: 'MISSING_REQUIRED_FIELDS',
        detail: {
          subjectEmpty: !subject,
          messageEmpty: !message,
        },
      });
    }

    // 🟡 ZIELADRESSE: **immer** complaint@dfs-diamon.de (für Tests)
    // später kannst du das beliebig ändern/parametrisieren
    const to = (process.env.REP_CONTACT_OVERRIDE_TO || 'complaint@dfs-diamon.de').trim();

    const contactName = [contactFirstName, contactLastName]
      .filter((s) => typeof s === 'string' && s.trim().length > 0)
      .join(' ')
      .trim();

    const lines: string[] = [];

    if (company)      lines.push(`Firma: ${company}`);
    if (companyEmail) lines.push(`Firmen-E-Mail: ${companyEmail}`);
    if (contactName)  lines.push(`Kontaktperson: ${contactName}`);
    if (repFirstName || repLastName) {
      lines.push(
        `Vertreter: ${(repFirstName ?? '')} ${(repLastName ?? '')}`.trim()
      );
    }
    lines.push('');
    lines.push(message);

    const text = lines.join('\n');

    // 📨 Versand über deinen bestehenden Mail-Layer (CI, HTML, Logo, SMTP etc.)
    const info = await send(to, {
      subject,
      text,
      lang: 'de', // oder später dynamisch
    });

    console.log('rep/contact sent', { to, messageId: info?.messageId });

    return res.status(200).json({ ok: true });
  } catch (err: any) {
    console.error('rep/contact error', err);
    return res.status(500).json({
      error: 'INTERNAL_MAIL_ERROR',
      detail: err?.message ?? String(err),
    });
  }
}
