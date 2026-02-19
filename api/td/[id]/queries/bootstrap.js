export const config = { runtime: 'nodejs' };
import { handlePreflight, setCors, ok, bad } from '../../../_lib/http.js';
import { requirePortalAccess } from '../../../admin/_guard.js';
import { tdBootstrapQueries, tdOverviewFast, tdSections } from '../../../_lib/tdStore.js';
import { withTiming } from '../../../_lib/timing.js';

const BOOTSTRAP_TTL_MS = 30 * 1000;
const bootstrapCache = new Map();

function sectionToMeta(section) {
  return {
    id: section.id,
    sectionId: section.id,
    name: section.name,
    title: section.name,
    templateKey: section.templateKey,
    status: section.status,
    order: section.order,
    linkCount: section.linkCount || 0,
    queryStats: section.queryTotal == null
        ? null
        : {
            total: section.queryTotal,
            complete: section.queryComplete || 0,
            completion: section.completion || 0,
          },
  };
}

export default async function handler(req, res) {
  if (handlePreflight(req, res)) return;
  setCors(req, res);

  const id = String(req.query?.id || '').trim();
  if (!id) return bad(res, 'id is required', 400);

  if (req.method === 'GET') {
    const actor = await requirePortalAccess(req, res, { tile: 'td', write: false });
    if (!actor) return;
    return withTiming('td.queries.bootstrap.get', async (timing) => {
      timing.stats.route = '/api/td/:id/queries/bootstrap';
      timing.stats.tdId = id;
      try {
        const now = Date.now();
        const cached = bootstrapCache.get(id);
        if (cached && now - cached.ts <= BOOTSTRAP_TTL_MS) {
          timing.setCacheHit(true);
          timing.addRows(cached.payload?.sections?.items?.length || 0);
          timing.setServerTiming(res);
          return ok(res, { ...cached.payload, cacheHit: true });
        }

        const overview = (await tdOverviewFast(id)) || {
          section_count: 0,
          answered_count: 0,
          link_count: 0,
        };
        const sections = await tdSections(id);
        const sectionMeta = sections.map(sectionToMeta);
        const payload = {
          ok: true,
          overview,
          sections: {
            items: sectionMeta,
            page: {
              limit: sectionMeta.length,
              cursor: 0,
              nextCursor: null,
              total: sectionMeta.length,
            },
          },
          progress: {
            answeredCount: overview.answered_count || 0,
            sectionCount: overview.section_count || sectionMeta.length,
            linkCount: overview.link_count || 0,
          },
          cacheHit: false,
        };
        bootstrapCache.set(id, { ts: now, payload });
        timing.addRows(sectionMeta.length);
        timing.setServerTiming(res);
        return ok(res, payload);
      } catch (err) {
        return bad(res, err?.message || 'server error', 500);
      }
    });
  }

  if (req.method === 'POST') {
    const actor = await requirePortalAccess(req, res, { tile: 'td', write: true });
    if (!actor) return;
    try {
      return ok(res, { ok: true, ...(await tdBootstrapQueries(id, actor.email || actor.id || null)) });
    } catch (err) {
      return bad(res, err?.message || 'server error', 500);
    }
  }

  return bad(res, 'method not allowed', 405);
}
