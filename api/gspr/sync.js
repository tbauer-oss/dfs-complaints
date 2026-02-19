// /api/gspr/sync.js – manual source sync trigger for GSPR metadata
export const config = { runtime: 'nodejs' };

import { handlePreflight, setCors, ok, bad } from '../_lib/http.js';
import { requirePortalAccess } from '../admin/_guard.js';
import {
  GSPR_SOURCE_NAME,
  GSPR_SOURCE_PERMALINK,
} from '../_lib/gsprRequirements.js';
import { gsprSourceMetaGet, gsprSourceMetaSave } from '../_lib/store.js';
import { redis } from '../_lib/redis.js';
import { fetchEurLexMdrText } from '../_lib/eurlexMdr.js';
import {
  gsprSourceCacheGet,
  gsprSourceCacheGetRaw,
  gsprSourceCacheSet,
  gsprSourceCacheVersionMarker,
} from '../_lib/gsprSourceCache.js';

const GSPR_TILE = 'gspr';
const SYNC_MIN_INTERVAL_MS = 12 * 60 * 60 * 1000;
const ANTI_BOT_COOLDOWN_MS = 6 * 60 * 60 * 1000;
const RAW_CACHE_TTL_SECONDS = 15 * 60;
const RAW_CACHE_KEY = 'dfs:gspr:eurlex:raw:last';
const TD_META_KEY = (tdKey) => `dfs:gspr:source-meta:${tdKey}`;

function isTruthy(value) {
  return ['1', 'true', 'yes', 'on'].includes((value ?? '').toString().trim().toLowerCase());
}

function readForceFlag(req) {
  return isTruthy(req.query?.force) || isTruthy(req.body?.force);
}

function mapSourceForResponse(source = {}) {
  const lastGoodSyncAt = source.lastGoodSyncAt || source.lastSyncAt || null;
  const lastSyncError = source.lastSyncError || source.lastError || '';
  return {
    name: source.name || GSPR_SOURCE_NAME,
    permalink: source.permalink || GSPR_SOURCE_PERMALINK,
    sourceUrl: source.sourceUrl || source.permalink || GSPR_SOURCE_PERMALINK,
    parserVersion: source.parserVersion || '',
    contentHash: source.contentHash || '',
    previousContentHash: source.previousContentHash || '',
    lastSyncAt: source.lastSyncAt || lastGoodSyncAt,
    lastGoodSyncAt,
    lastAttemptAt: source.lastAttemptAt || source.lastSyncAttemptAt || null,
    lastSyncAttemptAt: source.lastSyncAttemptAt || source.lastAttemptAt || null,
    lastError: source.lastError || lastSyncError,
    lastSyncError,
    lastFailureReason: source.lastFailureReason || '',
    cooldownUntil: source.cooldownUntil || null,
    updatedBy: source.updatedBy || '',
    lastChangeAt: source.lastChangeAt || null,
    lastChangeSummary: source.lastChangeSummary || '',
    lastChangeDetails: source.lastChangeDetails || [],
  };
}

function withinWindow(isoDate, windowMs) {
  const ts = Date.parse((isoDate || '').toString());
  if (!Number.isFinite(ts)) return false;
  return (Date.now() - ts) < windowMs;
}

function isAntiBotReason(reason = '') {
  const normalized = (reason || '').toString().toLowerCase();
  return normalized.includes('anti_bot') || normalized.includes('access denied') || normalized.includes('forbidden');
}

function shouldApplyCooldown(reason = '') {
  return isAntiBotReason(reason) || reason.startsWith('HTTP_403');
}

async function cacheRawResponse(result) {
  if (!result?.rawBody) return;
  if (!redis || typeof redis.set !== 'function') return;
  const payload = JSON.stringify({
    at: new Date().toISOString(),
    reason: result.reason || '',
    sourceMeta: result.sourceMeta || {},
    snippet: result.rawBody.slice(0, 500),
  });

  try {
    await redis.set(RAW_CACHE_KEY, payload, { ex: RAW_CACHE_TTL_SECONDS });
  } catch (err) {
    console.warn('[gspr/sync] raw response cache failed', err?.message || err);
  }
}


function readTdKey(req) {
  return String(req.query?.tdKey || req.body?.tdKey || 'MDR-TD1').trim().toUpperCase();
}

async function readSourceMeta(tdKey) {
  const global = await gsprSourceMetaGet();
  if (!tdKey || !redis || typeof redis.get !== 'function') return global;
  try {
    const raw = await redis.get(TD_META_KEY(tdKey));
    if (!raw) return global;
    const parsed = typeof raw === 'string' ? JSON.parse(raw) : raw;
    return { ...global, ...parsed };
  } catch {
    return global;
  }
}

async function saveSourceMeta(tdKey, patch = {}) {
  const saved = await gsprSourceMetaSave(patch);
  if (tdKey && redis && typeof redis.set === 'function') {
    try {
      await redis.set(TD_META_KEY(tdKey), JSON.stringify(saved), { ex: 60 * 60 * 24 * 14 });
    } catch (err) {
      console.warn('[gspr/sync] td scoped source meta cache failed', err?.message || err);
    }
  }
  return saved;
}

export default async function handler(req, res) {
  if (handlePreflight(req, res)) return;
  setCors(req, res);

  const actor = await requirePortalAccess(req, res, { tile: GSPR_TILE, write: true, allowPrrc: true });
  if (!actor) return;

  try {
    if (req.method === 'GET') {
      const tdKey = readTdKey(req);
      const source = await readSourceMeta(tdKey);
      return ok(res, { ok: true, tdKey, source: mapSourceForResponse(source) });
    }

    if (req.method !== 'POST') return bad(res, 'method not allowed', 405);

    const force = readForceFlag(req);
    const tdKey = readTdKey(req);
    const before = await readSourceMeta(tdKey);
    const cachedProcessed = await gsprSourceCacheGet();
    const cachedRaw = await gsprSourceCacheGetRaw();
    const cooldownUntilTs = Date.parse(before.cooldownUntil || '');

    if (!force && Number.isFinite(cooldownUntilTs) && cooldownUntilTs > Date.now()) {
      const msg = `GSPR sync is in cooldown until ${new Date(cooldownUntilTs).toISOString()} (anti-bot suspected).`;
      return bad(res, msg, 429, {
        code: 'SYNC_COOLDOWN_ACTIVE',
        retryAfterSeconds: Math.max(1, Math.ceil((cooldownUntilTs - Date.now()) / 1000)),
        tdKey,
        source: mapSourceForResponse(before),
      });
    }

    if (!force && withinWindow(before.lastSyncAttemptAt || before.lastAttemptAt, SYNC_MIN_INTERVAL_MS)) {
      return ok(res, {
        ok: true,
        skipped: true,
        reason: 'SYNC_RATE_LIMIT_12H',
        tdKey,
        source: mapSourceForResponse(before),
      });
    }

    if (!force && cachedProcessed && before?.lastSyncAt) {
      return ok(res, {
        ok: true,
        skipped: true,
        reason: 'CACHE_HIT_STALE_WHILE_REVALIDATE',
        tdKey,
        cache: {
          hit: true,
          version: gsprSourceCacheVersionMarker(),
          builtAt: cachedProcessed.builtAt || null,
        },
        source: mapSourceForResponse(before),
      });
    }

    const startedAt = new Date().toISOString();
    await saveSourceMeta(tdKey, {
      name: GSPR_SOURCE_NAME,
      lastAttemptAt: startedAt,
      lastSyncAttemptAt: startedAt,
      lastError: '',
      lastSyncError: '',
      updatedBy: actor?.email || '',
    });

    const result = await fetchEurLexMdrText();
    await cacheRawResponse(result);

    if (!result.ok) {
      const failureReason = result.reason || 'SYNC_FAILED';
      const debugSnippet = (result.rawBody || '').slice(0, 500);
      console.error('[gspr/sync] EUR-Lex fetch failed', {
        reason: failureReason,
        sourceUrl: result.sourceMeta?.sourceUrl || '',
        debugSnippet,
      });

      const hasUsableStale = Boolean(before?.normalizedText || cachedProcessed);
      const patch = {
        name: GSPR_SOURCE_NAME,
        permalink: before?.permalink || GSPR_SOURCE_PERMALINK,
        lastAttemptAt: startedAt,
        lastSyncAttemptAt: startedAt,
        lastError: hasUsableStale ? '' : `MDR sync failed: ${failureReason}`,
        lastSyncError: hasUsableStale ? '' : `MDR sync failed: ${failureReason}`,
        lastFailureReason: failureReason,
        updatedBy: actor?.email || '',
      };

      if (shouldApplyCooldown(failureReason)) {
        patch.cooldownUntil = new Date(Date.now() + ANTI_BOT_COOLDOWN_MS).toISOString();
      }

      const source = await saveSourceMeta(tdKey, patch);
      if (hasUsableStale) {
        return ok(res, {
          ok: false,
          code: 'SOURCE_UNSTABLE',
          stale: true,
          lastGoodAt: before?.lastGoodSyncAt || before?.lastSyncAt || null,
          lastGoodHash: before?.contentHash || '',
          tdKey,
          cache: {
            hit: Boolean(cachedProcessed),
            version: gsprSourceCacheVersionMarker(),
            builtAt: cachedProcessed?.builtAt || null,
            rawFetchedAt: cachedRaw?.fetchedAt || null,
          },
          source: mapSourceForResponse(source),
        });
      }
      return ok(res, {
        ok: false,
        code: shouldApplyCooldown(failureReason) ? 'EUR_LEX_ANTI_BOT_SUSPECTED' : 'EUR_LEX_SYNC_FAILED',
        stale: false,
        degraded: true,
        message: `MDR sync currently unavailable (${failureReason}). Existing GSPR catalog data remains available.`,
        detectedFailureReason: failureReason,
        debugSnippet,
        tdKey,
        source: mapSourceForResponse(source),
      });
    }

    const finishedAt = new Date().toISOString();
    const previousHash = (before?.contentHash || '').toString();
    const changed = previousHash.length > 0 && previousHash !== result.contentHash;

    await gsprSourceCacheSet({
      rawBody: result.rawBody || '',
      normalizedText: result.text || '',
      sourceMeta: result.sourceMeta || {},
    });

    const source = await saveSourceMeta(tdKey, {
      name: GSPR_SOURCE_NAME,
      permalink: result.sourceMeta?.sourceUrl || GSPR_SOURCE_PERMALINK,
      sourceUrl: result.sourceMeta?.sourceUrl || GSPR_SOURCE_PERMALINK,
      parserVersion: result.sourceMeta?.parserVersion || '',
      normalizedText: result.text,
      previousContentHash: previousHash,
      contentHash: result.contentHash,
      lastSyncAt: finishedAt,
      lastGoodSyncAt: finishedAt,
      lastAttemptAt: finishedAt,
      lastSyncAttemptAt: finishedAt,
      lastError: '',
      lastSyncError: '',
      lastFailureReason: '',
      cooldownUntil: null,
      updatedBy: actor?.email || '',
      lastChangeAt: changed ? finishedAt : before?.lastChangeAt || null,
      lastChangeSummary: changed ? 'MDR source content hash changed.' : '',
      lastChangeDetails: changed
        ? [{
            location: result.sourceMeta?.sourceUrl || GSPR_SOURCE_PERMALINK,
            before: previousHash || '—',
            after: result.contentHash,
          }]
        : [],
    });

    return ok(res, { ok: true, tdKey, source: mapSourceForResponse(source), changesDetected: changed, cache: { hit: false, version: gsprSourceCacheVersionMarker() } });
  } catch (err) {
    console.error('[gspr/sync] unhandled error', err);
    const failedAt = new Date().toISOString();
    const tdKey = readTdKey(req);
    const source = await saveSourceMeta(tdKey, {
      name: GSPR_SOURCE_NAME,
      lastAttemptAt: failedAt,
      lastSyncAttemptAt: failedAt,
      lastError: err?.message || 'sync failed',
      lastSyncError: err?.message || 'sync failed',
      updatedBy: actor?.email || '',
    });
    return ok(res, {
      ok: false,
      code: 'SYNC_UNHANDLED_ERROR',
      degraded: true,
      message: source.lastSyncError || 'sync failed',
      tdKey,
      source: mapSourceForResponse(source),
    });
  }
}
