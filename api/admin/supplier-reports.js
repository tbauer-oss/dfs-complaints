// /api/admin/supplier-reports.js – Exporte Lieferantenbewertung
export const config = { runtime: 'nodejs' };

import PDFDocument from 'pdfkit';
import fs from 'fs/promises';
import path from 'path';
import puppeteer from 'puppeteer';
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
  {
    key: 'communication',
    labelDe: 'Zusammenarbeit / Kommunikation',
    labelEn: 'Collaboration / communication',
    weight: 0.1,
  },
  { key: 'quality', labelDe: 'Produktqualität', labelEn: 'Product quality', weight: 0.3 },
  {
    key: 'delivery',
    labelDe: 'Einhaltung der Lieferfrist',
    labelEn: 'On-time delivery',
    weight: 0.15,
  },
  {
    key: 'price',
    labelDe: 'Preis / Rechnungsstellung korrekt (vs. Auftragsbestätigung/Angebot)',
    labelEn: 'Price / invoice correctness (vs. order confirmation/offer)',
    weight: 0.15,
  },
  {
    key: 'quantity',
    labelDe: 'Richtige Mengen / richtige Produkte (Fehl-/Falschlieferungen)',
    labelEn: 'Correct quantity / products (wrong/short deliveries)',
    weight: 0.2,
  },
  {
    key: 'backorders',
    labelDe: 'Nachlieferungen (Teillieferungen / Backorders)',
    labelEn: 'Backorders (partial deliveries)',
    weight: 0.1,
  },
];

function entryGrade(entry) {
  const ratings = entry?.ratings || {};
  const ratingsNa = entry?.ratingsNa || {};
  let total = 0;
  let weightTotal = 0;
  for (const { key, weight } of PERFORMANCE_CRITERIA) {
    const value = ratings[key];
    if (ratingsNa?.[key] === true) {
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

const AUDIT_NOTE = {
  DE: 'Die Lieferantenbewertung ist Bestandteil des Lieferantenmanagements nach DIN EN ISO 13485 (Beschaffung und Lieferantensteuerung). Ziel ist eine nachvollziehbare, objektivierte und wiederholbare Beurteilung anhand definierter Kriterien. Die Notenvergabe erfolgt anhand der unten beschriebenen Stufenbeschreibung und dient als dokumentierter Nachweis der Überwachung sowie als Grundlage für Eskalationen und Maßnahmen.',
  EN: 'Supplier performance evaluation is part of supplier control according to ISO 13485 (purchasing and supplier management). The purpose is a traceable, objective and repeatable assessment using defined criteria. The grading scale below provides documented evidence of monitoring and supports escalation and corrective actions where needed.',
};

const RATING_SCALE = {
  DE: [
    '1 = Sehr gut: Anforderungen werden vollständig und dauerhaft erfüllt, keine Abweichungen.',
    '2 = Gut: Anforderungen werden überwiegend erfüllt, nur geringe/vereinzelte Abweichungen ohne relevante Auswirkung.',
    '3 = Befriedigend: Erkennbare Abweichungen; Aufwand zur Steuerung/Korrektur vorhanden, Liefer-/Prozessabläufe teilweise beeinträchtigt.',
    '4 = Ausreichend: Wiederkehrende oder relevante Abweichungen; erhöhte Steuerung erforderlich; Risiko für Termine/Qualität/Compliance erkennbar.',
    '5 = Mangelhaft: Häufige oder schwerwiegende Abweichungen; Lieferfähigkeit/Qualität/Compliance unzuverlässig; Maßnahmen/Eskalation zwingend.',
    '6 = Ungenügend: Anforderungen werden nicht erfüllt; gravierende Abweichungen oder fehlende Kooperation; Lieferant kritisch, Sperrung/Abkündigung prüfen.',
  ],
  EN: [
    '1 = Excellent: Requirements fully and consistently met; no deviations.',
    '2 = Good: Requirements mostly met; minor/isolated deviations without relevant impact.',
    '3 = Satisfactory: Noticeable deviations; corrective steering effort required; partial impact on operations.',
    '4 = Adequate: Recurrent or relevant deviations; increased control needed; risk to delivery/quality/compliance.',
    '5 = Poor: Frequent or severe deviations; unreliable performance; escalation/actions mandatory.',
    '6 = Unsatisfactory: Requirements not met; severe deviations or lack of cooperation; supplier critical, blocking/discontinuation to be considered.',
  ],
};

const RATING_EXPLANATION = {
  DE: [
    {
      title: 'Zusammenarbeit / Kommunikation (Gewichtung 10 %)',
      lines: [
        '1: Reagiert proaktiv, zeitnah und vollständig; keine Erinnerung erforderlich (oder N/A falls keine Anfrage nötig war).',
        '2: Reagiert zeitnah, gelegentlich 1 Nachfrage; Kommunikation ausreichend klar.',
        '3: Reagiert verzögert; wiederholt Nachfragen nötig; Abstimmungen verursachen Mehraufwand.',
        '4: Häufige Verzögerungen; unklare/inkonsistente Antworten; Abläufe beeinträchtigt.',
        '5: Sehr schlechte Erreichbarkeit; Rückmeldungen spät oder unvollständig; Eskalation erforderlich.',
        '6: Keine bzw. verweigerte Kommunikation trotz mehrfacher Kontaktversuche.',
      ],
    },
    {
      title: 'Produktqualität (Gewichtung 30 %)',
      lines: [
        '1: Keine qualitätsrelevanten Beanstandungen im Bewertungszeitraum.',
        '2: Vereinzelte geringfügige Beanstandungen ohne systematische Ursache, gut beherrscht.',
        '3: Wiederkehrende Beanstandungen oder relevante Abweichungen; Nacharbeit/Sortierung erforderlich.',
        '4: Häufige Abweichungen; deutliche Auswirkungen auf Produktion/Wareneingang; Ursachenklärung notwendig.',
        '5: Schwerwiegende Mängel oder hohe Fehlerquote; Lieferant verursacht erhebliche Störungen; Maßnahmen zwingend.',
        '6: Kritische/inakzeptable Qualität; Lieferungen nicht verwendbar; Sperrung/Abkündigung prüfen.',
      ],
    },
    {
      title: 'Einhaltung der Lieferfrist (Gewichtung 15 %)',
      lines: [
        '1: Termine werden zuverlässig eingehalten.',
        '2: Seltene Verzögerungen; frühzeitige Information; geringe Auswirkung.',
        '3: Wiederholte Verzögerungen; spürbare Auswirkungen auf Planung/Produktion.',
        '4: Häufige Verzögerungen; Information verspätet; Termintreue unzuverlässig.',
        '5: Regelmäßige erhebliche Lieferverzüge; Eskalation/Alternativen erforderlich.',
        '6: Liefertermine werden systematisch nicht eingehalten; Versorgungssicherheit nicht gegeben.',
      ],
    },
    {
      title: 'Preis / Rechnungsstellung korrekt (Gewichtung 15 %)',
      lines: [
        '1: Rechnungen stets korrekt und vertragskonform (Preis, Menge, Konditionen, Referenzen).',
        '2: Einzelne formale Fehler ohne finanzielle Auswirkung; schnell korrigiert.',
        '3: Wiederkehrende Fehler; Korrekturaufwand/Abstimmung notwendig.',
        '4: Häufige Preis-/Positionsabweichungen; verzögerte Korrekturen; Risiko für falsche Zahlungen.',
        '5: Schwerwiegende/regelmäßige Abrechnungsfehler; Eskalation erforderlich.',
        '6: Preis-/Rechnungsstellung nicht vertragskonform; Korrektur verweigert oder nicht nachvollziehbar.',
      ],
    },
    {
      title: 'Richtige Mengen / richtige Produkte (Gewichtung 20 %)',
      lines: [
        '1: Lieferungen vollständig und korrekt (Artikel, Menge, Identifikation).',
        '2: Vereinzelte Abweichungen ohne relevante Auswirkung; unkomplizierte Korrektur.',
        '3: Wiederkehrende Mengen-/Artikelfehler; Mehraufwand im Wareneingang/Produktion.',
        '4: Häufige Fehl-/Falschlieferungen; deutliche Prozessstörungen.',
        '5: Schwerwiegende Fehl-/Falschlieferungen; Lieferzuverlässigkeit kritisch; Maßnahmen zwingend.',
        '6: Systematische Falschlieferungen/Identifikationsfehler; Versorgung und Rückverfolgbarkeit gefährdet.',
      ],
    },
    {
      title: 'Nachlieferungen (Teillieferungen / Backorders) (Gewichtung 10 %)',
      lines: [
        '1: Bestellungen werden vollständig geliefert; keine Nachlieferungen erforderlich.',
        '2: Gelegentliche Teillieferungen ohne Beeinträchtigung; transparent kommuniziert.',
        '3: Regelmäßige Nachlieferungen; Planungsaufwand entsteht.',
        '4: Häufige Teillieferungen; Planung und Verfügbarkeit beeinträchtigt.',
        '5: Umfangreiche/regelmäßige Nachlieferungen; Eskalation/Alternativen erforderlich.',
        '6: Systematisch unvollständige Lieferungen; Versorgungssicherheit nicht gegeben.',
      ],
    },
  ],
  EN: [
    {
      title: 'Collaboration / communication (Weighting 10%)',
      lines: [
        '1: Responds proactively, promptly, and completely; no reminder required (or N/A if no inquiry was needed).',
        '2: Responds promptly, occasional single follow-up; communication sufficiently clear.',
        '3: Responds with delays; repeated follow-ups needed; coordination causes extra effort.',
        '4: Frequent delays; unclear/inconsistent answers; workflows impacted.',
        '5: Very poor availability; responses late or incomplete; escalation required.',
        '6: No or refused communication despite repeated contact attempts.',
      ],
    },
    {
      title: 'Product quality (Weighting 30%)',
      lines: [
        '1: No quality-related complaints in the assessment period.',
        '2: Isolated minor complaints without systematic cause, well controlled.',
        '3: Recurring complaints or relevant deviations; rework/sorting required.',
        '4: Frequent deviations; clear impact on production/goods receipt; root cause analysis needed.',
        '5: Severe defects or high error rate; supplier causes major disruptions; actions mandatory.',
        '6: Critical/unacceptable quality; deliveries unusable; consider blocking/discontinuation.',
      ],
    },
    {
      title: 'On-time delivery (Weighting 15%)',
      lines: [
        '1: Dates are reliably met.',
        '2: Rare delays; early information; minor impact.',
        '3: Repeated delays; noticeable impact on planning/production.',
        '4: Frequent delays; late information; reliability is poor.',
        '5: Regular significant delays; escalation/alternatives required.',
        '6: Delivery dates are systematically not met; supply security not ensured.',
      ],
    },
    {
      title: 'Price / invoice correctness (Weighting 15%)',
      lines: [
        '1: Invoices always correct and contract-compliant (price, quantity, terms, references).',
        '2: Isolated formal errors without financial impact; corrected quickly.',
        '3: Recurring errors; correction/coordination effort required.',
        '4: Frequent price/line deviations; delayed corrections; risk of incorrect payments.',
        '5: Severe/regular billing errors; escalation required.',
        '6: Price/invoicing not contract-compliant; correction refused or not traceable.',
      ],
    },
    {
      title: 'Correct quantity / products (Weighting 20%)',
      lines: [
        '1: Deliveries complete and correct (items, quantities, identification).',
        '2: Isolated deviations without relevant impact; easy correction.',
        '3: Recurring quantity/item errors; extra effort in goods receipt/production.',
        '4: Frequent missing/wrong deliveries; significant process disruptions.',
        '5: Severe missing/wrong deliveries; reliability critical; actions mandatory.',
        '6: Systematic wrong deliveries/identification errors; supply and traceability at risk.',
      ],
    },
    {
      title: 'Backorders / partial deliveries (Weighting 10%)',
      lines: [
        '1: Orders delivered in full; no backorders required.',
        '2: Occasional partial deliveries without impact; transparently communicated.',
        '3: Regular backorders; planning effort arises.',
        '4: Frequent partial deliveries; planning and availability impacted.',
        '5: Extensive/regular backorders; escalation/alternatives required.',
        '6: Systematically incomplete deliveries; supply security not ensured.',
      ],
    },
  ],
};

function drawCriteriaOverview(doc, language) {
  doc.fontSize(11).fillColor('#000').text(language === 'EN' ? 'Criteria & weights' : 'Bewertungskriterien & Gewichte');
  PERFORMANCE_CRITERIA.forEach((criterion) => {
    const label = language === 'EN' ? criterion.labelEn : criterion.labelDe;
    doc
      .fontSize(9)
      .fillColor('#333')
      .text(`• ${label} (${Math.round(criterion.weight * 100)}%)`);
  });
  doc.moveDown(0.5);
}

function drawRatingSystem(doc, language) {
  const scale = language === 'EN' ? RATING_SCALE.EN : RATING_SCALE.DE;
  doc.fontSize(11).fillColor('#000').text(language === 'EN' ? 'Rating system' : 'Bewertungssystem');
  doc.fontSize(9).fillColor('#333').text(language === 'EN' ? 'Audit note' : 'Audit-Hinweis');
  doc.fontSize(8).fillColor('#555').text(language === 'EN' ? AUDIT_NOTE.EN : AUDIT_NOTE.DE);
  doc.moveDown(0.3);
  doc.fontSize(9).fillColor('#333').text(
    language === 'EN'
      ? 'Grades: 1 = excellent … 6 = unsatisfactory. Lower is better.'
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
      .filter((item) => item.entry?.ratingsNa?.[criterion.key] !== true)
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
      ratingsNa: entry.ratingsNa || {},
    })),
  };
}

function formatDate(dateValue, locale = 'de-DE') {
  if (!dateValue) return '—';
  return new Date(dateValue).toLocaleDateString(locale);
}

function escapeHtml(value) {
  return String(value ?? '')
    .replace(/&/g, '&amp;')
    .replace(/</g, '&lt;')
    .replace(/>/g, '&gt;')
    .replace(/"/g, '&quot;')
    .replace(/'/g, '&#39;');
}

function buildSupplierReference(supplierId, year) {
  const text = String(supplierId || '').toUpperCase();
  const hash = [...text].reduce((acc, char) => acc + char.charCodeAt(0), 0);
  const sequence = String(hash % 1000).padStart(3, '0');
  const refYear = year || new Date().getFullYear();
  return `SUP-EVAL-${refYear}-${sequence}`;
}

function statusClassFor(classification) {
  if (classification === 'A' || classification === 'B') return classification;
  if (classification === 'C') return 'C';
  if (classification === 'D' || classification === 'E' || classification === 'F') return 'D';
  return '';
}

function statusColorFor(statusClass) {
  if (statusClass === 'A' || statusClass === 'B') return '#2e7d32';
  if (statusClass === 'C') return '#f9a825';
  if (statusClass === 'D') return '#c62828';
  return '#455a64';
}

function statusTextFor(statusClass, language) {
  if (statusClass === 'A' || statusClass === 'B') {
    return language === 'EN'
      ? 'Your company remains listed as an approved supplier at DFS-DIAMON.'
      : 'Ihr Unternehmen ist weiterhin als zugelassener Lieferant bei DFS-DIAMON gelistet.';
  }
  if (statusClass === 'C') {
    return language === 'EN'
      ? 'Your company is currently under observation. Improvement measures are required.'
      : 'Ihr Unternehmen wird aktuell unter Beobachtung geführt. Verbesserungsmaßnahmen sind erforderlich.';
  }
  if (statusClass === 'D') {
    return language === 'EN'
      ? 'Based on the evaluation, further cooperation is currently not possible.'
      : 'Aufgrund der Bewertung ist derzeit keine weitere Zusammenarbeit möglich.';
  }
  return '';
}

function ratingDescriptions(language) {
  const lines = language === 'EN' ? RATING_SCALE.EN : RATING_SCALE.DE;
  const descriptions = new Map();
  lines.forEach((line) => {
    const match = line.match(/^(\d)\s*=\s*([^:]+):\s*(.+)$/);
    if (match) {
      descriptions.set(Number(match[1]), `${match[2].trim()}: ${match[3].trim()}`);
    }
  });
  return descriptions;
}

function formatWeighted(value, weight) {
  if (!Number.isFinite(value)) return '—';
  return Number((value * weight).toFixed(2));
}

class SupplierReportError extends Error {
  constructor(message, status = 400) {
    super(message);
    this.status = status;
  }
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
    doc.fontSize(10).fillColor('#333').text(`${criterion.labelDe}: ${criterion.average ?? '—'}`);
  });
  doc.moveDown();

  doc.fontSize(11).fillColor('#000').text('Nachweise (Evidence)');
  if (!aggregates.evidence.length) {
    doc.fontSize(10).fillColor('#555').text('Keine Einträge vorhanden.');
  } else {
    aggregates.evidence.forEach((entry) => {
      const naCount = Object.values(entry.ratingsNa || {}).filter(Boolean).length;
      doc
        .fontSize(9)
        .fillColor('#333')
        .text(
          `${formatDate(entry.date)} • ${entry.referenceType || 'Bezug'} ${entry.referenceNumber || ''} • ${
            entry.description
          } • Score ${entry.grade ?? '—'} • N/A Kriterien: ${naCount}`
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

async function buildSupplierLetter({ supplierId, year, actor }) {
  const suppliers = await supplierAll();
  const supplierLookup = new Map(suppliers.map((s) => [s.id, s]));
  const entries = await supplierPerformanceAll({ supplierId });
  const escalations = await supplierEscalationAll({ supplierId });
  const filtered = entries.filter((entry) => {
    if (!entry.includeInAnnual || entry.status !== 'ABGESCHLOSSEN' || entry.deletedAt) return false;
    if (Number.isFinite(year)) {
      const entryYear = new Date(entry.date).getFullYear();
      return entryYear === Number(year);
    }
    return true;
  });
  if (!filtered.length) {
    throw new SupplierReportError('Es liegen keine bewertbaren Einträge für den Lieferanten vor.');
  }
  const aggregates = buildAggregates(filtered);
  if (!Number.isFinite(aggregates.averageGrade)) {
    throw new SupplierReportError('Gesamtnote konnte nicht berechnet werden.');
  }
  const supplier = supplierLookup.get(supplierId) || {};
  const language = supplier.correspondenceLanguage === 'EN' ? 'EN' : 'DE';
  const locale = language === 'EN' ? 'en-US' : 'de-DE';
  const statusClass = statusClassFor(aggregates.classification);
  const statusColor = statusColorFor(statusClass);
  const reference = buildSupplierReference(supplierId, year);
  const descriptions = ratingDescriptions(language);
  const now = Date.now();
  const periodDates = filtered.map((entry) => entry.date).filter(Boolean).sort();
  const periodFrom = periodDates[0] ? formatDate(periodDates[0], locale) : null;
  const periodTo = periodDates.length ? formatDate(periodDates[periodDates.length - 1], locale) : null;
  const periodLabel = Number.isFinite(year)
    ? language === 'EN'
        ? `Calendar year ${year}`
        : `Kalenderjahr ${year}`
    : periodFrom && periodTo
        ? language === 'EN'
            ? `${periodFrom} – ${periodTo}`
            : `${periodFrom} – ${periodTo}`
        : language === 'EN'
            ? 'Evaluation period'
            : 'Bewertungszeitraum';
  const criteriaRows = aggregates.criterionAverages.map((criterion) => {
    const grade = Number.isFinite(criterion.average) ? Number(criterion.average.toFixed(2)) : null;
    const description = grade ? descriptions.get(Math.max(1, Math.min(6, Math.round(grade)))) : null;
    return {
      label: language === 'EN' ? criterion.labelEn : criterion.labelDe,
      grade,
      weight: Math.round(criterion.weight * 100),
      weighted: formatWeighted(grade, criterion.weight),
      description,
    };
  });
  const activeEscalations = escalations.filter((esc) => {
    const status = (esc.status || '').toLowerCase();
    return status && !['geschlossen', 'abgeschlossen', 'closed', 'done'].includes(status);
  });
  const measures = activeEscalations.map((esc) => ({
    title: esc.trigger || esc.reason || esc.actions || '',
    details: [esc.reason, esc.actions, esc.owner ? `${language === 'EN' ? 'Owner' : 'Verantwortlich'}: ${esc.owner}` : null]
      .filter(Boolean)
      .join(' • '),
    due: esc.dueDate ? formatDate(esc.dueDate, locale) : null,
    status: esc.status || '',
  }));
  const footerMeta = language === 'EN'
    ? `Generated on ${new Date(now).toLocaleString(locale)} by ${escapeHtml(actor || 'System')} • Supplier ID: ${escapeHtml(
        supplierId
      )}`
    : `Erzeugt am ${new Date(now).toLocaleString(locale)} durch ${escapeHtml(actor || 'System')} • Lieferanten-ID: ${escapeHtml(
        supplierId
      )}`;

  const logoPath = path.join(process.cwd(), 'api', '_assets', 'dfs-logo.png');
  const logoBuffer = await fs.readFile(logoPath);
  const logoBase64 = logoBuffer.toString('base64');
  const dfsBlue = '#7aa7d8';
  const fromLine = language === 'EN' ? 'DFS – Quality Management' : 'DFS – Quality Management';
  const headerTemplate = `
    <div style="font-family: Arial, sans-serif; font-size: 9px; color: ${dfsBlue}; width: 100%; padding: 24px 40px 0 40px; box-sizing: border-box;">
      <div style="display: flex; justify-content: space-between; align-items: flex-start;">
        <div style="line-height: 1.4;">
          DFS – DIAMON GmbH<br />
          Ländenstraße 1<br />
          D-93339 Riedenburg
        </div>
        <div style="text-align: right; line-height: 1.4;">
          <div><img src="data:image/png;base64,${logoBase64}" style="width: 110px;" /></div>
          DFS – DIAMON GmbH<br />
          Ländenstraße 1<br />
          D-93339 Riedenburg<br /><br />
          Telefon: +49 (0) 94 42 | 91 89-0<br />
          Telefax: +49 (0) 94 42 | 91 89-37<br />
          info@dfs-diamon.de<br />
          www.dfs-diamon.de
        </div>
      </div>
      <div style="border-bottom: 2px solid ${dfsBlue}; margin-top: 12px;"></div>
      <div style="display: flex; justify-content: space-between; margin-top: 8px; font-size: 9px;">
        <div>Our ref: ${escapeHtml(reference)}</div>
        <div>From: ${escapeHtml(fromLine)}</div>
        <div>Date: ${escapeHtml(formatDate(now, locale))}</div>
        <div>Page <span class="pageNumber"></span> of <span class="totalPages"></span></div>
      </div>
    </div>
  `;
  const footerTemplate = `
    <div style="font-family: Arial, sans-serif; font-size: 8px; color: #6d6d6d; width: 100%; padding: 0 40px 18px 40px; box-sizing: border-box;">
      <div style="border-top: 1px solid ${dfsBlue}; padding-top: 6px;">
        Managing Director: Dr. Stefan Brand • Amtsgericht Regensburg HRB 2966 • USt-IdNr.: DE 128580122<br />
        Bankverbindung: HypoVereinsbank München • IBAN DE68 7002 0270 0062 8465 33 • BIC HYVEDEMMXXX
      </div>
    </div>
  `;

  const criteriaTable = criteriaRows
    .map(
      (row) => `
        <tr>
          <td>${escapeHtml(row.label)}</td>
          <td>${row.grade ?? '—'}</td>
          <td>${row.weight}%</td>
          <td>${row.weighted ?? '—'}</td>
        </tr>
        <tr class="criteria-detail">
          <td colspan="4">${row.description ? escapeHtml(row.description) : language === 'EN' ? 'N/A' : 'k. A.'}</td>
        </tr>
      `
    )
    .join('');

  const measuresBlock = measures.length
    ? `
      <ul>
        ${measures
          .map(
            (measure) => `
            <li>
              <strong>${escapeHtml(measure.title || (language === 'EN' ? 'Measure' : 'Maßnahme'))}</strong>
              ${measure.details ? ` – ${escapeHtml(measure.details)}` : ''}
              ${measure.due ? ` (${language === 'EN' ? 'Due' : 'Fällig'}: ${escapeHtml(measure.due)})` : ''}
              ${measure.status ? ` • ${escapeHtml(measure.status)}` : ''}
            </li>
          `
          )
          .join('')}
      </ul>
    `
    : `<p>${language === 'EN' ? 'No actions are currently required.' : 'Derzeit sind keine Maßnahmen erforderlich.'}</p>`;

  const html = `
    <!DOCTYPE html>
    <html lang="${language === 'EN' ? 'en' : 'de'}">
      <head>
        <meta charset="UTF-8" />
        <style>
          body {
            font-family: Arial, sans-serif;
            color: #1f1f1f;
            font-size: 11px;
            margin: 0;
            padding: 0;
          }
          .page {
            padding: 0 40px 40px 40px;
          }
          h1, h2, h3 {
            color: #1a1a1a;
            margin: 18px 0 6px;
          }
          h1 {
            font-size: 16px;
          }
          h2 {
            font-size: 13px;
          }
          h3 {
            font-size: 12px;
          }
          p {
            margin: 6px 0;
            line-height: 1.5;
          }
          .address-block {
            margin-top: 0;
            margin-bottom: 12px;
          }
          .summary-grid {
            display: grid;
            grid-template-columns: 1fr 1fr;
            gap: 12px;
            margin-top: 10px;
          }
          .summary-card {
            border: 1px solid #d8d8d8;
            padding: 10px;
            border-radius: 4px;
          }
          .status-pill {
            display: inline-block;
            padding: 4px 10px;
            border-radius: 12px;
            background: ${statusColor};
            color: #fff;
            font-weight: bold;
          }
          table {
            width: 100%;
            border-collapse: collapse;
            margin-top: 8px;
          }
          th, td {
            border: 1px solid #dcdcdc;
            padding: 6px;
            text-align: left;
          }
          th {
            background: #f5f7fb;
          }
          .criteria-detail td {
            font-size: 9px;
            color: #4f4f4f;
            background: #fafafa;
          }
          .signature {
            margin-top: 24px;
          }
          .meta {
            margin-top: 12px;
            font-size: 9px;
            color: #666;
          }
        </style>
      </head>
      <body>
        <div class="page">
          <div class="address-block">
            <strong>${escapeHtml(supplier.name || supplierId)}</strong><br />
            ${supplier.address ? `${escapeHtml(supplier.address).replace(/\n/g, '<br />')}` : ''}
          </div>

          <h1>${language === 'EN' ? 'Supplier Evaluation Report' : 'Lieferantenbewertung – PDF-Report'}</h1>
          <p>${language === 'EN' ? 'Supplier evaluation – official communication' : 'Offizielle Lieferanteninformation'}</p>

          <h2>${language === 'EN' ? 'Cover letter' : 'Anschreiben'}</h2>
          <p>
            ${
              language === 'EN'
                ? `Dear Sir or Madam,<br /><br />
                As part of our quality management system according to DIN EN ISO 13485, we regularly evaluate our suppliers.<br />
                Based on the performance data recorded during the evaluation period, we hereby inform you about the current status of your supplier evaluation.<br />
                The assessment is based on objective criteria such as product quality, delivery reliability, communication, and order fulfillment.<br />
                Please find the detailed results in the following overview.`
                : `Sehr geehrte Damen und Herren,<br /><br />
                im Rahmen unseres Qualitätsmanagementsystems gemäß DIN EN ISO 13485 führen wir regelmäßig eine Bewertung unserer Lieferanten durch.<br />
                Nach Auswertung der im Bewertungszeitraum erfassten Leistungsdaten teilen wir Ihnen hiermit den aktuellen Status Ihrer Lieferantenbewertung mit.<br />
                Diese Bewertung basiert auf objektiven Kriterien wie Produktqualität, Liefertreue, Kommunikation sowie der Abwicklung von Bestellungen und Lieferungen.<br />
                Die detaillierten Ergebnisse entnehmen Sie bitte der nachfolgenden Übersicht.`
            }
          </p>

          <h2>${language === 'EN' ? 'Overall evaluation' : 'Gesamtbewertung'}</h2>
          <div class="summary-grid">
            <div class="summary-card">
              <strong>${language === 'EN' ? 'Evaluation period' : 'Bewertungszeitraum'}</strong>
              <p>${escapeHtml(periodLabel)}</p>
              <strong>${language === 'EN' ? 'Average grade' : 'Gesamtnote'}</strong>
              <p>${aggregates.averageGrade.toFixed(2)}</p>
            </div>
            <div class="summary-card">
              <strong>${language === 'EN' ? 'Status class' : 'Statusklasse'}</strong>
              <p><span class="status-pill">${escapeHtml(statusClass)}</span></p>
              <strong>${language === 'EN' ? 'Decision' : 'Entscheidung'}</strong>
              <p>${escapeHtml(decisionFor(aggregates.classification) || '')}</p>
            </div>
          </div>

          <table>
            <thead>
              <tr>
                <th>${language === 'EN' ? 'Criterion' : 'Kriterium'}</th>
                <th>${language === 'EN' ? 'Grade' : 'Note'}</th>
                <th>${language === 'EN' ? 'Weighting' : 'Gewichtung'}</th>
                <th>${language === 'EN' ? 'Weighted contribution' : 'Bewertung'}</th>
              </tr>
            </thead>
            <tbody>
              ${criteriaTable}
            </tbody>
          </table>

          <h2>${language === 'EN' ? 'Current supplier status' : 'Aktueller Lieferantenstatus'}</h2>
          <p>${escapeHtml(statusTextFor(statusClass, language))}</p>

          <h2>${language === 'EN' ? 'Measures / notes' : 'Maßnahmen / Hinweise'}</h2>
          ${measuresBlock}

          <div class="signature">
            <p>${language === 'EN' ? 'Best regards' : 'Mit freundlichen Grüßen'}</p>
            <p>
              Tobias Bauer<br />
              Head of Quality Management (QMB/BdoL)<br />
              Person Responsible for Regulatory Compliance (PRRC)
            </p>
          </div>

          <div class="meta">
            ${footerMeta}
          </div>
        </div>
      </body>
    </html>
  `;

  const browser = await puppeteer.launch({
    args: ['--no-sandbox', '--disable-setuid-sandbox'],
  });
  try {
    const page = await browser.newPage();
    await page.setContent(html, { waitUntil: 'networkidle0' });
    const pdf = await page.pdf({
      format: 'A4',
      printBackground: true,
      displayHeaderFooter: true,
      headerTemplate,
      footerTemplate,
      margin: { top: '220px', bottom: '90px', left: '40px', right: '40px' },
    });
    return pdf;
  } finally {
    await browser.close();
  }
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
    if (err instanceof SupplierReportError) {
      return bad(res, err.message, err.status);
    }
    console.error('[admin/supplier-reports] failed', err);
    return bad(res, 'Export konnte nicht erstellt werden.', 500);
  }
}
