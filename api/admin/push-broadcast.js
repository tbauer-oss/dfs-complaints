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
import { sendPushToTokens } from '../_lib/fcm.js';
import { requirePortalAccess } from './_guard.js';

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

export default async function handler(req, res) {
  if (handlePreflight(req, res)) return;
  setCors(req, res);
  const actor = await requirePortalAccess(req, res, { write: true });
  if (!actor) return;

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

    // --- 1. Alle Geräte / Tokens einsammeln ---
    const users = await usersList();
    const tokenByLang = new Map(); // lang -> Set(tokens)
    const tokenOwners = new Map(); // token -> email

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
      for (const entry of pushTokens) {
        const tok = (entry?.token || '').toString().trim();
        if (!tok) continue;
        const lang = normLang(entry?.lang || entry?.locale || defaultLang);
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
    const sortedLangEntries = Array.from(tokenByLang.entries()).sort((a, b) =>
      a[0].localeCompare(b[0]),
    );

    // --- 2. Konfiguration prüfen ---
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
        errors: [
          'Push-Versand ist nicht konfiguriert (Service Account fehlt oder ist ungültig).',
        ],
        timestamp: new Date().toISOString(),
      });
    }

    // --- 3. Pro Sprache senden ---
    for (const [lang, set] of sortedLangEntries) {
      const tokens = Array.from(set);
      let sendResult = null;

      if (!dryRun) {
        try {
          sendResult = await sendPushToTokens(
            tokens,
            { title, body: message },
            {
              type: 'admin-broadcast',
              lang,
              ...(actionUrl ? { actionUrl } : {}),
            },
          );

          // Invalid Tokens zum Aufräumen merken
          if (Array.isArray(sendResult?.invalidTokens)) {
            sendResult.invalidTokens.forEach((t) => invalidTokens.add(t));
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
