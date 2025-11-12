// /api/push/register.js
export const config = { runtime: 'nodejs' };

import jwt from 'jsonwebtoken';
import {
  handlePreflight,
  ok,
  bad,
  noContent,
  methodNotAllowed,
  readJson,
} from '../_lib/http.js';
import {
  pushTokenRegister,
  pushTokenRemove,
} from '../_lib/store.js';

const JWT_SECRET = process.env.JWT_SECRET || process.env.JWT || '';

function authEmail(req) {
  const header = req.headers?.authorization || req.headers?.Authorization || '';
  const match = /^Bearer\s+(.+)$/i.exec(header);
  if (!match) return null;
  try {
    const payload = jwt.verify(match[1], JWT_SECRET);
    const email = (payload?.email || payload?.sub || '').toString().trim().toLowerCase();
    return email || null;
  } catch {
    return null;
  }
}

export default async function handler(req, res) {
  if (handlePreflight(req, res)) return;
  if (!JWT_SECRET) return bad(res, 'server misconfig', 500);

  const email = authEmail(req);
  if (!email) return bad(res, 'unauthorized', 401);

  if (req.method === 'POST') {
    const body = readJson(req) || {};
    const token = (body?.token || '').toString().trim();
    if (!token) return bad(res, 'missing token', 400);
    const platform = (body?.platform || '').toString().trim();
    const locale = (body?.locale || '').toString().trim();
    const lang = (body?.lang || '').toString().trim();

    await pushTokenRegister(email, token, { platform, locale, lang });
    return ok(res, { ok: true });
  }

  if (req.method === 'DELETE') {
    const queryToken = (req.query?.token || '').toString().trim();
    let token = queryToken;
    if (!token && req.body) {
      try {
        const parsed = typeof req.body === 'string' ? JSON.parse(req.body || '{}') : req.body;
        token = (parsed?.token || '').toString().trim();
      } catch {}
    }
    if (!token) {
      const body = readJson(req) || {};
      token = (body?.token || '').toString().trim();
    }
    if (!token) return bad(res, 'missing token', 400);

    await pushTokenRemove(email, token);
    return noContent(res);
  }

  return methodNotAllowed(res);
}
