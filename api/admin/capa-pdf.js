// /api/admin/capa-pdf.js – PDF-Export für CAPA / 8D-Reports
export const config = { runtime: 'nodejs' };

import { handlePreflight, setCors, bad, methodNotAllowed } from '../_lib/http.js';
import { requirePortalAccess } from './_guard.js';
import { capaGet } from '../_lib/store.js';
import { createCapaPdf } from '../_lib/capaPdf.js';

const CAPA_TILE = 'capaReports';

export default async function handler(req, res) {
  if (handlePreflight(req, res)) return;
  setCors(req, res);

  const actor = await requirePortalAccess(req, res, { tile: CAPA_TILE, write: false });
  if (!actor) return;

  if (req.method !== 'GET') return methodNotAllowed(res);

  const id = req.query?.id || req.query?.capaId || req.query?.capaNumber;
  if (!id) return bad(res, 'id missing', 400);

  const lang = (req.query?.lang || 'de').toString();

  const report = await capaGet(id);
  if (!report) return bad(res, 'not found', 404);

  try {
    const doc = createCapaPdf(report, { lang });
    const filename = `${report.capaNumber || report.id}.pdf`;
    res.setHeader('Content-Type', 'application/pdf');
    res.setHeader('Content-Disposition', `attachment; filename="${filename}"`);
    doc.pipe(res);
    doc.end();
  } catch (err) {
    console.error('[admin/capa-pdf] generation failed', err);
    return bad(res, 'failed to generate', 500);
  }
}
