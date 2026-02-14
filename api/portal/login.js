export const config = { runtime: 'nodejs' };

import bcrypt from 'bcryptjs';
import jwt from 'jsonwebtoken';
import { methodNotAllowed, readJson } from '../_lib/http.js';
import { portalUserByEmail } from '../_lib/store.js';
import { normalizeRole, normalizeStatus } from '../_lib/portalAuth.js';

const JWT_SECRET = String(process.env.JWT_SECRET || '').trim() || 'devsecret';
const EXPIRES_IN = '12h';

function logOutcome(outcome) {
  console.info('[portal/login]', { outcome });
}

function respond(res, statusCode, payload) {
  if (!res.getHeader('Content-Type')) {
    res.setHeader('Content-Type', 'application/json; charset=utf-8');
  }
  res.statusCode = statusCode;
  res.end(JSON.stringify(payload));
}

export default async function handler(req, res) {
  if (req.method === 'OPTIONS') return res.status(204).end();
  if (req.method !== 'POST') return methodNotAllowed(res);

  let body;
  try {
    body = await readJson(req);
  } catch {
    logOutcome('DB_ERROR');
    return respond(res, 400, { code: 'BAD_REQUEST', message: 'Bitte alle Felder ausfüllen.' });
  }

  const email = String(body?.email || '').trim().toLowerCase();
  const password = String(body?.password || '');
  if (!email || !password) {
    logOutcome('PASSWORD_MISMATCH');
    return respond(res, 400, { code: 'BAD_REQUEST', message: 'Bitte alle Felder ausfüllen.' });
  }

  let user;
  try {
    user = await portalUserByEmail(email);
  } catch (err) {
    logOutcome('DB_ERROR');
    return respond(res, 503, {
      code: 'STORE_UNAVAILABLE',
      message: 'Service temporär nicht verfügbar. Bitte später erneut versuchen.',
    });
  }

  if (!user) {
    logOutcome('USER_NOT_FOUND');
    return respond(res, 401, { code: 'INVALID_CREDENTIALS', message: 'E-Mail/Passwort ungültig.' });
  }

  const passwordHash = String(user.passhash || user.passwordHash || '').trim();
  const passwordOk = passwordHash ? await bcrypt.compare(password, passwordHash).catch(() => false) : false;
  if (!passwordOk) {
    logOutcome('PASSWORD_MISMATCH');
    return respond(res, 401, { code: 'INVALID_CREDENTIALS', message: 'E-Mail/Passwort ungültig.' });
  }

  const role = normalizeRole(user.role);
  const portalStatus = normalizeStatus(user.portalStatus, user.revoked);
  if (portalStatus !== 'active') {
    logOutcome('PASSWORD_MISMATCH');
    return respond(res, 401, { code: 'INVALID_CREDENTIALS', message: 'E-Mail/Passwort ungültig.' });
  }

  const token = jwt.sign(
    { sub: user.id || user.email, email: user.email, role, portalStatus },
    JWT_SECRET,
    { expiresIn: EXPIRES_IN },
  );

  logOutcome('OK');
  return respond(res, 200, {
    token,
    user: { id: user.id, email: user.email, role },
    profile: { id: user.id, email: user.email, role, portalStatus },
    expiresIn: EXPIRES_IN,
  });
}
