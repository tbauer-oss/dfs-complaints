export const config = { runtime: 'nodejs' };

import { handlePreflight, setCors, ok, bad } from '../../_lib/http.js';
import { requirePortalAccess } from '../../admin/_guard.js';
import { loadSectionsMetaFromDb, loadSectionsMetaFallback } from '../../_lib/tdFastQueries.js';
import { queryWithStatementTimeout } from '../../_lib/db.js';
import { getLegalDocument } from '../../_lib/regulatory/db.js';

async function resolveSections(tdId) {
  try {
    const data = await loadSectionsMetaFromDb(tdId, 500, 0, 5000, (sql, params) => queryWithStatementTimeout(sql, params, 5000));
    if (data) return data.items || [];
  } catch (err) {
    console.warn('[td/structure] db fallback', err?.message || err);
  }
  const fallback = await loadSectionsMetaFallback(tdId, 500, 0);
  return fallback.items || [];
}

export default async function handler(req, res) {
  if (handlePreflight(req, res)) return;
  setCors(req, res);

  const actor = await requirePortalAccess(req, res, { tile: 'td', write: false });
  if (!actor) return;
  if (req.method !== 'GET') return bad(res, 'method not allowed', 405);

  const tdId = String(req.query?.id || '').trim();
  if (!tdId) return bad(res, 'id is required', 400);

  const [sections, regulation] = await Promise.all([
    resolveSections(tdId),
    getLegalDocument('mdr-2017-745').catch(() => null),
  ]);

  const items = sections.map((row, idx) => ({
    sectionKey: String(row.template_key || row.section_id || ''),
    title: String(row.title || ''),
    parentKey: null,
    level: 0,
    order: Number(row.order ?? idx),
    status: String(row.status || 'NotStarted'),
    linksCount: Number(row.link_count ?? 0),
    completeness: row.query_total > 0 ? Math.round(((row.completed_queries || 0) / row.query_total) * 100) : 0,
    updatedAt: row.updated_at || null,
    sectionId: String(row.section_id || ''),
  }));

  return ok(res, {
    ok: true,
    tdId,
    versionLabel: regulation?.current_version_label || 'mdr-2017-745',
    versionHash: regulation?.current_version_id || '',
    source: 'Regulatory Cache',
    items,
  });
}
