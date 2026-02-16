// /api/gspr/sync.js – manual source sync trigger for GSPR metadata
export const config = { runtime: 'nodejs' };

import { createHash } from 'node:crypto';

import { handlePreflight, setCors, ok, bad } from '../_lib/http.js';
import { requirePortalAccess } from '../admin/_guard.js';
import {
  GSPR_SOURCE_NAME,
  GSPR_SOURCE_PERMALINK,
} from '../_lib/gsprRequirements.js';
import { gsprSourceMetaGet, gsprSourceMetaSave } from '../_lib/store.js';

const GSPR_TILE = 'gspr';
const GSPR_SYNC_TTL_MS = 7 * 24 * 60 * 60 * 1000;
const EUR_LEX_FALLBACK_URL = 'https://eur-lex.europa.eu/legal-content/DE/TXT/HTML/?uri=CELEX:32017R0745';
const EUR_LEX_FETCH_TIMEOUT_MS = 12_000;
const EUR_LEX_FETCH_ATTEMPTS = 2;

function normalizeTextForHash(html = '') {
  return html
    .replace(/<script[^>]*>[\s\S]*?<\/script>/gi, ' ')
    .replace(/<style[^>]*>[\s\S]*?<\/style>/gi, ' ')
    .replace(/<[^>]+>/g, ' ')
    .replace(/&nbsp;/gi, ' ')
    .replace(/&amp;/gi, '&')
    .replace(/\s+/g, ' ')
    .trim();
}

function extractTextLines(normalizedText = '') {
  if (!normalizedText) return [];
  return normalizedText
    .split(/(?<=[\.;:])\s+/)
    .map((part) => part.trim())
    .filter((part) => part.length > 35)
    .slice(0, 140);
}

const BOILERPLATE_LINE_PATTERNS = [
  /javascript is disabled/i,
  /verify that you're not a robot/i,
  /enable javascript and then reload the page/i,
  /sign in register my recent searches/i,
  /official eu languages/i,
  /experimental features/i,
  /eur-lex access to european union law/i,
];

function sanitizeExtractedLines(lines = []) {
  return lines.filter((line) => !BOILERPLATE_LINE_PATTERNS.some((pattern) => pattern.test(line)));
}

function ensureContentLooksLikeEurLexDocument(lines = []) {
  if (!lines.length) return false;

  const combined = lines.join(' ').toLowerCase();
  const legalAnchors = [
    /verordnung \(eu\) 2017\/745/i,
    /grundlegende sicherheits- und leistungsanforderungen/i,
    /medizinprodukte/i,
  ];

  return legalAnchors.some((pattern) => pattern.test(combined));
}

function detectChangedLines(previous = [], current = []) {
  if (!previous.length || !current.length) return [];
  const previousSet = new Set(previous);
  const currentSet = new Set(current);
  const added = current.filter((line) => !previousSet.has(line));
  const removed = previous.filter((line) => !currentSet.has(line));

  const max = Math.min(5, Math.max(added.length, removed.length));
  const details = [];
  for (let index = 0; index < max; index += 1) {
    details.push({
      location: `EUR-Lex konsolidierte Fassung (Ausschnitt ${index + 1})`,
      before: removed[index] || '—',
      after: added[index] || '—',
    });
  }
  return details;
}

function hasCachedSource(source = {}) {
  if (!source || typeof source !== 'object') return false;
  if (source.lastSyncAt) return true;
  if ((source.contentHash || '').toString().trim()) return true;
  if (Array.isArray(source.lastSeenLines) && source.lastSeenLines.length > 0) return true;
  return false;
}

function isWithinSyncTtl(source = {}) {
  if (!source?.lastSyncAt) return false;
  const lastSyncTs = Date.parse(source.lastSyncAt);
  if (!Number.isFinite(lastSyncTs)) return false;
  return (Date.now() - lastSyncTs) < GSPR_SYNC_TTL_MS;
}

async function fetchEurLexPage(url) {
  let lastError = null;

  for (let attempt = 1; attempt <= EUR_LEX_FETCH_ATTEMPTS; attempt += 1) {
    const controller = new AbortController();
    const timeout = setTimeout(() => controller.abort('timeout'), EUR_LEX_FETCH_TIMEOUT_MS);

    try {
      const response = await fetch(url, {
        redirect: 'follow',
        signal: controller.signal,
        headers: {
          'user-agent': 'Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/125.0.0.0 Safari/537.36',
          accept: 'text/html,application/xhtml+xml,application/xml;q=0.9,image/avif,image/webp,*/*;q=0.8',
          'accept-language': 'de-DE,de;q=0.9,en-US;q=0.8,en;q=0.7',
          'cache-control': 'no-cache',
        },
      });

      if (!response.ok) {
        lastError = new Error(`HTTP ${response.status} ${response.statusText}`);
        continue;
      }

      const html = await response.text();
      if (!html || html.trim().length === 0) {
        lastError = new Error('empty response body');
        continue;
      }

      return { html, url: response.url || url };
    } catch (err) {
      lastError = err;
    } finally {
      clearTimeout(timeout);
    }
  }

  const reason = lastError?.message || 'unknown fetch failure';
  throw new Error(`EUR-Lex request failed (${url}): ${reason}`);
}

async function saveStaleState(before, actorEmail, reasonText) {
  return await gsprSourceMetaSave({
    name: GSPR_SOURCE_NAME,
    permalink: before?.permalink || GSPR_SOURCE_PERMALINK,
    lastAttemptAt: new Date().toISOString(),
    lastError: reasonText,
    updatedBy: actorEmail || '',
  });
}

export default async function handler(req, res) {
  if (handlePreflight(req, res)) return;
  setCors(req, res);

  const actor = await requirePortalAccess(req, res, { tile: GSPR_TILE, write: true, allowPrrc: true });
  if (!actor) return;

  try {
    if (req.method === 'GET') {
      const source = await gsprSourceMetaGet();
      return ok(res, {
        ok: true,
        source: {
          name: source.name || GSPR_SOURCE_NAME,
          permalink: source.permalink || GSPR_SOURCE_PERMALINK,
          lastSyncAt: source.lastSyncAt || null,
          lastAttemptAt: source.lastAttemptAt || null,
          lastError: source.lastError || '',
          updatedBy: source.updatedBy || '',
          contentHash: source.contentHash || '',
          previousContentHash: source.previousContentHash || '',
          lastChangeAt: source.lastChangeAt || null,
          lastChangeSummary: source.lastChangeSummary || '',
          lastChangeDetails: source.lastChangeDetails || [],
        },
      });
    }

    if (req.method !== 'POST') return bad(res, 'method not allowed', 405);

    const before = await gsprSourceMetaGet();
    const cacheAvailable = hasCachedSource(before);
    if (isWithinSyncTtl(before)) {
      return ok(res, {
        ok: true,
        skipped: true,
        reason: 'SYNC_TTL_ACTIVE',
        usedCache: cacheAvailable,
        source: before,
      });
    }

    const startedAt = new Date().toISOString();
    await gsprSourceMetaSave({
      name: GSPR_SOURCE_NAME,
      permalink: before?.permalink || GSPR_SOURCE_PERMALINK,
      lastAttemptAt: startedAt,
      lastError: '',
      updatedBy: actor?.email || '',
    });

    const candidates = [GSPR_SOURCE_PERMALINK, EUR_LEX_FALLBACK_URL];
    let validatedFrom = null;
    let fetchedHtml = '';
    let lastSyncError = null;
    for (const candidate of candidates) {
      try {
        const result = await fetchEurLexPage(candidate);
        validatedFrom = result.url;
        fetchedHtml = result.html;
        break;
      } catch (err) {
        lastSyncError = err;
      }
    }

    if (!validatedFrom) {
      const reasonText = lastSyncError?.message || 'EUR-Lex source validation failed';
      if (cacheAvailable) {
        const source = await saveStaleState(before, actor?.email || '', reasonText);
        return ok(res, { ok: false, stale: true, reason: 'EUR_LEX_FETCH_FAILED', usedCache: true, source });
      }
      throw new Error(reasonText);
    }

    const normalizedText = normalizeTextForHash(fetchedHtml);
    const currentLines = sanitizeExtractedLines(extractTextLines(normalizedText));
    if (!ensureContentLooksLikeEurLexDocument(currentLines)) {
      const reasonText = 'EUR-Lex response did not contain stable regulation text (likely anti-bot or navigation markup)';
      if (cacheAvailable) {
        const source = await saveStaleState(before, actor?.email || '', reasonText);
        return ok(res, { ok: false, stale: true, reason: 'EUR_LEX_UNSTABLE', usedCache: true, source });
      }
      throw new Error(reasonText);
    }

    const contentFingerprint = currentLines.join('\n');
    const contentHash = createHash('sha256').update(contentFingerprint).digest('hex');
    const previousHash = (before?.contentHash || '').toString();
    const changed = previousHash.length > 0 && previousHash !== contentHash;

    const previousLines = Array.isArray(before?.lastSeenLines)
      ? before.lastSeenLines.map((entry) => (entry ?? '').toString())
      : [];
    const changeDetails = changed ? detectChangedLines(previousLines, currentLines) : [];

    const finishedAt = new Date().toISOString();
    const source = await gsprSourceMetaSave({
      name: GSPR_SOURCE_NAME,
      permalink: validatedFrom,
      lastSyncAt: finishedAt,
      lastAttemptAt: finishedAt,
      lastError: '',
      updatedBy: actor?.email || '',
      previousContentHash: previousHash,
      contentHash,
      lastSeenLines: currentLines,
      lastChangeAt: changed ? finishedAt : before?.lastChangeAt || null,
      lastChangeSummary: changed
        ? `Inhaltliche Änderungen in der EUR-Lex-Quelle erkannt (${changeDetails.length || 1} Textstelle(n)).`
        : '',
      lastChangeDetails: changed ? changeDetails : [],
    });

    return ok(res, { ok: true, source, changesDetected: changed, changeDetails });
  } catch (err) {
    const before = await gsprSourceMetaGet();
    const cacheAvailable = hasCachedSource(before);
    if (cacheAvailable) {
      const source = await saveStaleState(before, actor?.email || '', err?.message || 'sync failed');
      return ok(res, {
        ok: false,
        stale: true,
        reason: 'EUR_LEX_SYNC_FAILED',
        usedCache: true,
        source,
      });
    }

    const failedAt = new Date().toISOString();
    const source = await gsprSourceMetaSave({
      name: GSPR_SOURCE_NAME,
      permalink: GSPR_SOURCE_PERMALINK,
      lastAttemptAt: failedAt,
      lastError: err?.message || 'sync failed',
      updatedBy: actor?.email || '',
    });
    return bad(res, source.lastError || 'sync failed', 502);
  }
}
