// api/admin/push/devices/[deviceId].js
export const config = { runtime: 'nodejs' };

import { handlePreflight, setCors, ok, bad, methodNotAllowed, readJson } from '../../../_lib/http.js';
import { usersList, userSave, repPushTokens, repPushTokensSave } from '../../../_lib/store.js';
import { getAllRepIds, loadRepById } from '../../../_lib/repsStore.js';
import { portalUserFromRequest, normalizeRole, PORTAL_ROLES } from '../../../_lib/portalAuth.js';
import {
  normalizePushTokenEntry,
  deviceIdForEntry,
  fingerprintForEntry,
  hashPushToken,
} from '../../../_lib/pushDevices.js';

function actorLabel(actor) {
  return (
    actor?.email ||
    actor?.displayName ||
    actor?.name ||
    actor?.username ||
    actor?.id ||
    'admin'
  );
}

async function updateCustomerDevice({ deviceId, updateFn }) {
  const users = await usersList();
  for (const user of users) {
    const tokens = Array.isArray(user?.pushTokens) ? user.pushTokens : [];
    const normalized = tokens
      .map((entry) => normalizePushTokenEntry(entry))
      .filter(Boolean);
    let changed = false;
    for (const entry of normalized) {
      if (deviceIdForEntry(entry) !== deviceId) continue;
      updateFn(entry);
      changed = true;
      break;
    }
    if (changed) {
      const nextTokens = normalized.filter((entry) => entry && entry.__remove__ !== true);
      if (nextTokens.length > 0) user.pushTokens = nextTokens;
      else delete user.pushTokens;
      await userSave(user);
      return true;
    }
  }
  return false;
}

async function updateRepDevice({ deviceId, updateFn }) {
  const repIds = await getAllRepIds();
  for (const repId of repIds) {
    const rep = await loadRepById(repId).catch(() => null);
    if (!rep) continue;
    const tokens = await repPushTokens(rep.id);
    const normalized = tokens
      .map((entry) => normalizePushTokenEntry(entry))
      .filter(Boolean);
    let changed = false;
    for (const entry of normalized) {
      if (deviceIdForEntry(entry) !== deviceId) continue;
      updateFn(entry);
      changed = true;
      break;
    }
    if (changed) {
      await repPushTokensSave(rep.id, normalized.filter((entry) => entry && entry.__remove__ !== true));
      return true;
    }
  }
  return false;
}

export default async function handler(req, res) {
  if (handlePreflight(req, res)) return;
  setCors(req, res);

  const actor = await portalUserFromRequest(req);
  if (!actor) return bad(res, 'unauthorized', 401);
  if (normalizeRole(actor.role) !== PORTAL_ROLES.superuser) return bad(res, 'forbidden', 403);

  const deviceId = (req.query?.deviceId || '').toString().trim();
  if (!deviceId) return bad(res, 'missing deviceId', 400);

  if (req.method === 'PATCH') {
    const payload = readJson(req) || {};
    const isDisabled = payload?.isDisabled;
    if (typeof isDisabled !== 'boolean') return bad(res, 'missing isDisabled', 400);
    const reason = payload?.disabledReason ? payload.disabledReason.toString().trim() : null;
    const now = Date.now();
    const by = actorLabel(actor);

    const updated = await updateCustomerDevice({
      deviceId,
      updateFn: (entry) => {
        const token = (entry?.token || '').toString().trim();
        const hash = fingerprintForEntry(entry) || hashPushToken(token);
        entry.tokenHash = entry.tokenHash || hash;
        entry.deviceId = entry.deviceId || deviceId;
        if (isDisabled) {
          entry.isDisabled = true;
          entry.disabledAt = now;
          entry.disabledBy = by;
          if (reason) entry.disabledReason = reason;
        } else {
          entry.isDisabled = false;
          delete entry.disabledAt;
          delete entry.disabledBy;
          delete entry.disabledReason;
        }
      },
    }) || await updateRepDevice({
      deviceId,
      updateFn: (entry) => {
        const token = (entry?.token || '').toString().trim();
        const hash = fingerprintForEntry(entry) || hashPushToken(token);
        entry.tokenHash = entry.tokenHash || hash;
        entry.deviceId = entry.deviceId || deviceId;
        if (isDisabled) {
          entry.isDisabled = true;
          entry.disabledAt = now;
          entry.disabledBy = by;
          if (reason) entry.disabledReason = reason;
        } else {
          entry.isDisabled = false;
          delete entry.disabledAt;
          delete entry.disabledBy;
          delete entry.disabledReason;
        }
      },
    });

    if (!updated) return bad(res, 'not found', 404);
    return ok(res, { ok: true, deviceId, isDisabled });
  }

  if (req.method === 'DELETE') {
    const removed = await updateCustomerDevice({
      deviceId,
      updateFn: (entry) => {
        entry.__remove__ = true;
      },
    }) || await updateRepDevice({
      deviceId,
      updateFn: (entry) => {
        entry.__remove__ = true;
      },
    });

    if (!removed) return bad(res, 'not found', 404);
    return ok(res, { ok: true, deviceId });
  }

  return methodNotAllowed(res);
}
