// api/admin/meta.js
export const config = { runtime: 'nodejs' };

// --- Utils ---
const nowIso = () => new Date().toISOString();
const envBuild = () => {
  const fromEnv =
    process.env.APP_BUILD ||
    process.env.BUILD_ID ||
    process.env.VERCEL_GIT_COMMIT_SHA ||
    process.env.VERCEL_GIT_COMMIT_REF ||
    '';
  return fromEnv.toString();
};
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

// --- Upstash Redis Speicherung ---
async function saveMeta(meta) {
  const url = process.env.UPSTASH_REDIS_REST_URL;
  const token = process.env.UPSTASH_REDIS_REST_TOKEN;
  const key = process.env.APP_META_KEY || 'dfs:app:meta';

  if (!url || !token) {
    // Dev-Fallback in Memory
    global.__APP_META__ = meta;
    return true;
  }

  const body = JSON.stringify(meta);
  const r = await fetch(`${url}/set/${encodeURIComponent(key)}/${encodeURIComponent(body)}`, {
    method: 'POST',
    headers: { Authorization: `Bearer ${token}` },
  });
  return r.ok;
}

export default async function handler(req, res) {
  setCors(req, res);
  if (isOptions(req)) return res.status(204).end();
  if (req.method !== 'POST') return json(res, 405, { error: 'Method not allowed' });

  if (!checkAdmin(req)) return json(res, 401, { error: 'Unauthorized' });

  try {
    const data = typeof req.body === 'string' ? JSON.parse(req.body || '{}') : (req.body || {});
    const version = (data.version ?? '').toString().trim();
    const build   = (data.build   ?? '').toString().trim() || envBuild();
    const notes   = (data.notes   ?? '').toString();

    if (!version) return json(res, 400, { error: 'version required' });

    const meta = {
      version,
      ...(build && { build }),
      ...(notes && { notes }),
      updatedAt: nowIso(),
    };

    const ok = await saveMeta(meta);
    if (!ok) return json(res, 500, { error: 'persist failed' });

    return json(res, 200, { ok: true, meta });
  } catch (e) {
    return json(res, 500, { error: String(e) });
  }
}
