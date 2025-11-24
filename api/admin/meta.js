// api/admin/meta.js
import { loadAppMeta, sanitizeAppMeta, updateAppMeta } from '../_lib/appMeta.js';

export const config = { runtime: 'nodejs' };

// --- Utils ---
const json = (res, code, data) => {
  res.statusCode = code;
  res.setHeader('Content-Type', 'application/json; charset=utf-8');
  res.end(JSON.stringify(data));
};

function setCors(req, res) {
  const origin = req.headers.origin || '';
  res.setHeader('Access-Control-Allow-Origin', origin || '*');
  res.setHeader('Vary', 'Origin');
  res.setHeader('Access-Control-Allow-Methods', 'POST,OPTIONS');
  res.setHeader('Access-Control-Allow-Headers', 'Content-Type, X-Admin-Secret, Authorization');
}
function isOptions(req) { return req.method === 'OPTIONS'; }

// --- Auth (Admin) ---
function checkAdmin(req) {
  const header = String(req.headers['x-admin-secret'] || '');
  const env = String(process.env.ADMIN_SECRET || '');
  return env && header && header === env;
}

export default async function handler(req, res) {
  setCors(req, res);
  if (isOptions(req)) return res.status(204).end();
  if (req.method !== 'POST') return json(res, 405, { error: 'Method not allowed' });

  if (!checkAdmin(req)) return json(res, 401, { error: 'Unauthorized' });

  try {
    const data = typeof req.body === 'string' ? JSON.parse(req.body || '{}') : (req.body || {});
    const version = (data.version ?? '').toString().trim();
    const build   = (data.build   ?? '').toString().trim();
    const notes   = (data.notes   ?? '').toString();
    const testMode = data.testMode;
    const testEmail = (data.testEmail ?? '').toString();
    const testPushTokens = Array.isArray(data.testPushTokens) ? data.testPushTokens : data.testPush;

    if (!version) return json(res, 400, { error: 'version required' });

    const current = await loadAppMeta({ refresh: true });
    const meta = sanitizeAppMeta({
      ...current,
      version,
      ...(build ? { build } : {}),
      ...(notes ? { notes } : { notes: '' }),
      ...(testEmail ? { testEmail } : {}),
      ...(testPushTokens ? { testPushTokens } : {}),
      testMode,
      updatedAt: new Date().toISOString(),
    });

    await updateAppMeta(meta);

    return json(res, 200, { ok: true, meta });
  } catch (e) {
    return json(res, 500, { error: String(e) });
  }
}
