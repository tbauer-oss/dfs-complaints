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
  { key: 'communication', label: 'Zusammenarbeit / Kommunikation', weight: 0.1 },
  { key: 'quality', label: 'Produktqualität', weight: 0.3 },
  { key: 'delivery', label: 'Einhaltung der Lieferfrist', weight: 0.15 },
  { key: 'price', label: 'Preis (Rechnung korrekt vs. AB/Angebot)', weight: 0.15 },
  { key: 'quantity', label: 'Fehllieferungen / Falschlieferungen', weight: 0.2 },
  { key: 'backorders', label: 'Nachlieferungen', weight: 0.1 },
];

function entryGrade(entry) {
  const ratings = entry?.ratings || {};
  const communicationNa = entry?.communicationNa === true;
  let total = 0;
  let weightTotal = 0;
  for (const { key, weight } of PERFORMANCE_CRITERIA) {
    const value = ratings[key];
    if (key === 'communication' && communicationNa && value == null) {
      continue;
    }
    if (!Number.isFinite(value)) return null;
    total += value * weight;
    weightTotal += weight;
  }
  if (!weightTotal) return null;
  return Number((total / weightTotal).toFixed(2));
}

function classify(avg) {
  if (!Number.isFinite(avg)) return '';
  if (avg <= 1.8) return 'A';
  if (avg <= 2.6) return 'B';
  if (avg <= 3.4) return 'C';
  if (avg <= 4.2) return 'D';
  if (avg <= 5.0) return 'E';
  return 'F';
}

function decisionFor(classification) {
  if (classification === 'A' || classification === 'B' || classification === 'C') return 'weiterhin zugelassen';
  if (classification === 'D') return 'in Beobachtung';
  if (classification === 'E' || classification === 'F') return 'gesperrt / nicht zugelassen';
  return '';
}

const RATING_SCALE = {
  DE: [
    'Note 1 = sehr gut / keine Abweichungen',
    'Note 2 = gut / geringe Abweichungen',
    'Note 3 = befriedigend / gelegentliche Abweichungen',
    'Note 4 = ausreichend / wiederkehrende Abweichungen, spürbarer Aufwand',
    'Note 5 = mangelhaft / häufige Abweichungen, deutlicher Aufwand/Eskalation',
    'Note 6 = ungenügend / schwerwiegend, sofortige Maßnahmen erforderlich',
  ],
  EN: [
    'Grade 1 = very good / no deviations',
    'Grade 2 = good / minor deviations',
    'Grade 3 = satisfactory / occasional deviations',
    'Grade 4 = sufficient / recurring deviations, noticeable effort',
    'Grade 5 = deficient / frequent deviations, clear effort/escalation',
    'Grade 6 = unsatisfactory / severe, immediate measures required',
  ],
};

const RATING_EXPLANATION = {
  DE: [
    {
      title: 'Zusammenarbeit / Kommunikation (Gewichtung 10 %)',
      lines: [
        '1: Reagiert zeitnah und zuverlässig ohne Erinnerung (oder N/A bei keiner Anfrage)',
        '2: Reaktion erst nach einmaliger Nachfrage',
        '3: Mehrmalige Nachfragen erforderlich, Verzögerungen beeinträchtigen Abläufe',
        '4: Häufig verspätete/unklare Rückmeldungen, merkliche Prozessstörungen',
        '5: Kommunikation regelmäßig unzureichend, Eskalation intern erforderlich',
        '6: Keine oder unzureichende Rückmeldungen trotz mehrfacher Kontaktversuche',
      ],
    },
    {
      title: 'Produktqualität (Gewichtung 30 %)',
      lines: [
        '1: Keine qualitätsrelevanten Beanstandungen im Bewertungszeitraum',
        '2: Vereinzelte, geringfügige Beanstandungen ohne systematische Ursache',
        '3: Wiederkehrende geringere Beanstandungen / moderate Abweichungen mit Nacharbeit',
        '4: Wiederkehrende relevante Abweichungen, erheblicher Prüf-/Nacharbeitsaufwand',
        '5: Häufige Qualitätsmängel, formale Eskalation erforderlich',
        '6: Schwerwiegende/häufige Qualitätsmängel, CAPA zwingend erforderlich',
      ],
    },
    {
      title: 'Einhaltung der Lieferfrist (Gewichtung 15 %)',
      lines: [
        '1: Liefertermine werden zuverlässig eingehalten',
        '2: Gelegentliche Verzögerungen mit frühzeitiger Information',
        '3: Wiederholte Verzögerungen, begrenzte Auswirkungen auf Planung',
        '4: Wiederholte Verzögerungen mit deutlichen Auswirkungen auf interne Planung',
        '5: Regelmäßige Lieferverzüge, Maßnahmen/Eskalation erforderlich',
        '6: Erhebliche oder dauerhafte Lieferverzüge ohne angemessene Kommunikation',
      ],
    },
    {
      title: 'Preis (Rechnung korrekt vs. AB/Angebot) (Gewichtung 15 %)',
      lines: [
        '1: Rechnungen stets korrekt und vertragskonform',
        '2: Einzelne formale Fehler ohne finanzielle Auswirkung',
        '3: Gelegentliche Abweichungen, Korrekturaufwand gering',
        '4: Wiederkehrende Rechnungsfehler mit Korrekturaufwand',
        '5: Häufige Abweichungen, finanzielle/operative Klärung nötig',
        '6: Schwerwiegende oder wiederholte Abrechnungsfehler, Eskalation erforderlich',
      ],
    },
    {
      title: 'Fehllieferungen / Falschlieferungen (Gewichtung 20 %)',
      lines: [
        '1: Lieferungen vollständig und korrekt',
        '2: Vereinzelte Abweichungen ohne relevante Auswirkungen',
        '3: Gelegentliche Mengen-/Artikelfehler mit Korrekturaufwand',
        '4: Wiederkehrende Mengen- oder Artikelfehler, Prozessaufwand deutlich',
        '5: Häufige Falschlieferungen / gravierende Abweichungen, Eskalation nötig',
        '6: Regelmäßig gravierende Falschlieferungen, Versorgung/Produktion gefährdet',
      ],
    },
    {
      title: 'Nachlieferungen (Gewichtung 10 %)',
      lines: [
        '1: Bestellungen werden vollständig geliefert',
        '2: Gelegentliche Teillieferungen ohne Beeinträchtigung',
        '3: Wiederkehrende Teillieferungen mit moderatem Planungsaufwand',
        '4: Regelmäßige Nachlieferungen mit spürbarem Planungsaufwand',
        '5: Häufige oder umfangreiche Nachlieferungen, Eskalation erforderlich',
        '6: Sehr häufige/umfangreiche Nachlieferungen, erhebliche Beeinträchtigung',
      ],
    },
  ],
  EN: [
    {
      title: 'Collaboration / Communication (Weighting 10%)',
      lines: [
        '1: Responds promptly and reliably without reminder (or N/A if no request occurred)',
        '2: Response only after a single follow-up',
        '3: Multiple follow-ups required; delays affect workflows',
        '4: Frequent late/unclear responses, noticeable process disruptions',
        '5: Communication regularly insufficient; internal escalation required',
        '6: No or insufficient responses despite repeated contact attempts',
      ],
    },
    {
      title: 'Product quality (Weighting 30%)',
      lines: [
        '1: No quality-related complaints in the assessment period',
        '2: Isolated, minor complaints without systematic cause',
        '3: Recurring minor complaints / moderate deviations with rework',
        '4: Recurring relevant deviations with significant inspection/rework effort',
        '5: Frequent quality defects; formal escalation required',
        '6: Severe/frequent quality defects; CAPA mandatory',
      ],
    },
    {
      title: 'Delivery reliability (Weighting 15%)',
      lines: [
        '1: Delivery dates are reliably met',
        '2: Occasional delays with early notification',
        '3: Repeated delays with limited impact on planning',
        '4: Repeated delays with clear impact on internal planning',
        '5: Regular delivery delays; measures/escalation required',
        '6: Significant or ongoing delays without adequate communication',
      ],
    },
    {
      title: 'Price (invoice vs. order/offer) (Weighting 15%)',
      lines: [
        '1: Invoices always correct and contract-compliant',
        '2: Isolated formal errors without financial impact',
        '3: Occasional deviations; low correction effort',
        '4: Recurring billing errors with correction effort',
        '5: Frequent deviations; financial/operational clarification needed',
        '6: Severe or repeated billing errors; escalation required',
      ],
    },
    {
      title: 'Wrong deliveries (Weighting 20%)',
      lines: [
        '1: Deliveries complete and correct',
        '2: Isolated deviations without relevant impact',
        '3: Occasional quantity/item errors with correction effort',
        '4: Recurring quantity or item errors; clear process effort',
        '5: Frequent wrong deliveries/major deviations; escalation required',
        '6: Regular severe wrong deliveries; supply/production at risk',
      ],
    },
    {
      title: 'Backorders (Weighting 10%)',
      lines: [
        '1: Orders delivered in full',
        '2: Occasional partial deliveries without impact',
        '3: Recurring partial deliveries with moderate planning effort',
        '4: Regular backorders with noticeable planning effort',
        '5: Frequent or extensive backorders; escalation required',
        '6: Very frequent/extensive backorders; significant impact',
      ],
    },
  ],
};

function drawCriteriaOverview(doc, language) {
  doc.fontSize(11).fillColor('#000').text(language === 'EN' ? 'Criteria & weights' : 'Bewertungskriterien & Gewichte');
  PERFORMANCE_CRITERIA.forEach((criterion) => {
    doc
      .fontSize(9)
      .fillColor('#333')
      .text(`• ${criterion.label} (${Math.round(criterion.weight * 100)}%)`);
  });
  doc.moveDown(0.5);
}

function drawRatingSystem(doc, language) {
  const scale = language === 'EN' ? RATING_SCALE.EN : RATING_SCALE.DE;
  doc.fontSize(11).fillColor('#000').text(language === 'EN' ? 'Rating system' : 'Bewertungssystem');
  doc.fontSize(9).fillColor('#333').text(
    language === 'EN'
      ? 'Grades: 1 = very good … 6 = unsatisfactory. Lower is better.'
      : 'Noten: 1=sehr gut … 6=ungenügend. Niedriger ist besser.'
  );
  scale.forEach((line) => {
    doc.fontSize(8).fillColor('#555').text(line);
  });
  doc.moveDown(0.5);
}

function drawCriteriaDefinitions(doc, language) {
  const content = language === 'EN' ? RATING_EXPLANATION.EN : RATING_EXPLANATION.DE;
  doc.fontSize(11).fillColor('#000').text(
    language === 'EN' ? 'Criteria & grade definitions' : 'Kriterien & Notendefinitionen'
  );
  content.forEach((section) => {
    doc.fontSize(9).fillColor('#333').text(section.title);
    section.lines.forEach((line) => {
      doc.fontSize(8).fillColor('#555').text(line);
    });
    doc.moveDown(0.2);
  });
  doc.moveDown(0.5);
}

function buildAggregates(entries) {
  const graded = entries
    .map((entry) => ({
      entry,
      grade: entry.computedScore ?? entry.computedGrade ?? entryGrade(entry),
    }))
    .filter((item) => Number.isFinite(item.grade));
  const avg = graded.length ? graded.reduce((sum, item) => sum + item.grade, 0) / graded.length : null;
  const classification = classify(avg);
  const decision = decisionFor(classification);
  const criterionAverages = PERFORMANCE_CRITERIA.map((criterion) => {
    const values = graded
      .filter((item) => !(criterion.key === 'communication' && item.entry?.communicationNa === true))
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
      grade: entry.computedScore ?? entry.computedGrade ?? entryGrade(entry),
      communicationNa: entry.communicationNa === true,
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
  doc.text(`Ø-Score: ${aggregates.averageGrade ?? '—'}`);
  doc.text(`Klassifikation: ${aggregates.classification || '—'}`);
  doc.text(`Entscheidung: ${aggregates.decision || '—'}`);
  doc.moveDown();

  drawRatingSystem(doc, 'DE');
  drawCriteriaOverview(doc, 'DE');
  drawCriteriaDefinitions(doc, 'DE');

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
          `${formatDate(entry.date)} • ${entry.referenceType || 'Bezug'} ${entry.referenceNumber || ''} • ${
            entry.description
          } • Score ${entry.grade ?? '—'} • Kommunikation N/A: ${entry.communicationNa ? 'Ja' : 'Nein'}`
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
    aggregates.classification === 'E' || aggregates.classification === 'F'
      ? language === 'EN'
          ? '\nPlease note: escalation is required for this status.'
          : '\nHinweis: Für diesen Status ist eine Eskalation erforderlich.'
      : '';
  const avgScore = aggregates.averageGrade ?? '—';
  const bodyTextDe = `Sehr geehrte Damen und Herren,

im Rahmen unserer Lieferantenbewertung für das Jahr ${year || ''} haben wir die Leistung Ihres Unternehmens bewertet. Der Ø-Score beträgt ${avgScore}. Das Ergebnis lautet: ${decision}. Die Bewertung basiert auf sechs Kriterien und einer Notenskala von 1 (sehr gut) bis 6 (ungenügend). Niedriger ist besser.

Bitte entnehmen Sie die wesentlichen Kennzahlen der untenstehenden Zusammenfassung. Bei Rückfragen stehen wir gerne zur Verfügung.
${escalationNote}`;
  const bodyTextEn = `Dear Supplier,

as part of our supplier evaluation for ${year || ''}, we assessed your overall performance. The average score is ${avgScore}. The result is: ${decision}. The evaluation is based on six criteria and a rating scale from 1 (very good) to 6 (unsatisfactory). Lower is better.

Please find the key figures in the summary below. If you have questions, feel free to contact us.
${escalationNote}`;
  doc.fontSize(11).fillColor('#333').text(language === 'EN' ? bodyTextEn : bodyTextDe, {
    align: 'left',
  });

  doc.moveDown();
  const criteriaLines = aggregates.criterionAverages || [];
  const baseLines = 4;
  const boxHeight = 22 + (baseLines + criteriaLines.length + 1) * 12;
  doc.rect(48, doc.y, 500, boxHeight).stroke('#ccc');
  let boxTop = doc.y + 8;
  doc
    .fontSize(10)
    .fillColor('#000')
    .text(`${language === 'EN' ? 'Average score' : 'Ø-Score'}: ${aggregates.averageGrade ?? '—'}`, 60, boxTop);
  boxTop += 14;
  doc.text(`${language === 'EN' ? 'Classification' : 'Klassifikation'}: ${aggregates.classification || '—'}`, 60, boxTop);
  boxTop += 14;
  doc.text(`${language === 'EN' ? 'Decision' : 'Entscheidung'}: ${decision || '—'}`, 60, boxTop);
  boxTop += 18;
  doc.text(language === 'EN' ? 'Criterion averages:' : 'Durchschnitt je Kriterium:', 60, boxTop);
  boxTop += 12;
  criteriaLines.forEach((criterion) => {
    doc.text(`${criterion.label}: ${criterion.average ?? '—'}`, 72, boxTop);
    boxTop += 12;
  });
  doc.moveDown(6);

  drawRatingSystem(doc, language);
  drawCriteriaOverview(doc, language);
  drawCriteriaDefinitions(doc, language);

  doc.fontSize(11).fillColor('#000').text(language === 'EN' ? 'Evidence' : 'Nachweise (Evidence)');
  if (!aggregates.evidence.length) {
    doc.fontSize(9).fillColor('#555').text(language === 'EN' ? 'No entries available.' : 'Keine Einträge vorhanden.');
  } else {
    aggregates.evidence.forEach((entry) => {
      doc
        .fontSize(9)
        .fillColor('#333')
        .text(
          `${formatDate(entry.date, language === 'EN' ? 'en-US' : 'de-DE')} • ${
            entry.referenceType || (language === 'EN' ? 'Reference' : 'Bezug')
          } ${entry.referenceNumber || ''} • ${entry.description} • Score ${entry.grade ?? '—'} • ${
            language === 'EN' ? 'Communication N/A' : 'Kommunikation N/A'
          }: ${entry.communicationNa ? (language === 'EN' ? 'Yes' : 'Ja') : language === 'EN' ? 'No' : 'Nein'}`
        );
    });
  }

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
