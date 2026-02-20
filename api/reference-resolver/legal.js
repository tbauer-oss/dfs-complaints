export const config = { runtime: 'nodejs' };

import { handlePreflight, setCors, ok, bad } from '../_lib/http.js';
import { requirePortalAccess } from '../admin/_guard.js';
import { legalReferenceResolver } from '../_lib/legalRefService.js';
import { query } from '../_lib/db.js';

async function resolveCachedSection(documentSlug, sectionKey) {
  if (!documentSlug || !sectionKey) return null;
  const result = await query(
    `select s.section_key, s.section_type, s.heading, s.content_text, s.content_html, s.sort_order,
            v.id as version_id, v.version_label
       from legal_documents d
       join legal_versions v on v.id = d.current_version_id
       join legal_sections s on s.version_id = v.id
      where d.slug = $1 and s.section_key = $2
      limit 1`,
    [documentSlug, sectionKey],
  );
  return result.rows?.[0] || null;
}

export default async function handler(req, res) {
  if (handlePreflight(req, res)) return;
  setCors(req, res);
  const actor = await requirePortalAccess(req, res, { tile: 'td', write: false });
  if (!actor) return;
  if (req.method !== 'GET') return bad(res, 'method not allowed', 405);

  const type = String(req.query?.type || '').trim();
  const value = String(req.query?.value || '').trim();
  if (!type || !value) return bad(res, 'type and value are required', 400);

  const item = legalReferenceResolver(type, value);
  if (!item) return bad(res, 'reference not found', 404);

  let section = null;
  try {
    section = await resolveCachedSection(item.document_slug, item.section_key);
  } catch (err) {
    console.warn('[reference-resolver/legal] section lookup unavailable', err?.message || err);
  }

  return ok(res, {
    ok: true,
    item,
    cached_section: section,
  });
}
