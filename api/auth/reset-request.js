// api/auth/reset-request.js
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
import { sendMail } from '../_lib/mailer.js';

const APP_ORIGIN = (process.env.APP_ORIGIN || process.env.APP_BASE_URL || 'https://dfs-complaints-web.vercel.app').replace(/\/$/, '');
const RESET_PATH = (process.env.PASSWORD_RESET_PATH || '/#/reset-password').trim() || '/#/reset-password';
const RESET_LINK_BASE = `${APP_ORIGIN}${RESET_PATH.startsWith('/') ? '' : '/'}${RESET_PATH}`;
const RESET_EXPIRY_MS = Number(process.env.PASSWORD_RESET_EXPIRY_MS || 1000 * 60 * 60 * 24);

const TEXTS = {
  de: {
    subject: 'DFS Complaints – Passwort zurücksetzen',
    intro: 'Sie haben angefordert, Ihr Passwort für das DFS Kundenportal zurückzusetzen.',
    temp: (code) => `Ihr temporäres Passwort lautet: <strong>${code}</strong>`,
    link: 'Klicken Sie auf den folgenden Link, um das temporäre Passwort freizuschalten und ein neues Passwort zu vergeben:',
    expiry: 'Das temporäre Passwort ist 24 Stunden gültig.',
  },
  en: {
    subject: 'DFS Complaints – Reset your password',
    intro: 'You requested to reset the password for the DFS customer portal.',
    temp: (code) => `Your temporary password is: <strong>${code}</strong>`,
    link: 'Use the following link to activate the temporary password and choose a new one:',
    expiry: 'The temporary password is valid for 24 hours.',
  },
};

function pickLang(user) {
  const lang = (user?.lang || '').toString().toLowerCase();
  return TEXTS[lang] ? lang : 'de';
}

function randomCode(len = 8) {
  const chars = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
  let out = '';
  for (let i = 0; i < len; i += 1) {
    const idx = Math.floor(Math.random() * chars.length);
    out += chars[idx];
  }
  return out;
}

function buildResetLink(email) {
  const sep = RESET_LINK_BASE.includes('?') ? '&' : '?';
  return `${RESET_LINK_BASE}${sep}email=${encodeURIComponent(email)}&mode=unlock`;
}

export default async function handler(req, res) {
  if (handlePreflight(req, res)) return;
  if (req.method !== 'POST') return methodNotAllowed(res);

  try {
    const body = readJson(req);
    const email = String(body?.email || '').trim().toLowerCase();
    if (!email || !email.includes('@')) return bad(res, 'missing email', 400);

    const user = await userByEmail(email);
    if (!user) return bad(res, 'account not found', 404);

    const tempPw = randomCode(8);
    const hash = await bcrypt.hash(tempPw, 10);
    const expiresAt = Date.now() + RESET_EXPIRY_MS;

    await userSave({
      ...user,
      resetTempHash: hash,
      resetTempExpiresAt: expiresAt,
      resetTempIssuedAt: Date.now(),
    });

    const langKey = pickLang(user);
    const texts = TEXTS[langKey];
    const link = buildResetLink(email);
    const html = [
      `<p>${texts.intro}</p>`,
      `<p>${texts.temp(tempPw)}</p>`,
      `<p>${texts.link}<br/><a href="${link}">${link}</a></p>`,
      `<p>${texts.expiry}</p>`,
    ].join('\n');

    const mailResult = await sendMail({
      to: email,
      subject: texts.subject,
      html,
    });

    if (!mailResult?.ok) {
      return bad(res, 'unable to send mail', 500);
    }

    return ok(res, { ok: true });
  } catch (err) {
    console.error('[reset-request]', err);
    return bad(res, 'server error', 500);
  }
}
