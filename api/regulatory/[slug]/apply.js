export const config = { runtime: 'nodejs' };

import { handlePreflight, setCors, ok, bad } from '../../_lib/http.js';
import { requirePortalAccess } from '../../admin/_guard.js';
import { query } from '../../_lib/db.js';
import { verifySyncToken } from '../../_lib/regulatory/token.js';
import { sha256 } from '../../_lib/regulatory/hash.js';

function parseBody(req) {
  if (req.body && typeof req.body === 'object') return req.body;
  try { return JSON.parse(req.body || '{}'); } catch { return {}; }
}

function uuidOrNull(value) {
  const v = String(value || '').trim();
  return /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i.test(v) ? v : null;
}

export default async function handler(req, res) {
  if (handlePreflight(req, res)) return;
  setCors(req, res);
  const actor = await requirePortalAccess(req, res, { write: true, allowPrrc: true });
  if (!actor) return;
  if (req.method !== 'POST') return bad(res, 'method not allowed', 405);

  try {
    const body = parseBody(req);
    const slug = String(req.query?.slug || '').trim();
    const expected = String(body.expected_version_label || '').trim();

    const payload = verifySyncToken(body.sync_token);
    if (payload.slug !== slug) return bad(res, 'sync token slug mismatch', 409);
    if (expected && expected !== payload.version_label) return bad(res, 'version mismatch', 409);
    const tokenHash = sha256((payload.sections || []).map((s) => `${s.section_key}:${s.content_hash}`).join('|'));
    if (tokenHash !== payload.candidate_hash) return bad(res, 'candidate hash mismatch', 409);

    const docQ = await query('select * from legal_documents where slug = $1 limit 1', [slug]);
    const doc = docQ.rows[0];
    if (!doc) return bad(res, 'document not found', 404);

    const versionResult = await query(
      `insert into legal_versions (document_id, version_label, source_url, content_hash)
       values ($1,$2,$3,$4)
       on conflict (document_id, version_label) do update set source_url = excluded.source_url, content_hash = excluded.content_hash
       returning id`,
      [doc.id, payload.version_label, payload.source_url, payload.candidate_hash],
    );
    const versionId = versionResult.rows[0].id;

    await query('delete from legal_sections where version_id = $1', [versionId]);
    for (const section of payload.sections || []) {
      await query(
        `insert into legal_sections (version_id, section_type, section_key, heading, content_html, content_text, content_hash, sort_order)
         values ($1,$2,$3,$4,$5,$6,$7,$8)`,
        [versionId, section.section_type, section.section_key, section.heading || '', section.content_html || '', section.content_text || '', section.content_hash, section.sort_order || null],
      );
    }

    const changeResult = await query(
      `insert into legal_changes (document_id, from_version_id, to_version_id, synced_by, status, meta)
       values ($1,$2,$3,$4,$5,$6)
       returning id`,
      [doc.id, doc.current_version_id, versionId, uuidOrNull(actor.id), (payload.changes || []).length ? 'changes_applied' : 'no_change', { version_label: payload.version_label }],
    );
    const changeId = changeResult.rows[0].id;

    for (const change of payload.changes || []) {
      await query(
        `insert into legal_section_changes (change_id, section_key, section_type, change_type, old_hash, new_hash, diff_summary, diff_detail)
         values ($1,$2,$3,$4,$5,$6,$7,$8)`,
        [changeId, change.section_key, change.section_type || 'other', change.change_type, change.old_hash || null, change.new_hash || null, change.diff_summary || '', {}],
      );
    }

    await query('update legal_documents set current_version_id = $1 where id = $2', [versionId, doc.id]);

    const changedKeys = (payload.changes || []).map((c) => c.section_key);
    const impactRows = changedKeys.length
      ? await query(
          `select distinct g.id, g.code
           from gspr_requirements g
           join gspr_links l on l.gspr_id = g.id
           where l.document_slug = $1 and l.section_key = any($2::text[])`,
          [slug, changedKeys],
        )
      : { rows: [] };

    for (const row of impactRows.rows) {
      await query(
        `insert into gspr_impacts (change_id, gspr_id, section_key, impact_type)
         values ($1,$2,$3,'referenced_section_changed')`,
        [changeId, row.id, 'multiple'],
      );
    }

    return ok(res, { ok: true, change_id: changeId, impacted_gspr: impactRows.rows });
  } catch (err) {
    console.error('[regulatory/apply] failed', err);
    return bad(res, err?.message || 'apply failed', 500, { code: 'REGULATORY_APPLY_FAILED' });
  }
}
