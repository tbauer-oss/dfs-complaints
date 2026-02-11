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
const START_MARKERS = [
  'ANHANG I\nGRUNDLEGENDE SICHERHEITS- UND LEISTUNGSANFORDERUNGEN',
  'ANHANG I: GRUNDLEGENDE SICHERHEITS- UND LEISTUNGSANFORDERUNGEN',
  '## ANHANG I: GRUNDLEGENDE SICHERHEITS- UND LEISTUNGSANFORDERUNGEN',
];
const END_MARKERS = [
  'ANHANG II\nTECHNISCHE DOKUMENTATION',
  'ANHANG II: TECHNISCHE DOKUMENTATION',
  '## ANHANG II: TECHNISCHE DOKUMENTATION',
];

const START_REGEX = /ANHANG\s*I\s*[:\n]?\s*GRUNDLEGENDE\s+SICHERHEITS-\s*UND\s+LEISTUNGSANFORDERUNGEN/i;
const END_REGEX = /ANHANG\s*II\s*[:\n]?\s*TECHNISCHE\s+DOKUMENTATION/i;

function normalizeWhitespace(input) {
  return String(input || '')
    .replace(/\r\n?/g, '\n')
    .replace(/[ \t]+$/gm, '')
    .replace(/\u00a0/g, ' ')
    .replace(/\n{3,}/g, '\n\n')
    .trim();
}

function cleanMarkers(input) {
  return String(input || '').replace(/【\d+†/g, '').replace(/】/g, '');
}

function containsAny(text, markers) {
  return markers.some((marker) => text.includes(marker));
}

function decodeHtmlEntities(input) {
  return String(input || '')
    .replace(/&nbsp;/gi, ' ')
    .replace(/&amp;/gi, '&')
    .replace(/&quot;/gi, '"')
    .replace(/&#39;/gi, "'")
    .replace(/&lt;/gi, '<')
    .replace(/&gt;/gi, '>');
}

function extractPlainText(html) {
  const withoutScripts = String(html || '')
    .replace(/<script[\s\S]*?<\/script>/gi, ' ')
    .replace(/<style[\s\S]*?<\/style>/gi, ' ')
    .replace(/<noscript[\s\S]*?<\/noscript>/gi, ' ');
  const textLike = withoutScripts
    .replace(/<br\s*\/?>/gi, '\n')
    .replace(/<\/p>/gi, '\n')
    .replace(/<\/div>/gi, '\n')
    .replace(/<\/h[1-6]>/gi, '\n')
    .replace(/<[^>]+>/g, ' ');
  return normalizeWhitespace(cleanMarkers(decodeHtmlEntities(textLike)));
}

function hasAnnexBounds(text) {
  const hasStart = containsAny(text, START_MARKERS) || START_REGEX.test(text);
  if (!hasStart) return false;
  return containsAny(text, END_MARKERS) || END_REGEX.test(text);
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

    const response = await fetch(GSPR_SOURCE_PERMALINK);
    if (!response.ok) {
      throw new Error(`fetch failed: ${response.status} ${response.statusText}`);
    }

    const html = await response.text();
    const text = extractPlainText(html);
    if (!hasAnnexBounds(text)) {
      throw new Error('annex markers not found in EUR-Lex content');
    }

    const finishedAt = new Date().toISOString();
    const source = await gsprSourceMetaSave({
      name: GSPR_SOURCE_NAME,
      permalink: GSPR_SOURCE_PERMALINK,
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
