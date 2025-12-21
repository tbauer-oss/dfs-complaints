// /api/admin/supplier-reports.js – Exporte Lieferantenbewertung
export const config = {
  runtime: 'nodejs',
  api: {
    bodyParser: { sizeLimit: '2mb' },
  },
};

import PDFDocument from 'pdfkit';
import fs from 'fs/promises';
import path from 'path';
import { fileURLToPath } from 'url';
import { PDFDocument as PdfDocument, StandardFonts, rgb, degrees } from 'pdf-lib';
import { applyAdminCors } from '../_lib/adminCors.js';
import { readJson } from '../_lib/http.js';
import { requirePortalAccess } from './_guard.js';
import {
  supplierEvaluationAll,
  supplierEscalationAll,
  supplierAll,
  supplierPerformanceAll,
  supplierReportLetterLayoutGet,
} from '../_lib/store.js';

const SUPPLIER_TILE = 'supplierEvaluation';
const MAX_REQUEST_BYTES = 25000;
const ALLOWED_BODY_KEYS = new Set(['locale', 'debug', 'layout']);
const LAYOUT_KEYS = new Set(['page', 'header', 'recipientBlock', 'dateBlock', 'titleBlock', 'bodyStartMm', 'signature']);
const SIGNATURE_KEYS = new Set([
  'enabled',
  'startY',
  'compact',
  'showName',
  'showTitle',
  'showEmail',
  'showLegalFooter',
]);
const isPlainObject = (value) => Boolean(value) && typeof value === 'object' && !Array.isArray(value);
const BASE64_PATTERN = /^[A-Za-z0-9+/=]+$/;

function sendJson(res, statusCode, payload) {
  if (!res.getHeader('Content-Type')) {
    res.setHeader('Content-Type', 'application/json; charset=utf-8');
  }
  res.statusCode = statusCode;
  res.end(JSON.stringify(payload ?? {}));
}

function sendError(res, statusCode, message, extra) {
  const body = typeof extra === 'object' && extra !== null ? { error: message, ...extra } : { error: message };
  sendJson(res, statusCode, body);
}

function containsProhibitedContent(value, keyPath = '') {
  if (typeof value === 'string') {
    const loweredKey = keyPath.toLowerCase();
    if (loweredKey.includes('html')) return true;
    if (loweredKey.includes('base64')) return true;
    if (/<\/?[a-z][\s\S]*>/i.test(value)) return true;
    if (value.includes('data:image')) return true;
    if (value.length > 2000) return true;
    if (value.length > 500 && BASE64_PATTERN.test(value)) return true;
    return false;
  }
  if (Array.isArray(value)) {
    return value.some((item, index) => containsProhibitedContent(item, `${keyPath}[${index}]`));
  }
  if (isPlainObject(value)) {
    return Object.entries(value).some(([key, val]) => containsProhibitedContent(val, key));
  }
  return false;
}

function validateSupplierReportBody(body) {
  if (!isPlainObject(body)) {
    return { ok: false, status: 400, error: 'Ungültiges Anfrageformat.' };
  }
  for (const key of Object.keys(body)) {
    if (!ALLOWED_BODY_KEYS.has(key)) {
      return { ok: false, status: 400, error: 'Ungültige Anfragefelder.' };
    }
  }
  if (body.locale != null && !['de', 'en'].includes(String(body.locale).toLowerCase())) {
    return { ok: false, status: 400, error: 'Ungültige Sprache.' };
  }
  if (body.debug != null && typeof body.debug !== 'boolean') {
    return { ok: false, status: 400, error: 'Ungültiger Debug-Wert.' };
  }
  return {
    ok: true,
    locale: body.locale ? String(body.locale).toLowerCase() : null,
    debug: body.debug === true,
    layout: body.layout ?? null,
  };
}

function normalizePreviewLayout(input) {
  if (!isPlainObject(input)) return null;
  const toNumber = (value) => (Number.isFinite(Number(value)) ? Number(value) : null);
  const toBoolean = (value) => (typeof value === 'boolean' ? value : null);
  const cleaned = {};
  for (const key of Object.keys(input)) {
    if (!LAYOUT_KEYS.has(key)) return null;
  }

  const takeNumericMap = (raw) => {
    if (!isPlainObject(raw)) return null;
    const map = {};
    for (const [key, value] of Object.entries(raw)) {
      const numeric = toNumber(value);
      if (numeric == null) return null;
      map[key] = numeric;
    }
    return map;
  };

  if (input.page != null) {
    const page = takeNumericMap(input.page);
    if (!page) return null;
    cleaned.page = page;
  }
  if (input.header != null) {
    const header = takeNumericMap(input.header);
    if (!header) return null;
    cleaned.header = header;
  }
  if (input.recipientBlock != null) {
    const recipientBlock = takeNumericMap(input.recipientBlock);
    if (!recipientBlock) return null;
    cleaned.recipientBlock = recipientBlock;
  }
  if (input.dateBlock != null) {
    const dateBlock = takeNumericMap(input.dateBlock);
    if (!dateBlock) return null;
    cleaned.dateBlock = dateBlock;
  }
  if (input.titleBlock != null) {
    const titleBlock = takeNumericMap(input.titleBlock);
    if (!titleBlock) return null;
    cleaned.titleBlock = titleBlock;
  }
  if (input.bodyStartMm != null) {
    const numeric = toNumber(input.bodyStartMm);
    if (numeric == null) return null;
    cleaned.bodyStartMm = numeric;
  }
  if (input.signature != null) {
    if (!isPlainObject(input.signature)) return null;
    const signature = {};
    for (const [key, value] of Object.entries(input.signature)) {
      if (!SIGNATURE_KEYS.has(key)) return null;
      if (key === 'startY') {
        const numeric = toNumber(value);
        if (numeric == null) return null;
        signature[key] = numeric;
        continue;
      }
      const bool = toBoolean(value);
      if (bool == null) return null;
      signature[key] = bool;
    }
    cleaned.signature = signature;
  }

  return cleaned;
}

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);
const LETTERHEAD_PATH = path.join(__dirname, '../_assets/dfs_letterhead.png');
const PAGE_SIZE = { width: 595.28, height: 841.89 };
const PAGE_MARGIN = { left: 52, right: 52, top: 150, bottom: 70 };

const mmToPt = (mm) => mm * 2.83464567;

function hexToRgb(hex) {
  const normalized = hex.replace('#', '');
  const value = parseInt(normalized, 16);
  const r = (value >> 16) & 255;
  const g = (value >> 8) & 255;
  const b = value & 255;
  return rgb(r / 255, g / 255, b / 255);
}

function topToPdfY(top, pageHeight) {
  return pageHeight - top;
}

function wrapText(text, font, fontSize, maxWidth) {
  const lines = [];
  const paragraphs = String(text ?? '').split('\n');
  paragraphs.forEach((paragraph, index) => {
    const words = paragraph.split(/\s+/).filter(Boolean);
    if (!words.length) {
      lines.push('');
      return;
    }
    let line = '';
    words.forEach((word) => {
      const testLine = line ? `${line} ${word}` : word;
      if (font.widthOfTextAtSize(testLine, fontSize) <= maxWidth) {
        line = testLine;
      } else {
        if (line) lines.push(line);
        line = word;
      }
    });
    if (line) lines.push(line);
    if (index < paragraphs.length - 1) lines.push('');
  });
  return lines;
}

function drawWrappedText(
  page,
  {
    text,
    x,
    top,
    maxWidth,
    font,
    size,
    color = rgb(0, 0, 0),
    lineHeight = size * 1.3,
  }
) {
  const lines = wrapText(text, font, size, maxWidth);
  const pageHeight = page.getHeight();
  let cursorTop = top;
  lines.forEach((line) => {
    if (!line) {
      cursorTop += lineHeight;
      return;
    }
    page.drawText(line, {
      x,
      y: topToPdfY(cursorTop + size, pageHeight),
      size,
      font,
      color,
    });
    cursorTop += lineHeight;
  });
  return cursorTop;
}

function addLetterheadPage(pdfDoc, backgroundImage) {
  const page = pdfDoc.addPage([PAGE_SIZE.width, PAGE_SIZE.height]);
  page.drawImage(backgroundImage, {
    x: 0,
    y: 0,
    width: PAGE_SIZE.width,
    height: PAGE_SIZE.height,
  });
  return page;
}

function createPdfLayout(pdfDoc, backgroundImage) {
  let page = addLetterheadPage(pdfDoc, backgroundImage);
  let cursorY = PAGE_SIZE.height - PAGE_MARGIN.top;

  const ensureSpace = (height) => {
    if (cursorY - height < PAGE_MARGIN.bottom) {
      page = addLetterheadPage(pdfDoc, backgroundImage);
      cursorY = PAGE_SIZE.height - PAGE_MARGIN.top;
    }
  };

  const drawLines = ({
    lines,
    x,
    font,
    fontSize,
    color = rgb(0, 0, 0),
    lineHeight = fontSize * 1.2,
  }) => {
    ensureSpace(lines.length * lineHeight);
    lines.forEach((line) => {
      if (line) {
        page.drawText(line, {
          x,
          y: cursorY - fontSize,
          size: fontSize,
          font,
          color,
        });
      }
      cursorY -= lineHeight;
    });
  };

  const drawTextBlock = ({
    text,
    x,
    font,
    fontSize,
    color = rgb(0, 0, 0),
    maxWidth,
    lineHeight = fontSize * 1.3,
    marginBottom = 0,
  }) => {
    const lines = wrapText(text, font, fontSize, maxWidth);
    drawLines({ lines, x, font, fontSize, color, lineHeight });
    cursorY -= marginBottom;
  };

  const moveDown = (distance) => {
    cursorY -= distance;
  };

  const setCursorY = (value) => {
    cursorY = value;
  };

  const getCursorY = () => cursorY;

  const getPage = () => page;

  return {
    ensureSpace,
    drawLines,
    drawTextBlock,
    moveDown,
    setCursorY,
    getCursorY,
    getPage,
  };
}

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

function statusClassFor(classification) {
  if (classification === 'A' || classification === 'B') return classification;
  if (classification === 'C') return 'C';
  if (classification === 'D' || classification === 'E' || classification === 'F') return 'D';
  return '';
}

function statusTextFor(statusClass, language) {
  if (statusClass === 'A' || statusClass === 'B') {
    return language === 'EN'
      ? 'Your company remains listed as an approved supplier at DFS-DIAMON.'
      : 'Ihr Unternehmen ist weiterhin als zugelassener Lieferant bei DFS-DIAMON gelistet.';
  }
  if (statusClass === 'C') {
    return language === 'EN'
      ? 'Your company is approved with conditions. Improvement measures are required.'
      : 'Ihr Unternehmen ist mit Auflagen zugelassen. Verbesserungsmaßnahmen sind erforderlich.';
  }
  if (statusClass === 'D') {
    return language === 'EN'
      ? 'Based on the evaluation, further cooperation is currently not possible.'
      : 'Aufgrund der Bewertung ist derzeit keine weitere Zusammenarbeit möglich.';
  }
  return '';
}

function statusDecisionText(classification, language) {
  const labels = {
    DE: {
      A: 'weiterhin zugelassen',
      B: 'weiterhin zugelassen',
      C: 'zugelassen mit Auflagen',
      D: 'in Beobachtung',
      E: 'gesperrt',
      F: 'gesperrt',
    },
    EN: {
      A: 'approved',
      B: 'approved',
      C: 'approved with conditions',
      D: 'under observation',
      E: 'blocked',
      F: 'blocked',
    },
  };
  const lang = language === 'EN' ? 'EN' : 'DE';
  return labels[lang][classification] || '';
}

function formatWeighted(value, weight) {
  if (!Number.isFinite(value)) return '—';
  return Number((value * weight).toFixed(2));
}

function mergeLayoutConfig(base, override) {
  if (!override || typeof override !== 'object') return base;
  const toNumber = (value, fallback) => (Number.isFinite(Number(value)) ? Number(value) : fallback);
  const toBoolean = (value, fallback) => (typeof value === 'boolean' ? value : fallback);
  const merged = {
    ...base,
    ...override,
    page: {
      ...base.page,
      ...(override.page || {}),
    },
    header: {
      ...base.header,
      ...(override.header || {}),
    },
    recipientBlock: {
      ...base.recipientBlock,
      ...(override.recipientBlock || {}),
    },
    dateBlock: {
      ...base.dateBlock,
      ...(override.dateBlock || {}),
    },
    titleBlock: {
      ...base.titleBlock,
      ...(override.titleBlock || {}),
    },
    signature: {
      ...base.signature,
      ...(override.signature || {}),
    },
  };
  merged.page = {
    marginTopMm: toNumber(merged.page?.marginTopMm, base.page.marginTopMm),
    marginRightMm: toNumber(merged.page?.marginRightMm, base.page.marginRightMm),
    marginBottomMm: toNumber(merged.page?.marginBottomMm, base.page.marginBottomMm),
    marginLeftMm: toNumber(merged.page?.marginLeftMm, base.page.marginLeftMm),
  };
  merged.header = {
    logoWidthMm: toNumber(merged.header?.logoWidthMm, base.header.logoWidthMm),
    headerTopMm: toNumber(merged.header?.headerTopMm, base.header.headerTopMm),
  };
  merged.recipientBlock = {
    topMm: toNumber(merged.recipientBlock?.topMm, base.recipientBlock.topMm),
    leftMm: toNumber(merged.recipientBlock?.leftMm, base.recipientBlock.leftMm),
  };
  merged.dateBlock = {
    topMm: toNumber(merged.dateBlock?.topMm, base.dateBlock.topMm),
    rightMm: toNumber(merged.dateBlock?.rightMm, base.dateBlock.rightMm),
  };
  merged.titleBlock = {
    topMm: toNumber(merged.titleBlock?.topMm, base.titleBlock.topMm),
  };
  merged.bodyStartMm = toNumber(merged.bodyStartMm, base.bodyStartMm);
  merged.signature = {
    enabled: toBoolean(merged.signature?.enabled, base.signature.enabled),
    startY: toNumber(merged.signature?.startY, base.signature.startY),
    compact: toBoolean(merged.signature?.compact, base.signature.compact),
    showName: toBoolean(merged.signature?.showName, base.signature.showName),
    showTitle: toBoolean(merged.signature?.showTitle, base.signature.showTitle),
    showEmail: toBoolean(merged.signature?.showEmail, base.signature.showEmail),
    showLegalFooter: toBoolean(merged.signature?.showLegalFooter, base.signature.showLegalFooter),
  };
  return merged;
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

function drawPdfTable(layout, {
  headers,
  rows,
  columnWidths,
  fontRegular,
  fontBold,
  fontSize = 9,
  headerFill = hexToRgb('#f4f6fa'),
  borderColor = hexToRgb('#d0d0d0'),
  textColor = rgb(0, 0, 0),
  padding = 4,
}) {
  const startX = PAGE_MARGIN.left;
  const lineHeight = fontSize * 1.25;
  const totalWidth = columnWidths.reduce((sum, width) => sum + width, 0);

  const drawRow = (cells, font, isHeader) => {
    const normalized = cells.map((cell, index) => {
      const cellText = cell == null ? '' : String(cell);
      const maxWidth = columnWidths[index] - padding * 2;
      const lines = wrapText(cellText, font, fontSize, maxWidth);
      return lines.length ? lines : [''];
    });
    const rowLines = Math.max(...normalized.map((lines) => lines.length));
    const rowHeight = rowLines * lineHeight + padding * 2;
    layout.ensureSpace(rowHeight);

    const page = layout.getPage();
    const yTop = layout.getCursorY();
    const yBottom = yTop - rowHeight;

    if (isHeader) {
      page.drawRectangle({ x: startX, y: yBottom, width: totalWidth, height: rowHeight, color: headerFill });
    }

    let x = startX;
    normalized.forEach((lines, index) => {
      page.drawRectangle({
        x,
        y: yBottom,
        width: columnWidths[index],
        height: rowHeight,
        borderColor,
        borderWidth: 1,
      });
      lines.forEach((line, lineIndex) => {
        if (!line) return;
        const textY = yTop - padding - fontSize - lineIndex * lineHeight + 1;
        page.drawText(line, {
          x: x + padding,
          y: textY,
          size: fontSize,
          font,
          color: textColor,
        });
      });
      x += columnWidths[index];
    });

    layout.setCursorY(yBottom);
  };

  drawRow(headers, fontBold, true);
  rows.forEach((row) => drawRow(row, fontRegular, false));
  layout.moveDown(8);
}

async function buildSupplierLetter({ supplierId, year, actor, layoutConfig, preview, localeOverride }) {
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
  const supplier = supplierLookup.get(supplierId);
  if (!supplier) {
    throw new SupplierReportError('Lieferant nicht gefunden.', 404);
  }

  const normalizedLocale = localeOverride === 'en' ? 'EN' : localeOverride === 'de' ? 'DE' : null;
  const language = normalizedLocale || (supplier.correspondenceLanguage === 'EN' ? 'EN' : 'DE');
  const locale = language === 'EN' ? 'en-US' : 'de-DE';
  const statusClass = statusClassFor(aggregates.classification);
  const periodDates = filtered.map((entry) => entry.date).filter(Boolean).sort();
  const periodFrom = periodDates[0] ? formatDate(periodDates[0], locale) : null;
  const periodTo = periodDates.length ? formatDate(periodDates[periodDates.length - 1], locale) : null;
  const periodLabel = Number.isFinite(year)
    ? language === 'EN'
      ? `Calendar year ${year}`
      : `Kalenderjahr ${year}`
    : periodFrom && periodTo
      ? `${periodFrom} – ${periodTo}`
      : language === 'EN'
        ? 'Evaluation period'
        : 'Bewertungszeitraum';

  const criteriaRows = aggregates.criterionAverages.map((criterion) => ({
    label: language === 'EN' ? criterion.labelEn : criterion.labelDe,
    grade: Number.isFinite(criterion.average) ? Number(criterion.average.toFixed(2)) : '—',
    weight: `${Math.round(criterion.weight * 100)}%`,
    weighted: Number.isFinite(criterion.average) ? formatWeighted(criterion.average, criterion.weight) : '—',
  }));

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

  const storedLayout = await supplierReportLetterLayoutGet();
  const layout = mergeLayoutConfig(storedLayout, layoutConfig);
  const letterheadBytes = await fs.readFile(LETTERHEAD_PATH);

  const subject = language === 'EN'
    ? `Supplier Evaluation ${year || new Date().getFullYear()} – Result & Status`
    : `Lieferantenbewertung ${year || new Date().getFullYear()} – Ergebnis & Status`;

  const introText = language === 'EN'
    ? `Dear Sir or Madam,\n\nAs part of our quality management system according to ISO 13485, we evaluate our suppliers on a regular basis. This letter summarizes your evaluation for ${periodLabel}. Your overall score is ${aggregates.averageGrade.toFixed(
        2
      )} (status class ${aggregates.classification}). The assessment is based on documented evidence and weighted criteria.`
    : `Sehr geehrte Damen und Herren,\n\nim Rahmen unseres Qualitätsmanagementsystems gemäß ISO 13485 bewerten wir unsere Lieferanten regelmäßig. Dieses Schreiben fasst Ihre Bewertung für ${periodLabel} zusammen. Die Gesamtnote beträgt ${aggregates.averageGrade.toFixed(
        2
      )} (Statusklasse ${aggregates.classification}). Die Bewertung basiert auf dokumentierten Nachweisen und gewichteten Kriterien.`;

  const classification = aggregates.classification || '';
  const statusDecision = statusDecisionText(classification, language);
  const statusLine = language === 'EN'
    ? `Status: ${statusDecision} (class ${classification}) – ${statusTextFor(statusClass, 'EN')}`
    : `Status: ${statusDecision} (Statusklasse ${classification}) – ${statusTextFor(statusClass, 'DE')}`;

  const overallRow = {
    label: language === 'EN' ? 'Overall score' : 'Gesamtnote',
    grade: aggregates.averageGrade.toFixed(2),
    weight: '100%',
    weighted: aggregates.averageGrade.toFixed(2),
  };

  const measuresLines = [];
  if (measures.length) {
    measuresLines.push(
      ...measures.map((measure) => {
        const line = `${measure.title || (language === 'EN' ? 'Measure' : 'Maßnahme')}${
          measure.details ? ` – ${measure.details}` : ''
        }${measure.due ? ` (${language === 'EN' ? 'Due' : 'Fällig'}: ${measure.due})` : ''}${
          measure.status ? ` • ${measure.status}` : ''
        }`;
        return line;
      })
    );
  }

  if (!measuresLines.length) {
    if (['D', 'E', 'F'].includes(classification)) {
      measuresLines.push(
        language === 'EN'
          ? 'Please provide a corrective action plan and mitigation timeline. Continued approval depends on effective remediation.'
          : 'Bitte legen Sie einen Maßnahmenplan mit Korrektur- und Präventionsmaßnahmen sowie Zeitplan vor. Die weitere Zulassung hängt von der wirksamen Umsetzung ab.'
      );
      measuresLines.push(
        language === 'EN'
          ? 'Coordinate corrective actions with DFS-DIAMON quality management.'
          : 'Stimmen Sie die Korrekturmaßnahmen mit dem Qualitätsmanagement von DFS-DIAMON ab.'
      );
    } else if (classification === 'C') {
      measuresLines.push(
        language === 'EN'
          ? 'Improvement measures are required; please align actions and timelines with our quality management.'
          : 'Verbesserungsmaßnahmen sind erforderlich; bitte stimmen Sie Maßnahmen und Zeitplan mit unserem Qualitätsmanagement ab.'
      );
    } else {
      measuresLines.push(
        language === 'EN'
          ? 'No corrective actions are currently required. Please continue to maintain the proven performance level.'
          : 'Derzeit sind keine Korrekturmaßnahmen erforderlich. Bitte sichern Sie das bestätigte Leistungsniveau weiterhin ab.'
      );
    }
  }

  const addressParts = [
    supplier.address,
    supplier.country,
  ]
    .filter(Boolean)
    .flatMap((line) => String(line).split('\n'))
    .map((line) => line.trim())
    .filter(Boolean);

  const pdfDoc = await PdfDocument.create();
  const backgroundImage = await pdfDoc.embedPng(letterheadBytes);
  const fontRegular = await pdfDoc.embedFont(StandardFonts.Helvetica);
  const fontBold = await pdfDoc.embedFont(StandardFonts.HelveticaBold);

  const pageWidth = PAGE_SIZE.width;
  const pageHeight = PAGE_SIZE.height;
  const marginLeft = mmToPt(layout.page.marginLeftMm);
  const marginRight = mmToPt(layout.page.marginRightMm);
  const marginTop = mmToPt(layout.page.marginTopMm);
  const marginBottom = mmToPt(layout.page.marginBottomMm);
  const recipientTop = mmToPt(layout.recipientBlock.topMm);
  const recipientLeft = mmToPt(layout.recipientBlock.leftMm);
  const dateTop = mmToPt(layout.dateBlock.topMm);
  const dateRight = mmToPt(layout.dateBlock.rightMm);
  const subjectTop = mmToPt(layout.titleBlock.topMm);
  const bodyStart = mmToPt(layout.bodyStartMm);

  const createPage = (withLetterhead) => {
    const page = pdfDoc.addPage([PAGE_SIZE.width, PAGE_SIZE.height]);
    if (withLetterhead) {
      page.drawImage(backgroundImage, {
        x: 0,
        y: 0,
        width: PAGE_SIZE.width,
        height: PAGE_SIZE.height,
      });
    }
    return page;
  };

  let page = createPage(true);
  let cursorTop = bodyStart;

  const ensureSpace = (height) => {
    if (cursorTop + height > pageHeight - marginBottom) {
      page = createPage(false);
      cursorTop = marginTop;
    }
  };

  const drawRightAlignedText = (text, xRight, top, size, font, color = rgb(0, 0, 0)) => {
    const width = font.widthOfTextAtSize(text, size);
    page.drawText(text, {
      x: xRight - width,
      y: topToPdfY(top + size, pageHeight),
      size,
      font,
      color,
    });
  };

  const drawBulletList = (items, { x, top, maxWidth, font, size, lineHeight }) => {
    const bullet = '• ';
    const bulletWidth = font.widthOfTextAtSize(bullet, size);
    cursorTop = top;
    items.forEach((item) => {
      const lines = wrapText(item, font, size, maxWidth - bulletWidth);
      const safeLines = lines.length ? lines : [''];
      safeLines.forEach((line, index) => {
        ensureSpace(lineHeight);
        if (index === 0) {
          page.drawText(bullet, {
            x,
            y: topToPdfY(cursorTop + size, pageHeight),
            size,
            font,
          });
          page.drawText(line, {
            x: x + bulletWidth,
            y: topToPdfY(cursorTop + size, pageHeight),
            size,
            font,
          });
        } else {
          page.drawText(line, {
            x: x + bulletWidth,
            y: topToPdfY(cursorTop + size, pageHeight),
            size,
            font,
          });
        }
        cursorTop += lineHeight;
      });
    });
    return cursorTop;
  };

  const drawTable = ({ headers, rows, columnWidths, fontSize }) => {
    const lineHeight = fontSize * 1.3;
    const padding = 4;
    const tableX = marginLeft;
    const headerFill = hexToRgb('#f4f6fa');
    const borderColor = hexToRgb('#d0d0d0');

    const drawRow = (cells, font, isHeader, isTotal) => {
      const normalized = cells.map((cell, index) => {
        const cellText = cell == null ? '' : String(cell);
        const maxWidth = columnWidths[index] - padding * 2;
        const lines = wrapText(cellText, font, fontSize, maxWidth);
        return lines.length ? lines : [''];
      });
      const rowLines = Math.max(...normalized.map((lines) => lines.length));
      const rowHeight = rowLines * lineHeight + padding * 2;
      ensureSpace(rowHeight);

      if (cursorTop + rowHeight > pageHeight - marginBottom) {
        page = createPage(false);
        cursorTop = marginTop;
      }

      const yTop = cursorTop;
      const yBottom = yTop + rowHeight;

      if (isHeader) {
        page.drawRectangle({
          x: tableX,
          y: topToPdfY(yBottom, pageHeight),
          width: columnWidths.reduce((sum, width) => sum + width, 0),
          height: rowHeight,
          color: headerFill,
        });
      }

      let x = tableX;
      normalized.forEach((lines, index) => {
        page.drawRectangle({
          x,
          y: topToPdfY(yBottom, pageHeight),
          width: columnWidths[index],
          height: rowHeight,
          borderColor,
          borderWidth: 1,
        });
        lines.forEach((line, lineIndex) => {
          if (!line) return;
          page.drawText(line, {
            x: x + padding,
            y: topToPdfY(yTop + padding + fontSize + lineIndex * lineHeight, pageHeight),
            size: fontSize,
            font,
          });
        });
        x += columnWidths[index];
      });

      cursorTop += rowHeight;
      if (isTotal) cursorTop += 6;
    };

    const drawHeader = () => {
      drawRow(headers, fontBold, true, false);
    };

    drawHeader();
    rows.forEach((row, index) => {
      if (cursorTop + lineHeight * 2 > pageHeight - marginBottom) {
        page = createPage(false);
        cursorTop = marginTop;
        drawHeader();
      }
      const isTotal = index === rows.length - 1;
      drawRow(row, isTotal ? fontBold : fontRegular, false, isTotal);
    });
  };

  const recipientLines = [supplier.name || supplierId, ...addressParts];
  let recipientTopCursor = recipientTop;
  recipientLines.forEach((line, index) => {
    const font = index === 0 ? fontBold : fontRegular;
    const size = 10.5;
    page.drawText(line, {
      x: recipientLeft,
      y: topToPdfY(recipientTopCursor + size, pageHeight),
      size,
      font,
    });
    recipientTopCursor += size * 1.3;
  });

  const dateLabel = language === 'EN' ? `Date: ${formatDate(Date.now(), locale)}` : `Datum: ${formatDate(Date.now(), locale)}`;
  drawRightAlignedText(dateLabel, pageWidth - dateRight, dateTop, 10, fontRegular, rgb(0.35, 0.35, 0.35));

  page.drawText(subject, {
    x: marginLeft,
    y: topToPdfY(subjectTop + 13, pageHeight),
    size: 13,
    font: fontBold,
  });

  if (preview) {
    page.drawText('VORSCHAU', {
      x: pageWidth / 4,
      y: pageHeight / 2,
      size: 72,
      font: fontBold,
      color: rgb(0.75, 0.75, 0.75),
      rotate: degrees(-20),
      opacity: 0.2,
    });
  }

  ensureSpace(0);

  cursorTop = drawWrappedText(page, {
    text: introText,
    x: marginLeft,
    top: cursorTop,
    maxWidth: pageWidth - marginLeft - marginRight,
    font: fontRegular,
    size: 10.5,
    lineHeight: 14,
  });
  cursorTop += 6;

  cursorTop = drawWrappedText(page, {
    text: statusLine,
    x: marginLeft,
    top: cursorTop,
    maxWidth: pageWidth - marginLeft - marginRight,
    font: fontBold,
    size: 10.5,
    lineHeight: 14,
  });
  cursorTop += 10;

  const tableTitle = language === 'EN' ? 'Evaluation results' : 'Bewertungsergebnisse';
  cursorTop = drawWrappedText(page, {
    text: tableTitle,
    x: marginLeft,
    top: cursorTop,
    maxWidth: pageWidth - marginLeft - marginRight,
    font: fontBold,
    size: 11,
    lineHeight: 14,
  });
  cursorTop += 4;

  const tableRows = [
    ...criteriaRows.map((row) => [row.label, row.grade, row.weight, row.weighted]),
    [overallRow.label, overallRow.grade, overallRow.weight, overallRow.weighted],
  ];

  const tableWidth = pageWidth - marginLeft - marginRight;
  const columnWidths = [
    tableWidth * 0.48,
    tableWidth * 0.14,
    tableWidth * 0.14,
    tableWidth * 0.24,
  ];

  drawTable({
    headers: [
      language === 'EN' ? 'Criterion' : 'Kriterium',
      language === 'EN' ? 'Grade' : 'Note',
      language === 'EN' ? 'Weight' : 'Gewicht',
      language === 'EN' ? 'Weighted score' : 'Gewichtete Note',
    ],
    rows: tableRows,
    columnWidths,
    fontSize: 9,
  });

  const measuresTitle = language === 'EN' ? 'Measures / next steps' : 'Maßnahmen / nächste Schritte';
  ensureSpace(18);
  cursorTop = drawWrappedText(page, {
    text: measuresTitle,
    x: marginLeft,
    top: cursorTop,
    maxWidth: pageWidth - marginLeft - marginRight,
    font: fontBold,
    size: 11,
    lineHeight: 14,
  });
  cursorTop += 4;

  cursorTop = drawBulletList(measuresLines, {
    x: marginLeft,
    top: cursorTop,
    maxWidth: pageWidth - marginLeft - marginRight,
    font: fontRegular,
    size: 10,
    lineHeight: 13,
  });

  cursorTop += 10;
  const closingText = language === 'EN'
    ? 'Thank you for your collaboration.'
    : 'Vielen Dank für die Zusammenarbeit.';
  cursorTop = drawWrappedText(page, {
    text: closingText,
    x: marginLeft,
    top: cursorTop,
    maxWidth: pageWidth - marginLeft - marginRight,
    font: fontRegular,
    size: 10.5,
    lineHeight: 14,
  });
  cursorTop += 12;

  const signatureConfig = layout.signature || {};
  if (signatureConfig.enabled) {
    const signatureName = 'Tobias Bauer';
    const signatureTitle = 'PRRC • Head of Quality Management (QMB/BdoL)';
    const signatureEmail = actor ? `E-Mail: ${actor}` : null;
    const showLegalFooter = signatureConfig.showLegalFooter !== false;
    const signatureLines = [];
    if (signatureConfig.showName !== false) signatureLines.push(signatureName);
    if (signatureConfig.showTitle !== false) signatureLines.push(signatureTitle);
    if (showLegalFooter && signatureConfig.showEmail !== false && signatureEmail) signatureLines.push(signatureEmail);

    const legalFooterColumns = {
      regular: [
        ['DFS-DIAMON GmbH', 'Amtsgericht: Hanau HRB 00000'],
        ['IBAN: DE00 0000 0000 0000 0000 00', 'BIC: XXXXDEFFXXX'],
        ['USt-IdNr.: DE000000000', 'VDDI'],
      ],
      compact: [
        ['DFS-DIAMON GmbH', 'Amtsgericht: Hanau HRB 00000', 'USt-IdNr.: DE000000000'],
        ['IBAN: DE00 0000 0000 0000 0000 00', 'BIC: XXXXDEFFXXX', 'VDDI'],
      ],
    };

    const estimateSignatureHeight = (compact) => {
      const textSize = compact ? 8.5 : 10;
      const lineHeight = textSize * 1.35;
      let height = signatureLines.length * lineHeight;
      if (showLegalFooter) {
        const footerSize = compact ? 6.5 : 7.5;
        const footerLineHeight = footerSize * 1.2;
        const footerSpacing = compact ? 4 : 6;
        const columns = compact ? legalFooterColumns.compact : legalFooterColumns.regular;
        const rows = Math.max(...columns.map((column) => column.length));
        height += footerSpacing + rows * footerLineHeight;
      }
      return height;
    };

    let compact = signatureConfig.compact === true;
    let signatureTop = Math.max(mmToPt(signatureConfig.startY), cursorTop);
    let signatureHeight = estimateSignatureHeight(compact);
    const availableBottom = pageHeight - marginBottom;
    if (signatureTop + signatureHeight > availableBottom && !compact) {
      compact = true;
      signatureHeight = estimateSignatureHeight(true);
    }
    const maxTop = availableBottom - signatureHeight;
    if (signatureTop > maxTop) {
      signatureTop = Math.max(marginTop, maxTop);
    }

    const textSize = compact ? 8.5 : 10;
    const lineHeight = textSize * 1.35;
    let sigCursor = signatureTop;
    signatureLines.forEach((line, index) => {
      const font = index === 0 ? fontBold : fontRegular;
      page.drawText(line, {
        x: marginLeft,
        y: topToPdfY(sigCursor + textSize, pageHeight),
        size: textSize,
        font,
      });
      sigCursor += lineHeight;
    });

    if (showLegalFooter) {
      const footerSize = compact ? 6.5 : 7.5;
      const footerLineHeight = footerSize * 1.2;
      const footerSpacing = compact ? 4 : 6;
      const columns = compact ? legalFooterColumns.compact : legalFooterColumns.regular;
      const columnGap = compact ? 16 : 12;
      const columnWidth =
        (pageWidth - marginLeft - marginRight - columnGap * (columns.length - 1)) / columns.length;
      sigCursor += footerSpacing;
      columns.forEach((column, columnIndex) => {
        column.forEach((line, rowIndex) => {
          page.drawText(line, {
            x: marginLeft + columnIndex * (columnWidth + columnGap),
            y: topToPdfY(sigCursor + footerSize + rowIndex * footerLineHeight, pageHeight),
            size: footerSize,
            font: fontRegular,
            color: rgb(0.25, 0.25, 0.25),
          });
        });
      });
    }
  }

  const pdfBytes = await pdfDoc.save();
  return Buffer.from(pdfBytes);
}

async function buildSupplierReport({ supplierId, year, actor }) {
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
  const supplier = supplierLookup.get(supplierId);
  if (!supplier) {
    throw new SupplierReportError('Lieferant nicht gefunden.', 404);
  }
  if (!filtered.length) {
    throw new SupplierReportError('Es liegen keine bewertbaren Einträge für den Lieferanten vor.');
  }
  const aggregates = buildAggregates(filtered);
  const language = supplier.correspondenceLanguage === 'EN' ? 'EN' : 'DE';
  const locale = language === 'EN' ? 'en-US' : 'de-DE';
  const statusClass = statusClassFor(aggregates.classification);
  const decisionLabel = statusDecisionText(aggregates.classification, language);
  const rationale =
    aggregates.topNegativeDrivers.length
      ? aggregates.topNegativeDrivers
          .map((driver) => `${language === 'EN' ? driver.labelEn : driver.labelDe} (${driver.average ?? '—'})`)
          .join(', ')
      : language === 'EN'
        ? 'No dominant negative drivers identified.'
        : 'Keine dominanten negativen Treiber identifiziert.';

  const pdfDoc = await PdfDocument.create();
  const backgroundImage = await pdfDoc.embedPng(await fs.readFile(LETTERHEAD_PATH));
  const fontRegular = await pdfDoc.embedFont(StandardFonts.Helvetica);
  const fontBold = await pdfDoc.embedFont(StandardFonts.HelveticaBold);
  const layout = createPdfLayout(pdfDoc, backgroundImage);

  layout.setCursorY(PAGE_SIZE.height - 190);
  layout.drawTextBlock({
    text:
      language === 'EN'
        ? `Supplier Evaluation Report ${year || ''}`.trim()
        : `Lieferantenbewertung – Report ${year || ''}`.trim(),
    x: PAGE_MARGIN.left,
    font: fontBold,
    fontSize: 14,
    maxWidth: PAGE_SIZE.width - PAGE_MARGIN.left - PAGE_MARGIN.right,
    marginBottom: 8,
  });

  layout.drawTextBlock({
    text: language === 'EN' ? 'Supplier master data' : 'Lieferantenstammdaten',
    x: PAGE_MARGIN.left,
    font: fontBold,
    fontSize: 11,
    maxWidth: PAGE_SIZE.width - PAGE_MARGIN.left - PAGE_MARGIN.right,
    marginBottom: 4,
  });

  const masterDataRows = [
    [language === 'EN' ? 'Supplier ID' : 'Lieferanten-ID', supplierId],
    [language === 'EN' ? 'Supplier name' : 'Lieferantenname', supplier.name || '—'],
    [language === 'EN' ? 'Supplier number' : 'Lieferantennummer', supplier.supplierNumber || '—'],
    [language === 'EN' ? 'Address' : 'Adresse', supplier.address || '—'],
    [language === 'EN' ? 'Country' : 'Land', supplier.country || '—'],
    [language === 'EN' ? 'Contact' : 'Kontakt', supplier.contactName || '—'],
    [language === 'EN' ? 'Email' : 'E-Mail', supplier.contactEmail || '—'],
    [language === 'EN' ? 'Critical supplier' : 'Kritischer Lieferant', supplier.critical ? 'Yes' : 'No'],
    [language === 'EN' ? 'Language' : 'Korrespondenzsprache', supplier.correspondenceLanguage || 'DE'],
  ];

  drawPdfTable(layout, {
    headers: [language === 'EN' ? 'Field' : 'Feld', language === 'EN' ? 'Value' : 'Wert'],
    rows: masterDataRows,
    columnWidths: [160, 320],
    fontRegular,
    fontBold,
    fontSize: 9,
  });

  layout.drawTextBlock({
    text: language === 'EN' ? 'Aggregated results' : 'Aggregierte Ergebnisse',
    x: PAGE_MARGIN.left,
    font: fontBold,
    fontSize: 11,
    maxWidth: PAGE_SIZE.width - PAGE_MARGIN.left - PAGE_MARGIN.right,
    marginBottom: 4,
  });

  const summaryText =
    language === 'EN'
      ? `Entries considered: ${aggregates.gradedEntries}\nAverage grade: ${aggregates.averageGrade ?? '—'}\nStatus class: ${
          aggregates.classification || '—'
        } (${decisionLabel})`
      : `Berücksichtigte Einträge: ${aggregates.gradedEntries}\nGesamtnote: ${aggregates.averageGrade ?? '—'}\nStatusklasse: ${
          aggregates.classification || '—'
        } (${decisionLabel})`;

  layout.drawTextBlock({
    text: summaryText,
    x: PAGE_MARGIN.left,
    font: fontRegular,
    fontSize: 10,
    maxWidth: PAGE_SIZE.width - PAGE_MARGIN.left - PAGE_MARGIN.right,
    marginBottom: 6,
  });

  layout.drawTextBlock({
    text: language === 'EN' ? 'Status & rationale' : 'Status & Begründung',
    x: PAGE_MARGIN.left,
    font: fontBold,
    fontSize: 11,
    maxWidth: PAGE_SIZE.width - PAGE_MARGIN.left - PAGE_MARGIN.right,
    marginBottom: 4,
  });

  layout.drawTextBlock({
    text:
      language === 'EN'
        ? `Status: ${statusDecisionText(aggregates.classification, 'EN')} – ${statusTextFor(statusClass, 'EN')}\nKey drivers: ${rationale}`
        : `Status: ${statusDecisionText(aggregates.classification, 'DE')} – ${statusTextFor(statusClass, 'DE')}\nHaupttreiber: ${rationale}`,
    x: PAGE_MARGIN.left,
    font: fontRegular,
    fontSize: 10,
    maxWidth: PAGE_SIZE.width - PAGE_MARGIN.left - PAGE_MARGIN.right,
    marginBottom: 8,
  });

  layout.drawTextBlock({
    text: language === 'EN' ? 'Criteria summary' : 'Kriterienübersicht',
    x: PAGE_MARGIN.left,
    font: fontBold,
    fontSize: 11,
    maxWidth: PAGE_SIZE.width - PAGE_MARGIN.left - PAGE_MARGIN.right,
    marginBottom: 4,
  });

  const criteriaRows = aggregates.criterionAverages.map((criterion) => [
    language === 'EN' ? criterion.labelEn : criterion.labelDe,
    Number.isFinite(criterion.average) ? Number(criterion.average.toFixed(2)) : '—',
    `${Math.round(criterion.weight * 100)}%`,
    Number.isFinite(criterion.average) ? formatWeighted(criterion.average, criterion.weight) : '—',
  ]);

  drawPdfTable(layout, {
    headers: [
      language === 'EN' ? 'Criterion' : 'Kriterium',
      language === 'EN' ? 'Grade' : 'Note',
      language === 'EN' ? 'Weighting' : 'Gewichtung',
      language === 'EN' ? 'Weighted' : 'Bewertung',
    ],
    rows: criteriaRows,
    columnWidths: [240, 60, 70, 90],
    fontRegular,
    fontBold,
    fontSize: 9,
  });

  layout.drawTextBlock({
    text: language === 'EN' ? 'Evaluation entries' : 'Bewertungseinträge',
    x: PAGE_MARGIN.left,
    font: fontBold,
    fontSize: 11,
    maxWidth: PAGE_SIZE.width - PAGE_MARGIN.left - PAGE_MARGIN.right,
    marginBottom: 4,
  });

  const entryRows = filtered.map((entry) => {
    const grade = entry.computedScore ?? entry.computedGrade ?? entryGrade(entry);
    const reference = `${entry.referenceType || (language === 'EN' ? 'Reference' : 'Bezug')}${
      entry.referenceNumber ? ` ${entry.referenceNumber}` : ''
    }`.trim();
    return [
      formatDate(entry.date, locale),
      reference,
      entry.description || '—',
      Number.isFinite(grade) ? Number(grade.toFixed(2)) : '—',
    ];
  });

  drawPdfTable(layout, {
    headers: [
      language === 'EN' ? 'Date' : 'Datum',
      language === 'EN' ? 'Reference' : 'Bezug',
      language === 'EN' ? 'Description' : 'Beschreibung',
      language === 'EN' ? 'Grade' : 'Note',
    ],
    rows: entryRows,
    columnWidths: [70, 120, 210, 60],
    fontRegular,
    fontBold,
    fontSize: 8,
  });

  layout.drawTextBlock({
    text:
      language === 'EN'
        ? `Generated on ${new Date().toLocaleString(locale)} by ${actor || 'System'}`
        : `Erzeugt am ${new Date().toLocaleString(locale)} durch ${actor || 'System'}`,
    x: PAGE_MARGIN.left,
    font: fontRegular,
    fontSize: 8,
    maxWidth: PAGE_SIZE.width - PAGE_MARGIN.left - PAGE_MARGIN.right,
  });

  const pdfBytes = await pdfDoc.save();
  return Buffer.from(pdfBytes);
}

export default async function handler(req, res) {
  if (applyAdminCors(req, res)) return;

  try {
    if (req.method === 'POST') {
      const raw = typeof req.body === 'string' ? req.body : JSON.stringify(req.body || {});
      if (Buffer.byteLength(raw || '', 'utf8') > MAX_REQUEST_BYTES) {
        return sendError(res, 413, 'payload too large', { limit: MAX_REQUEST_BYTES });
      }
    }

    const wantsWrite = ['POST'].includes(req.method);
    const actor = await requirePortalAccess(req, res, { tile: SUPPLIER_TILE, write: wantsWrite });
    if (!actor) return;

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
      let body = {};
      let localeOverride = null;
      let layoutOverride = null;
      if (req.method === 'POST') {
        body = readJson(req) || {};
        if (containsProhibitedContent(body)) {
          return sendError(
            res,
            400,
            'Do not send HTML/images. Only send small JSON. Layout is saved via supplier-report-layout.'
          );
        }
        const previewOnly = String(req.query?.preview).toLowerCase() === 'true';
        const allowedPreviewKeys = new Set(['locale', 'layout']);
        if (previewOnly) {
          const keys = Object.keys(body || {});
          if (keys.some((key) => !allowedPreviewKeys.has(key))) {
            return sendError(
              res,
              400,
              'Do not send HTML/images. Only send small JSON. Layout is saved via supplier-report-layout.'
            );
          }
        }
        const validated = validateSupplierReportBody(body);
        if (!validated.ok) {
          return sendError(res, validated.status || 400, validated.error);
        }
        localeOverride = validated.locale;
        if (validated.layout != null) {
          layoutOverride = normalizePreviewLayout(validated.layout);
          if (!layoutOverride) {
            return sendError(res, 400, 'Ungültiges Layout-Format.');
          }
        }
        body = {
          debug: validated.debug,
        };
      }
      const reportType = req.query?.type || 'report';
      const yearParam = req.query?.year;
      const year = yearParam ? Number(yearParam) : null;
      const actorName = actor?.email || '';
      const preview = String(req.query?.preview).toLowerCase() === 'true';
      if (!localeOverride && req.query?.locale) {
        const localeParam = String(req.query.locale).toLowerCase();
        if (['de', 'en'].includes(localeParam)) {
          localeOverride = localeParam;
        } else {
          return sendError(res, 400, 'Ungültige Sprache.');
        }
      }
      if (yearParam && !Number.isFinite(year)) {
        return sendError(res, 400, 'Bitte ein gültiges Bewertungsjahr angeben.');
      }
      if (reportType !== 'summary' && !supplierId) {
        return sendError(res, 400, 'Bitte einen Lieferanten auswählen.');
      }
      if (reportType !== 'summary' && !yearParam) {
        return sendError(res, 400, 'Bitte ein Bewertungsjahr angeben.');
      }
      let pdf;
      if (reportType === 'letter') {
        pdf = await buildSupplierLetter({
          supplierId,
          year,
          actor: actorName,
          layoutConfig: layoutOverride,
          preview,
          localeOverride,
        });
      } else if (reportType === 'report' || reportType === 'internal') {
        pdf = await buildSupplierReport({ supplierId, year, actor: actorName });
      } else if (reportType === 'summary') {
        pdf = await buildSummaryPdf();
      } else {
        return sendError(res, 400, 'Bitte einen gültigen Berichtstyp angeben.');
      }
      console.info('[supplier-reports] pdf generated', { type: reportType, supplierId, year });
      res.setHeader('Content-Type', 'application/pdf');
      const filenameYear = Number.isFinite(year) ? year : 'report';
      res.setHeader(
        'Content-Disposition',
        `inline; filename="supplier_letter_${filenameYear}.pdf"`
      );
      if (typeof res.status === 'function') {
        res.status(200).send(pdf);
      } else {
        res.statusCode = 200;
        res.end(pdf);
      }
      return;
    }
    if (req.method === 'POST') {
      const body = readJson(req) || {};
      if (containsProhibitedContent(body)) {
        return sendError(
          res,
          400,
          'Do not send HTML/images. Only send small JSON. Layout is saved via supplier-report-layout.'
        );
      }
      if (body?.format === 'csv') {
        const csv = await buildCsvReport();
        return sendJson(res, 200, { ok: true, csv });
      }
    }
    return sendError(res, 400, 'Bitte ein gültiges Exportformat angeben.');
  } catch (err) {
    applyAdminCors(req, res);
    if (err instanceof SupplierReportError) {
      return sendError(res, err.status, err.message);
    }
    console.error('[admin/supplier-reports] failed', err);
    return sendError(res, 500, 'Export konnte nicht erstellt werden.');
  }
}
