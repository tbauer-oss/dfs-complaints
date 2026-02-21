export const config = { runtime: 'nodejs' };

import { handlePreflight, setCors, ok, bad } from '../../_lib/http.js';
import { requirePortalAccess } from '../../admin/_guard.js';
import { getLegalDocument, getSectionsForCurrentVersion } from '../../_lib/regulatory/db.js';
import { getLatestMdrVersionMeta, isExpectedAnchorsMissingError } from '../../_lib/regulatory/eurlex_client.js';
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

  try {
    const body = (() => {
      try { return req.body && typeof req.body === 'object' ? req.body : JSON.parse(req.body || '{}'); } catch { return {}; }
    })();
    const force = body.force === true;

    const slug = String(req.query?.slug || '').trim();
    if (!slug) return bad(res, 'slug missing', 400);

    const doc = await getLegalDocument(slug).catch(() => null);
    const currentLabel = doc?.current_version_label || null;
    const currentId = doc?.current_version_id || null;

    const latest = await getLatestMdrVersionMeta();
    console.info(`[regulatory/diff] Resolved consolidated celex: ${latest.consolidated_celex}`);
    console.info(`[regulatory/diff] Fetched HTML size: ${Buffer.byteLength(latest.html || '', 'utf8')}`);

    const hasUpdate = force || latest.versionLabel !== currentLabel;
    if (!hasUpdate) {
      return ok(res, {
        ok: true,
        has_update: false,
        counts: { added: 0, removed: 0, modified: 0, total: 0 },
        changes: [],
      });
    }

    const parsed = parseMdrSections(latest.html).map((section) => {
      const contentText = normalizeText(section.content_text || '');
      return { ...section, content_text: contentText, content_hash: sha256(contentText) };
    });

    console.info(`[regulatory/diff] Parsed sections count: ${parsed.length}`);
    if (!parsed.length) throw new Error('PARSER_RETURNED_ZERO_SECTIONS');

    const fullNormalizedText = normalizeText(parsed.map((s) => s.content_text).join('\n'));
    const contentHash = sha256(fullNormalizedText);
    const candidateHash = sha256(parsed.map((s) => `${s.section_key}:${s.content_hash}`).join('|'));
    const oldSections = await getSectionsForCurrentVersion(slug).catch(() => []);
    const diff = computeSectionDiff(oldSections, parsed);
    const issuedAt = Date.now();
    const exp = issuedAt + 30 * 60 * 1000;

    const syncToken = signSyncToken({
      slug,
      consolidated_celex: latest.consolidated_celex,
      version_label: latest.versionLabel,
      consolidation_date: latest.consolidation_date,
      candidate_hash: candidateHash,
      source_url: latest.source_url,
      content_hash: contentHash,
      issued_at: issuedAt,
      exp,
    });

    return ok(res, {
      ok: true,
      has_update: true,
      sync_token: syncToken,
      from_version: currentLabel ? { id: currentId, version_label: currentLabel } : null,
      to_version_preview: {
        version_label: latest.versionLabel,
        source_url: latest.source_url,
        consolidation_date: latest.consolidation_date,
        content_hash: contentHash,
      },
      counts: diff.counts,
      changes: diff.changes,
    });
  } catch (err) {
    if (isExpectedAnchorsMissingError(err)) {
      console.error('[regulatory/diff] EXPECTED_ANCHORS_MISSING', {
        message: err?.message || String(err),
        counts: err?.details?.counts || null,
        excerpts: err?.details?.excerpts || [],
      });
      return bad(
        res,
        'EXPECTED_ANCHORS_MISSING: EUR-Lex page structure changed. Please retry later or switch source locale before syncing.',
        500,
        { code: 'EXPECTED_ANCHORS_MISSING', details: err?.details || null },
      );
    }
    console.error('[regulatory/diff] failed', err);
    return bad(res, err?.message || 'diff failed', 500, { code: 'REGULATORY_DIFF_FAILED' });
  }
}
