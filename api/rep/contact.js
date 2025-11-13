// api/rep/contact.js
import { send } from '../_lib/mail.js'; // oder '../_lib/mail' je nach Projekt

// Hilfsfunktion: immer sauberer String
function asString(v) {
  return (typeof v === 'string' ? v : '').trim();
}

export default async function handler(req, res) {
  if (req.method !== 'POST') {
    return res.status(405).json({ error: 'Method not allowed' });
  }

  try {
    const body = req.body || {};

    const repEmail        = asString(body.repEmail);        // kommt mit, wird fürs TESTEN aber ignoriert
    const repFirstName    = asString(body.repFirstName);
    const repLastName     = asString(body.repLastName);
    const company         = asString(body.company);
    const companyEmail    = asString(body.companyEmail);
    const contactFirst    = asString(body.contactFirstName);
    const contactLast     = asString(body.contactLastName);
    const subjectRaw      = asString(body.subject);
    const messageRaw      = asString(body.message);

    if (!subjectRaw || !messageRaw) {
      return res.status(400).json({ error: 'Missing subject or message' });
    }

    const contactName = [contactFirst, contactLast]
      .filter((s) => s.length > 0)
      .join(' ')
      .trim();

    const lines = [];

    lines.push('Kontakt über das DFS Kundenportal – Vertreterkontakt');
    lines.push('');
    if (company)      lines.push(`Firma: ${company}`);
    if (companyEmail) lines.push(`Firmen-E-Mail: ${companyEmail}`);
    if (contactName)  lines.push(`Kontaktperson: ${contactName}`);
    if (repEmail)     lines.push(`Zugeteilter Vertreter (App): ${repEmail}`);
    lines.push('');
    lines.push('--- Nachricht des Kunden ---');
    lines.push('');
    lines.push(messageRaw);

    const fullText = lines.join('\n');

    // 🔴 TEST: IMMER an complaint@dfs-diamon.de
    const toAddress = 'complaint@dfs-diamon.de';

    await send(toAddress, {
      subject: `[Rep-Kontakt] ${subjectRaw}`,
      text: fullText,
      lang: 'de',
    });

    return res.status(200).json({ ok: true });
  } catch (err) {
    console.error('rep/contact error', err);
    const msg = err && err.message ? err.message : String(err);
    return res.status(500).json({
      error: 'rep_contact_failed',
      message: msg,
    });
  }
}
