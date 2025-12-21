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
    const label = language === 'EN' ? criterion.labelEn : criterion.labelDe;
    doc.text(`${label}: ${criterion.average ?? '—'}`, 72, boxTop);
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
      const naCount = Object.values(entry.ratingsNa || {}).filter(Boolean).length;
      doc
        .fontSize(9)
        .fillColor('#333')
        .text(
          `${formatDate(entry.date, language === 'EN' ? 'en-US' : 'de-DE')} • ${
            entry.referenceType || (language === 'EN' ? 'Reference' : 'Bezug')
          } ${entry.referenceNumber || ''} • ${entry.description} • Score ${entry.grade ?? '—'} • ${
            language === 'EN' ? 'N/A criteria' : 'N/A Kriterien'
          }: ${naCount}`
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
