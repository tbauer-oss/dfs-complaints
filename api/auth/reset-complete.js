// api/auth/reset-complete.js
export const config = { runtime: 'nodejs' };

import bcrypt from 'bcryptjs';
import {
  handlePreflight,
  ok,
  bad,
  methodNotAllowed,
  readJson,
} from '../_lib/http.js';
import { userByEmail, userSave } from '../_lib/store.js';
import { isStrongPassword } from '../_lib/passwords.js';
import { sendMail } from '../_lib/mailer.js';

const TEXTS = {
  de: {
    subject: 'DFS Complaints – Passwort aktualisiert',
    body: 'Ihr Passwort wurde erfolgreich geändert. Falls Sie diese Änderung nicht ausgelöst haben, kontaktieren Sie bitte umgehend complaint@dfs-diamon.de.',
  },
  en: {
    subject: 'DFS Complaints – Password updated',
    body: 'Your password has been updated successfully. If you did not initiate this change, please contact complaint@dfs-diamon.de immediately.',
  },
};

function pickLang(user) {
  const lang = (user?.lang || '').toString().toLowerCase();
  return TEXTS[lang] ? lang : 'de';
}

export default async function handler(req, res) {
  if (handlePreflight(req, res)) return;
  if (req.method !== 'POST') return methodNotAllowed(res);

  try {
    const body = readJson(req);
    const email = String(body?.email || '').trim().toLowerCase();
    const temp = String(body?.tempPassword || '').trim();
    const next = String(body?.newPassword || '');

    if (!email || !temp || !next) return bad(res, 'missing fields', 400);

    const user = await userByEmail(email);
    if (!user || !user.resetTempHash) return bad(res, 'invalid temporary password', 400);

    const expiredAt = Number(user.resetTempExpiresAt || 0);
    if (Number.isFinite(expiredAt) && expiredAt > 0 && expiredAt < Date.now()) {
      return bad(res, 'temporary password expired', 410);
    }

    const matches = await bcrypt.compare(temp, user.resetTempHash);
    if (!matches) return bad(res, 'invalid temporary password', 400);

    if (!isStrongPassword(next)) {
      return bad(res, 'password requirements not met', 400);
    }

    const passhash = await bcrypt.hash(next, 10);
    const updated = { ...user, passhash };
    delete updated.resetTempHash;
    delete updated.resetTempExpiresAt;
    delete updated.resetTempIssuedAt;

    await userSave(updated);

    const langKey = pickLang(user);
    const texts = TEXTS[langKey];
    try {
      await sendMail({
        to: email,
        subject: texts.subject,
        html: `<p>${texts.body}</p>`,
      });
    } catch (mailErr) {
      console.error('[reset-complete][mail]', mailErr);
    }

    return ok(res, { ok: true });
  } catch (err) {
    console.error('[reset-complete]', err);
    return bad(res, 'server error', 500);
  }
}
