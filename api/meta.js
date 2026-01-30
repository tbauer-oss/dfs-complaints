// api/meta.js
import { loadAppMeta } from './_lib/appMeta.js';
import { handlePreflight, setCors } from './_lib/http.js';

export const config = { runtime: 'nodejs' };

// --- Utils ---
const nowIso = () => new Date().toISOString();
const json = (res, code, data) => {
  res.statusCode = code;
  res.setHeader('Content-Type', 'application/json; charset=utf-8');
  res.end(JSON.stringify(data));
};

export default async function handler(req, res) {
  if (handlePreflight(req, res)) return;
  setCors(req, res);
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
