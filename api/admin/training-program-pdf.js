// /api/admin/training-program-pdf.js – PDF-Export für Jahresprogramme
export const config = { runtime: 'nodejs' };

import { handlePreflight, setCors, bad, methodNotAllowed } from '../_lib/http.js';
import { requireTrainingScopeAccess } from './_guard.js';
import { trainingProgramsAll, trainingRecordsAll } from '../_lib/store.js';
import { createTrainingProgramPdf } from '../_lib/trainingPdf.js';

const TRAINING_TILE = 'trainingProgram';

export default async function handler(req, res) {
  if (handlePreflight(req, res)) return;
  setCors(req, res);

  const actor = await requireTrainingScopeAccess(req, res, { tile: TRAINING_TILE, write: false });
  if (!actor) return;

  if (req.method !== 'GET') return methodNotAllowed(res);

  const year = Number(req.query?.year || 0);
  if (!year) return bad(res, 'year missing', 400);

  const programs = await trainingProgramsAll();
  const items = programs.filter((entry) => entry.year === year);
  if (!items.length) return bad(res, 'not found', 404);

  try {
    const trainings = (await trainingRecordsAll()).filter((entry) => entry.year === year && !entry.deletedAt);
    const filename = `Schulungsprogramm-${year}.pdf`;
    const chunks = [];
    const doc = createTrainingProgramPdf(items, trainings, { year, finalize: false });

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
    console.error('[admin/training-program-pdf] generation failed', err);
    if (!res.headersSent) return bad(res, 'failed to generate', 500);
    res.end();
  }
}
