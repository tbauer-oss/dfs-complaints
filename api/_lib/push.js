// api/_lib/push.js – Push Notification helper (FCM)
export const config = { runtime: 'nodejs' };

import admin from 'firebase-admin';

const FCM_ENDPOINT = 'https://fcm.googleapis.com/fcm/send';
const FCM_SERVER_KEY =
  process.env.FCM_SERVER_KEY ||
  process.env.FIREBASE_SERVER_KEY ||
  process.env.FCM_LEGACY_SERVER_KEY ||
  '';
const FIREBASE_SERVICE_ACCOUNT_JSON = process.env.FIREBASE_SERVICE_ACCOUNT_JSON || '';

let firebaseMessaging = null;
let parsedServiceAccount = null;

function getFcmServerKey() {
  return (FCM_SERVER_KEY || '').trim();
}

function hasServiceAccountConfig() {
  return (FIREBASE_SERVICE_ACCOUNT_JSON || '').trim().length > 0;
}

function ensureFirebaseMessaging() {
  if (firebaseMessaging) {
    return firebaseMessaging;
  }
  if (!hasServiceAccountConfig()) {
    return null;
  }

  if (!parsedServiceAccount) {
    try {
      parsedServiceAccount = JSON.parse(FIREBASE_SERVICE_ACCOUNT_JSON);
    } catch (err) {
      console.error('[push] Failed to parse FIREBASE_SERVICE_ACCOUNT_JSON', err);
      return null;
    }
  }

  try {
    if (!admin.apps || admin.apps.length === 0) {
      admin.initializeApp({ credential: admin.credential.cert(parsedServiceAccount) });
    }
    firebaseMessaging = admin.messaging();
    return firebaseMessaging;
  } catch (err) {
    console.error('[push] Failed to initialize firebase-admin messaging', err);
    return null;
  }
}

export function isPushConfigured() {
  return getFcmServerKey().length > 0 || hasServiceAccountConfig();
}

function chunk(list, size) {
  const out = [];
  for (let i = 0; i < list.length; i += size) {
    out.push(list.slice(i, i + size));
  }
  return out;
}

function normalizeDataPayload(data = {}) {
  const payload = { ...data, _ts: Date.now() };
  const normalized = {};
  for (const [key, value] of Object.entries(payload)) {
    if (value === undefined) continue;
    normalized[key] = typeof value === 'string' ? value : JSON.stringify(value);
  }
  return normalized;
}

async function sendWithLegacyHttp({ tokens, authKey, title, body, data }) {
  const invalidTokens = new Set();
  const responses = [];
  let successCount = 0;
  let failureCount = 0;

  for (const batch of chunk(tokens, 1000)) {
    const payload = {
      registration_ids: batch,
      notification: {
        title: String(title || ''),
        body: String(body || ''),
        android_channel_id: 'complaint-status',
      },
      data: {
        ...data,
        _ts: Date.now(),
      },
    };

    try {
      const res = await fetch(FCM_ENDPOINT, {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json; charset=utf-8',
          Authorization: `key=${authKey}`,
        },
        body: JSON.stringify(payload),
      });

      const txt = await res.text();
      let json = null;
      try { json = txt ? JSON.parse(txt) : null; } catch (_) {}

      if (!res.ok) {
        console.error('[push] FCM send failed', res.status, txt);
        responses.push({ ok: false, status: res.status, body: txt });
        failureCount += batch.length;
        continue;
      }

      const successRaw = typeof json?.success === 'number' ? json.success : null;
      const failureRaw = typeof json?.failure === 'number' ? json.failure : null;
      if (successRaw !== null) {
        successCount += Math.max(0, successRaw);
      } else if (failureRaw !== null) {
        successCount += Math.max(0, batch.length - failureRaw);
      } else {
        successCount += batch.length;
      }
      if (failureRaw !== null) {
        failureCount += Math.max(0, failureRaw);
      }

      const results = Array.isArray(json?.results) ? json.results : [];
      results.forEach((r, idx) => {
        const err = r?.error;
        if (err === 'NotRegistered' || err === 'InvalidRegistration' || err === 'MismatchSenderId') {
          invalidTokens.add(batch[idx]);
        } else if (err) {
          console.warn('[push] FCM token error', err, batch[idx]);
        }
      });

      responses.push({ ok: true, status: res.status, body: json });
    } catch (e) {
      console.error('[push] Network error', e);
      responses.push({ ok: false, error: e?.message || String(e) });
      failureCount += batch.length;
    }
  }

  return {
    ok: responses.every(r => r.ok !== false),
    invalidTokens: Array.from(invalidTokens),
    responses,
    sent: successCount,
    failed: failureCount,
  };
}

async function sendWithFirebaseAdmin({ tokens, title, body, data }) {
  const messaging = ensureFirebaseMessaging();
  if (!messaging) {
    console.warn('[push] firebase-admin messaging not available');
    return { ok: false, reason: 'missing-service-account', skipped: tokens.length, sent: 0, failed: tokens.length };
  }

  const invalidTokens = new Set();
  const responses = [];
  let successCount = 0;
  let failureCount = 0;

  const dataPayload = normalizeDataPayload(data);

  for (const batch of chunk(tokens, 500)) {
    try {
      const res = await messaging.sendEachForMulticast({
        tokens: batch,
        notification: {
          title: String(title || ''),
          body: String(body || ''),
        },
        data: dataPayload,
      });

      successCount += Math.max(0, res?.successCount || 0);
      failureCount += Math.max(0, res?.failureCount || 0);

      responses.push({
        ok: (res?.failureCount || 0) === 0,
        transport: 'firebase-admin',
        successCount: res?.successCount || 0,
        failureCount: res?.failureCount || 0,
      });

      const perToken = Array.isArray(res?.responses) ? res.responses : [];
      perToken.forEach((r, idx) => {
        if (r?.success) return;
        const code = r?.error?.code || '';
        const message = r?.error?.message || '';
        responses.push({ ok: false, code, error: message, transport: 'firebase-admin' });
        if (
          code === 'messaging/registration-token-not-registered' ||
          code === 'messaging/invalid-registration-token' ||
          code === 'messaging/mismatched-credential'
        ) {
          invalidTokens.add(batch[idx]);
        }
      });
    } catch (err) {
      console.error('[push] firebase-admin send failed', err);
      responses.push({ ok: false, error: err?.message || String(err), transport: 'firebase-admin' });
      failureCount += batch.length;
    }
  }

  return {
    ok: failureCount === 0,
    invalidTokens: Array.from(invalidTokens),
    responses,
    sent: successCount,
    failed: failureCount,
  };
}

export async function sendPushNotification({ tokens = [], title = '', body = '', data = {} }) {
  const authKey = getFcmServerKey();
  const flat = Array.from(new Set((tokens || []).map(t => (t || '').toString().trim()))).filter(Boolean);
  if (flat.length === 0) {
    return { ok: false, reason: 'no-tokens', sent: 0, failed: 0 };
  }

  if (!authKey && !hasServiceAccountConfig()) {
    console.warn('[push] Missing FCM credentials – skipping push send');
    return { ok: false, reason: 'missing-credentials', skipped: flat.length, sent: 0, failed: flat.length };
  }

  if (authKey) {
    return sendWithLegacyHttp({ tokens: flat, authKey, title, body, data });
  }

  return sendWithFirebaseAdmin({ tokens: flat, title, body, data });
}
