export const config = { runtime: 'nodejs' };
import { handlePreflight, setCors, ok, bad } from '../../_lib/http.js';
import { requirePortalAccess } from '../../admin/_guard.js';
import { tdSections, tdSectionContentGet, tdLinksBySection, tdQueries } from '../../_lib/tdStore.js';

export default async function handler(req, res) {
  if (handlePreflight(req, res)) return;
  setCors(req, res);
  const actor = await requirePortalAccess(req, res, { tile: 'td', write: false });
  if (!actor) return;
  if (req.method !== 'GET') return bad(res, 'method not allowed', 405);
  const id = String(req.query?.id || '').trim();
  if (!id) return bad(res, 'id is required', 400);
  try {
    const sections = await tdSections(id);
    const queries = await tdQueries(id);
    const items = await Promise.all(sections.map(async (section) => {
      const [content, links] = await Promise.all([tdSectionContentGet(section.id), tdLinksBySection(id, section.id)]);
      const sectionQueries = queries.filter((q) => q.sectionId === section.id);
      const complete = sectionQueries.filter((q) => q.status === 'Complete' || q.status === 'NotApplicable').length;
      const completion = sectionQueries.length ? Math.round((complete / sectionQueries.length) * 100) : 0;
      return { ...section, content, linkCount: links.length, queryStats: { total: sectionQueries.length, complete, completion } };
    }));
    return ok(res, { ok: true, items });
  } catch (err) {
    return bad(res, err?.message || 'server error', 500);
  }
}
