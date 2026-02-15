// /api/rep/login.js
export const config = { runtime: 'nodejs' };

import jwt from 'jsonwebtoken';
import bcrypt from 'bcryptjs';
import { redis } from '../_lib/redis.js';
import { safeHandler } from '../_lib/http.js';

const REP_SECRET = process.env.REP_JWT_SECRET;

const S = (v) => (v ?? '').toString().trim();
const keyForRep = (id) => `dfs:reps:${id}`;

function parseJsonValue(raw, context) {
  if (raw == null) return null;
  if (typeof raw === 'object') return raw;
  if (typeof raw !== 'string') return null;
  try {
    return JSON.parse(raw);
  } catch (err) {
    console.warn('[rep/login] corrupted JSON entry', {
      context,
      message: err?.message || String(err),
    });
    return null;
  }
}

function normalizeRep(rep) {
  if (!rep || typeof rep !== 'object') return null;
  const email = S(rep.email || rep.mail || rep.emailAddress).toLowerCase();
  return {
    id: S(rep.id || rep.repId),
    email,
    passHash: S(rep.passHash),
    active: rep.active === undefined ? true : !!rep.active,
    mustChangePw: !!rep.mustChangePw,
  };
}

async function loadRepByEmail(email) {
  const normalizedEmail = S(email).toLowerCase();
  if (!normalizedEmail) return null;

  const oldIndexKey = `dfs:repBy:${normalizedEmail}`;
  const newIndexKey = `dfs:reps:email:${normalizedEmail}`;

  const oldIndexRaw = await redis.get(oldIndexKey);
  const newIndexRaw = await redis.get(newIndexKey);

  const oldIndex = parseJsonValue(oldIndexRaw, oldIndexKey) ?? oldIndexRaw;
  const newIndex = parseJsonValue(newIndexRaw, newIndexKey) ?? newIndexRaw;

  const repId = S(oldIndex || newIndex);
  if (repId) {
    const repRaw = await redis.get(keyForRep(repId));
    const repObj = parseJsonValue(repRaw, keyForRep(repId)) ?? repRaw;
    return normalizeRep(repObj);
  }

  const directRep = normalizeRep(parseJsonValue(newIndexRaw, newIndexKey));
  if (directRep?.email === normalizedEmail) return directRep;

  return null;
}

async function recordRepLogin(repId, { appVersion = '', appBuild = '' } = {}) {
  const id = S(repId);
  if (!id) return;
  const key = keyForRep(id);
  const raw = await redis.get(key);
  const rep = parseJsonValue(raw, key) ?? raw;
  if (!rep || typeof rep !== 'object') return;

  const updated = {
    ...rep,
    lastLoginAt: Date.now(),
    ...(S(appVersion) ? { lastLoginAppVersion: S(appVersion) } : {}),
    ...(S(appBuild) ? { lastLoginAppBuild: S(appBuild) } : {}),
  };

  await redis.set(key, updated);
}

async function loginHandler(req, res) {
  if (req.method !== 'POST') {
    return res.status(405).json({ error: 'method not allowed' });
  }

  if (!REP_SECRET) {
    return res.status(500).json({ error: 'server misconfig (REP_JWT_SECRET not set)' });
  }

  const raw = typeof req.body === 'string' ? req.body : JSON.stringify(req.body || {});
  let body = {};
  try {
    body = JSON.parse(raw || '{}');
  } catch {
    body = {};
  }

  const email = S(body.email).toLowerCase();
  const password = S(body.password);
  const secret = S(body.secret);
  const appVersion = S(body.appVersion);
  const appBuild = S(body.appBuild);

  if (!email) return res.status(400).json({ error: 'missing email' });

  let rep;
  try {
    rep = await loadRepByEmail(email);
  } catch (err) {
    err.code = err?.code || 'STORE_UNAVAILABLE';
    throw err;
  }

  if (!rep || rep.active === false) {
    return res.status(401).json({ code: 'INVALID_CREDENTIALS', message: 'Invalid credentials' });
  }

  if (secret) {
    if (secret !== REP_SECRET) {
      return res.status(401).json({ code: 'INVALID_CREDENTIALS', message: 'Invalid credentials' });
    }

    const token = jwt.sign({ repId: rep.id }, REP_SECRET, { expiresIn: '7d' });
    try {
      await recordRepLogin(rep.id, { appVersion, appBuild });
    } catch (e) {
      console.warn('[rep/login] recordRepLogin failed', e?.message || String(e));
    }
    return res.status(200).json({ token, mustChangePw: !!rep.mustChangePw, email });
  }

  if (!password || !rep.passHash) {
    return res.status(401).json({ code: 'INVALID_CREDENTIALS', message: 'Invalid credentials' });
  }

  const passwordOk = await bcrypt.compare(password, rep.passHash).catch(() => false);
  if (!passwordOk) {
    return res.status(401).json({ code: 'INVALID_CREDENTIALS', message: 'Invalid credentials' });
  }

  const token = jwt.sign({ repId: rep.id }, REP_SECRET, { expiresIn: '7d' });
  try {
    await recordRepLogin(rep.id, { appVersion, appBuild });
  } catch (e) {
    console.warn('[rep/login] recordRepLogin failed', e?.message || String(e));
  }
  return res.status(200).json({ token, mustChangePw: false, email });
}

export default safeHandler(loginHandler, { route: '/api/rep/login' });
