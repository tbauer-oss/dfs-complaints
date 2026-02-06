// api/admin/meta.js
import { loadAppMeta, sanitizeAppMeta, updateAppMeta } from '../_lib/appMeta.js';
import { handlePreflight, setCors } from '../_lib/http.js';
import { requirePortalAccess } from './_guard.js';

export const config = { runtime: 'nodejs' };

// --- Utils ---
const json = (res, code, data) => {
  res.statusCode = code;
  res.setHeader('Content-Type', 'application/json; charset=utf-8');
  res.end(JSON.stringify(data));
};

export default async function handler(req, res) {
  if (handlePreflight(req, res)) return;
  setCors(req, res);
  if (req.method !== 'POST') return json(res, 405, { error: 'Method not allowed' });

  const actor = await requirePortalAccess(req, res, { write: true, tile: 'appMeta' });
  if (!actor) return;

  try {
    const data = typeof req.body === 'string' ? JSON.parse(req.body || '{}') : (req.body || {});
    const current = await loadAppMeta({ refresh: true });

    const fromRequest = (key) => Object.prototype.hasOwnProperty.call(data, key);

    const version = fromRequest('version')
      ? (data.version ?? '').toString().trim()
      : (current.version ?? '').toString().trim();
    const build = fromRequest('build') ? (data.build ?? '').toString().trim() : undefined;
    const notes = fromRequest('notes') ? (data.notes ?? '').toString() : undefined;
    const testMode = fromRequest('testMode') ? data.testMode : current.testMode;
    const testEmail = fromRequest('testEmail') ? (data.testEmail ?? '').toString() : undefined;

    let testPushTokens = undefined;
    if (fromRequest('testPushTokens')) {
      testPushTokens = data.testPushTokens;
    } else if (fromRequest('testPush')) {
      testPushTokens = data.testPush;
    }

    if (!version) return json(res, 400, { error: 'version required' });

    const meta = sanitizeAppMeta({
      ...current,
      version,
      ...(build !== undefined ? { build } : {}),
      ...(notes !== undefined ? { notes } : {}),
      ...(testEmail !== undefined ? { testEmail } : {}),
      ...(testPushTokens !== undefined ? { testPushTokens } : {}),
      ...(fromRequest('testMode') ? { testMode } : {}),
      updatedAt: new Date().toISOString(),
    });

    await updateAppMeta(meta);

    return json(res, 200, { ok: true, meta });
  } catch (e) {
    return json(res, 500, { error: String(e) });
  }
}
