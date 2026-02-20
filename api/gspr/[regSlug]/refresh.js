export const config = { runtime: 'nodejs' };

import { handlePreflight, setCors, ok, bad } from '../../_lib/http.js';
import { requirePortalAccess } from '../../admin/_guard.js';
import { normalizeRole, PORTAL_ROLES } from '../../_lib/portalAuth.js';
import { getDbClient } from '../../_lib/db.js';
import { extractGsprRequirements } from '../../_lib/gsprCache.js';

function isAdminLike(actor) {
  const role = normalizeRole(actor?.role);
  return role === PORTAL_ROLES.superuser || role === PORTAL_ROLES.admin;
}

export default async function handler(req, res) {
  if (handlePreflight(req, res)) return;
  setCors(req, res);

  const actor = await requirePortalAccess(req, res, { tile: 'gspr', write: true, allowPrrc: false });
  if (!actor) return;
  if (!isAdminLike(actor)) return bad(res, 'forbidden', 403);
  if (req.method !== 'POST') return bad(res, 'method not allowed', 405);

  const regSlug = String(req.query?.regSlug || '').trim();
  if (!regSlug) return bad(res, 'regSlug missing', 400);

  const client = await getDbClient();
  let txOpen = false;

  try {
    const versionQ = await client.query(
      `select d.current_version_id
       from legal_documents d
       where d.slug = $1
       limit 1`,
      [regSlug],
    );
    const versionId = versionQ.rows?.[0]?.current_version_id || null;
    if (!versionId) return bad(res, 'LEGAL_VERSION_NOT_FOUND', 404);

    const annexQ = await client.query(
      `select section_key, heading, content_text
       from legal_sections
       where version_id = $1
         and (
           section_key ilike 'Annex_I%'
           or section_key ilike 'ANNEX_I%'
           or section_key ilike '%Annex%'
           or section_type ilike 'annex%'
         )
       order by sort_order asc nulls last, section_key asc`,
      [versionId],
    );

    const annexRows = annexQ.rows || [];
    const annexText = annexRows
      .map((row) => String(row.content_text || '').trim())
      .filter(Boolean)
      .join('\n\n');

    const extracted = extractGsprRequirements(annexText).map((row) => ({
      ...row,
      source_section_key: 'Annex_I',
    }));

    if (!extracted.length) {
      return bad(res, 'GSPR_PARSE_ZERO', 500);
    }

    let inserted = 0;
    let updated = 0;

    await client.query('BEGIN');
    txOpen = true;

    for (const item of extracted) {
      const upsertQ = await client.query(
        `insert into gspr_requirements
          (reg_slug, source_version_id, gspr_code, title, requirement_text, requirement_hash, sort_order, source_section_key, updated_at)
         values ($1,$2,$3,$4,$5,$6,$7,$8,now())
         on conflict (reg_slug, source_version_id, gspr_code)
         do update set
           title = excluded.title,
           requirement_text = excluded.requirement_text,
           requirement_hash = excluded.requirement_hash,
           sort_order = excluded.sort_order,
           source_section_key = excluded.source_section_key,
           updated_at = now()
         returning (xmax = 0) as inserted`,
        [
          regSlug,
          versionId,
          item.gspr_code,
          item.title,
          item.requirement_text,
          item.requirement_hash,
          item.sort_order,
          item.source_section_key,
        ],
      );
      if (upsertQ.rows?.[0]?.inserted) inserted += 1;
      else updated += 1;
    }

    await client.query('COMMIT');
    txOpen = false;

    return ok(res, { ok: true, inserted, updated, total: extracted.length });
  } catch (err) {
    if (txOpen) {
      try { await client.query('ROLLBACK'); } catch {}
    }
    console.error('[gspr/refresh] failed', err);
    return bad(res, err?.message || 'refresh failed', 500);
  } finally {
    client.release();
  }
}
