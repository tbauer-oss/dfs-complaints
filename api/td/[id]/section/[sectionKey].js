export const config = { runtime: 'nodejs' };

import { handlePreflight, setCors, ok, bad } from '../../../../_lib/http.js';
import { requirePortalAccess } from '../../../../admin/_guard.js';
import { tdSectionGetDetailed } from '../../../../_lib/tdStore.js';
import { getLegalDocument } from '../../../../_lib/regulatory/db.js';

export default async function handler(req, res) {
  if (handlePreflight(req, res)) return;
  setCors(req, res);

  const actor = await requirePortalAccess(req, res, { tile: 'td', write: false });
  if (!actor) return;
  if (req.method !== 'GET') return bad(res, 'method not allowed', 405);

  const tdId = String(req.query?.id || '').trim();
  const sectionKey = String(req.query?.sectionKey || '').trim();
  if (!tdId || !sectionKey) return bad(res, 'id and sectionKey are required', 400);

  const section = await tdSectionGetDetailed(sectionKey);
  if (!section || String(section.tdId || section.td_id || '') != tdId) return bad(res, 'not found', 404);

  const regulation = await getLegalDocument('mdr-2017-745').catch(() => null);

  return ok(res, {
    ok: true,
    tdId,
    sectionKey,
    versionLabel: regulation?.current_version_label || 'mdr-2017-745',
    versionHash: regulation?.current_version_id || '',
    source: 'Regulatory Cache',
    item: {
      sectionKey,
      title: section.name || section.title || sectionKey,
      status: section.status || 'NotStarted',
      summaryMarkdown: section.content?.summaryMarkdown || '',
      contentJson: section.content?.contentJson || null,
      queryStats: section.queryStats || null,
      linkCount: section.linkCount || 0,
      updatedAt: section.updatedAt || null,
      applicability: section.applicability || null,
    },
  });
}
