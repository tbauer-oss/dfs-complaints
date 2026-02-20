export const config = { runtime: 'nodejs' };

import { handlePreflight, setCors, ok, bad } from '../../_lib/http.js';
import { requirePortalAccess } from '../../admin/_guard.js';
import { getDbClient } from '../../_lib/db.js';
import { verifySyncToken } from '../../_lib/regulatory/token.js';
import { getSectionsForCurrentVersion } from '../../_lib/regulatory/db.js';
import { sha256 } from '../../_lib/regulatory/hash.js';
import { getLatestMdrVersionMeta } from '../../_lib/regulatory/eurlex_client.js';
import { parseMdrSections } from '../../_lib/regulatory/parser_mdr.js';
import { normalizeText } from '../../_lib/regulatory/normalize.js';
import { computeSectionDiff } from '../../_lib/regulatory/diff.js';

function parseBody(req) {
  if (req.body && typeof req.body === 'object') return req.body;
  try { return JSON.parse(req.body || '{}'); } catch { return {}; }
}

function uuidOrNull(value) {
  const v = String(value || '').trim();
  return /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i.test(v) ? v : null;
}

function dedupeSectionsByKey(sections) {
  const byKey = new Map();

  for (const section of sections) {
    const key = String(section.section_key || '');
    const existing = byKey.get(key);
    if (!existing) {
      byKey.set(key, section);
      continue;
    }

    const existingLen = String(existing.content_text || existing.content_html || '').length;
    const incomingLen = String(section.content_text || section.content_html || '').length;
    if (incomingLen > existingLen) {
      byKey.set(key, section);
    }
  }

  return Array.from(byKey.values());
}

export default async function handler(req, res) {
  if (handlePreflight(req, res)) return;
  setCors(req, res);
  const actor = await requirePortalAccess(req, res, { write: true, allowPrrc: true });
  if (!actor) return;
  if (req.method !== 'POST') return bad(res, 'method not allowed', 405);

  const client = await getDbClient();
  let transactionOpen = false;

  try {
    const body = parseBody(req);
    const slug = String(req.query?.slug || '').trim();
    const syncToken = String(body.sync_token || '').trim();
    if (!syncToken) return bad(res, 'SYNC_TOKEN_REQUIRED', 400);

    let payload;
    try {
      payload = verifySyncToken(syncToken);
    } catch {
      return bad(res, 'SYNC_TOKEN_INVALID', 401);
    }

    if (payload.slug !== slug) return bad(res, 'sync token slug mismatch', 409);

    const latest = await getLatestMdrVersionMeta();
    console.info(`[regulatory/apply] Resolved consolidated celex: ${latest.consolidated_celex}`);
    console.info(`[regulatory/apply] Fetched HTML size: ${Buffer.byteLength(latest.html || '', 'utf8')}`);

    if (payload.consolidated_celex && payload.consolidated_celex !== latest.consolidated_celex) {
      return bad(res, 'sync token celex mismatch', 409);
    }
    if (payload.version_label !== latest.versionLabel) return bad(res, 'sync token version mismatch', 409);

    const parsedSections = parseMdrSections(latest.html).map((section) => {
      const contentText = normalizeText(section.content_text || '');
      return { ...section, content_text: contentText, content_hash: section.content_hash || sha256(contentText) };
    });

    console.info(`[regulatory/apply] Parsed sections count: ${parsedSections.length}`);
    if (!parsedSections.length) return bad(res, 'PARSER_RETURNED_ZERO_SECTIONS', 500);

    const candidateHash = sha256(parsedSections.map((s) => `${s.section_key}:${s.content_hash}`).join('|'));
    if (payload.candidate_hash && payload.candidate_hash !== candidateHash) return bad(res, 'candidate hash mismatch', 409);

    const fullNormalizedText = normalizeText(parsedSections.map((s) => s.content_text).join('\n'));
    const contentHash = sha256(fullNormalizedText);
    if (payload.content_hash && payload.content_hash !== contentHash) return bad(res, 'content hash mismatch', 409);

    const uniqueSections = dedupeSectionsByKey(parsedSections);
    if (uniqueSections.length !== parsedSections.length) {
      console.warn(`[regulatory/apply] Deduped sections: original=${parsedSections.length}, unique=${uniqueSections.length}`);
    }
    console.info(`[regulatory/apply] Inserting sections: uniqueCount=${uniqueSections.length}`);

    await client.query('BEGIN');
    transactionOpen = true;

    const docQ = await client.query('select * from legal_documents where slug = $1 limit 1', [slug]);
    const doc = docQ.rows[0];
    if (!doc) throw new Error('document not found');

    const versionResult = await client.query(
      `insert into legal_versions (document_id, version_label, consolidation_date, source_url, content_hash)
       values ($1,$2,$3,$4,$5)
       on conflict (document_id, version_label) do update set
         consolidation_date = excluded.consolidation_date,
         source_url = excluded.source_url,
         content_hash = excluded.content_hash
       returning id`,
      [doc.id, latest.versionLabel, latest.consolidation_date, latest.source_url, contentHash],
    );
    const versionId = versionResult.rows[0].id;

    await client.query('delete from legal_sections where version_id = $1', [versionId]);

    for (const section of uniqueSections) {
      await client.query(
        `insert into legal_sections (version_id, section_type, section_key, heading, content_html, content_text, content_hash, sort_order)
         values ($1,$2,$3,$4,$5,$6,$7,$8)
         on conflict (version_id, section_key) do update set
           heading = excluded.heading,
           content_text = excluded.content_text,
           content_html = excluded.content_html,
           content_hash = excluded.content_hash,
           sort_order = excluded.sort_order,
           section_type = excluded.section_type`,
        [
          versionId,
          section.section_type,
          section.section_key,
          section.heading || '',
          section.content_html || '',
          section.content_text || '',
          section.content_hash,
          section.sort_order || null,
        ],
      );
    }

    const sectionCountQ = await client.query('select count(*)::int as count from legal_sections where version_id = $1', [versionId]);
    const sectionCount = Number(sectionCountQ.rows?.[0]?.count || 0);

    if (!sectionCount) {
      throw new Error('PARSER_RETURNED_ZERO_SECTIONS');
    }

    const oldSections = await getSectionsForCurrentVersion(slug).catch(() => []);
    const diff = computeSectionDiff(oldSections, uniqueSections);

    const changeResult = await client.query(
      `insert into legal_changes (document_id, from_version_id, to_version_id, synced_by, status, meta)
       values ($1,$2,$3,$4,$5,$6)
       returning id`,
      [doc.id, doc.current_version_id, versionId, uuidOrNull(actor.id), diff.changes.length ? 'changes_applied' : 'no_change', { version_label: latest.versionLabel }],
    );
    const changeId = changeResult.rows[0].id;

    for (const change of diff.changes) {
      await client.query(
        `insert into legal_section_changes (change_id, section_key, section_type, change_type, old_hash, new_hash, diff_summary, diff_detail)
         values ($1,$2,$3,$4,$5,$6,$7,$8)`,
        [changeId, change.section_key, change.section_type || 'other', change.change_type, change.old_hash || null, change.new_hash || null, change.diff_summary || '', {}],
      );
    }

    await client.query('update legal_documents set current_version_id = $1 where id = $2', [versionId, doc.id]);

    await client.query('COMMIT');
    transactionOpen = false;

    const impactedGspr = [];
    console.info(`[regulatory/apply] Skipping GSPR update for slug=${slug}`);

    return ok(res, { ok: true, change_id: changeId, impacted_gspr: impactedGspr, sections_written: sectionCount });
  } catch (err) {
    if (transactionOpen) {
      try {
        await client.query('ROLLBACK');
      } catch {}
    }
    console.error('[regulatory/apply] failed', err);
    return bad(res, err?.message || 'apply failed', 500, { code: 'REGULATORY_APPLY_FAILED' });
  } finally {
    client.release();
  }
}
