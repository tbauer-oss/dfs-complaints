export const config = { runtime: 'nodejs' };

import { requirePortalAccess } from '../../admin/_guard.js';
import { bad, handlePreflight, ok, setCors } from '../../_lib/http.js';
import { PORTAL_ROLES, normalizeRole } from '../../_lib/portalAuth.js';
import { clearTdCatalogCache, rebuildTdCatalog } from '../../_lib/tdCatalog.js';

export default async function handler(req, res) {
  if (handlePreflight(req, res)) return;
  setCors(req, res);

  const actor = await requirePortalAccess(req, res, { tile: 'td', write: true });
  if (!actor) return;

  if (normalizeRole(actor.role) !== PORTAL_ROLES.superuser) {
    return bad(res, 'forbidden', 403);
  }

  if (req.method !== 'POST') return bad(res, 'method not allowed', 405);

  const debugId = `td_rebuild_${Date.now().toString(36)}`;
  const startedAt = Date.now();
  try {
    const meta = await rebuildTdCatalog();
    await clearTdCatalogCache();
    const totalMs = Date.now() - startedAt;
    console.info('[td/catalog/rebuild] ok', {
      debugId,
      totalMs,
      catalogRows: meta.catalogRows,
      parsedRows: meta.parsedRows,
      sourceHash: meta.sourceHash,
      actor: actor.email || actor.id || null,
    });
    return ok(res, { ok: true, meta: { ...meta, totalMs }, debugId });
  } catch (err) {
    const totalMs = Date.now() - startedAt;
    console.error('[td/catalog/rebuild] failed', {
      debugId,
      totalMs,
      message: err?.message || String(err),
    });
    return bad(res, 'td catalog rebuild failed', 500, { debugId });
  }
}
