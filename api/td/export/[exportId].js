export const config = { runtime: 'nodejs' };
import { handlePreflight, setCors, bad } from '../../_lib/http.js';
import { requirePortalAccess } from '../../admin/_guard.js';
import { tdExportGet } from '../../_lib/tdStore.js';

export default async function handler(req, res) {
  if (handlePreflight(req, res)) return;
  setCors(req, res);
  const actor = await requirePortalAccess(req, res, { tile: 'td', write: false });
  if (!actor) return;
  if (req.method !== 'GET') return bad(res, 'method not allowed', 405);
  const exportId = String(req.query?.exportId || '').trim();
  if (!exportId) return bad(res, 'exportId is required', 400);
  const item = await tdExportGet(exportId);
  if (!item?.pdfBase64) return bad(res, 'not found', 404);
  const pdf = Buffer.from(item.pdfBase64, 'base64');
  res.statusCode = 200;
  res.setHeader('Content-Type', 'application/pdf');
  res.setHeader('Content-Disposition', `attachment; filename="nb-package-${item.tdId}.pdf"`);
  res.end(pdf);
}
