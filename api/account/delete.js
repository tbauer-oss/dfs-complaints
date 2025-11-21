// api/account/delete.js
export const config = { runtime: 'nodejs' };

import { setCors, ok, bad, noContent, methodNotAllowed } from '../_lib/http.js';
import { getAuthUser } from '../_lib/auth.js';
import { userByEmail, userDelete } from '../_lib/store.js';
import bcrypt from 'bcryptjs';
import { sendMail } from '../_lib/mailer.js';

export default async function handler(req, res) {
  setCors(req, res);
  if (req.method === 'OPTIONS') return noContent(res);
  if (req.method !== 'POST') return methodNotAllowed(res);

  const auth = getAuthUser(req);
  if (!auth) return bad(res, 'unauthorized', 401);

  const body = typeof req.body === 'object' ? req.body : JSON.parse(req.body ?? '{}');
  const pw = body?.password || '';

  const u = await userByEmail(auth.email);
  if (!u) return bad(res, 'not found', 404);

  const okPw = await bcrypt.compare(pw, u.passhash);
  if (!okPw) return bad(res, 'wrong password', 400);

  await userDelete(auth.email);

  await sendMail({
    to: auth.email, cc: 'complaint@dfs-diamon.de',
    subject: '[DFS Complaint] Account gelöscht',
    html: `<p>Ihr Account wurde gelöscht. Alle zugehörigen Daten werden entfernt, soweit gesetzlich zulässig.</p>`
  });

  return ok(res, { ok: true });
}
