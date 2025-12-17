// /api/chat/v1/users.js
export const config = { runtime: 'nodejs' };

import { bad, handlePreflight, methodNotAllowed, ok, setCors } from '../../_lib/http.js';
import { requirePortalAccess } from '../../admin/_guard.js';
import { portalUsersList } from '../../_lib/store.js';
import { resolvePortalDisplayName } from '../../_lib/userDirectory.js';
import { normalizeUserId } from './_lib/schema.js';

function clampLimit(raw) {
  const parsed = Number(raw || 50);
  if (!Number.isFinite(parsed) || parsed <= 0) return 50;
  return Math.min(Math.max(parsed, 1), 200);
}

function normalizePortalUser(user) {
  const email = String(user?.email || '').trim().toLowerCase();
  const uid = normalizeUserId(email || user?.uid || user?.id || '');
  if (!uid) return null;

  const displayName = resolvePortalDisplayName(user) || email || uid;
  const portalStatus = String(user?.portalStatus || '').trim().toLowerCase();
  const activeFlag = portalStatus ? portalStatus === 'active' : user?.active !== false && user?.revoked !== true;
  const role = String(user?.role || '').trim().toLowerCase() || 'user';

  return { uid, displayName, email, role, active: !!activeFlag };
}

function sortUsers(a, b) {
  const nameA = (a.displayName || '').toLowerCase();
  const nameB = (b.displayName || '').toLowerCase();
  if (nameA !== nameB) return nameA.localeCompare(nameB);
  return (a.email || '').localeCompare(b.email || '');
}

export default async function handler(req, res) {
  if (handlePreflight(req, res)) return;
  setCors(req, res);

  const actor = await requirePortalAccess(req, res, { write: false });
  if (!actor) return;

  if (req.method !== 'GET') return methodNotAllowed(res);

  try {
    const query = req.query?.query?.toString().trim() || '';
    const limit = clampLimit(req.query?.limit);

    const portalUsers = await portalUsersList();
    const normalized = portalUsers.map(normalizePortalUser).filter(Boolean);

    const filtered = query
      ? normalized.filter((u) => {
          const haystack = `${u.displayName}\u0000${u.email}`.toLowerCase();
          return haystack.includes(query.toLowerCase());
        })
      : normalized;

    const sorted = filtered.sort(sortUsers).slice(0, limit);

    if (sorted.length === 0) {
      console.warn('[chat/v1/users] no users found', {
        source: 'portalUsersList',
        total: normalized.length,
        query,
        limit,
      });
    }

    return ok(res, { users: sorted });
  } catch (err) {
    console.error('[chat/v1/users] error', err);
    return bad(res, 'server error', 500);
  }
}
