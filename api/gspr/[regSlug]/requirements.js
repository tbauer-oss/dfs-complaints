export const config = { runtime: 'nodejs' };

import { handlePreflight, setCors, ok, bad } from '../../_lib/http.js';
import { requirePortalAccess } from '../../admin/_guard.js';
import { query } from '../../_lib/db.js';

export default async function handler(req, res) {
  if (handlePreflight(req, res)) return;
  setCors(req, res);
  const actor = await requirePortalAccess(req, res, { tile: 'gspr', write: false, allowPrrc: true });
  if (!actor) return;
  if (req.method !== 'GET') return bad(res, 'method not allowed', 405);

  try {
    const regSlug = String(req.query?.regSlug || '').trim();
    const tdId = String(req.query?.td || '').trim();
    if (!regSlug) return bad(res, 'regSlug missing', 400);
    if (!tdId) return bad(res, 'td missing', 400);

    const { rows } = await query(
      `select r.gspr_code,
              r.title,
              r.requirement_text,
              coalesce(a.status, 'open') as status,
              a.justification,
              a.evidence_refs
       from gspr_requirements r
       left join gspr_assessments a
         on a.gspr_code = r.gspr_code
        and a.td_id = $2
       where r.reg_slug = $1
       order by r.sort_order asc, r.gspr_code asc`,
      [regSlug, tdId],
    );

    return ok(res, { ok: true, items: rows });
  } catch (err) {
    console.error('[gspr/requirements] failed', err);
    return bad(res, err?.message || 'requirements failed', 500);
  }
}
