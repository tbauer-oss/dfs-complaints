import { createKvRedisCompat } from './kvStore.js';
import { normalizeEmail } from './identity.js';

const DIRECTORY_CACHE_KEYS = [
  'dfs:users',
  'dfs:userDirectory',
  'dfs:roles',
];

export function portalUserCacheKeys(email) {
  const emailNorm = normalizeEmail(email);
  if (!emailNorm) return [];
  return [
    `dfs:portal:user:${emailNorm}`,
    `dfs:portal:user_safe:${emailNorm}`,
    ...DIRECTORY_CACHE_KEYS,
  ];
}

export async function invalidatePortalUserCaches(email, { logPrefix = 'portal/user-cache' } = {}) {
  const keys = portalUserCacheKeys(email);
  if (!keys.length) return { emailNorm: null, cacheInvalidated: false, keys: [] };

  const redis = createKvRedisCompat();
  let cacheInvalidated = true;

  for (const key of keys) {
    try {
      await redis.del(key);
    } catch (err) {
      if (String(err?.code || '') === 'SECURITY_GUARD_AUTH_CACHE_FORBIDDEN') continue;
      cacheInvalidated = false;
      console.warn(`[${logPrefix}] cache delete failed`, { key, error: err?.message || String(err) });
    }
  }

  return {
    emailNorm: normalizeEmail(email),
    cacheInvalidated,
    keys,
  };
}


export async function writePortalUserSafeCache(email, user) {
  const emailNorm = normalizeEmail(email);
  if (!emailNorm) return false;

  const safeKey = `dfs:portal:user_safe:${emailNorm}`;
  const safePayload = {
    id: user?.id || null,
    email_norm: emailNorm,
    role: String(user?.role || 'user').toLowerCase(),
    is_active: user?.portalStatus !== 'inactive',
    portal_status: user?.portalStatus === 'inactive' ? 'inactive' : 'active',
    is_prrc: user?.isPRRC === true,
    is_sales: user?.isSales === true,
    assigned_departments: Array.isArray(user?.assignedDepartments) ? user.assignedDepartments : [],
    department: user?.department || '',
    display_name: user?.displayName || '',
    tile_permissions: user?.tilePermissions && typeof user.tilePermissions === 'object' ? user.tilePermissions : {},
    tour_seen: user?.tourSeen === true,
    tour_version: user?.tourVersion || null,
    created_at: user?.createdAt || null,
    updated_at: user?.updatedAt || null,
  };

  try {
    const redis = createKvRedisCompat();
    await redis.set(safeKey, safePayload, { ex: 900 });
    return true;
  } catch (err) {
    console.warn('[portal/user-cache] safe cache write failed', { key: safeKey, error: err?.message || String(err) });
    return false;
  }
}
