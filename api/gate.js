// /api/gate/request.js
export const config = { runtime: 'nodejs' };

import {
  handlePreflight,
  ok,
  bad,
  methodNotAllowed,
  readJson,
} from '../_lib/http.js';

const isPreview = process.env.VERCEL_ENV !== 'production';
const validEmail = (s) => /^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(String(s || ''));

export default async function handler(req, res) {
  if (handlePreflight(req, res)) return;
  if (req.method !== 'POST') return methodNotAllowed(res);

  let email;
  let company;
  try {
    const body = readJson(req);
    email = String(body?.email || '').trim().toLowerCase();
    company = String(body?.company || '').trim();
  } catch (err) {
    const msg = isPreview ? err?.message || String(err) : 'bad request';
    return bad(res, msg, 400);
  }

  if (!email) return bad(res, 'email required', 400);
  if (!company) return bad(res, 'company required', 400);
  if (!validEmail(email)) return bad(res, 'invalid email', 400);

  try {
    const { notifyQM, tpl, verifyTransport } = await import('../_lib/mail.js');
    await verifyTransport().catch(() => {});
    await notifyQM(tpl.gateRequest(email, company));
    await new Promise((resolve) => setTimeout(resolve, 500));
  } catch (err) {
    console.error('gate/request mail failed:', err);
    const msg = isPreview ? err?.message || String(err) : 'mail failed';
    return bad(res, msg, 502);
  }

  return ok(res, { ok: true });
}
