// api/meta.js
import { loadAppMeta } from './_lib/appMeta.js';

export const config = { runtime: 'nodejs' };

// --- Utils ---
const nowIso = () => new Date().toISOString();
const json = (res, code, data) => {
  res.statusCode = code;
  res.setHeader('Content-Type', 'application/json; charset=utf-8');
  res.end(JSON.stringify(data));
};

// --- (Optional) CORS ---
function setCors(req, res) {
  const origin = req.headers.origin || '';
  res.setHeader('Access-Control-Allow-Origin', origin || '*');
  res.setHeader('Vary', 'Origin');
  res.setHeader('Access-Control-Allow-Methods', 'GET,OPTIONS');
  res.setHeader('Access-Control-Allow-Headers', 'Content-Type, X-Admin-Secret, Authorization');
}
function isOptions(req) { return req.method === 'OPTIONS'; }

export default async function handler(req, res) {
  setCors(req, res);
  if (isOptions(req)) return res.status(204).end();
  if (req.method !== 'GET') return json(res, 405, { error: 'Method not allowed' });

  try {
    const meta = await loadAppMeta();
    // Falls leer, optional Default befüllen
    return json(res, 200, {
      version: meta.version || '',
      build: meta.build || '',
      notes: meta.notes || '',
      updatedAt: meta.updatedAt || '',
      testMode: meta.testMode || false,
      testEmail: meta.testEmail || '',
      testPushTokens: Array.isArray(meta.testPushTokens) ? meta.testPushTokens : [],
      // Optionale Zusatzfelder möglich
      serverTime: nowIso(),
    });
  } catch (e) {
    return json(res, 500, { error: String(e) });
  }
}
