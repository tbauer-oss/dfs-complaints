// api/admin/push-broadcast.js
export const config = { runtime: 'nodejs' };

import {
  setCors,
  handlePreflight,
  ok,
  bad,
  methodNotAllowed,
  readJson,
} from '../_lib/http.js';
import { usersList, pushTokenRemove } from '../_lib/store.js';
import { sendPushNotification, isPushConfigured } from '../_lib/push.js';

function requireAdmin(req, res) {
  const sec = (req.headers?.['x-admin-secret'] || '').toString().trim();
  const expected = (process.env.ADMIN_SECRET || '').toString().trim();
  if (!sec || !expected || sec !== expected) {
    bad(res, 'unauthorized', 401);
    return false;
  }
  return true;
}

const SUPPORTED_LANGS = new Set(['de', 'en', 'fr', 'it', 'es']);
function normLang(value) {
  const raw = (value || '').toString().trim().toLowerCase();
  if (SUPPORTED_LANGS.has(raw)) return raw;
  const two = raw.split(/[-_]/)[0];
  return SUPPORTED_LANGS.has(two) ? two : 'de';
}

function describeSendFailure(result) {
  if (!result) return null;
  const reason = result.reason ? result.reason.toString() : '';
  if (reason === 'missing-server-key' || reason === 'missing-credentials' || reason === 'missing-service-account') {
    return 'Push-Dienst ist nicht konfiguriert (Firebase Server Key oder Service Account fehlen).';
  }
  if (reason === 'no-tokens') {
    return 'Keine gültigen Geräte vorhanden.';
  }
  if (reason && reason !== 'missing-server-key' && reason !== 'no-tokens') {
    return reason;
  }
  if (Array.isArray(result.responses)) {
    for (const resp of result.responses) {
      if (!resp || resp.ok !== false) continue;
      if (resp.error) return resp.error;
      if (resp.status && resp.body) {
        const snippet = typeof resp.body === 'string'
          ? resp.body
          : (() => {
              try { return JSON.stringify(resp.body); }
              catch { return String(resp.body); }
            })();
        return `FCM HTTP ${resp.status}: ${snippet.length > 240 ? `${snippet.slice(0, 237)}…` : snippet}`;
      }
      if (resp.status) {
        return `FCM HTTP ${resp.status}`;
      }
    }
  }
  return null;
}

export default async function handler(req, res) {
  if (handlePreflight(req, res)) return;
  setCors(req, res);
  if (!requireAdmin(req, res)) return;

  if (req.method !== 'POST') {
    return methodNotAllowed(res);
  }

  try {
    const body = readJson(req);
    const title = (body?.title || '').toString().trim();
    const message = (body?.body || '').toString().trim();
    const actionUrl = (body?.actionUrl || '').toString().trim();
    const dryRun = body?.dryRun === true || body?.dryRun === '1';

    if (!title || !message) {
      return bad(res, 'title/body required', 400);
    }

    const users = await usersList();
    const tokenByLang = new Map();
    const tokenOwners = new Map();

    for (const user of users) {
      const owner = (user?.email || '').toString();
      const defaultLang = normLang(user?.lang || 'de');
      const pushTokens = Array.isArray(user?.pushTokens) ? user.pushTokens : [];
      for (const entry of pushTokens) {
        const tok = (entry?.token || '').toString().trim();
        if (!tok) continue;
        const lang = normLang(entry?.lang || defaultLang);
        if (!tokenByLang.has(lang)) tokenByLang.set(lang, new Set());
        tokenByLang.get(lang).add(tok);
        if (!tokenOwners.has(tok)) tokenOwners.set(tok, owner);
      }
    }

    const languages = [];
    let totalTokens = 0;
    for (const set of tokenByLang.values()) {
      totalTokens += set.size;
    }

    if (totalTokens === 0) {
      return ok(res, {
        dryRun,
        totalTokens: 0,
        languages: [],
        invalidTokens: 0,
        errors: [],
        timestamp: new Date().toISOString(),
      });
    }

    const invalidTokens = new Set();
    const errors = [];
    const sortedLangEntries = Array.from(tokenByLang.entries()).sort((a, b) => a[0].localeCompare(b[0]));

    if (!dryRun && !isPushConfigured()) {
      return ok(res, {
        dryRun,
        totalTokens,
        languages: sortedLangEntries.map(([lang, set]) => ({
          lang,
          tokens: set.size,
          sent: 0,
          ok: false,
        })),
        invalidTokens: 0,
        errors: ['Push-Versand ist nicht konfiguriert (Firebase Server Key oder Service Account fehlen).'],
        timestamp: new Date().toISOString(),
      });
    }

    for (const [lang, set] of sortedLangEntries) {
      const tokens = Array.from(set);
      let sendResult = null;
      if (!dryRun) {
        try {
          sendResult = await sendPushNotification({
            tokens,
            title,
            body: message,
            data: {
              type: 'admin-broadcast',
              lang,
              ...(actionUrl ? { actionUrl } : {}),
            },
          });
          if (Array.isArray(sendResult?.invalidTokens)) {
            sendResult.invalidTokens.forEach((t) => invalidTokens.add(t));
          }
          if (!sendResult?.ok) {
            const detail = describeSendFailure(sendResult);
            errors.push(`Sprache ${lang}: ${detail || 'Versand teilweise fehlgeschlagen.'}`);
          }
        } catch (err) {
          errors.push(`Sprache ${lang}: ${err?.message || err}`);
        }
      }

      languages.push({
        lang,
        tokens: tokens.length,
        sent: dryRun
          ? 0
          : Math.min(
              tokens.length,
              Math.max(
                0,
                sendResult && typeof sendResult.sent === 'number'
                  ? Math.floor(sendResult.sent)
                  : sendResult?.ok
                      ? tokens.length
                      : 0,
              ),
            ),
        ok: dryRun ? true : !!sendResult?.ok,
      });
    }

    if (!dryRun && invalidTokens.size > 0) {
      for (const badToken of invalidTokens) {
        const owner = tokenOwners.get(badToken);
        if (!owner) continue;
        try {
          await pushTokenRemove(owner, badToken);
        } catch (err) {
          console.error('[admin/push-broadcast] cleanup failed', err);
        }
      }
    }

    return ok(res, {
      dryRun,
      totalTokens,
      languages,
      invalidTokens: invalidTokens.size,
      errors,
      timestamp: new Date().toISOString(),
    });
  } catch (err) {
    console.error('admin/push-broadcast error', err);
    return bad(res, 'internal error', 500);
  }
}
