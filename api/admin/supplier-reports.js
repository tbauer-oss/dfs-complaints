// /api/admin/supplier-reports.js – Exporte Lieferantenbewertung
export const config = { runtime: 'nodejs' };

import PDFDocument from 'pdfkit';
import path from 'path';
import { handlePreflight, setCors, ok, bad, readJson } from '../_lib/http.js';
import { requirePortalAccess } from './_guard.js';
import {
  supplierEvaluationAll,
  supplierEscalationAll,
  supplierAll,
  supplierPerformanceAll,
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

async function buildSummaryPdf() {
  const evaluations = await supplierEvaluationAll();
  const suppliers = await supplierAll();
  const supplierLookup = new Map(suppliers.map((s) => [s.id, s]));

  const doc = new PDFDocument({ size: 'A4', margin: 48 });
  const chunks = [];
  doc.on('data', (d) => chunks.push(d));

  drawHeader(doc, 'Lieferantenbewertung – Jahresübersicht');

  if (evaluations.length === 0) {
    doc.fillColor('#000').text('Keine Bewertungen vorhanden.');
  }

  evaluations.forEach((evalEntry, idx) => {
    const supplier = supplierLookup.get(evalEntry.supplierId);
    if (idx > 0) doc.addPage();
    doc.fontSize(14).fillColor('#000').text(`Lieferant: ${supplier?.name || evalEntry.supplierId}`);
    doc.fontSize(11).text(`Bewertungsjahr: ${evalEntry.evalYear}`);
    doc.text(`Entscheidung: ${evalEntry.decision || '—'}`);
    doc.text(`Gesamtscore: ${evalEntry.aggregates?.averageGrade ?? evalEntry.aggregates?.totalScore ?? '—'}`);
    doc.moveDown(0.5);
    doc.text('Kriterien:');
    const categories = evalEntry.aggregates?.criterionAverages || {};
    if (Array.isArray(categories)) {
      categories.forEach((entry) => {
        doc.text(`• ${entry.label || entry.key}: ${entry.average ?? '—'}`);
      });
    }
  });

  doc.end();
  return await new Promise((resolve) => {
    doc.on('end', () => resolve(Buffer.concat(chunks)));
  });
}

const PERFORMANCE_CRITERIA = [
  { key: 'communication', label: 'Kommunikation', weight: 0.1 },
  { key: 'quality', label: 'Produktqualität', weight: 0.4 },
  { key: 'delivery', label: 'Einhaltung der Lieferfrist', weight: 0.2 },
  { key: 'price', label: 'Preis korrekt', weight: 0.1 },
  { key: 'quantity', label: 'Richtige Mengen/Produkte', weight: 0.1 },
  { key: 'backorders', label: 'Nachlieferungen', weight: 0.1 },
];

function entryGrade(entry) {
  const ratings = entry?.ratings || {};
  const parts = PERFORMANCE_CRITERIA.map(({ key, weight }) => {
    const value = ratings[key];
    return Number.isFinite(value) ? value * weight : null;
  });
  if (parts.some((value) => value == null)) return null;
  return Number(parts.reduce((sum, value) => sum + value, 0).toFixed(2));
}

function classify(avg) {
  if (!Number.isFinite(avg)) return '';
  if (avg <= 1.5) return 'A';
  if (avg <= 2.0) return 'B';
  if (avg <= 2.5) return 'C';
  return 'D';
}

function decisionFor(classification) {
  if (classification === 'A' || classification === 'B') return 'weiterhin zugelassen';
  if (classification === 'C') return 'in Beobachtung';
  if (classification === 'D') return 'gesperrt / nicht zugelassen';
  return '';
}

function buildAggregates(entries) {
  const graded = entries
    .map((entry) => ({
      entry,
      grade: entry.computedGrade ?? entryGrade(entry),
    }))
    .filter((item) => Number.isFinite(item.grade));
  const avg = graded.length ? graded.reduce((sum, item) => sum + item.grade, 0) / graded.length : null;
  const classification = classify(avg);
  const decision = decisionFor(classification);
  const criterionAverages = PERFORMANCE_CRITERIA.map((criterion) => {
    const values = graded
      .map((item) => item.entry?.ratings?.[criterion.key])
      .filter((value) => Number.isFinite(value));
    const avgValue = values.length ? values.reduce((sum, value) => sum + value, 0) / values.length : null;
    return {
      ...criterion,
      average: avgValue == null ? null : Number(avgValue.toFixed(2)),
    };
  });
  const topNegativeDrivers = [...criterionAverages]
    .filter((item) => Number.isFinite(item.average))
    .sort((a, b) => (b.average ?? 0) - (a.average ?? 0))
    .slice(0, 2);
  return {
    averageGrade: avg == null ? null : Number(avg.toFixed(2)),
    classification,
    decision,
    criterionAverages,
    topNegativeDrivers,
    totalEntries: entries.length,
    gradedEntries: graded.length,
    evidence: entries.map((entry) => ({
      id: entry.id,
      date: entry.date,
      referenceType: entry.referenceType,
      referenceNumber: entry.referenceNumber,
      description: entry.description,
      status: entry.status,
      grade: entry.computedGrade ?? entryGrade(entry),
    })),
  };
}

function formatDate(dateValue, locale = 'de-DE') {
  if (!dateValue) return '—';
  return new Date(dateValue).toLocaleDateString(locale);
}

function drawHeader(doc, title) {
  doc.fontSize(16).fillColor('#000').text(title, { align: 'left' });
  doc.moveDown(0.4);
  doc.fontSize(10).fillColor('#555').text(`Generiert am ${formatDate(Date.now())}`);
  doc.moveDown();
}

async function buildInternalPdf({ supplierId, year, actor }) {
  const suppliers = await supplierAll();
  const supplierLookup = new Map(suppliers.map((s) => [s.id, s]));
  const entries = await supplierPerformanceAll({ supplierId });
  const filtered = entries.filter((entry) => {
    if (!entry.includeInAnnual || entry.status !== 'ABGESCHLOSSEN' || entry.deletedAt) return false;
    if (Number.isFinite(year)) {
      const entryYear = new Date(entry.date).getFullYear();
      return entryYear === Number(year);
    }
    return true;
  });
  const aggregates = buildAggregates(filtered);
  const supplier = supplierLookup.get(supplierId) || {};

  const doc = new PDFDocument({ size: 'A4', margin: 48 });
  const chunks = [];
  doc.on('data', (d) => chunks.push(d));
  drawHeader(doc, `Lieferantenbewertung – Jahresbewertung ${year || ''}`.trim());

  doc.fontSize(12).fillColor('#000').text(`Lieferant: ${supplier.name || supplierId}`);
  doc.fontSize(10)
    .fillColor('#555')
    .text(`Lieferantennummer: ${supplier.supplierNumber || '—'}`)
    .text(`Adresse: ${supplier.address || '—'}`)
    .text(`Kontakt: ${supplier.contactName || '—'}`)
    .text(`E-Mail: ${supplier.contactEmail || '—'}`)
    .text(`Kritisch: ${supplier.critical ? 'Ja' : 'Nein'}`)
    .text(`Korrespondenzsprache: ${supplier.correspondenceLanguage || 'DE'}`);
  doc.moveDown();

  doc.fontSize(12).fillColor('#000').text('Gesamtbewertung');
  doc.fontSize(10).fillColor('#333').text(`Einträge berücksichtigt: ${aggregates.gradedEntries}`);
  doc.text(`Durchschnittsnote: ${aggregates.averageGrade ?? '—'}`);
  doc.text(`Klassifikation: ${aggregates.classification || '—'}`);
  doc.text(`Entscheidung: ${aggregates.decision || '—'}`);
  doc.moveDown();

  doc.fontSize(11).fillColor('#000').text('Kriterien (Durchschnitt)');
  aggregates.criterionAverages.forEach((criterion) => {
    doc.fontSize(10).fillColor('#333').text(`${criterion.label}: ${criterion.average ?? '—'}`);
  });
  doc.moveDown();

  doc.fontSize(11).fillColor('#000').text('Nachweise (Evidence)');
  if (!aggregates.evidence.length) {
    doc.fontSize(10).fillColor('#555').text('Keine Einträge vorhanden.');
  } else {
    aggregates.evidence.forEach((entry) => {
      doc
        .fontSize(9)
        .fillColor('#333')
        .text(
          `${formatDate(entry.date)} • ${entry.referenceType || 'Bezug'} ${entry.referenceNumber || ''} • ${entry.description} • Note ${entry.grade ?? '—'}`
        );
    });
  }
  doc.moveDown();
  doc.fontSize(9).fillColor('#555').text(`Erstellt von ${actor || 'System'} am ${new Date().toLocaleString('de-DE')}`);

  doc.end();
  return await new Promise((resolve) => {
    doc.on('end', () => resolve(Buffer.concat(chunks)));
  });
}

function addLetterHead(doc) {
  const logoPath = path.join(process.cwd(), 'api', '_assets', 'dfs-logo.png');
  try {
    doc.image(logoPath, 420, 40, { width: 120 });
  } catch (err) {
    doc.rect(420, 40, 120, 40).stroke('#999');
    doc.fontSize(8).fillColor('#999').text('TODO Logo', 430, 55);
  }
  doc.fontSize(9).fillColor('#333');
  doc.text('DFS DIAMON GmbH', 360, 100);
  doc.text('Max-Planck-Straße 11', 360, 112);
  doc.text('70771 Leinfelden-Echterdingen', 360, 124);
  doc.text('Tel. +49 711 902 010-0', 360, 136);
  doc.text('info@dfs-diamon.de', 360, 148);
  doc.text('www.dfs-diamon.de', 360, 160);

  doc.moveTo(48, 180).lineTo(547, 180).strokeColor('#999').stroke();
}

async function buildSupplierLetter({ supplierId, year, actor }) {
  const suppliers = await supplierAll();
  const supplierLookup = new Map(suppliers.map((s) => [s.id, s]));
  const entries = await supplierPerformanceAll({ supplierId });
  const filtered = entries.filter((entry) => {
    if (!entry.includeInAnnual || entry.status !== 'ABGESCHLOSSEN' || entry.deletedAt) return false;
    if (Number.isFinite(year)) {
      const entryYear = new Date(entry.date).getFullYear();
      return entryYear === Number(year);
    }
    return true;
  });
  const aggregates = buildAggregates(filtered);
  const supplier = supplierLookup.get(supplierId) || {};
  const language = supplier.correspondenceLanguage === 'EN' ? 'EN' : 'DE';

  const doc = new PDFDocument({ size: 'A4', margin: 48 });
  const chunks = [];
  doc.on('data', (d) => chunks.push(d));

  addLetterHead(doc);

  doc.fontSize(10).fillColor('#333');
  doc.text('Our ref: DFS-QM-LE', 48, 195);
  doc.text('From: Tobias Bauer (PRRC)', 48, 210);
  doc.text(`Date: ${formatDate(Date.now(), language === 'EN' ? 'en-US' : 'de-DE')}`, 48, 225);

  doc.fontSize(11).fillColor('#000');
  doc.text(supplier.name || supplierId, 48, 250);
  if (supplier.address) {
    doc.fontSize(10).fillColor('#333').text(supplier.address, 48, 265);
  }

  doc.moveDown(8);
  doc.fontSize(12).fillColor('#000').text(
    language === 'EN'
      ? `Supplier Evaluation ${year || ''} – Status`
      : `Lieferantenbewertung ${year || ''} – Status`
  );
  doc.moveDown();

  const decision = aggregates.decision || decisionFor(aggregates.classification);
  const escalationNote =
    aggregates.classification === 'D'
      ? language === 'EN'
          ? '\nPlease note: escalation is required for this status.'
          : '\nHinweis: Für diesen Status ist eine Eskalation erforderlich.'
      : '';
  const bodyTextDe = `Sehr geehrte Damen und Herren,

im Rahmen unserer Lieferantenbewertung für das Jahr ${year || ''} haben wir die Leistung Ihres Unternehmens bewertet. Das Ergebnis lautet: ${decision}.

Bitte entnehmen Sie die wesentlichen Kennzahlen der untenstehenden Zusammenfassung. Bei Rückfragen stehen wir gerne zur Verfügung.
${escalationNote}`;
  const bodyTextEn = `Dear Supplier,

as part of our supplier evaluation for ${year || ''}, we assessed your overall performance. The result is: ${decision}.

Please find the key figures in the summary below. If you have questions, feel free to contact us.
${escalationNote}`;
  doc.fontSize(11).fillColor('#333').text(language === 'EN' ? bodyTextEn : bodyTextDe, {
    align: 'left',
  });

  doc.moveDown();
  doc.rect(48, doc.y, 500, 70).stroke('#ccc');
  const boxTop = doc.y + 8;
  doc.fontSize(10).fillColor('#000').text(`Ø Note: ${aggregates.averageGrade ?? '—'}`, 60, boxTop);
  doc.text(`Klassifikation: ${aggregates.classification || '—'}`, 60, boxTop + 14);
  doc.text(`Entscheidung: ${decision || '—'}`, 60, boxTop + 28);
  doc.text(
    `Top Treiber: ${aggregates.topNegativeDrivers.map((d) => d.label).join(', ') || '—'}`,
    60,
    boxTop + 42
  );
  doc.moveDown(6);

  doc.fontSize(11).fillColor('#333').text(
    language === 'EN'
      ? 'Best regards,\n\nTobias Bauer (PRRC)'
      : 'Mit freundlichen Grüßen,\n\nTobias Bauer (PRRC)'
  );

  doc.moveDown();
  doc.fontSize(8).fillColor('#777').text(`Generated by ${actor || 'System'} on ${new Date().toLocaleString()}`);

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
      const reportType = req.query?.type || 'internal';
      const year = req.query?.year ? Number(req.query.year) : null;
      const actorName = actor?.email || '';
      if (!supplierId && reportType !== 'summary') {
        return bad(res, 'Bitte einen Lieferanten auswählen.', 400);
      }
      const pdf =
        reportType === 'letter'
          ? await buildSupplierLetter({ supplierId, year, actor: actorName })
          : reportType === 'summary'
              ? await buildSummaryPdf()
              : await buildInternalPdf({ supplierId, year, actor: actorName });
      console.info('[supplier-reports] pdf generated', { type: reportType, supplierId, year });
      res.statusCode = 200;
      res.setHeader('Content-Type', 'application/pdf');
      res.setHeader(
        'Content-Disposition',
        `attachment; filename="${reportType === 'letter' ? 'lieferantenbrief' : 'lieferantenbewertung'}_${year || 'report'}.pdf"`
      );
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
