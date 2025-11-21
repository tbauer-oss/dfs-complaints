// api/account/password.js
export const config = { runtime: 'nodejs' };

import { setCors, ok, bad, noContent, methodNotAllowed } from '../_lib/http.js';
import { getAuthUser } from '../_lib/auth.js';
import { userByEmail, userSave } from '../_lib/store.js';
import { isStrongPassword } from '../_lib/passwords.js';
import bcrypt from 'bcryptjs';
import { sendMail } from '../_lib/mailer.js';

export default async function handler(req, res) {
  setCors(req, res);
  if (req.method === 'OPTIONS') return noContent(res);
  if (req.method !== 'POST') return methodNotAllowed(res);

  const auth = getAuthUser(req);
  if (!auth) return bad(res, 'unauthorized', 401);

  const body = typeof req.body === 'object' ? req.body : JSON.parse(req.body ?? '{}');
  const oldPw = body?.oldPassword || '';
  const newPw = body?.newPassword || '';

  const u = await userByEmail(auth.email);
  if (!u) return bad(res, 'not found', 404);

  const okOld = await bcrypt.compare(oldPw, u.passhash);
  if (!okOld) return bad(res, 'wrong password', 400);

  if (!isStrongPassword(newPw)) {
    return bad(res, 'password requirements not met (min. 8 chars incl. letters, numbers & special characters)', 400);
  }

  const passhash = await bcrypt.hash(newPw, 10);
  await userSave({ ...u, passhash });

  await sendMail({
    to: auth.email, cc: 'complaint@dfs-diamon.de',
    subject: '[DFS Complaint] Passwort geändert',
    html: `<p>Ihr Passwort wurde erfolgreich geändert.</p>`
  });

  return ok(res, { ok: true });
}
