// api/meta.js
import { loadAppMeta } from './_lib/appMeta.js';
import { ok, methodNotAllowed, safeHandler } from './_lib/http.js';

export const config = { runtime: 'nodejs' };

const nowIso = () => new Date().toISOString();

async function handler(req, res) {
  if (req.method !== 'GET') {
    return methodNotAllowed(res);
  }

  const meta = await loadAppMeta();
  const version = meta.version || '';
  const buildTime = meta.updatedAt || nowIso();
  return ok(res, {
    ok: true,
    name: 'dfs-complaints-backend',
    version,
    buildTime,
  });
}

export default safeHandler(handler, { route: '/api/meta' });
