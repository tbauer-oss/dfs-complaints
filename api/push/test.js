// /api/push/test.js
export const config = { runtime: 'nodejs' };

import {
  handlePreflight,
  ok,
  bad,
  methodNotAllowed,
  readJson,
} from '../_lib/http.js';

import { sendPushToTokens } from '../_lib/fcm.js';

const ADMIN_SECRET = process.env.ADMIN_SECRET || '';

function isAdmin(req) {
  if (!ADMIN_SECRET) return false;
  const header =
    req.headers?.['x-admin-secret'] ??
    req.headers?.['X-Admin-Secret'] ??
    req.headers?.['x-admin_secret'] ??
    req.headers?.['X-Admin_Secret'];
  if (!header) return false;
  return header === ADMIN_SECRET;
}

export default async function handler(req, res) {
  if (handlePreflight(req, res)) return;

  if (!isAdmin(req)) {
    return bad(res, 'unauthorized', 401);
  }

  if (req.method !== 'POST') {
    return methodNotAllowed(res);
  }

  const body = readJson(req) || {};
  const token = (body?.token || '').toString().trim();

  if (!token) {
    return bad(res, 'missing token', 400);
  }

  const title =
    (body?.title || 'DFS Complaint – Testbenachrichtigung').toString();
  const bodyText =
    (body?.body ||
      'Dies ist eine Test-Push-Nachricht aus dem DFS Complaints Backend.').toString();

  const data = {};
  if (body?.data && typeof body.data === 'object') {
    for (const [k, v] of Object.entries(body.data)) {
      data[String(k)] = String(v);
    }
  }

  try {
    const result = await sendPushToTokens(
      [token],
      { title, body: bodyText },
      data,
    );
    return ok(res, result);
  } catch (err) {
    console.error('[push/test] send failed', err);
    return bad(res, 'send failed: ' + err, 500);
  }
}
