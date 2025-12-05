// /api/admin/ui-config.js – Zentrales Admin-Dashboard (Kacheln/Layout)
export const config = { runtime: 'nodejs' };

import { handlePreflight, setCors, ok, bad, methodNotAllowed, readJson } from '../_lib/http.js';
import { loadPortalAdminUi, savePortalAdminUi } from '../_lib/store.js';
import { canManageUsers } from '../_lib/portalAuth.js';
import { requirePortalAccess } from './_guard.js';

export default async function handler(req, res) {
  if (handlePreflight(req, res)) return;
  setCors(req, res);

  // Das UI-Layout wird von allen angemeldeten Portal-Nutzern gelesen, daher
  // darf der GET-Handler nicht an der PortalUsers-Kachel scheitern. Für
  // Änderungen (POST) bleiben wir streng und koppeln an die tile-Berechtigung
  // plus Rollen-Prüfung unten.
  const actor = await requirePortalAccess(req, res, {
    write: req.method !== 'GET',
    tile: req.method === 'GET' ? undefined : 'portalUsers',
  });
  if (!actor) return;

  if (req.method === 'GET') {
    const config = await loadPortalAdminUi().catch(() => ({}));
    return ok(res, { ok: true, config });
  }

  if (req.method === 'POST') {
    if (!canManageUsers(actor.role)) return bad(res, 'forbidden', 403);

    const body = readJson(req) || {};
    try {
      const config = await savePortalAdminUi(body);
      return ok(res, { ok: true, config });
    } catch (err) {
      console.error('[admin/ui-config] save failed', err);
      return bad(res, err?.message || 'server error', 500);
    }
  }

  return methodNotAllowed(res);
}

