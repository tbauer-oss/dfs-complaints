// Gemeinsamer Guard für DFS Portal Endpunkte (ehem. Adminbereich)
import { bad } from '../_lib/http.js';
import {
  canReadTile,
  canWrite,
  canWriteTile,
  normalizeRole,
  PORTAL_ROLES,
  portalUserFromRequest,
} from '../_lib/portalAuth.js';

export async function requirePortalAccess(req, res, { write = false, tile, allowPrrc = false } = {}) {
  const actor = await portalUserFromRequest(req, { allowSecretFallback: false });
  if (!actor) {
    bad(res, 'unauthorized', 401);
    return null;
  }

  const tileId = (tile ?? '').toString().trim();
  const isPrrc = actor?.isPRRC === true || normalizeRole(actor?.role) === PORTAL_ROLES.prrc;

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

