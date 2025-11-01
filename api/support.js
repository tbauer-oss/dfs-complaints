// api/support.js
export const config = { runtime: 'nodejs' };

import { setCors, ok, bad, noContent, methodNotAllowed } from './_lib/http.js';
import { getAuthUser } from './_lib/auth.js';
import { sendMail } from './_lib/mailer.js';

const CATS = new Set(['general','complaint','technical','account','privacy','feedback','other']);

export default async function handler(req, res) {
  setCors(req, res);
  if (req.method === 'OPTIONS') return noContent(res);
  if (req.method !== 'POST') return methodNotAllowed(res);

  const user = getAuthUser(req);
  if (!user) return bad(res, 'unauthorized', 401);

  const body = typeof req.body === 'object' ? req.body : JSON.parse(req.body ?? '{}');
  const cat = (body?.category || 'other').toString().toLowerCase();
  const text = (body?.message || '').toString();
  const consent = !!body?.consent;

  if (!CATS.has(cat)) return bad(res, 'invalid category', 400);
  if (!text.trim()) return bad(res, 'empty message', 400);
  if (!consent) return bad(res, 'consent required', 400);

  await sendMail({
    to: 'complaint@dfs-diamon.de',
    cc: user.email,
    subject: `[DFS Support] ${cat} von ${user.email}`,
    html: `<p>${text.replace(/\n/g,'<br/>')}</p>`
  });

  return ok(res, { ok: true });
}
