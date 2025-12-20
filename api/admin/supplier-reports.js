// /api/admin/supplier-reports.js – Exporte Lieferantenbewertung
export const config = { runtime: 'nodejs' };

import PDFDocument from 'pdfkit';
import { handlePreflight, setCors, ok, bad, readJson } from '../_lib/http.js';
import { requirePortalAccess } from './_guard.js';
import {
  supplierEvaluationAll,
  supplierEscalationAll,
  supplierAll,
} from '../_lib/store.js';

const SUPPLIER_TILE = 'supplierEvaluation';

function toCsv(rows) {
  const escape = (value) => {
    const str = String(value ?? '');
    if (str.includes(',') || str.includes('"') || str.includes('\n')) {
      return `"${str.replace(/"/g, '""')}"`;
    }
    return str;
  };
  return rows.map((row) => row.map(escape).join(',')).join('\n');
}

async function buildCsvReport() {
  const evaluations = await supplierEvaluationAll();
  const escalations = await supplierEscalationAll();
  const ratingFor = (entry) => {
    const total = Number(entry.aggregates?.totalScore || 0);
    const thresholds = entry.configSnapshot?.thresholds || {};
    const green = Number(thresholds.green || 0);
    const yellow = Number(thresholds.yellow || 0);
    const red = Number(thresholds.red || 0);
    if (green && total >= green) return 'grün';
    if (yellow && total >= yellow) return 'gelb';
    if (red && total > 0) return 'rot';
    return '';
  };
  const header = ['supplier', 'year', 'score total', 'rating', 'decision', 'escalations count'];
  const escalationCounts = new Map();
  for (const esc of escalations) {
    escalationCounts.set(esc.supplierId, (escalationCounts.get(esc.supplierId) || 0) + 1);
  }
  const rows = [header];
  for (const evalEntry of evaluations) {
    rows.push([
      evalEntry.supplierId,
      evalEntry.evalYear,
      evalEntry.aggregates?.totalScore ?? '',
      ratingFor(evalEntry),
      evalEntry.decision ?? '',
      escalationCounts.get(evalEntry.supplierId) || 0,
    ]);
  }
  return toCsv(rows);
}

async function buildPdfReport({ supplierId } = {}) {
  const evaluations = await supplierEvaluationAll({ supplierId });
  const suppliers = await supplierAll();
  const supplierLookup = new Map(suppliers.map((s) => [s.id, s]));

  const doc = new PDFDocument({ size: 'A4', margin: 48 });
  const chunks = [];
  doc.on('data', (d) => chunks.push(d));

  doc.fontSize(18).text('Lieferantenbewertung – Jahresübersicht', { align: 'left' });
  doc.moveDown(0.5);
  doc.fontSize(11).fillColor('#555').text(`Generiert am ${new Date().toLocaleDateString('de-DE')}`);
  doc.moveDown();

  if (evaluations.length === 0) {
    doc.fillColor('#000').text('Keine Bewertungen vorhanden.');
  }

  evaluations.forEach((evalEntry, idx) => {
    const supplier = supplierLookup.get(evalEntry.supplierId);
    if (idx > 0) doc.addPage();
    doc.fontSize(14).fillColor('#000').text(`Lieferant: ${supplier?.name || evalEntry.supplierId}`);
    doc.fontSize(11).text(`Bewertungsjahr: ${evalEntry.evalYear}`);
    doc.text(`Entscheidung: ${evalEntry.decision || '—'}`);
    doc.text(`Gesamtscore: ${evalEntry.aggregates?.totalScore ?? '—'}`);
    doc.moveDown(0.5);
    doc.text('Kategorien:');
    const categories = evalEntry.aggregates?.categoryScores || {};
    Object.entries(categories).forEach(([name, values]) => {
      doc.text(`• ${name}: ${values.avgPoints} Punkte (gewichtet ${values.weightedScore})`);
    });
    if (evalEntry.commentEk || evalEntry.commentQm) {
      doc.moveDown(0.5);
      doc.text(`Kommentar EK: ${evalEntry.commentEk || '—'}`);
      doc.text(`Kommentar QM: ${evalEntry.commentQm || '—'}`);
    }
  });

  doc.end();
  return await new Promise((resolve) => {
    doc.on('end', () => resolve(Buffer.concat(chunks)));
  });
}

export default async function handler(req, res) {
  if (handlePreflight(req, res)) return;
  setCors(req, res);

  const wantsWrite = ['POST'].includes(req.method);
  const actor = await requirePortalAccess(req, res, { tile: SUPPLIER_TILE, write: wantsWrite });
  if (!actor) return;

  try {
    const { format, supplierId } = req.query || {};
    if (format === 'csv') {
      const csv = await buildCsvReport();
      res.statusCode = 200;
      res.setHeader('Content-Type', 'text/csv; charset=utf-8');
      res.setHeader('Content-Disposition', 'attachment; filename="supplier_evaluations.csv"');
      res.end(csv);
      return;
    }
    if (format === 'pdf') {
      const pdf = await buildPdfReport({ supplierId });
      res.statusCode = 200;
      res.setHeader('Content-Type', 'application/pdf');
      res.setHeader('Content-Disposition', 'attachment; filename="supplier_evaluations.pdf"');
      res.end(pdf);
      return;
    }
    if (req.method === 'POST') {
      const body = readJson(req) || {};
      if (body?.format === 'csv') {
        const csv = await buildCsvReport();
        return ok(res, { ok: true, csv });
      }
    }
    return bad(res, 'Bitte ein gültiges Exportformat angeben.', 400);
  } catch (err) {
    console.error('[admin/supplier-reports] failed', err);
    return bad(res, 'Export konnte nicht erstellt werden.', 500);
  }
}
