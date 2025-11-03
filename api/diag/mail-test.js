// /api/diag/mail-test.js
export const config = { runtime: 'nodejs' };
import { mailer } from '../_lib/mail.js';

export default async function handler(_req, res) {
  try {
    await mailer.sendMail({
      from: process.env.MAIL_FROM,
      to: 'tobias_bauer@hotmail.com',
      subject: 'DFS Complaint App – SMTP-Test erfolgreich',
      text: 'Hallo Tobias,\n\nDein DFS Complaint Backend hat gerade erfolgreich über GMX gesendet ✅.\n\nViele Grüße\nDFS-System'
    });
    res.end(JSON.stringify({ ok: true }));
  } catch (e) {
    res.statusCode = 500;
    res.end(JSON.stringify({ ok: false, error: e?.message || String(e) }));
  }
}
