// /api/_lib/fcm.js
// Hilfsmodul zum Senden von FCM-Push-Nachrichten aus deinem Backend.
//
// Voraussetzungen:
// - Env-Variable FIREBASE_SERVICE_ACCOUNT_JSON mit kompletter Service-Account-JSON
// - "firebase-admin" als Dependency in package.json

import admin from 'firebase-admin';

let initialized = false;

/**
 * Initialisiert firebase-admin einmalig mit dem Servicekonto
 */
function ensureFirebaseAdmin() {
  if (initialized && admin.apps && admin.apps.length > 0) {
    return;
  }

  const raw = process.env.FIREBASE_SERVICE_ACCOUNT_JSON;
  if (!raw) {
    throw new Error(
      'FIREBASE_SERVICE_ACCOUNT_JSON is not set. Please add your Firebase service account JSON to the Vercel environment variables.',
    );
  }

  let serviceAccount;
  try {
    serviceAccount = JSON.parse(raw);
  } catch (err) {
    throw new Error('Invalid FIREBASE_SERVICE_ACCOUNT_JSON: ' + err);
  }

  if (!admin.apps.length) {
    admin.initializeApp({
      credential: admin.credential.cert(serviceAccount),
    });
  }

  initialized = true;
}

/**
 * Sendet eine Push-Nachricht an mehrere FCM-Tokens.
 *
 * @param {string[]} tokens - Array von FCM-Tokens
 * @param {{ title: string, body: string }} notification - Titel und Text der Notification
 * @param {Record<string, string>} [data] - optionale zusätzliche Daten (als String-Map)
 * @returns {Promise<{
 *   ok: boolean,
 *   sent: number,
 *   total: number,
 *   successCount: number,
 *   failureCount: number,
 *   invalidTokens: string[],
 *   responses: { success: boolean, error: string | null, code: string | null }[]
 * }>}
 */
export async function sendPushToTokens(tokens, notification, data = {}) {
  if (!tokens || tokens.length === 0) {
    return {
      ok: false,
      sent: 0,
      total: 0,
      successCount: 0,
      failureCount: 0,
      invalidTokens: [],
      responses: [],
    };
  }

  ensureFirebaseAdmin();

  const messaging = admin.messaging();

  const message = {
    tokens,
    notification,
    data,
  };

  const res = await messaging.sendEachForMulticast(message);

  const invalidTokens = [];
  const responses = [];

  res.responses.forEach((r, idx) => {
    const code = r.error?.code || null;
    const msg = r.error?.message || null;

    // Typische "Token ungültig" Fälle:
    const isInvalid =
      code === 'messaging/invalid-registration-token' ||
      code === 'messaging/registration-token-not-registered' ||
      (msg && msg.includes('Requested entity was not found'));

    if (isInvalid) {
      invalidTokens.push(tokens[idx]);
    }

    responses.push({
      success: r.success,
      error: msg,
      code,
    });
  });

  const ok = res.successCount > 0;

  return {
    ok,
    sent: res.successCount,
    total: tokens.length,
    successCount: res.successCount,
    failureCount: res.failureCount,
    invalidTokens,
    responses,
  };
}
