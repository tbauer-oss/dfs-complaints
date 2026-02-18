import { createHash } from 'node:crypto';

import { redis } from './redis.js';

const CACHE_TTL_SECONDS = 60 * 60 * 24;
const RAW_TTL_SECONDS = 60 * 60 * 24;
const MDR_VERSION = 'MDR-2017-745';
const ANNEX_EXTRACTION_VERSION = 'annex-i-v1';
const KEY_BASE = `dfs:gspr:source:${MDR_VERSION}:${ANNEX_EXTRACTION_VERSION}`;
const KEY_RAW = `${KEY_BASE}:raw`;
const KEY_PROCESSED = `${KEY_BASE}:processed`;

function safeJsonParse(raw) {
  if (!raw) return null;
  try {
    return typeof raw === 'string' ? JSON.parse(raw) : raw;
  } catch {
    return null;
  }
}

function extractAnnexI(text = '') {
  const normalized = String(text || '');
  const start = normalized.search(/annex\s+i\b/i);
  if (start < 0) return '';
  const tail = normalized.slice(start);
  const endCandidates = [
    tail.search(/annex\s+ii\b/i),
    tail.search(/annex\s+2\b/i),
  ].filter((value) => value > 0);
  const end = endCandidates.length ? Math.min(...endCandidates) : tail.length;
  return tail.slice(0, end).trim();
}

function buildSearchIndex(text = '') {
  const tokens = String(text || '')
    .toLowerCase()
    .replace(/[^a-z0-9äöüß\s]/g, ' ')
    .split(/\s+/)
    .filter((token) => token.length >= 4);
  return Array.from(new Set(tokens)).slice(0, 4000);
}

export function buildProcessedSource(text = '', sourceMeta = {}) {
  const annexIText = extractAnnexI(text);
  const searchIndex = buildSearchIndex(annexIText || text);
  const normalizedTextHash = createHash('sha256').update(text).digest('hex');
  return {
    mdrVersion: MDR_VERSION,
    annexExtractionVersion: ANNEX_EXTRACTION_VERSION,
    builtAt: new Date().toISOString(),
    sourceMeta,
    normalizedTextHash,
    normalizedText: text,
    annexIText,
    searchIndex,
  };
}

export async function gsprSourceCacheGet() {
  if (!redis || typeof redis.get !== 'function') return null;
  const processed = safeJsonParse(await redis.get(KEY_PROCESSED));
  if (!processed) return null;
  return processed;
}

export async function gsprSourceCacheGetRaw() {
  if (!redis || typeof redis.get !== 'function') return null;
  return safeJsonParse(await redis.get(KEY_RAW));
}

export async function gsprSourceCacheSet({ rawBody = '', normalizedText = '', sourceMeta = {} } = {}) {
  if (!redis || typeof redis.set !== 'function') return;
  const processed = buildProcessedSource(normalizedText, sourceMeta);
  const rawPayload = {
    mdrVersion: MDR_VERSION,
    annexExtractionVersion: ANNEX_EXTRACTION_VERSION,
    sourceMeta,
    fetchedAt: new Date().toISOString(),
    rawSnippet: String(rawBody || '').slice(0, 5000),
  };
  await redis.set(KEY_RAW, JSON.stringify(rawPayload), { ex: RAW_TTL_SECONDS });
  await redis.set(KEY_PROCESSED, JSON.stringify(processed), { ex: CACHE_TTL_SECONDS });
}

export function gsprSourceCacheVersionMarker() {
  return `${MDR_VERSION}:${ANNEX_EXTRACTION_VERSION}`;
}
