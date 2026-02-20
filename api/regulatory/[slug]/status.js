export const config = { runtime: 'nodejs' };

import { handlePreflight, setCors, ok, bad } from '../../_lib/http.js';
import { requirePortalAccess } from '../../admin/_guard.js';
import { getLegalDocument } from '../../_lib/regulatory/db.js';
import { getLatestMdrVersionMeta } from '../../_lib/regulatory/eurlex_client.js';

export default async function handler(req, res) {
  if (handlePreflight(req, res)) return;
  setCors(req, res);
  const actor = await requirePortalAccess(req, res, { write: false, allowPrrc: true });
  if (!actor) return;
  if (req.method !== 'GET') return bad(res, 'method not allowed', 405);

  const slug = String(req.query?.slug || '').trim();
  const doc = await getLegalDocument(slug);
  if (!doc) return bad(res, 'document not found', 404);

  const latest = slug === 'mdr-2017-745' ? await getLatestMdrVersionMeta() : null;
  return ok(res, {
    ok: true,
    slug,
    current_version: doc.current_version_label ? {
      id: doc.current_version_id,
      version_label: doc.current_version_label,
      consolidation_date: doc.current_consolidation_date,
    } : null,
    latest_available: latest,
    has_update: Boolean(latest?.versionLabel && latest.versionLabel !== doc.current_version_label),
  });
}
