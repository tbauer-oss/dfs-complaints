export const config = { runtime: 'nodejs' };

import { handlePreflight, setCors, ok, bad } from '../_lib/http.js';
import { listLegalDocuments } from '../_lib/regulatory/db.js';

const FALLBACK_DOCS = [
  {
    slug: 'mdr-2017-745',
    title: 'Regulation (EU) 2017/745 (MDR)',
    celex: '32017R0745',
    current_version_id: null,
    current_version_label: null,
    current_consolidation_date: null,
    current_fetched_at: null,
  },
];

export default async function handler(req, res) {
  if (handlePreflight(req, res)) return;
  setCors(req, res);
  if (req.method !== 'GET') return bad(res, 'method not allowed', 405);
  try {
    const docs = await listLegalDocuments();
    return ok(res, { ok: true, docs: docs.length ? docs : FALLBACK_DOCS });
  } catch (err) {
    console.error('[regulatory/docs] failed, returning fallback', err?.message || err);
    return ok(res, {
      ok: true,
      degraded: true,
      reason: 'REGULATORY_DB_UNAVAILABLE',
      docs: FALLBACK_DOCS,
    });
  }
}
