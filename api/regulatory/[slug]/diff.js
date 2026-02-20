export const config = { runtime: 'nodejs' };

import { handlePreflight, setCors, ok, bad, readJson } from '../../_lib/http.js';
import { requirePortalAccess } from '../../admin/_guard.js';
import { getLegalDocument, getSectionsForCurrentVersion } from '../../_lib/regulatory/db.js';
import { getLatestMdrVersionMeta, fetchMdrConsolidatedHtml } from '../../_lib/regulatory/eurlex_client.js';
import { parseMdrSections } from '../../_lib/regulatory/parser_mdr.js';
import { normalizeText } from '../../_lib/regulatory/normalize.js';
import { sha256 } from '../../_lib/regulatory/hash.js';
import { computeSectionDiff } from '../../_lib/regulatory/diff.js';
import { signSyncToken } from '../../_lib/regulatory/token.js';

export default async function handler(req, res) {
  if (handlePreflight(req, res)) return;
  setCors(req, res);
  const actor = await requirePortalAccess(req, res, { write: true, allowPrrc: true });
  if (!actor) return;
  if (req.method !== 'POST') return bad(res, 'method not allowed', 405);
  const body = readJson(req) || {};
  const force = body.force === true;

  const slug = String(req.query?.slug || '').trim();
  const doc = await getLegalDocument(slug);
  if (!doc) return bad(res, 'document not found', 404);

  const latest = await getLatestMdrVersionMeta();
  const hasUpdate = force || latest.versionLabel !== doc.current_version_label;
  if (!hasUpdate) return ok(res, { ok: true, has_update: false });

  const fetched = await fetchMdrConsolidatedHtml(latest);
  const parsed = parseMdrSections(fetched.html).map((section) => {
    const contentText = normalizeText(section.content_text || '');
    return {
      ...section,
      content_text: contentText,
      content_hash: sha256(contentText),
    };
  });
  const candidateHash = sha256(parsed.map((s) => `${s.section_key}:${s.content_hash}`).join('|'));
  const oldSections = await getSectionsForCurrentVersion(slug);
  const diff = computeSectionDiff(oldSections, parsed);
  const exp = Date.now() + (30 * 60 * 1000);
  const syncToken = signSyncToken({
    slug,
    version_label: latest.versionLabel,
    candidate_hash: candidateHash,
    source_url: fetched.sourceUrl,
    exp,
    sections: parsed,
    changes: diff.changes,
  });

  return ok(res, {
    ok: true,
    has_update: true,
    sync_token: syncToken,
    from_version: doc.current_version_label ? { id: doc.current_version_id, version_label: doc.current_version_label } : null,
    to_version_preview: { version_label: latest.versionLabel, source_url: fetched.sourceUrl, consolidation_date: latest.consolidationDate },
    counts: diff.counts,
    changes: diff.changes,
  });
}
