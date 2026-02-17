export const config = { runtime: 'nodejs' };

import { handlePreflight, setCors, ok, bad, readJson } from '../../_lib/http.js';
import { requirePortalAccess } from '../../admin/_guard.js';
import { tdApplicabilityGet, tdApplicabilityOverrideUpsert, tdApplicabilityProfileUpsert, tdGet } from '../../_lib/tdStore.js';

export default async function handler(req, res) {
  if (handlePreflight(req, res)) return;
  setCors(req, res);

  const id = String(req.query?.id || '').trim();
  if (!id) return bad(res, 'id is required', 400);

  const wantsWrite = req.method !== 'GET';
  const actor = await requirePortalAccess(req, res, { tile: 'td', write: wantsWrite });
  if (!actor) return;

  try {
    if (req.method === 'GET') {
      return ok(res, { ok: true, ...(await tdApplicabilityGet(id)) });
    }

    if (req.method === 'PUT') {
      const body = readJson(req);
      const td = await tdGet(id);
      if (!td) return bad(res, 'not found', 404);
      await tdApplicabilityProfileUpsert(id, body?.profile || body || {}, td.rule || null);
      return ok(res, { ok: true, ...(await tdApplicabilityGet(id)) });
    }

    if (req.method === 'POST') {
      const body = readJson(req);
      const item = await tdApplicabilityOverrideUpsert(id, body || {});
      return ok(res, { ok: true, item, ...(await tdApplicabilityGet(id)) });
    }

    return bad(res, 'method not allowed', 405);
  } catch (err) {
    return bad(res, err?.message || 'server error', 500);
  }
}
