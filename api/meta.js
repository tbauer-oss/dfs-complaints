// api/meta.js
import { loadAppMeta } from './_lib/appMeta.js';
import { withCorsHandler, ok, bad, methodNotAllowed } from './_lib/http.js';

export const config = { runtime: 'nodejs' };

const nowIso = () => new Date().toISOString();

export default withCorsHandler(async function handler(req, res) {
  if (req.method !== 'GET') {
    return methodNotAllowed(res);
  }

  try {
    const meta = await loadAppMeta();
    const version = meta.version || '';
    const buildTime = meta.updatedAt || nowIso();
    ok(res, {
      ok: true,
      name: 'dfs-complaints-backend',
      version,
      buildTime,
    });
  } catch (error) {
    bad(res, 'failed to load meta', 500, { detail: String(error) });
  }
});
