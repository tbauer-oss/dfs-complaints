export const config = { runtime: 'nodejs' };
import { handlePreflight, setCors, ok, bad } from '../../../_lib/http.js';
import { requirePortalAccess } from '../../../admin/_guard.js';
import { tdNbExport } from '../../../_lib/tdStore.js';

export default async function handler(req, res) {
  if (handlePreflight(req, res)) return;
  setCors(req, res);
  const actor = await requirePortalAccess(req, res, { tile: 'td', write: false });
  if (!actor) return;
  if (req.method !== 'POST') return bad(res, 'method not allowed', 405);
  try {
    const id = String(req.query?.id || '').trim();
    const exportResult = await tdNbExport(id);
    return ok(res, { ok: true, export: exportResult, downloadUrl: null, status: exportResult.status });
  } catch (err) {
    return bad(res, err?.message || 'server error', 500);
  }
}
