// api/meta.js
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

// --- (Optional) CORS ---
function setCors(req, res) {
  const origin = req.headers.origin || '';
  res.setHeader('Access-Control-Allow-Origin', origin || '*');
  res.setHeader('Vary', 'Origin');
  res.setHeader('Access-Control-Allow-Methods', 'GET,OPTIONS');
  res.setHeader('Access-Control-Allow-Headers', 'Content-Type, X-Admin-Secret, Authorization');
}
function isOptions(req) { return req.method === 'OPTIONS'; }

// --- Upstash Redis (empfohlen) ---
async function loadMeta() {
  const url = process.env.UPSTASH_REDIS_REST_URL;
  const token = process.env.UPSTASH_REDIS_REST_TOKEN;
  const key = process.env.APP_META_KEY || 'dfs:app:meta';

  if (!url || !token) {
    // Dev-Fallback in Memory (Prozesslebenszeit)
    global.__APP_META__ = global.__APP_META__ || null;
    return global.__APP_META__ || {
      version: '',
      build: envBuild(),
      notes: '',
      updatedAt: '',
    };
  }

  const r = await fetch(`${url}/get/${encodeURIComponent(key)}`, {
    headers: { Authorization: `Bearer ${token}` },
    cache: 'no-store',
  });
  const j = await r.json();
  if (j && typeof j.result === 'string' && j.result) {
    try { return JSON.parse(j.result); } catch {}
  }
  return { version: '', build: envBuild(), notes: '', updatedAt: '' };
}

export default async function handler(req, res) {
  setCors(req, res);
  if (isOptions(req)) return res.status(204).end();
  if (req.method !== 'GET') return json(res, 405, { error: 'Method not allowed' });

  try {
    const meta = await loadMeta();
    // Falls leer, optional Default befüllen
    return json(res, 200, {
      version: meta.version || '',
      build: meta.build || envBuild(),
      notes: meta.notes || '',
      updatedAt: meta.updatedAt || '',
      // Optionale Zusatzfelder möglich
      serverTime: nowIso(),
    });
  } catch (e) {
    return json(res, 500, { error: String(e) });
  }
}
