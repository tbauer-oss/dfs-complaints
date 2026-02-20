export const config = { runtime: 'nodejs' };

import { handlePreflight, setCors, ok, bad } from '../../_lib/http.js';
import { requirePortalAccess } from '../../admin/_guard.js';
import { query } from '../../_lib/db.js';

function parseBody(req) {
  if (req.body && typeof req.body === 'object') return req.body;
  try { return JSON.parse(req.body || '{}'); } catch { return {}; }
}

function toJson(value) {
  if (value == null) return null;
  if (typeof value === 'string') {
    try { return JSON.parse(value); } catch { return value; }
  }
  return value;
}

export default async function handler(req, res) {
  if (handlePreflight(req, res)) return;
  setCors(req, res);

  const actor = await requirePortalAccess(req, res, { tile: 'gspr', write: true, allowPrrc: true });
  if (!actor) return;
  if (req.method !== 'POST') return bad(res, 'method not allowed', 405);

  try {
    const regSlug = String(req.query?.regSlug || '').trim();
    if (!regSlug) return bad(res, 'regSlug missing', 400);

    const body = parseBody(req);
    const tdId = String(body.td_id || '').trim();
    const gsprCode = String(body.gspr_code || '').trim();
    const status = String(body.status || 'open').trim().toLowerCase();
    const justification = body.justification == null ? null : String(body.justification);
    const evidenceRefs = toJson(body.evidence_refs);

    if (!tdId || !gsprCode) return bad(res, 'td_id and gspr_code required', 400);
    if (!['open', 'ok', 'nok', 'na'].includes(status)) return bad(res, 'invalid status', 400);

    const exists = await query(
      `select 1
       from gspr_requirements
       where reg_slug = $1 and gspr_code = $2
       limit 1`,
      [regSlug, gsprCode],
    );
    if (!exists.rows?.length) return bad(res, 'GSPR_NOT_FOUND', 404);

    const upsert = await query(
      `insert into gspr_assessments (td_id, gspr_code, status, justification, evidence_refs, updated_by, updated_at)
       values ($1,$2,$3,$4,$5,$6,now())
       on conflict (td_id, gspr_code)
       do update set
         status = excluded.status,
         justification = excluded.justification,
         evidence_refs = excluded.evidence_refs,
         updated_by = excluded.updated_by,
         updated_at = now()
       returning id, td_id, gspr_code, status, justification, evidence_refs, updated_at`,
      [tdId, gsprCode, status, justification, evidenceRefs, actor?.id || null],
    );

    return ok(res, { ok: true, item: upsert.rows?.[0] || null });
  } catch (err) {
    console.error('[gspr/assessment] failed', err);
    return bad(res, err?.message || 'assessment failed', 500);
  }
}
