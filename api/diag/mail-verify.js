// /api/diag/mail-verify.js
export const config = { runtime: 'nodejs' };
import { verifyTransport } from '../_lib/mail.js';

export default async function handler(req, res) {
  res.setHeader('Content-Type', 'application/json');
  try {
    await verifyTransport();
    res.end(JSON.stringify({ ok: true }));
  } catch (e) {
    res.statusCode = 500;
    res.end(JSON.stringify({
      ok: false,
      error: e?.message || String(e)
    }));
  }
}
