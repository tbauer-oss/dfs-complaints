export const config = { runtime: 'nodejs' };

import { handlePreflight, setCors, ok, bad } from '../../_lib/http.js';
import { requirePortalAccess } from '../../admin/_guard.js';
import { verifySyncToken } from '../../_lib/regulatory/token.js';
import { query } from '../../_lib/db.js';

export default async function handler(req, res) {
  if (handlePreflight(req, res)) return;
  setCors(req, res);
  const actor = await requirePortalAccess(req, res, { write: false, allowPrrc: true });
  if (!actor) return;
  if (req.method !== 'GET') return bad(res, 'method not allowed', 405);

  try {
    const slug = String(req.query?.slug || '').trim();
    const key = String(req.query?.key || '').trim();
    const side = String(req.query?.side || 'new').trim();

    if (!slug) return bad(res, 'slug missing', 400);
    if (!key) return bad(res, 'key missing', 400);

    if ((side === 'old' || side === 'new') && req.query?.token) {
      const token = verifySyncToken(req.query?.token);
      const row = (token.sections || []).find((entry) => entry.section_key === key);
      return ok(res, { ok: true, section: row || null });
    }

    const result = await query(
      `select s.section_key, s.heading, s.content_text, s.content_html, s.content_hash
       from legal_documents d
       join legal_sections s on s.version_id = d.current_version_id
       where d.slug = $1 and s.section_key = $2
       limit 1`,
      [slug, key],
    );

    return ok(res, { ok: true, section: result.rows?.[0] || null });
  } catch (err) {
    console.error('[regulatory/section] failed', err?.message || err);
    return bad(res, err?.message || 'section lookup failed', 500);
  }
}
