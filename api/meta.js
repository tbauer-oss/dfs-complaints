// api/meta.js
import { loadAppMeta } from './_lib/appMeta.js';
import { withCors, ok, bad, methodNotAllowed } from './_lib/http.js';

export const config = { runtime: 'nodejs' };

const nowIso = () => new Date().toISOString();

export default async function handler(req, res) {
  withCors(req, res);
  if (req.method === 'OPTIONS') {
    return res.status(204).end();
  }

  try {
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
  } catch (error) {
    return bad(res, 'failed to load meta', 500, { detail: String(error) });
  }
}
