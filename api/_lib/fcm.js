// /api/_lib/fcm.js
// Kleines Hilfsmodul zum Senden von FCM-Push-Nachrichten aus deinem Backend.
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
      'FIREBASE_SERVICE_ACCOUNT_JSON is not set. Please add your Firebase service account JSON to the Vercel environment variables.'
    );
  }

  let serviceAccount;
  try {
    serviceAccount = JSON.parse(raw);
  } catch (err) {
    throw new Error('Invalid FIREBASE_SERVICE_ACCOUNT_JSON: ' + err);
  }

  // Nur initialisieren, wenn noch keine App existiert
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
 * @returns {Promise<{successCount:number,failureCount:number,responses:any[]}>}
 */
export async function sendPushToTokens(tokens, notification, data = {}) {
  if (!tokens || tokens.length === 0) {
    return { successCount: 0, failureCount: 0, responses: [] };
  }

  ensureFirebaseAdmin();

  const messaging = admin.messaging();

  const message = {
    tokens,
    notification,
    data,
  };

  const res = await messaging.sendEachForMulticast(message);

  return {
    successCount: res.successCount,
    failureCount: res.failureCount,
    responses: (res.responses || []).map((r) => ({
      success: r.success,
      error: r.error ? r.error.message : null,
    })),
  };
}
