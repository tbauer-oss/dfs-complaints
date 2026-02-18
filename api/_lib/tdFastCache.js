import { redis } from './redis.js';

const TTL_SECONDS = 300;

function safeJsonParse(raw) {
  if (!raw) return null;
  if (typeof raw === 'object') return raw;
  try {
    return JSON.parse(String(raw));
  } catch {
    return null;
  }
}

export function overviewCacheKey(tdId) {
  return `dfs:td:overview:${tdId}`;
}

export function sectionsMetaCacheKey(tdId, pageKey) {
  return `dfs:td:sections-meta:${tdId}:${pageKey}`;
}

export async function getCachedJson(key, timing = null) {
  try {
    const raw = timing ? await timing.kv(() => redis.get(key)) : await redis.get(key);
    return safeJsonParse(raw);
  } catch {
    return null;
  }
}

export async function setCachedJson(key, value, timing = null, ttlSeconds = TTL_SECONDS) {
  try {
    const payload = JSON.stringify(value || null);
    if (timing) {
      await timing.kv(() => redis.set(key, payload, { ex: ttlSeconds }));
    } else {
      await redis.set(key, payload, { ex: ttlSeconds });
    }
  } catch {
    // cache is optional
  }
}

export function refreshInBackground(refreshFn) {
  Promise.resolve()
    .then(refreshFn)
    .catch((err) => {
      console.warn('[tdCacheRefresh] background refresh failed', { message: err?.message || String(err) });
    });
}
