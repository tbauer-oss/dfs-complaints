// api/admin/push-broadcast.js
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
import { usersList, pushTokenRemove, repPushTokens, repPushTokenRemove } from '../_lib/store.js';
import { sendPushToTokens } from '../_lib/fcm.js';
import { requirePortalAccess } from './_guard.js';
import { loadRepById } from '../_lib/repsStore.js';

const SUPPORTED_LANGS = new Set(['de', 'en', 'fr', 'it', 'es']);
const LANG_ALIASES = {
  german: 'de',
  deutsch: 'de',
  englisch: 'en',
  english: 'en',
  french: 'fr',
  français: 'fr',
  francais: 'fr',
  italienisch: 'it',
  italian: 'it',
  spanish: 'es',
  spanisch: 'es',
  español: 'es',
  espanol: 'es',
};

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

function normalizeLangValue(value) {
  const raw = (value || '').toString().trim().toLowerCase();
  if (!raw) return null;
  if (LANG_ALIASES[raw]) return LANG_ALIASES[raw];
  if (SUPPORTED_LANGS.has(raw)) return raw;
  const two = raw.split(/[-_]/)[0];
  if (SUPPORTED_LANGS.has(two)) return two;
  if (LANG_ALIASES[two]) return LANG_ALIASES[two];
  return null;
}

function normLang(value, fallback = 'en') {
  return normalizeLangValue(value) || fallback;
}

function isPushConfigured() {
  const raw = (process.env.FIREBASE_SERVICE_ACCOUNT_JSON || '').trim();
  return raw.length > 0;
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

  try {
    const startedAt = Date.now();
    const body = readJson(req);
    const title = (body?.title || '').toString().trim();
    const message = (body?.body || '').toString().trim();
    // Optional: linkUrl (neues Feld), actionUrl (legacy)
    const linkUrl = (body?.linkUrl || body?.actionUrl || '').toString().trim();
    const dryRun = body?.dryRun === true || body?.dryRun === '1';
    const debug = body?.debug === true;
    const modeRaw = (body?.mode || '').toString().trim().toLowerCase();
    const mode = modeRaw || 'broadcast';
    const targetType = (body?.targetType || '').toString().trim().toLowerCase();
    const targetIdsRaw = Array.isArray(body?.targetIds) ? body.targetIds : [];
    const targetIds = Array.from(
      new Set(
        targetIdsRaw
          .map((id) => (id ?? '').toString().trim())
          .filter(Boolean),
      ),
    );

    if (!title || !message) {
      return bad(res, 'title/body required', 400);
    }

    // Token storage keys found: dfs:user:{email}.pushTokens, dfs:rep:{repId}:pushTokens, dfs:admin:pushTokens.
    const tokenByLang = new Map(); // lang -> Set(tokens)
    const tokenOwners = new Map(); // token -> email
    const tokenRepOwners = new Map(); // token -> repId
    const targetUserIds = new Set();

    if (mode !== 'broadcast' && mode !== 'targeted') {
      return bad(res, 'mode invalid', 400);
    }

    if (mode === 'targeted') {
      if (targetType !== 'customer' && targetType !== 'rep') {
        return bad(res, 'targetType required', 400);
      }
      if (targetIds.length === 0) {
        return bad(res, 'targetIds required', 400);
      }
      if (targetIds.length > 200) {
        return bad(res, 'targetIds exceeds limit', 400);
      }

      if (targetType === 'customer') {
        const users = await usersList();
        const targets = new Set(targetIds.map((id) => id.toLowerCase()));
        for (const user of users) {
          const owner = (user?.email || '').toString().toLowerCase();
          if (!owner || !targets.has(owner)) continue;
          targetUserIds.add(owner);
          const defaultLang = normLang(
            user?.lang ||
            user?.language ||
            user?.preferredLanguage ||
            user?.preferred_language ||
            user?.preferred_lang ||
            user?.langCode ||
            user?.lang_code ||
            user?.languageCode ||
            user?.language_code ||
            user?.locale ||
            user?.customerLang ||
            'en',
          );
          const pushTokens = Array.isArray(user?.pushTokens) ? user.pushTokens : [];
          for (const entry of pushTokens) {
            const tok = (entry?.token || '').toString().trim();
            if (!tok) continue;
            const lang = normLang(entry?.lang || entry?.locale || defaultLang);
            if (!tokenByLang.has(lang)) tokenByLang.set(lang, new Set());
            tokenByLang.get(lang).add(tok);
            if (!tokenOwners.has(tok)) tokenOwners.set(tok, owner);
          }
        }
      } else {
        for (const repId of targetIds) {
          const rep = await loadRepById(repId).catch(() => null);
          if (rep) targetUserIds.add(repId);
          const defaultLang = normLang(rep?.lang || 'en');
          const pushTokens = await repPushTokens(repId);
          for (const entry of pushTokens) {
            const tok = (entry?.token || '').toString().trim();
            if (!tok) continue;
            const lang = normLang(entry?.lang || entry?.locale || defaultLang);
            if (!tokenByLang.has(lang)) tokenByLang.set(lang, new Set());
            tokenByLang.get(lang).add(tok);
            if (!tokenRepOwners.has(tok)) tokenRepOwners.set(tok, repId);
          }
        }
      }
    } else {
      // --- 1. Alle Geräte / Tokens einsammeln ---
      const users = await usersList();

      for (const user of users) {
        const owner = (user?.email || '').toString();
        const defaultLang = normLang(
          user?.lang ||
          user?.language ||
          user?.preferredLanguage ||
          user?.preferred_language ||
          user?.preferred_lang ||
          user?.langCode ||
          user?.lang_code ||
          user?.languageCode ||
          user?.language_code ||
          user?.locale ||
          user?.customerLang ||
          'en',
        );
        const pushTokens = Array.isArray(user?.pushTokens) ? user.pushTokens : [];
        if (pushTokens.length > 0 && owner) targetUserIds.add(owner);
        for (const entry of pushTokens) {
          const tok = (entry?.token || '').toString().trim();
          if (!tok) continue;
          const lang = normLang(entry?.lang || entry?.locale || defaultLang);
          if (!tokenByLang.has(lang)) tokenByLang.set(lang, new Set());
          tokenByLang.get(lang).add(tok);
          if (!tokenOwners.has(tok)) tokenOwners.set(tok, owner);
        }
      }
    }

    const languages = [];
    let totalTokens = 0;
    for (const set of tokenByLang.values()) {
      totalTokens += set.size;
    }

    const stats = {
      mode,
      targetUsers: targetUserIds.size,
      foundTokens: totalTokens,
      sentOk: 0,
      sentFailed: 0,
      invalidTokensRemoved: 0,
      durationMs: 0,
    };
    const errorsSample = [];

    if (totalTokens === 0) {
      stats.durationMs = Date.now() - startedAt;
      return ok(res, {
        dryRun,
        totalTokens: 0,
        languages: [],
        invalidTokens: 0,
        errors: [],
        stats,
        errorsSample,
        timestamp: new Date().toISOString(),
      });
    }

    const invalidTokens = new Set();
    const errors = [];
    const sortedLangEntries = Array.from(tokenByLang.entries()).sort((a, b) =>
      a[0].localeCompare(b[0]),
    );

    // --- 2. Konfiguration prüfen ---
    if (!dryRun && !isPushConfigured()) {
      stats.durationMs = Date.now() - startedAt;
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
        errors: [
          'Push-Versand ist nicht konfiguriert (Service Account fehlt oder ist ungültig).',
        ],
        stats,
        errorsSample,
        timestamp: new Date().toISOString(),
      });
    }

    // --- 3. Pro Sprache senden ---
    for (const [lang, set] of sortedLangEntries) {
      const tokens = Array.from(set);
      let sendResult = null;

      if (!dryRun) {
        try {
          sendResult = await withTimeout(
            sendPushToTokens(
              tokens,
              { title, body: message },
              {
                type: 'admin-broadcast',
                lang,
                ...(linkUrl ? { actionUrl: linkUrl } : {}),
              },
            ),
            PUSH_SEND_TIMEOUT_MS,
            `push send (${lang})`,
          );

          stats.sentOk += Number(sendResult?.successCount || 0);
          stats.sentFailed += Number(sendResult?.failureCount || 0);

          // Invalid Tokens zum Aufräumen merken
          if (Array.isArray(sendResult?.invalidTokens)) {
            sendResult.invalidTokens.forEach((t) => invalidTokens.add(t));
          }
          if (Array.isArray(sendResult?.responses)) {
            sendResult.responses.forEach((entry, idx) => {
              if (entry?.success) return;
              const token = tokens[idx];
              const code = entry?.code || null;
              const detail = entry?.error || '';
              if (errorsSample.length < 10) {
                errorsSample.push({
                  tokenHash: token ? tokenHash(token) : 'unknown',
                  code: code || 'send_failed',
                  detail: detail?.toString() || '',
                });
              }
              if (token && isInvalidTokenError({ code, message: detail })) {
                invalidTokens.add(token);
              }
            });
          }

          // Nur echten Fehler loggen, wenn GAR KEIN Token erfolgreich war
          if (!sendResult.ok) {
            const firstRealError = (sendResult.responses || []).find(
              (r) =>
                !r.success &&
                r.error &&
                // typische "nur Token ungültig" Fehler rausfiltern
                !(
                  r.code === 'messaging/invalid-registration-token' ||
                  r.code === 'messaging/registration-token-not-registered' ||
                  r.error.includes('Requested entity was not found')
                ),
            );

            if (firstRealError) {
              errors.push(`Sprache ${lang}: ${firstRealError.error}`);
            } else if (sendResult.failureCount > 0) {
              errors.push(
                `Sprache ${lang}: Versand teilweise fehlgeschlagen (${sendResult.failureCount} Fehler).`,
              );
            }
          }
        } catch (err) {
          errors.push(`Sprache ${lang}: ${err?.message || err}`);
          stats.sentFailed += tokens.length;
          if (errorsSample.length < 10) {
            errorsSample.push({
              tokenHash: tokens[0] ? tokenHash(tokens[0]) : 'unknown',
              code: err?.code || 'send_failed',
              detail: err?.message || String(err),
            });
          }
        }
      }

      const sent = dryRun ? 0 : sendResult?.sent ?? 0;

      languages.push({
        lang,
        tokens: tokens.length,
        sent,
        ok: dryRun ? true : sent > 0,
      });
    }

    // --- 4. Ungültige Tokens aus der DB aufräumen ---
    if (!dryRun && invalidTokens.size > 0) {
      if (mode === 'targeted' && targetType === 'rep') {
        for (const badToken of invalidTokens) {
          const owner = tokenRepOwners.get(badToken);
          if (!owner) continue;
          try {
            if (await repPushTokenRemove(owner, badToken)) stats.invalidTokensRemoved += 1;
          } catch (err) {
            console.error('[admin/push-broadcast] cleanup failed', err);
          }
        }
      } else {
        for (const badToken of invalidTokens) {
          const owner = tokenOwners.get(badToken);
          if (!owner) continue;
          try {
            if (await pushTokenRemove(owner, badToken)) stats.invalidTokensRemoved += 1;
          } catch (err) {
            console.error('[admin/push-broadcast] cleanup failed', err);
          }
        }
      }
    }

    stats.durationMs = Date.now() - startedAt;
    return ok(res, {
      dryRun,
      totalTokens,
      languages,
      invalidTokens: invalidTokens.size,
      errors,
      stats,
      errorsSample: debug ? errorsSample : errorsSample,
      timestamp: new Date().toISOString(),
    });
  } catch (err) {
    console.error('admin/push-broadcast error', err);
    return bad(res, 'internal error', 500);
  }
}
