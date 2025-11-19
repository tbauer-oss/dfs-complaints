// api/_lib/push.js – Push Notification helper (FCM HTTP v1)
import crypto from 'crypto';

export const config = { runtime: 'nodejs' };

// Service-Account-basiertes FCM HTTP v1
const PROJECT_ID = process.env.FIREBASE_PROJECT_ID || '';
const CLIENT_EMAIL = process.env.FIREBASE_CLIENT_EMAIL || '';
const PRIVATE_KEY_RAW = process.env.FIREBASE_PRIVATE_KEY || '';

// Bei \n-Variante in Vercel wieder in echte Zeilenumbrüche umwandeln
const PRIVATE_KEY = PRIVATE_KEY_RAW.replace(/\\n/g, '\n');

const GOOGLE_TOKEN_URL = 'https://oauth2.googleapis.com/token';
const FCM_V1_ENDPOINT = PROJECT_ID
  ? `https://fcm.googleapis.com/v1/projects/${PROJECT_ID}/messages:send`
  : '';

function chunk(list, size) {
  const out = [];
  for (let i = 0; i < list.length; i += size) {
    out.push(list.slice(i, i + size));
  }
  return out;
}

// Access-Token-Caching (damit wir nicht bei jedem Push neu zu Google rennen)
let cachedAccessToken = null;
let cachedAccessTokenExpiry = 0;

async function getAccessToken() {
  const now = Math.floor(Date.now() / 1000);

  if (cachedAccessToken && now < cachedAccessTokenExpiry - 60) {
    return cachedAccessToken;
  }

  if (!CLIENT_EMAIL || !PRIVATE_KEY) {
    throw new Error('[push] Missing FIREBASE_CLIENT_EMAIL or FIREBASE_PRIVATE_KEY');
  }

  const header = {
    alg: 'RS256',
    typ: 'JWT',
  };

  const payload = {
    iss: CLIENT_EMAIL,
    scope: 'https://www.googleapis.com/auth/firebase.messaging',
    aud: GOOGLE_TOKEN_URL,
    iat: now,
    exp: now + 3600,
  };

  const base64url = obj =>
    Buffer.from(JSON.stringify(obj))
      .toString('base64')
      .replace(/\+/g, '-')
      .replace(/\//g, '_')
      .replace(/=+$/, '');

  const headerB64 = base64url(header);
  const payloadB64 = base64url(payload);
  const toSign = `${headerB64}.${payloadB64}`;

  const signer = crypto.createSign('RSA-SHA256');
  signer.update(toSign);
  const signature = signer
    .sign(PRIVATE_KEY)
    .toString('base64')
    .replace(/\+/g, '-')
    .replace(/\//g, '_')
    .replace(/=+$/, '');

  const jwt = `${toSign}.${signature}`;

  const body = new URLSearchParams({
    grant_type: 'urn:ietf:params:oauth:grant-type:jwt-bearer',
    assertion: jwt,
  });

  const res = await fetch(GOOGLE_TOKEN_URL, {
    method: 'POST',
    headers: {
      'Content-Type': 'application/x-www-form-urlencoded',
    },
    body,
  });

  if (!res.ok) {
    const txt = await res.text();
    console.error('[push] Failed to fetch access token', res.status, txt);
    throw new Error(`[push] Failed to get access token: ${res.status}`);
  }

  const json = await res.json();
  cachedAccessToken = json.access_token;
  cachedAccessTokenExpiry = now + (json.expires_in || 3600);

  return cachedAccessToken;
}

export function isPushConfigured() {
  return Boolean(PROJECT_ID && CLIENT_EMAIL && PRIVATE_KEY);
}

export async function sendPushNotification({ tokens = [], title = '', body = '', data = {} }) {
  const flat = Array.from(
    new Set((tokens || []).map(t => (t || '').toString().trim())),
  ).filter(Boolean);

  if (!isPushConfigured()) {
    console.warn('[push] Missing FCM service account config – skipping push send');
    return {
      ok: false,
      reason: 'missing-service-account',
      skipped: flat.length,
      sent: 0,
      failed: flat.length,
    };
  }

  if (flat.length === 0) {
    return { ok: false, reason: 'no-tokens', sent: 0, failed: 0 };
  }

  let accessToken;
  try {
    accessToken = await getAccessToken();
  } catch (e) {
    console.error('[push] Could not get access token', e);
    return {
      ok: false,
      reason: 'auth-failed',
      sent: 0,
      failed: flat.length,
    };
  }

  const invalidTokens = new Set();
  const responses = [];
  let successCount = 0;
  let failureCount = 0;

  // Wir schicken jetzt pro Token eine HTTP v1-Nachricht
  // (Broadcast bleibt möglich, nur mit mehr Requests – bei deiner Menge unkritisch)
  for (const batch of chunk(flat, 100)) {
    for (const token of batch) {
      const payload = {
        message: {
          token,
          notification: {
            title: String(title || ''),
            body: String(body || ''),
          },
          data: {
            ...data,
            _ts: Date.now().toString(),
          },
        },
      };

      try {
        const res = await fetch(FCM_V1_ENDPOINT, {
          method: 'POST',
          headers: {
            'Content-Type': 'application/json; charset=utf-8',
            Authorization: `Bearer ${accessToken}`,
          },
          body: JSON.stringify(payload),
        });

        const txt = await res.text();
        let json = null;
        try {
          json = txt ? JSON.parse(txt) : null;
        } catch (_) {
          // ignore parse error, txt bleibt als Fallback
        }

        if (!res.ok) {
          failureCount += 1;

          const status = json?.error?.status || '';
          if (status === 'NOT_FOUND' || status === 'INVALID_ARGUMENT') {
            invalidTokens.add(token);
          } else {
            console.warn('[push] FCM v1 send failed', status, token);
          }

          responses.push({ ok: false, status: res.status, body: json || txt });
          continue;
        }

        successCount += 1;
        responses.push({ ok: true, status: res.status, body: json });
      } catch (e) {
        failureCount += 1;
        console.error('[push] Network error', e);
        responses.push({ ok: false, error: e?.message || String(e) });
      }
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
