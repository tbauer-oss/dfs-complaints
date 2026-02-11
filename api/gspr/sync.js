// /api/gspr/sync.js – manual source sync trigger for GSPR metadata
export const config = { runtime: 'nodejs' };

import { handlePreflight, setCors, ok, bad } from '../_lib/http.js';
import { requirePortalAccess } from '../admin/_guard.js';
import {
  GSPR_SOURCE_NAME,
  GSPR_SOURCE_PERMALINK,
} from '../_lib/gsprRequirements.js';
import { gsprSourceMetaGet, gsprSourceMetaSave } from '../_lib/store.js';

const GSPR_TILE = 'gspr';
const EUR_LEX_FALLBACK_URL = 'https://eur-lex.europa.eu/legal-content/DE/TXT/HTML/?uri=CELEX:32017R0745';
const EUR_LEX_FETCH_TIMEOUT_MS = 12_000;
const EUR_LEX_FETCH_ATTEMPTS = 2;

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
          'user-agent': 'DFS-Complaints GSPR sync/1.0 (+https://dfs-complaints-backend.vercel.app)',
          accept: 'text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8',
          'accept-language': 'de,en;q=0.8',
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

      return { htmlLength: html.length };
    } catch (err) {
      lastError = err;
    } finally {
      clearTimeout(timeout);
    }
  }

  const reason = lastError?.message || 'unknown fetch failure';
  throw new Error(`EUR-Lex request failed (${url}): ${reason}`);
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
        },
      });
    }

    if (req.method !== 'POST') return bad(res, 'method not allowed', 405);

    const startedAt = new Date().toISOString();
    await gsprSourceMetaSave({
      name: GSPR_SOURCE_NAME,
      permalink: GSPR_SOURCE_PERMALINK,
      lastAttemptAt: startedAt,
      lastError: '',
      updatedBy: actor?.email || '',
    });

    const candidates = [GSPR_SOURCE_PERMALINK, EUR_LEX_FALLBACK_URL];
    let validatedFrom = null;
    let lastSyncError = null;
    for (const candidate of candidates) {
      try {
        await fetchEurLexPage(candidate);
        validatedFrom = candidate;
        break;
      } catch (err) {
        lastSyncError = err;
      }
    }

    if (!validatedFrom) throw lastSyncError || new Error('EUR-Lex source validation failed');

    const finishedAt = new Date().toISOString();
    const source = await gsprSourceMetaSave({
      name: GSPR_SOURCE_NAME,
      permalink: validatedFrom,
      lastSyncAt: finishedAt,
      lastAttemptAt: finishedAt,
      lastError: '',
      updatedBy: actor?.email || '',
    });

    return ok(res, { ok: true, source });
  } catch (err) {
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
