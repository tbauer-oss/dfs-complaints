// api/rep/downloads/seen.js
export const config = { runtime: 'nodejs' };

import { setCors, handlePreflight, ok, bad, methodNotAllowed, readJson } from '../../_lib/http.js';
import { getRepFromAuthHeader } from '../../_lib/repAuth.js';
import { markDownloadsSeen } from '../../_lib/store.js';
import { loadRepById } from '../../_lib/repsStore.js';

export default async function handler(req, res) {
  if (handlePreflight(req, res)) return;
  setCors(req, res, 'Content-Type, Authorization');

  if (req.method !== 'POST') return methodNotAllowed(res);

  try {
    const auth = getRepFromAuthHeader(req);
    if (!auth?.repId) return bad(res, 'unauthorized', 401);
    const rep = await loadRepById(auth.repId);
    if (!rep || rep.active === false) return bad(res, 'unauthorized', 401);

    const body = readJson(req) || {};
    const ids = Array.isArray(body.ids)
      ? body.ids.map((x) => (x || '').toString().trim()).filter(Boolean)
      : (body.id ? [(body.id || '').toString().trim()] : []);
    if (!ids.length) return bad(res, 'id required', 400);
    await markDownloadsSeen(rep.id, ids);
    return ok(res, { ok: true });
  } catch (e) {
    console.error('[rep/downloads/seen] failed', e);
    return bad(res, 'internal error', 500);
  }
}
