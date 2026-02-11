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

function normalizeWhitespace(input) {
  return String(input || '')
    .replace(/\r\n?/g, '\n')
    .replace(/[ \t]+$/gm, '')
    .replace(/\n{3,}/g, '\n\n')
    .trim();
}

function cleanMarkers(input) {
  return input.replace(/【\d+†/g, '').replace(/】/g, '');
}

function containsAny(text, markers) {
  return markers.some((marker) => text.includes(marker));
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
    const text = normalizeWhitespace(cleanMarkers(html));
    if (!containsAny(text, START_MARKERS)) {
      throw new Error('annex start marker not found');
    }
    if (!containsAny(text, END_MARKERS)) {
      throw new Error('annex end marker not found');
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
