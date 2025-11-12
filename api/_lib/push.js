// api/_lib/push.js – Push Notification helper (FCM)
export const config = { runtime: 'nodejs' };

const FCM_ENDPOINT = 'https://fcm.googleapis.com/fcm/send';
const FCM_SERVER_KEY =
  process.env.FCM_SERVER_KEY ||
  process.env.FIREBASE_SERVER_KEY ||
  process.env.FCM_LEGACY_SERVER_KEY ||
  '';

function chunk(list, size) {
  const out = [];
  for (let i = 0; i < list.length; i += size) {
    out.push(list.slice(i, i + size));
  }
  return out;
}

export async function sendPushNotification({ tokens = [], title = '', body = '', data = {} }) {
  const authKey = (FCM_SERVER_KEY || '').trim();
  const flat = Array.from(new Set((tokens || []).map(t => (t || '').toString().trim()))).filter(Boolean);
  if (!authKey) {
    console.warn('[push] Missing FCM server key – skipping push send');
    return { ok: false, reason: 'missing-server-key', skipped: flat.length };
  }
  if (flat.length === 0) return { ok: false, reason: 'no-tokens' };

  const invalidTokens = new Set();
  const responses = [];

  for (const batch of chunk(flat, 1000)) {
    const payload = {
      registration_ids: batch,
      notification: {
        title: String(title || ''),
        body: String(body || ''),
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
        continue;
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
    }
  }

  return {
    ok: responses.every(r => r.ok !== false),
    invalidTokens: Array.from(invalidTokens),
    responses,
  };
}
