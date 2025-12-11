// api/portal/news/ack.js – Bestätigung für Mitarbeiter-News
export const config = { runtime: 'nodejs' };

import { bad, handlePreflight, methodNotAllowed, noContent, setCors } from '../../_lib/http.js';
import { portalUserFromRequest } from '../../_lib/portalAuth.js';
import { portalNewsAcknowledge } from '../../_lib/store.js';

export default async function handler(req, res) {
  if (handlePreflight(req, res)) return;
  setCors(req, res);
  if (req.method !== 'POST') return methodNotAllowed(res);

  const actor = await portalUserFromRequest(req);
  if (!actor) return bad(res, 'unauthorized', 401);
  const actorKind = String(actor.kind || actor.type || '').toLowerCase();
  if (actorKind && actorKind !== 'portal' && actorKind !== 'staff') {
    return bad(res, 'forbidden', 403);
  }

  try {
    const id = (req.body?.id ?? req.query?.id ?? '').toString().trim();
    if (!id) return bad(res, 'id required', 400);
    await portalNewsAcknowledge(id, actor);
    return noContent(res);
  } catch (err) {
    console.error('portal/news/ack failed', err);
    return bad(res, err?.message || 'internal error', 400);
  }
}
