// api/admin/push/users.js
export const config = { runtime: 'nodejs' };

import { handlePreflight, setCors, ok, bad, methodNotAllowed } from '../../../_lib/http.js';
import { usersList, repPushTokens } from '../../../_lib/store.js';
import { getAllRepIds, loadRepById } from '../../../_lib/repsStore.js';
import { portalUserFromRequest, normalizeRole, PORTAL_ROLES } from '../../../_lib/portalAuth.js';
import { normalizePushTokenEntry } from '../../../_lib/pushDevices.js';

function pickFirst(...values) {
  for (const value of values) {
    const text = (value ?? '').toString().trim();
    if (text) return text;
  }
  return '';
}

function countTokens(list) {
  const set = new Set();
  for (const entry of Array.isArray(list) ? list : []) {
    const normalized = normalizePushTokenEntry(entry);
    if (!normalized?.token) continue;
    set.add(normalized.token);
  }
  return set.size;
}

export default async function handler(req, res) {
  if (handlePreflight(req, res)) return;
  setCors(req, res);

  const actor = await portalUserFromRequest(req);
  if (!actor) return bad(res, 'unauthorized', 401);
  if (normalizeRole(actor.role) !== PORTAL_ROLES.superuser) return bad(res, 'forbidden', 403);

  if (req.method !== 'GET') {
    return methodNotAllowed(res);
  }

  try {
    const users = await usersList();
    const list = [];

    for (const user of users) {
      const email = (user?.email || '').toString().trim().toLowerCase();
      if (!email) continue;
      const name = pickFirst(
        user?.displayName,
        user?.name,
        user?.fullName,
        user?.contactName,
        user?.contactPerson,
        user?.contact,
        user?.company,
        email,
      );
      const customerRef = pickFirst(user?.customerRef, user?.customerNumber, user?.customer_no);
      const devicesCount = countTokens(user?.pushTokens);
      list.push({
        userId: email,
        name,
        email,
        role: 'customer',
        customerRef: customerRef || null,
        devicesCount,
      });
    }

    const repIds = await getAllRepIds();
    for (const repId of repIds) {
      const rep = await loadRepById(repId).catch(() => null);
      if (!rep) continue;
      const email = (rep?.email || '').toString().trim().toLowerCase();
      const name = pickFirst(
        [rep?.firstName, rep?.lastName].filter(Boolean).join(' ').trim(),
        rep?.displayName,
        rep?.name,
        rep?.fullName,
        email,
        rep?.id,
      );
      const devicesCount = countTokens(await repPushTokens(repId));
      list.push({
        userId: repId,
        name,
        email,
        role: 'rep',
        customerRef: null,
        devicesCount,
      });
    }

    list.sort((a, b) => (a.name || '').localeCompare(b.name || '', 'de', { sensitivity: 'base' }));

    return ok(res, { users: list });
  } catch (err) {
    console.error('[admin/push/users] error', err);
    return bad(res, 'internal error', 500);
  }
}
