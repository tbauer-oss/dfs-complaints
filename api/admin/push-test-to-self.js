// api/admin/push-test-to-self.js
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
import { adminPushTokens, adminPushTokenRemove } from '../_lib/store.js';
import { sendPushToTokens } from '../_lib/fcm.js';
import { requirePortalAccess } from './_guard.js';

const PUSH_SEND_TIMEOUT_MS = 15000;

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
  const actor = await requirePortalAccess(req, res, { write: true, tile: 'push' });
  if (!actor) return;

  if (req.method !== 'POST') {
    return methodNotAllowed(res);
  }

  const startedAt = Date.now();
  const body = readJson(req) || {};
  const title = (body?.title || 'Test').toString().trim() || 'Test';
  const message = (body?.body || 'Push Test').toString().trim() || 'Push Test';
  const linkUrl = (body?.linkUrl || body?.actionUrl || '').toString().trim();

  // Token storage keys found: dfs:user:{email}.pushTokens, dfs:rep:{repId}:pushTokens, dfs:admin:pushTokens.
  const tokens = (await adminPushTokens())
    .map((entry) => (entry?.token || '').toString().trim())
    .filter(Boolean);
  const uniqueTokens = Array.from(new Set(tokens));
  const tokensFound = uniqueTokens.length;

  const stats = {
    mode: 'targeted',
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

  const token = uniqueTokens[0];
  let provider = null;
  let invalidToken = null;
  let okFlag = true;
  let messageOut = 'sent';
  try {
    provider = await withTimeout(
      sendPushToTokens(
        [token],
        { title, body: message },
        {
          type: 'admin-self-test',
          ...(linkUrl ? { actionUrl: linkUrl } : {}),
        },
      ),
      PUSH_SEND_TIMEOUT_MS,
      'push self-test',
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
            tokenHash: tokenHash(token),
            code: code || 'send_failed',
            detail: detail?.toString() || '',
          });
        }
        if (isInvalidTokenError({ code, message: detail })) {
          invalidToken = token;
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
        tokenHash: tokenHash(token),
        code: err?.code || 'send_failed',
        detail: err?.message || String(err),
      });
    }
    if (isInvalidTokenError(err)) {
      invalidToken = token;
    }
  }

  if (invalidToken) {
    try {
      if (await adminPushTokenRemove(invalidToken)) stats.invalidTokensRemoved += 1;
    } catch (err) {
      console.error('[admin/push-test-to-self] cleanup failed', err);
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
