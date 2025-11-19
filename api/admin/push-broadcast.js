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
import { sendPushToTokens } from '../_lib/fcm.js'; // ⬅️ NEU: direkter Import aus fcm.js

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

// ⬅️ NEU: einfache Konfig-Check-Funktion nur für Service Account
function isPushConfigured() {
  const raw = (process.env.FIREBASE_SERVICE_ACCOUNT_JSON || '').trim();
  return raw.length > 0;
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

    // ---- Tokens aus allen Usern einsammeln ----
    const users = await usersList();
    const tokenByLang = new Map(); // lang -> Set(tokens)
    const tokenOwners = new Map(); // token -> email

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
    const sortedLangEntries = Array.from(tokenByLang.entries())
      .sort((a, b) => a[0].localeCompare(b[0]));

    // Konfigurationsprüfung (Service Account)
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

    // ---- Pro Sprache senden ----
    for (const [lang, set] of sortedLangEntries) {
      const tokens = Array.from(set);
      let sendResult = null;

      if (!dryRun) {
        try {
          // ⬅️ NEU: Versand über firebase-admin Helper
          sendResult = await sendPushToTokens(
            tokens,
            {
              title,
              body: message,
            },
            {
              type: 'admin-broadcast',
              lang,
              ...(actionUrl ? { actionUrl } : {}),
            },
          );

          // Optional: falls du später invalidTokens aus fcm.js zurückgibst
          if (Array.isArray(sendResult?.invalidTokens)) {
            sendResult.invalidTokens.forEach((t) => invalidTokens.add(t));
          }

          if (sendResult.failureCount > 0) {
            const firstErr = (sendResult.responses || [])
              .find((r) => !r.success && r.error)?.error;
            errors.push(
              `Sprache ${lang}: ${
                firstErr ||
                `Versand teilweise fehlgeschlagen (${sendResult.failureCount} Fehler).`
              }`,
            );
          }
        } catch (err) {
          errors.push(`Sprache ${lang}: ${err?.message || err}`);
        }
      }

      const sentCount =
        dryRun ? 0 : (sendResult?.successCount ?? 0);

      languages.push({
        lang,
        tokens: tokens.length,
        sent: sentCount,
        ok: dryRun ? true : sentCount > 0,
      });
    }

    // ---- Aufräumen: ungültige Tokens löschen (falls vorhanden) ----
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
