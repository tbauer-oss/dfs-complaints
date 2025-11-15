// api/rep/contact-qm.js
import { setCors } from '../_lib/cors.js';
import { getRepFromAuthHeader } from '../_lib/repAuth.js';
import { loadRepById } from '../_lib/repsStore.js';
import { send } from '../_lib/mail.js';

function asString(v) {
  return (typeof v === 'string' ? v : '').trim();
}

const QM_MAIL = asString(process.env.MAIL_QM) || 'complaint@dfs-diamon.de';

export default async function handler(req, res) {
  setCors(req, res, 'Content-Type, Authorization, X-Gate');
  if (req.method === 'OPTIONS') {
    return res.status(204).end();
  }
  if (req.method !== 'POST') {
    return res.status(405).json({ error: 'method_not_allowed' });
  }

  try {
    const auth = getRepFromAuthHeader(req);
    if (!auth) {
      return res.status(401).json({ error: 'unauthorized' });
    }

    const rep = await loadRepById(auth.repId);
    if (!rep || !rep.email || !rep.email.includes('@')) {
      return res.status(400).json({ error: 'rep_email_missing' });
    }

    let body = {};
    try {
      if (typeof req.body === 'string') {
        body = JSON.parse(req.body || '{}');
      } else if (req.body && typeof req.body === 'object') {
        body = req.body;
      }
    } catch (_) {
      body = {};
    }

    const subjectRaw = asString(body.subject);
    const messageRaw = asString(body.message).replace(/\r\n/g, '\n');
    const phone      = asString(body.phone);
    const company    = asString(body.company);

    if (!subjectRaw || !messageRaw) {
      return res.status(400).json({ error: 'subject_or_message_required' });
    }

    const repName = [asString(rep.firstName), asString(rep.lastName)]
      .filter((s) => s.length > 0)
      .join(' ')
      .trim();

    const lines = [];
    lines.push('Kontakt eines DFS-Vertreters an QM / Support');
    lines.push('');
    lines.push(`Vertreter: ${repName || '–'}`);
    lines.push(`E-Mail: ${rep.email}`);
    if (asString(rep.region)) {
      lines.push(`Region: ${asString(rep.region)}`);
    }
    if (company) {
      lines.push(`Firma: ${company}`);
    }
    if (phone) {
      lines.push(`Telefon: ${phone}`);
    }
    lines.push('');
    lines.push('--- Nachricht ---');
    lines.push('');
    lines.push(messageRaw);

    const textBody = lines.join('\n');
    const displayName = repName || rep.email;
    const fromHeader = displayName && rep.email
      ? `${displayName} <${rep.email}>`
      : rep.email;

    await send(QM_MAIL, {
      subject: `[Rep-Support] ${subjectRaw}`,
      text: textBody,
      lang: 'de',
      from: fromHeader,
      replyTo: rep.email,
    });

    return res.status(200).json({ ok: true });
  } catch (err) {
    console.error('[rep/contact-qm] error', err);
    const msg = err && err.message ? err.message : String(err);
    return res.status(500).json({ error: 'rep_contact_qm_failed', message: msg });
  }
}
