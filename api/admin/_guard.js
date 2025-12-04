// Gemeinsamer Guard für DFS Portal Endpunkte (ehem. Adminbereich)
import { bad } from '../_lib/http.js';
import { canWrite, portalUserFromRequest } from '../_lib/portalAuth.js';

export async function requirePortalAccess(req, res, { write = false } = {}) {
  const actor = await portalUserFromRequest(req);
  if (!actor) {
    bad(res, 'unauthorized', 401);
    return null;
  }

  // Rollenprüfung (Superuser/User dürfen schreiben, Readonly nur lesen)
  if (write && !canWrite(actor.role)) {
    bad(res, 'forbidden', 403);
    return null;
  }

  return actor;
}

