export const config = { runtime: 'nodejs' };

import { handlePreflight, setCors, ok, bad } from '../../_lib/http.js';
import { requirePortalAccess } from '../../admin/_guard.js';
import { getLegalDocument } from '../../_lib/regulatory/db.js';
import { getLatestMdrVersionMeta } from '../../_lib/regulatory/eurlex_client.js';

const FALLBACK_DOC = {
  slug: 'mdr-2017-745',
  current_version_id: null,
  current_version_label: null,
  current_consolidation_date: null,
};

export default async function handler(req, res) {
  if (handlePreflight(req, res)) return;
  setCors(req, res);
  const actor = await requirePortalAccess(req, res, { write: false, allowPrrc: true });
  if (!actor) return;
  if (req.method !== 'GET') return bad(res, 'method not allowed', 405);

  const slug = String(req.query?.slug || '').trim();
  if (!slug) return bad(res, 'slug missing', 400);

  let doc = null;
  try {
    doc = await getLegalDocument(slug);
  } catch (err) {
    console.error('[regulatory/status] getLegalDocument failed', err?.message || err);
  }
  if (!doc && slug === 'mdr-2017-745') doc = FALLBACK_DOC;
  if (!doc) return bad(res, 'document not found', 404);

  let latest = null;
  try {
    latest = slug === 'mdr-2017-745' ? await getLatestMdrVersionMeta() : null;
  } catch (err) {
    console.warn('[regulatory/status] latest meta unavailable', err?.message || err);
  }

  return ok(res, {
    ok: true,
    slug,
    current_version: doc.current_version_label
      ? {
          id: doc.current_version_id,
          version_label: doc.current_version_label,
          consolidation_date: doc.current_consolidation_date,
        }
      : null,
    latest_available: latest,
    has_update: Boolean(latest?.versionLabel && latest.versionLabel !== doc.current_version_label),
  });
}
