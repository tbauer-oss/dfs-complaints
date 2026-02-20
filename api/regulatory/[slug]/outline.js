export const config = { runtime: 'nodejs' };

import { handlePreflight, setCors, ok, bad } from '../../_lib/http.js';
import { requirePortalAccess } from '../../admin/_guard.js';
import { query } from '../../_lib/db.js';

export default async function handler(req, res) {
  if (handlePreflight(req, res)) return;
  setCors(req, res);
  const actor = await requirePortalAccess(req, res, { write: false, allowPrrc: true });
  if (!actor) return;
  if (req.method !== 'GET') return bad(res, 'method not allowed', 405);

  try {
    const slug = String(req.query?.slug || '').trim();
    if (!slug) return bad(res, 'slug missing', 400);

    const { rows } = await query(
      `select s.section_key, s.section_type, s.heading, s.sort_order
       from legal_documents d
       join legal_sections s on s.version_id = d.current_version_id
       where d.slug = $1
       order by s.sort_order asc nulls last, s.section_key asc`,
      [slug],
    );

    return ok(res, { ok: true, outline: rows });
  } catch (err) {
    console.error('[regulatory/outline] failed', err?.message || err);
    return bad(res, err?.message || 'outline lookup failed', 500);
  }
}
