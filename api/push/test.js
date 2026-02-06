// /api/push/test.js
export const config = { runtime: 'nodejs' };

import crypto from 'node:crypto';
import {
  setCors,
  handlePreflight,
  ok,
  bad,
  methodNotAllowed,
  readJson,
} from '../_lib/http.js';

import { sendPushToTokens } from '../_lib/fcm.js';
import { adminPushTokens, adminPushTokenRemove } from '../_lib/store.js';
import { requirePortalAccess } from '../admin/_guard.js';

const ADMIN_SECRET = process.env.ADMIN_SECRET || '';
const PUSH_SEND_TIMEOUT_MS = 15000;

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

function withTimeout(promise, ms, label) {
  let timer;
  const timeout = new Promise((_, reject) => {
    timer = setTimeout(() => {
      const err = new Error(`${label} timed out after ${ms}ms`);
      err.code = 'TIMEOUT';
      reject(err);
    }, ms);
  });
  return Promise.race([promise, timeout]).finally(() => clearTimeout(timer));
}

function tokenHash(token) {
  return crypto.createHash('sha256').update(token).digest('hex').slice(0, 12);
}

function isInvalidTokenError(err) {
  if (!err) return false;
  const status = err.status || err.statusCode;
  if (Number(status) === 404 || Number(status) === 410) return true;
  const code = (err.code || '').toString().toLowerCase();
  const message = (err.message || err.error || err.detail || err.body || err || '').toString().toLowerCase();
  const haystack = `${code} ${message}`;
  return (
    haystack.includes('notregistered') ||
    haystack.includes('invalidregistration') ||
    haystack.includes('registration-token-not-registered') ||
    haystack.includes('invalid-registration-token') ||
    haystack.includes('invalid-token') ||
    haystack.includes('expired') ||
    haystack.includes('unregistered') ||
    haystack.includes('requested entity was not found')
  );
}

export default async function handler(req, res) {
  if (handlePreflight(req, res)) return;
  setCors(req, res);

  let actor = null;
  if (!isAdmin(req)) {
    actor = await requirePortalAccess(req, res, { write: true, tile: 'push' });
    if (!actor) return;
  }

  if (req.method !== 'POST') {
    return methodNotAllowed(res);
  }

  const startedAt = Date.now();
  const body = readJson(req) || {};
  const token = (body?.token || '').toString().trim();
  const title = (body?.title || 'DFS Complaint – Testbenachrichtigung').toString();
  const bodyText =
    (body?.body ||
      'Dies ist eine Test-Push-Nachricht aus dem DFS Complaints Backend.').toString();

  const data = {};
  if (body?.data && typeof body.data === 'object') {
    for (const [k, v] of Object.entries(body.data)) {
      data[String(k)] = String(v);
    }
  }

  let targets = [];
  if (token) {
    targets = [token];
  } else {
    const tokens = (await adminPushTokens())
      .map((entry) => (entry?.token || '').toString().trim())
      .filter(Boolean);
    targets = Array.from(new Set(tokens));
  }

  const tokensFound = targets.length;
  const stats = {
    mode: token ? 'direct' : 'self',
    targetUsers: actor?.email ? 1 : 0,
    foundTokens: tokensFound,
    sentOk: 0,
    sentFailed: 0,
    invalidTokensRemoved: 0,
    durationMs: 0,
  };
  const errorsSample = [];

  if (tokensFound === 0) {
    stats.durationMs = Date.now() - startedAt;
    return ok(res, {
      ok: true,
      message: 'no tokens',
      stats,
      errorsSample,
      selfUserId: actor?.email || 'admin',
      tokensFound: 0,
      provider: null,
    });
  }

  const targetToken = targets[0];
  let provider = null;
  let invalidToken = null;
  let okFlag = true;
  let messageOut = 'sent';
  try {
    provider = await withTimeout(
      sendPushToTokens(
        [targetToken],
        { title, body: bodyText },
        data,
      ),
      PUSH_SEND_TIMEOUT_MS,
      'push test',
    );
    stats.sentOk = Number(provider?.successCount || 0);
    stats.sentFailed = Number(provider?.failureCount || 0);
    if (Array.isArray(provider?.responses)) {
      provider.responses.forEach((entry) => {
        if (entry?.success) return;
        const code = entry?.code || null;
        const detail = entry?.error || '';
        if (errorsSample.length < 10) {
          errorsSample.push({
            tokenHash: tokenHash(targetToken),
            code: code || 'send_failed',
            detail: detail?.toString() || '',
          });
        }
        if (isInvalidTokenError({ code, message: detail })) {
          invalidToken = targetToken;
        }
      });
    }
    if (!invalidToken && Array.isArray(provider?.invalidTokens) && provider.invalidTokens.length > 0) {
      invalidToken = provider.invalidTokens[0];
    }
    okFlag = provider?.ok === true;
    messageOut = okFlag ? 'sent' : 'failed';
  } catch (err) {
    stats.sentFailed = 1;
    okFlag = false;
    messageOut = 'failed';
    if (errorsSample.length < 10) {
      errorsSample.push({
        tokenHash: tokenHash(targetToken),
        code: err?.code || 'send_failed',
        detail: err?.message || String(err),
      });
    }
    if (isInvalidTokenError(err)) {
      invalidToken = targetToken;
    }
  }

  if (invalidToken && !token) {
    try {
      if (await adminPushTokenRemove(invalidToken)) stats.invalidTokensRemoved += 1;
    } catch (err) {
      console.error('[push/test] cleanup failed', err);
    }
  }

  stats.durationMs = Date.now() - startedAt;
  return ok(res, {
    ok: okFlag,
    message: messageOut,
    stats,
    errorsSample,
    selfUserId: actor?.email || 'admin',
    tokensFound,
    provider: provider
      ? {
          ok: provider.ok,
          sent: provider.sent,
          total: provider.total,
          successCount: provider.successCount,
          failureCount: provider.failureCount,
          responses: provider.responses,
        }
      : null,
  });
}
