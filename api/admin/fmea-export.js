// /api/admin/fmea-export.js – Export als PDF oder CSV
export const config = { runtime: 'nodejs' };

import PDFDocument from 'pdfkit';
import { handlePreflight, setCors, bad } from '../_lib/http.js';
import { requirePortalAccess } from './_guard.js';
import { fmeaGet } from '../_lib/store.js';

const FMEA_TILE = 'fmea';

function riskColumns() {
  return [
    { key: 'category', label: 'Kategorie', width: 80 },
    { key: 'riskNumber', label: 'Risiko-Nr.', width: 70 },
    { key: 'hazard', label: 'Gefährdung', width: 120 },
    { key: 'hazardSituation', label: 'Gefährdungssituation', width: 120 },
    { key: 'harm', label: 'Schaden', width: 90 },
    { key: 'causes', label: 'Ursachen', width: 100 },
    { key: 'affectedArea', label: 'Gefährdeter Bereich', width: 110 },
    { key: 'processReference', label: 'Prozessbezug', width: 80 },
    { key: 'severity', label: 'S', width: 20 },
    { key: 'occurrence', label: 'A', width: 20 },
    { key: 'riskScore', label: 'S×A', width: 32 },
    { key: 'riskLevel', label: 'Einstufung', width: 55 },
    { key: 'proposedAction', label: 'Vorgeschlagene Maßnahme', width: 120 },
    { key: 'actionTaken', label: 'Getroffene Maßnahme', width: 120 },
    { key: 'documents', label: 'Nachweise / Dokumente', width: 100 },
    { key: 'severityAfter', label: 'S(n)', width: 24 },
    { key: 'occurrenceAfter', label: 'A(n)', width: 24 },
    { key: 'riskScoreAfter', label: 'S×A (n)', width: 40 },
    { key: 'riskLevelAfter', label: 'Einstufung (n)', width: 65 },
    { key: 'newHazard', label: 'Neue Gefährdung?', width: 70 },
    { key: 'residualRiskOk', label: 'Restrisiko beherrschbar?', width: 90 },
    { key: 'riskBenefitAnalysis', label: 'Risiko-Nutzen-Analyse', width: 120 },
  ];
}

function riskToRow(risk = {}) {
  return riskColumns().map((c) => {
    const val = risk[c.key];
    if (c.key === 'newHazard' || c.key === 'residualRiskOk') return val ? 'Ja' : 'Nein';
    return val == null ? '' : String(val);
  });
}

function createCsv(fmea) {
  const header = [
    'MDR-TD',
    'Produktgruppe',
    'Medizinprodukt',
    'Moderator',
    'Revision',
    'PRRC-Name',
    'PRRC-Datum',
  ];
  const lines = [];
  lines.push([...header, ...riskColumns().map((c) => c.label)].join(';'));
  for (const risk of fmea.risks || []) {
    const meta = [
      fmea.mdrTd || '',
      fmea.productGroup || '',
      fmea.medicalProduct || '',
      fmea.moderator || '',
      fmea.revision || '',
      fmea.prrcName || '',
      fmea.prrcDate ? new Date(fmea.prrcDate).toISOString().slice(0, 10) : '',
    ];
    lines.push([...meta, ...riskToRow(risk)].join(';'));
  }
  return lines.join('\n');
}

function writeTableHeader(doc, cols, startY) {
  doc.fontSize(9).fillColor('black');
  let x = doc.page.margins.left;
  cols.forEach((c) => {
    doc.text(c.label, x, startY, { width: c.width, continued: false, lineBreak: false });
    x += c.width + 6;
  });
  doc.moveTo(doc.page.margins.left, startY + 14)
    .lineTo(doc.page.width - doc.page.margins.right, startY + 14)
    .stroke();
}

function renderPdf(fmea) {
  return new Promise((resolve) => {
    const doc = new PDFDocument({ layout: 'landscape', size: 'A4', margin: 32 });
    const chunks = [];
    doc.on('data', (d) => chunks.push(d));
    doc.on('end', () => resolve(Buffer.concat(chunks)));

    const cols = riskColumns();
    const startY = 90;

    // Kopfbereich
    doc.fontSize(18).text('FMEA', { align: 'left' });
    doc.fontSize(12).text(`MDR-TD: ${fmea.mdrTd || '—'}`);
    doc.text(`Produktgruppe: ${fmea.productGroup || '—'}`);
    doc.text(`Revision: ${fmea.revision || '—'} | Moderator: ${fmea.moderator || '—'}`);
    doc.text(`PRRC: ${fmea.prrcName || '—'} ${fmea.prrcDate ? '(' + new Date(fmea.prrcDate).toLocaleDateString('de-DE') + ')' : ''}`);

    writeTableHeader(doc, cols, startY);
    let y = startY + 18;

    const rowHeight = 32;
    for (const risk of fmea.risks || []) {
      if (y + rowHeight > doc.page.height - doc.page.margins.bottom) {
        doc.addPage({ layout: 'landscape' });
        writeTableHeader(doc, cols, doc.y + 10);
        y = doc.y + 24;
      }
      let x = doc.page.margins.left;
      const row = riskToRow(risk);
      cols.forEach((c, idx) => {
        doc.fontSize(9).text(row[idx], x, y, { width: c.width, height: rowHeight, ellipsis: true });
        x += c.width + 6;
      });
      y += rowHeight;
    }

    doc.end();
  });
}

export default async function handler(req, res) {
  if (handlePreflight(req, res)) return;
  setCors(req, res);
  const actor = await requirePortalAccess(req, res, { tile: FMEA_TILE, write: false });
  if (!actor) return;

  const id = req.query?.id;
  const format = (req.query?.format || 'pdf').toString().toLowerCase();
  if (!id) return bad(res, 'id missing', 400);

  try {
    const fmea = await fmeaGet(id);
    if (!fmea) return bad(res, 'not found', 404);

    if (format === 'csv' || format === 'excel') {
      const csv = createCsv(fmea);
      res.setHeader('Content-Type', 'text/csv; charset=utf-8');
      res.setHeader('Content-Disposition', `attachment; filename="fmea_${fmea.mdrTd || 'export'}.csv"`);
      return res.status(200).send(csv);
    }

    const pdf = await renderPdf(fmea);
    res.setHeader('Content-Type', 'application/pdf');
    res.setHeader('Content-Disposition', `attachment; filename="fmea_${fmea.mdrTd || 'export'}.pdf"`);
    return res.status(200).send(pdf);
  } catch (err) {
    console.error('[admin/fmea-export] error', err);
    return bad(res, 'server error', 500);
  }
}
