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
  repPushTokenRegister,
  repPushTokenRemove,
  adminPushTokenRegister,
  adminPushTokenRemove,
} from '../_lib/store.js';
import { getRepFromAuthHeader } from '../_lib/repAuth.js';

const ADMIN_SECRET = process.env.ADMIN_SECRET || '';

function isAdmin(req) {
  if (!ADMIN_SECRET) return false;
  const header = req.headers?.['x-admin-secret'] ?? req.headers?.['X-Admin-Secret'];
  if (!header) return false;
  return header === ADMIN_SECRET;
}

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
  console.log('[push/register] handler called', req.method, req.url);
  if (handlePreflight(req, res)) return;
  const email = JWT_SECRET ? authEmail(req) : null;
  const rep = email ? null : getRepFromAuthHeader(req);
  const admin = (!email && !rep) ? isAdmin(req) : false;

  // Wenn wir keinen JWT-Secret haben, können wir Kunden nicht verifizieren –
  // Vertreter:innen und Admins sollen trotzdem weiterarbeiten können.
  if (!JWT_SECRET && !rep && !admin) return bad(res, 'server misconfig', 500);
  if (!email && !rep && !admin) return bad(res, 'unauthorized', 401);

  if (req.method === 'POST') {
    const body = readJson(req) || {};
    const token = (body?.token || '').toString().trim();
    if (!token) return bad(res, 'missing token', 400);
    const platform = (body?.platform || '').toString().trim();
    const locale = (body?.locale || '').toString().trim();
    const lang = (body?.lang || '').toString().trim();

    console.log('[push/register] token=', token, 'platform=', platform, 'locale=', locale, 'lang=', lang);

    if (email) {
      await pushTokenRegister(email, token, { platform, locale, lang });
    } else if (rep) {
      console.warn('[push/register] rep push token registration disabled');
      await repPushTokenRegister(rep.repId, token, { platform, locale, lang });
    } else if (admin) {
      await adminPushTokenRegister(token, { platform, locale, lang });
    }
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

    if (email) await pushTokenRemove(email, token);
    else if (rep) {
      await repPushTokenRemove(rep.repId, token);
    }
    else if (admin) await adminPushTokenRemove(token);
    return noContent(res);
  }

  return methodNotAllowed(res);
}
