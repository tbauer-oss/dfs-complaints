// /api/training/program/pdf.js – PDF Export for training program list
export const config = { runtime: 'nodejs' };

import { bad, methodNotAllowed } from '../../_lib/http.js';
import { withCorsHandler } from '../../_lib/http.js';
import { requireTrainingScopeAccess } from '../../admin/_guard.js';
import { trainingProgramsAll, trainingRecordsAll } from '../../_lib/store.js';
import { createTrainingProgramPdf } from '../../_lib/trainingPdf.js';

const TRAINING_TILE = 'trainingProgram';

function normalize(text) {
  return `${text || ''}`.trim().toLowerCase();
}

function matchesSearch(item, query) {
  if (!query) return true;
  const hay = [
    item.title,
    item.trainingTitle,
    item.trainerProvider,
    item.responsiblePerson,
    item.owner,
  ]
    .filter(Boolean)
    .join(' ')
    .toLowerCase();
  return hay.includes(query);
}

async function handler(req, res) {
  if (req.method === 'OPTIONS') return res.status(204).end();
  const actor = await requireTrainingScopeAccess(req, res, { tile: TRAINING_TILE, write: false });
  if (!actor) return;
  if (req.method !== 'GET') return methodNotAllowed(res);

  const year = Number(req.query?.year || 0);
  if (!year) return bad(res, 'year missing', 400);

  try {
    const filters = {
      year: year ? `${year}` : '',
      department: req.query?.department || '',
      status: req.query?.status || '',
      format: req.query?.format || '',
      search: req.query?.search || '',
    };

    const programs = (await trainingProgramsAll()).filter((entry) => entry.year === year);
    const query = normalize(filters.search);
    const filtered = programs.filter((entry) => {
      if (filters.department && entry.department !== filters.department) return false;
      if (filters.status && entry.status !== filters.status) return false;
      if (filters.format && entry.format !== filters.format) return false;
      return matchesSearch(entry, query);
    });

    const sort = normalize(req.query?.sort || '');
    const sorted = [...filtered].sort((a, b) => {
      if (sort === 'title') return a.title.localeCompare(b.title);
      if (sort === 'status') return a.status.localeCompare(b.status);
      return (a.plannedPeriodValue || '').localeCompare(b.plannedPeriodValue || '');
    });

    const allExecutions = (await trainingRecordsAll()).filter((entry) => entry.year === year && !entry.deletedAt);
    const executionIds = new Set(sorted.map((entry) => entry.id));
    const executions = allExecutions.filter((entry) => entry.linkedProgramId && executionIds.has(entry.linkedProgramId));

    const filename = `Schulungsprogramm-${year}.pdf`;
    const chunks = [];
    const doc = createTrainingProgramPdf(sorted, executions, { year, filters, finalize: false });

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
    console.error('[training/program/pdf] generation failed', err);
    if (!res.headersSent) return bad(res, 'failed to generate', 500);
    res.end();
  }
}

export default withCorsHandler(handler);
