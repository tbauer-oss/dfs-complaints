// Gemeinsamer Guard für DFS Portal Endpunkte (ehem. Adminbereich)
import { bad, setCors, handlePreflight } from '../_lib/http.js';
import { canReadTile, canWrite, canWriteTile, portalUserFromRequest } from '../_lib/portalAuth.js';

export async function requirePortalAccess(req, res, { write = false, tile, allowPrrc = false } = {}) {
  // ✅ CORS immer zuerst – auch für 401/403
  if (handlePreflight(req, res)) return null;

  const actor = await portalUserFromRequest(req);
  if (!actor) {
    bad(res, 'unauthorized', 401);
    return null;
  }

  const tileId = (tile ?? '').toString().trim();
  const isPrrc = actor?.isPRRC === true;

  if (tileId) {
    const allowed = write ? canWriteTile(actor, tileId) : canReadTile(actor, tileId);
    if (!allowed) {
      if (allowPrrc && isPrrc) return actor;
      bad(res, 'forbidden', 403);
      return null;
    }
  } else if (write && !canWrite(actor.role)) {
    if (allowPrrc && isPrrc) return actor;
    bad(res, 'forbidden', 403);
    return null;
  }

  return actor;
}
