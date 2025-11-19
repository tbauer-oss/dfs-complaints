// api/_lib/fcm.js
import admin from 'firebase-admin';

let _initialized = false;

function ensureFirebaseAdmin() {
  if (_initialized) return;
  const raw = process.env.FIREBASE_SERVICE_ACCOUNT_JSON || '';
  if (!raw) throw new Error('FIREBASE_SERVICE_ACCOUNT_JSON not set');

  const creds = JSON.parse(raw);
  if (!admin.apps.length) {
    admin.initializeApp({
      credential: admin.credential.cert(creds),
    });
  }
  _initialized = true;
}

/**
 * Schickt eine einfache Push-Nachricht an ein Gerät.
 * title / body -> werden als "notification" Payload gesendet
 * data         -> zusätzliche Daten als Strings
 */
export async function sendToToken(token, { title, body, data } = {}) {
  ensureFirebaseAdmin();

  const cleanData = {};
  if (data) {
    for (const [k, v] of Object.entries(data)) {
      if (v != null) cleanData[k] = String(v);
    }
  }

  const message = {
    token,
    // 👉 WICHTIG: Notification-Payload, damit Android von sich aus was anzeigt
    notification: {
      title: title || 'DFS Complaint',
      body: body || '',
    },
    data: cleanData,
    android: {
      priority: 'high',
      notification: {
        // KEIN channelId hier erzwingen – Android nimmt einen Default-Kanal
        sound: 'default',
      },
    },
    apns: {
      payload: {
        aps: {
          sound: 'default',
        },
      },
    },
  };

  const messageId = await admin.messaging().send(message);
  return { messageId };
}
