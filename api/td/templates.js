export const config = { runtime: 'nodejs' };
import { handlePreflight, setCors, ok, bad } from '../_lib/http.js';
import { requirePortalAccess } from '../admin/_guard.js';
import { tdNodeTemplates } from '../_lib/tdStore.js';

export default async function handler(req, res) {
  if (handlePreflight(req, res)) return;
  setCors(req, res);
  const actor = await requirePortalAccess(req, res, { tile: 'td', write: false });
  if (!actor) return;
  if (req.method !== 'GET') return bad(res, 'method not allowed', 405);
  const sectionTemplateKey = req.query?.sectionTemplateKey ? String(req.query.sectionTemplateKey) : null;
  return ok(res, { ok: true, items: tdNodeTemplates(sectionTemplateKey) });
}
