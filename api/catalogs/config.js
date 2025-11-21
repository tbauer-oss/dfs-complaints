// api/catalogs/config.js
export const config = { runtime: 'nodejs' };

import {
  handlePreflight,
  setCors,
  ok,
  bad,
  methodNotAllowed,
  readJson,
} from '../_lib/http.js';
import { catalogConfigGet, catalogConfigSet } from '../_lib/store.js';

const ADMIN_SECRET = process.env.ADMIN_SECRET || '';

function isAdmin(req) {
  const hdr = req.headers?.['x-admin-secret'];
  return typeof hdr === 'string' && !!ADMIN_SECRET && hdr === ADMIN_SECRET;
}

export default async function handler(req, res) {
  if (handlePreflight(req, res)) return;
  setCors(req, res);

  try {
    if (req.method === 'GET') {
      const cfg = await catalogConfigGet();
      return ok(res, cfg);
    }

    if (req.method === 'PUT') {
      if (!isAdmin(req)) return bad(res, 'admin unauthorized', 401);
      const body = readJson(req) || {};
      const next = await catalogConfigSet(body);
      return ok(res, { ok: true, config: next });
    }

    return methodNotAllowed(res);
  } catch (e) {
    return bad(res, e?.message || String(e), 500);
  }
}
