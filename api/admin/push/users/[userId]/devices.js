// api/admin/push/users/[userId]/devices.js
export const config = { runtime: 'nodejs' };

import { handlePreflight, setCors, ok, bad, methodNotAllowed } from '../../../../_lib/http.js';
import { userByEmail, repPushTokens } from '../../../../_lib/store.js';
import { loadRepById } from '../../../../_lib/repsStore.js';
import { portalUserFromRequest, normalizeRole, PORTAL_ROLES } from '../../../../_lib/portalAuth.js';
import { normalizePushTokenEntry, mapDeviceEntry } from '../../../../_lib/pushDevices.js';

export default async function handler(req, res) {
  if (handlePreflight(req, res)) return;
  setCors(req, res);

  const actor = await portalUserFromRequest(req);
  if (!actor) return bad(res, 'unauthorized', 401);
  if (normalizeRole(actor.role) !== PORTAL_ROLES.superuser) return bad(res, 'forbidden', 403);

  if (req.method !== 'GET') {
    return methodNotAllowed(res);
  }

  const rawId = (req.query?.userId || '').toString().trim();
  if (!rawId) return bad(res, 'missing userId', 400);

  try {
    const isEmail = rawId.includes('@');
    let devices = [];

    const user = await userByEmail(rawId);
    if (user && (isEmail || user.email?.toString().toLowerCase() === rawId.toLowerCase())) {
      const tokens = Array.isArray(user?.pushTokens) ? user.pushTokens : [];
      devices = tokens
        .map((entry) => normalizePushTokenEntry(entry))
        .filter(Boolean)
        .map((entry) => mapDeviceEntry(entry));
      return ok(res, { devices });
    }

    const rep = await loadRepById(rawId).catch(() => null);
    if (!rep) return bad(res, 'not found', 404);
    const tokens = await repPushTokens(rep.id);
    devices = tokens
      .map((entry) => normalizePushTokenEntry(entry))
      .filter(Boolean)
      .map((entry) => mapDeviceEntry(entry));

    return ok(res, { devices });
  } catch (err) {
    console.error('[admin/push/users/devices] error', err);
    return bad(res, 'internal error', 500);
  }
}
