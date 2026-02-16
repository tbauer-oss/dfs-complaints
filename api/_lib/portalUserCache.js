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

  const redis = createKvRedisCompat();
  const safeKey = `dfs:portal:user_safe:${emailNorm}`;
  const safePayload = {
    email_norm: emailNorm,
    role: String(user?.role || 'user').toLowerCase(),
    is_active: user?.portalStatus !== 'inactive',
    portal_status: user?.portalStatus === 'inactive' ? 'inactive' : 'active',
    tour_seen: user?.tourSeen === true,
    updated_at: user?.updatedAt || null,
  };

  try {
    await redis.set(safeKey, safePayload, { ex: 900 });
    return true;
  } catch (err) {
    console.warn('[portal/user-cache] safe cache write failed', { key: safeKey, error: err?.message || String(err) });
    return false;
  }
}
