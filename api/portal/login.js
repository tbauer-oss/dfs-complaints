export const config = { runtime: 'nodejs' };

import bcrypt from 'bcryptjs';
import jwt from 'jsonwebtoken';
import { methodNotAllowed, readJson } from '../_lib/http.js';
import { portalUserByEmail } from '../_lib/store.js';
import { normalizeRole, normalizeStatus } from '../_lib/portalAuth.js';

const JWT_SECRET = String(process.env.JWT_SECRET || '').trim() || 'devsecret';
const EXPIRES_IN = '12h';
const AUTH_DEBUG = String(process.env.AUTH_DEBUG || '').toLowerCase() === 'true';
const AUTH_DEBUG_KEY = String(process.env.AUTH_DEBUG_KEY || '').trim();
const BCRYPT_PREFIX_PATTERN = /^\$(2[aby])\$/;

function logOutcome(outcome) {
  console.info('[portal/login]', { outcome });
}

function normalizeBcryptHash(passwordHash) {
  const hash = String(passwordHash || '').trim();
  if (!hash) return '';
  if (hash.startsWith('$2y$')) return `$2b$${hash.slice(4)}`;
  if (!BCRYPT_PREFIX_PATTERN.test(hash)) return '';
  return hash;
}

async function verifyPassword(password, passwordHash) {
  const normalizedHash = normalizeBcryptHash(passwordHash);
  if (!normalizedHash) return false;
  try {
    return await bcrypt.compare(password, normalizedHash);
  } catch {
    return false;
  }
}

function shouldIncludeReason(req) {
  if (!AUTH_DEBUG) return false;
  if (!AUTH_DEBUG_KEY) return true;
  return String(req.headers?.['x-auth-debug'] || '').trim() === AUTH_DEBUG_KEY;
}

function respond(req, res, statusCode, payload, outcome = null) {
  if (!res.getHeader('Content-Type')) {
    res.setHeader('Content-Type', 'application/json; charset=utf-8');
  }
  const body = { ...payload };
  if (outcome && shouldIncludeReason(req)) body.reason = outcome;
  res.statusCode = statusCode;
  res.end(JSON.stringify(body));
}

export default async function handler(req, res) {
  if (req.method === 'OPTIONS') return res.status(204).end();
  if (req.method !== 'POST') return methodNotAllowed(res);

  let body;
  try {
    body = await readJson(req);
  } catch {
    logOutcome('BAD_REQUEST');
    return respond(req, res, 400, { code: 'BAD_REQUEST', message: 'Bitte alle Felder ausfüllen.' }, 'BAD_REQUEST');
  }

  const email = String(body?.email || '').trim().toLowerCase();
  const password = String(body?.password || '');
  if (!email || !password) {
    logOutcome('BAD_REQUEST');
    return respond(req, res, 400, { code: 'BAD_REQUEST', message: 'Bitte alle Felder ausfüllen.' }, 'BAD_REQUEST');
  }

  let user;
  try {
    user = await portalUserByEmail(email);
  } catch {
    const outcome = 'STORE_UNAVAILABLE';
    logOutcome(outcome);
    return respond(
      req,
      res,
      503,
      { code: outcome, message: 'Service temporär nicht verfügbar. Bitte später erneut versuchen.' },
      outcome,
    );
  }

  if (!user) {
    const outcome = 'USER_NOT_FOUND';
    logOutcome(outcome);
    return respond(req, res, 401, { code: 'INVALID_CREDENTIALS', message: 'E-Mail/Passwort ungültig.' }, outcome);
  }

  const passwordHash = String(user.passhash || user.passwordHash || '').trim();
  const passwordOk = await verifyPassword(password, passwordHash);
  if (!passwordOk) {
    const outcome = 'PASSWORD_MISMATCH';
    logOutcome(outcome);
    return respond(req, res, 401, { code: 'INVALID_CREDENTIALS', message: 'E-Mail/Passwort ungültig.' }, outcome);
  }

  const role = normalizeRole(user.role);
  const portalStatus = normalizeStatus(user.portalStatus, user.revoked);
  if (portalStatus !== 'active') {
    const outcome = 'USER_INACTIVE';
    logOutcome(outcome);
    return respond(req, res, 401, { code: 'INVALID_CREDENTIALS', message: 'E-Mail/Passwort ungültig.' }, outcome);
  }

  const token = jwt.sign(
    { sub: user.id || user.email, email: user.email, role, portalStatus },
    JWT_SECRET,
    { expiresIn: EXPIRES_IN },
  );

  logOutcome('SUCCESS');
  return respond(req, res, 200, {
    token,
    user: { id: user.id, email: user.email, role },
    profile: { id: user.id, email: user.email, role, portalStatus },
    expiresIn: EXPIRES_IN,
  });
}
