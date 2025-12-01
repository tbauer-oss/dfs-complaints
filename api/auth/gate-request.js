export const config = { runtime: 'nodejs' };

import { handlePreflight, ok, bad, methodNotAllowed, readJson, setCors } from '../_lib/http.js';
import { randomGateCode, hashGateCode } from '../_lib/gate.js';
import { gateStoreSet, userByEmail } from '../_lib/store.js';
import { sendMail } from '../_lib/mailer.js';

const INTERNAL_GATE_EMAIL = process.env.GATE_NOTIFY_EMAIL || 'complaint@dfs-diamon.de';

const isPreview = process.env.VERCEL_ENV !== 'production';

function normalizeString(value) {
  return String(value || '').trim();
}

export default async function handler(req, res) {
  setCors(req, res);
  if (handlePreflight(req, res)) return;
  if (req.method !== 'POST') return methodNotAllowed(res);

  try {
    const body = readJson(req);
    const email = normalizeString(body.email).toLowerCase();
    const company = normalizeString(
      body.company ||
      body.companyName ||
      body.company_name ||
      body.organization ||
      body.firma ||
      body.business
    );
    const contact = normalizeString(body.contact || `${body.firstName || ''} ${body.lastName || ''}`);
    const note = normalizeString(body.note || body.message || '');

    if (!email) return bad(res, 'missing email', 400);
    if (!company) return bad(res, 'missing company', 400);

    const existingUser = await userByEmail(email);
    const isActiveUser =
      !!existingUser &&
      !existingUser.revoked &&
      (existingUser.status === 'active' || existingUser.status == null);
    if (isActiveUser) {
      return bad(res, 'email already registered', 409);
    }

    const gateCode = randomGateCode();
    const codeHash = hashGateCode(gateCode);
    if (!codeHash) return bad(res, 'failed to create gate code', 500);

    await gateStoreSet(email, {
      codeHash,
      used: false,
      meta: { company, contact, note: note || undefined },
    });

    let mailSent = false;
    let mailError = null;
    let mailDiagnostics = null;
    try {
      const html = `
        <p>Neue Gate-Code Anfrage:</p>
        <ul>
          <li><strong>Email:</strong> ${email}</li>
          <li><strong>Firma:</strong> ${company}</li>
          ${contact ? '<li><strong>Kontakt:</strong> ' + contact + '</li>' : ''}
        </ul>
        ${note ? '<p><strong>Nachricht:</strong><br>' + note.replace(/\n/g, '<br>') + '</p>' : ''}
        <p><strong>Gate-Passwort:</strong> ${gateCode}</p>
        <p>Bitte prüfen und dem Kunden manuell mitteilen.</p>
      `;
      const text = [
        'Neue Gate-Code Anfrage:',
        `Email: ${email}`,
        `Firma: ${company}`,
        contact ? `Kontakt: ${contact}` : null,
        note ? '' : null,
        note ? note : null,
        '',
        `Gate-Passwort: ${gateCode}`,
        'Bitte prüfen und dem Kunden manuell mitteilen.',
      ]
        .filter((line) => line !== null)
        .join('\n');
      const subject = `[Gate-Code] ${company || email}`;
      const result = await sendMail({
        to: INTERNAL_GATE_EMAIL,
        subject,
        html,
        text,
      });
      mailDiagnostics = result?.diagnostics || null;
      mailSent = !!result?.ok;
      if (!mailSent) {
        const raw = result?.message || result?.reason || 'send failed';
        const stackOverflow = /stack size/i.test(raw || '');
        mailError =
          result?.userMessage ||
          (stackOverflow
            ? 'Mailer stack overflow – check SMTP/test-mode routing configuration'
            : raw);
      }
    } catch (err) {
      mailError = err?.message || String(err);
      console.error('gate-request mail failed:', mailError);
    }

    if (!mailSent) {
      return ok(res, {
        ok: false,
        mailSent,
        mailError: mailError || 'mail send failed',
        mailDiagnostics,
      });
    }

    return ok(res, { ok: true, mailSent, mailError: null, mailDiagnostics });
  } catch (err) {
    console.error('gate-request fatal:', err);
    const stackOverflow = err instanceof RangeError && /stack size/i.test(err.message || '');
    const msg = isPreview
      ? err?.message || String(err)
      : stackOverflow
          ? 'Mailer stack overflow – bitte Maildienst prüfen.'
          : 'Maildienst aktuell nicht erreichbar.';
    return ok(res, { ok: false, mailSent: false, mailError: msg });
  }
}
