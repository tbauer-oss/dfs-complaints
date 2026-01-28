// /api/admin/training-pdf.js – PDF-Export für einzelne Schulungen
export const config = { runtime: 'nodejs' };

import { handlePreflight, setCors, bad, methodNotAllowed } from '../_lib/http.js';
import { requirePortalAccess } from './_guard.js';
import { trainingRecordGet, trainingQuestionnairesAll, trainingQuestionnaireTemplatesAll } from '../_lib/store.js';
import { createTrainingPdf } from '../_lib/trainingPdf.js';

const TRAINING_TILE = 'trainings';

export default async function handler(req, res) {
  if (handlePreflight(req, res)) return;
  setCors(req, res);

  const actor = await requirePortalAccess(req, res, { tile: TRAINING_TILE, write: false });
  if (!actor) return;

  if (req.method !== 'GET') return methodNotAllowed(res);

  const id = `${req.query?.id || req.query?.number || ''}`.trim();
  if (!id) return bad(res, 'id missing', 400);

  const record = await trainingRecordGet(id);
  if (!record) return bad(res, 'not found', 404);

  try {
    const templates = await trainingQuestionnaireTemplatesAll();
    const questionnaires = (await trainingQuestionnairesAll()).filter((q) => q.trainingId === record.id);
    const filename = `${record.trainingNumber || record.id}.pdf`;
    const chunks = [];
    const doc = createTrainingPdf(record, { questionnaires, templates, finalize: false });

    await new Promise((resolve, reject) => {
      doc.on('data', (chunk) => chunks.push(chunk));
      doc.on('end', resolve);
      doc.on('error', reject);
      doc.end();
    });

    const buffer = Buffer.concat(chunks);
    res.statusCode = 200;
    res.setHeader('Content-Type', 'application/pdf');
    res.setHeader('Content-Disposition', `attachment; filename="${filename}"`);
    res.setHeader('Content-Length', buffer.length);
    res.end(buffer);
  } catch (err) {
    console.error('[admin/training-pdf] generation failed', err);
    if (!res.headersSent) return bad(res, 'failed to generate', 500);
    res.end();
  }
}
