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
import { requirePortalAccess } from '../admin/_guard.js';
import { catalogConfigGet, catalogConfigSet } from '../_lib/store.js';

export default async function handler(req, res) {
  if (handlePreflight(req, res)) return;
  setCors(req, res);

  try {
    if (req.method === 'GET') {
      const cfg = await catalogConfigGet();
      return ok(res, cfg);
    }

    if (req.method === 'PUT') {
      const actor = await requirePortalAccess(req, res, { write: true });
      if (!actor) return;
      const body = readJson(req) || {};
      const next = await catalogConfigSet(body);
      return ok(res, { ok: true, config: next });
    }

    return methodNotAllowed(res);
  } catch (e) {
    return bad(res, e?.message || String(e), 500);
  }
}
