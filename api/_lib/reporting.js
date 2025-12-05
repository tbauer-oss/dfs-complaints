// api/_lib/reporting.js
// PDF-Reporting für Reklamationen (Mehrsprachig erweiterbar)

import fs from 'fs';
import path from 'path';
import PDFDocument from 'pdfkit';
import { storeGeneratedFile } from './uploads.js';
import { normalizeLangValue } from './store.js';
import {
  normalizeEvaluationText,
  normalizeEvaluationTranslations,
  normalizeDepartments,
  normalizeReportLinksMap,
} from './departments.js';

const REPORT_LANGS = {
  de: {
    title: 'Reklamationsbericht',
    ticket: 'Ticket',
    status: 'Status',
    decision: 'Entscheidung',
    customer: 'Kunde / Kontakt',
    email: 'E-Mail',
    created: 'Erstellt am',
    payload: 'Reklamationsdaten',
    internalEvaluation: 'Interne Bewertung',
    internalCause: 'Vermutete Ursache',
    departments: 'Betroffene Abteilungen',
    uploads: 'Anhänge',
    measures: 'Maßnahmen',
    qmSummary: 'QM Zusammenfassung',
    product: 'Produktdaten',
    batch: 'Charge / LOT',
    udi: 'UDI-DI',
    actions: 'Geplante Maßnahmen',
    notes: 'Interne Notizen',
    externalTitle: 'Externer Reklamationsbericht',
  },
  en: {
    title: 'Complaint Report',
    ticket: 'Ticket',
    status: 'Status',
    decision: 'Decision',
    customer: 'Customer / Contact',
    email: 'Email',
    created: 'Created at',
    payload: 'Complaint data',
    internalEvaluation: 'Internal assessment',
    internalCause: 'Likely cause',
    departments: 'Affected departments',
    uploads: 'Attachments',
    measures: 'Actions',
    qmSummary: 'QM summary',
    product: 'Product data',
    batch: 'Batch / LOT',
    udi: 'UDI-DI',
    actions: 'Planned actions',
    notes: 'Internal notes',
    externalTitle: 'External complaint report',
  },
  es: {
    title: 'Informe de reclamación',
    ticket: 'Ticket',
    status: 'Estado',
    decision: 'Decisión',
    customer: 'Cliente / Contacto',
    email: 'Correo',
    created: 'Creado el',
    payload: 'Datos de la reclamación',
    internalEvaluation: 'Evaluación interna',
    internalCause: 'Causa probable',
    departments: 'Departamentos afectados',
    uploads: 'Adjuntos',
    measures: 'Medidas',
    qmSummary: 'Resumen de QM',
    product: 'Datos del producto',
    batch: 'Lote',
    udi: 'UDI-DI',
    actions: 'Acciones planificadas',
    notes: 'Notas internas',
    externalTitle: 'Informe externo de reclamación',
  },
  fr: {
    title: 'Rapport de réclamation',
    ticket: 'Ticket',
    status: 'Statut',
    decision: 'Décision',
    customer: 'Client / Contact',
    email: 'E-mail',
    created: 'Créé le',
    payload: 'Données de réclamation',
    internalEvaluation: 'Évaluation interne',
    internalCause: 'Cause probable',
    departments: 'Départements concernés',
    uploads: 'Pièces jointes',
    measures: 'Mesures',
    qmSummary: 'Résumé QM',
    product: 'Données produit',
    batch: 'Lot',
    udi: 'UDI-DI',
    actions: 'Actions prévues',
    notes: 'Notes internes',
    externalTitle: 'Rapport de réclamation externe',
  },
  it: {
    title: 'Rapporto di reclamo',
    ticket: 'Ticket',
    status: 'Stato',
    decision: 'Decisione',
    customer: 'Cliente / Contatto',
    email: 'Email',
    created: 'Creato il',
    payload: 'Dati del reclamo',
    internalEvaluation: 'Valutazione interna',
    internalCause: 'Causa probabile',
    departments: 'Reparti coinvolti',
    uploads: 'Allegati',
    measures: 'Azioni',
    qmSummary: 'Sintesi QM',
    product: 'Dati prodotto',
    batch: 'Lotto',
    udi: 'UDI-DI',
    actions: 'Azioni pianificate',
    notes: 'Note interne',
    externalTitle: 'Rapporto reclamo esterno',
  },
};

const PAYLOAD_LABELS = {
  article: { de: 'Artikel', en: 'Article' },
  batch: { de: 'Charge', en: 'Batch' },
  qty: { de: 'Menge', en: 'Quantity' },
  expiry: { de: 'Ablaufdatum', en: 'Expiry' },
  desc: { de: 'Fehler / Beschreibung', en: 'Description' },
  reason: { de: 'Grund', en: 'Reason' },
  handling: { de: 'Gewünschte Behandlung', en: 'Requested handling' },
  segment: { de: 'Produktbereich', en: 'Segment' },
  productType: { de: 'Produkttyp', en: 'Product type' },
  product: { de: 'Produktname', en: 'Product name' },
  productName: { de: 'Produktname', en: 'Product name' },
  lot: { de: 'Charge/LOT', en: 'Batch/LOT' },
  udi: { de: 'UDI-DI', en: 'UDI-DI' },
  udiDi: { de: 'UDI-DI', en: 'UDI-DI' },
};

const DFS_BLUE = '#005AA9';
const DFS_DARK = '#0B345E';
const DFS_BLUE_LIGHT = '#0E6CC4';
const LIGHT_GREY = '#F4F6F9';
const BORDER_GREY = '#D5DBE5';
const TEXT_DARK = '#1F2933';
let cachedLogo;

function resolveLogoPath() {
  const candidates = [
    path.resolve(process.cwd(), 'flutter_web', 'assets', 'dfs_logo.png'),
  ];
  return candidates.find((p) => fs.existsSync(p));
}

function loadLogo() {
  if (cachedLogo === undefined) {
    const found = resolveLogoPath();
    cachedLogo = found ? fs.readFileSync(found) : null;
  }
  return cachedLogo;
}

function drawSectionTitle(doc, title, { index } = {}) {
  const startX = doc.page.margins.left;
  const availableWidth = doc.page.width - doc.page.margins.left - doc.page.margins.right;
  const label = index ? `${index}. ${title}` : title;

  doc.moveDown(0.8);

  doc
    .save()
    .fillColor(DFS_BLUE)
    .rect(startX, doc.y - 2, 6, 18)
    .fill()
    .restore();

  doc
    .save()
    .fillColor(DFS_DARK)
    .font('Helvetica-Bold')
    .fontSize(13)
    .text(label, startX + 12, doc.y - 2, { width: availableWidth - 12 });

  doc
    .strokeColor(BORDER_GREY)
    .lineWidth(1)
    .moveTo(startX, doc.y + 16)
    .lineTo(startX + availableWidth, doc.y + 16)
    .stroke();
  doc.restore();

  doc.moveDown(0.6);
}

function drawKeyValueTable(doc, entries, { columns = 2 } = {}) {
  if (!entries || entries.length === 0) return;
  const startX = doc.page.margins.left;
  const usableWidth = doc.page.width - doc.page.margins.left - doc.page.margins.right;
  const columnWidth = usableWidth / columns;

  const rows = [];
  for (let i = 0; i < entries.length; i += columns) {
    rows.push(entries.slice(i, i + columns));
  }

  rows.forEach((row) => {
    const baseY = doc.y;
    let rowHeight = 0;
    row.forEach((entry, idx) => {
      const x = startX + (idx * columnWidth);
      const label = entry?.label || '';
      const value = (entry?.value ?? '') || '–';
      const labelHeight = doc.heightOfString(label, { width: columnWidth - 10 });
      const valueHeight = doc.heightOfString(value, { width: columnWidth - 10 });
      rowHeight = Math.max(rowHeight, labelHeight + valueHeight + 10);

      doc
        .save()
        .lineWidth(0.5)
        .strokeColor(BORDER_GREY)
        .fillColor('#FFFFFF')
        .roundedRect(x + 2, baseY, columnWidth - 6, rowHeight + 10, 6)
        .fillAndStroke();

      doc
        .fillColor(DFS_BLUE)
        .font('Helvetica-Bold')
        .fontSize(9)
        .text(label, x + 10, baseY + 8, { width: columnWidth - 24, continued: false });
      doc
        .fillColor(TEXT_DARK)
        .font('Helvetica')
        .fontSize(11)
        .text(value, x + 10, baseY + 8 + labelHeight + 2, { width: columnWidth - 24 });
      doc.restore();
    });
    doc.y = baseY + rowHeight + 18;
  });
}

function drawBadge(doc, text, { color = DFS_BLUE } = {}) {
  if (!text) return;
  const paddingX = 8;
  const paddingY = 4;
  const width = doc.widthOfString(text, { fontSize: 10 }) + paddingX * 2;
  const startX = doc.page.width - doc.page.margins.right - width;
  const startY = doc.y;
  doc
    .save()
    .fillColor(color)
    .roundedRect(startX, startY, width, 20, 8)
    .fill();
  doc
    .fillColor('#FFFFFF')
    .fontSize(10)
    .text(text, startX + paddingX, startY + paddingY - 1, {
      width: width - paddingX * 2,
      align: 'center',
    })
    .restore();
  doc.moveDown(1.4);
}

function drawHeader(doc, { title, ticket, dateLabel, status, logoBuffer }) {
  const { left, right } = doc.page.margins;
  const startY = doc.y;
  const headerHeight = 130;
  const usableWidth = doc.page.width - left - right;

  doc
    .save()
    .fillColor(DFS_BLUE)
    .rect(left, startY, usableWidth, 10)
    .fill()
    .restore();

  doc
    .save()
    .rect(left, startY + 10, usableWidth, headerHeight - 10)
    .fill(LIGHT_GREY)
    .restore();

  if (logoBuffer) {
    doc
      .save()
      .image(logoBuffer, doc.page.width - right - 140, startY + 22, { fit: [130, 52], align: 'right' })
      .restore();
  }

  const metaStartX = left + 16;
  doc
    .save()
    .fillColor(DFS_DARK)
    .font('Helvetica-Bold')
    .fontSize(14)
    .text('DFS-DIAMON GmbH', metaStartX, startY + 18);
  doc
    .fillColor(TEXT_DARK)
    .font('Helvetica')
    .fontSize(10)
    .text('Reklamation / Complaint Management', metaStartX, doc.y + 2);

  doc
    .fillColor(DFS_DARK)
    .font('Helvetica-Bold')
    .fontSize(21)
    .text(title, metaStartX, startY + 48, { width: usableWidth / 1.6 });

  const chipY = doc.y + 8;
  doc
    .save()
    .fillColor('#FFFFFF')
    .roundedRect(metaStartX, chipY, usableWidth / 3, 44, 10)
    .fill()
    .lineWidth(0.7)
    .strokeColor(BORDER_GREY)
    .roundedRect(metaStartX, chipY, usableWidth / 3, 44, 10)
    .stroke()
    .restore();

  doc
    .fillColor(DFS_BLUE)
    .font('Helvetica-Bold')
    .fontSize(10)
    .text(ticket, metaStartX + 12, chipY + 8, { width: usableWidth / 3 - 24 });
  doc
    .fillColor(TEXT_DARK)
    .font('Helvetica')
    .fontSize(10)
    .text(dateLabel, metaStartX + 12, chipY + 24, { width: usableWidth / 3 - 24 });

  doc.y = startY + headerHeight;
  drawBadge(doc, status, { color: DFS_BLUE_LIGHT });
}

function labelFor(lang, key, fallback) {
  const lc = REPORT_LANGS[lang] ? lang : 'en';
  return REPORT_LANGS[lc][key] || fallback || key;
}

function payloadLabel(lang, key, fallback) {
  const lc = REPORT_LANGS[lang] ? lang : 'en';
  const map = PAYLOAD_LABELS[key];
  if (!map) return fallback || key;
  return map[lc] || map.en || fallback || key;
}

function formatDate(ts) {
  if (!ts) return '';
  try {
    return new Date(ts).toLocaleString('de-DE');
  } catch {
    return '';
  }
}

function textForEvaluation(complaint, lang) {
  const translations = normalizeEvaluationTranslations(complaint.internalEvaluationTranslations);
  if (lang && lang !== 'de' && translations[lang]) return translations[lang];
  return normalizeEvaluationText(complaint.internalEvaluationText_de) || '';
}

function qmSummaryForLang(complaint, lang) {
  const map = normalizeEvaluationTranslations(complaint.qmCustomerSummaryTranslations || {});
  if (lang && map[lang]) return map[lang];
  const base = (complaint.qmCustomerSummary ?? complaint.qmCustomerSummary_de)
    || complaint.qmCustomerSummary_en;
  return normalizeEvaluationText(base) || '';
}

function plannedActions(complaint) {
  const p = (complaint.payload && typeof complaint.payload === 'object') ? complaint.payload : {};
  const actions = p.plannedActions || p.actions || p.measures || p.massnahmen || p.maßnahmen;
  return (actions || '').toString();
}

function describeProduct(complaint) {
  const p = (complaint.payload && typeof complaint.payload === 'object') ? complaint.payload : {};
  return {
    name: p.product || p.productName || p.article || '',
    articleNo: p.articleNumber || p.article || p.item || '',
    batch: p.batch || p.lot || p.LOT || '',
    udi: p.udi || p.udiDi || p.udidi || '',
  };
}

function describeCustomer(complaint) {
  const p = (complaint.payload && typeof complaint.payload === 'object') ? complaint.payload : {};
  return {
    company: complaint.company || complaint.customer?.company || p.customerName || p.company || '',
    contact: complaint.contact || complaint.customer?.contact || p.contact || '',
    country: complaint.country || p.country || '',
    customerNo: complaint.customerNumber || complaint.customer?.customerNumber || p.customerNumber || '',
  };
}

function resolveReportLanguage(complaint, { preferredLang, fallback = 'de' } = {}) {
  const candidates = [
    preferredLang,
    complaint.reportLang,
    complaint.lang,
    complaint.language,
    complaint.account?.lang,
    complaint.account?.language,
    complaint.customer?.language,
    complaint.customer?.lang,
    complaint.payload?.lang,
    complaint.payload?.language,
  ];
  for (const cand of candidates) {
    const norm = normalizeLangValue(cand);
    if (norm) return norm;
  }
  return normalizeLangValue(fallback) || 'de';
}

async function buildPdf(complaint, { lang = 'de', variant = 'internal' } = {}) {
  const labels = REPORT_LANGS[lang] || REPORT_LANGS.en;
  const logoBuffer = loadLogo();
  const doc = new PDFDocument({ size: 'A4', margin: 50 });
  const chunks = [];
  doc.on('data', (chunk) => chunks.push(chunk));
  const done = new Promise((resolve) => doc.on('end', resolve));

  const customer = describeCustomer(complaint);
  const product = describeProduct(complaint);
  const payload = (complaint.payload && typeof complaint.payload === 'object') ? complaint.payload : {};
  const departments = normalizeDepartments(complaint.internalDepartments);
  const title = variant === 'external' ? labels.externalTitle : labels.title;

  drawHeader(doc, {
    title,
    ticket: `${labelFor(lang, 'ticket')}: ${complaint.ticket || '-'}`,
    dateLabel: `${labelFor(lang, 'created')}: ${formatDate(complaint.createdAt || complaint.updatedAt)}`,
    status: `${labelFor(lang, 'status')}: ${complaint.statusLabel || complaint.status || '-'}`,
    logoBuffer,
  });

  if (variant === 'internal') {
    const stammdaten = [
      { label: labelFor(lang, 'ticket'), value: complaint.ticket || '-' },
      { label: labelFor(lang, 'decision'), value: complaint.decision || '–' },
      { label: 'Datum / Uhrzeit', value: formatDate(complaint.createdAt || complaint.updatedAt) || '–' },
      { label: labelFor(lang, 'customer'), value: customer.company || customer.contact || '-' },
      { label: 'Kontakt', value: customer.contact || '-' },
      { label: labelFor(lang, 'email'), value: complaint.email || '-' },
      { label: 'Kundennummer', value: customer.customerNo || '–' },
      { label: 'Land', value: customer.country || '–' },
    ];

    drawSectionTitle(doc, 'Stammdaten', { index: 1 });
    drawKeyValueTable(doc, stammdaten);

    const produktDaten = [
      { label: payloadLabel(lang, 'product', 'Produkt'), value: product.name || '–' },
      { label: payloadLabel(lang, 'article', 'Artikelnummer'), value: product.articleNo || '–' },
      { label: labels.batch, value: product.batch || payload.batch || payload.lot || '–' },
      { label: labels.udi, value: product.udi || payload.udi || payload.udiDi || '–' },
      { label: payloadLabel(lang, 'qty', 'Menge'), value: payload.qty || payload.quantity || '–' },
      { label: payloadLabel(lang, 'expiry', 'Ablaufdatum'), value: payload.expiry || payload.expiration || '–' },
    ];

    drawSectionTitle(doc, 'Produktdaten', { index: 2 });
    drawKeyValueTable(doc, produktDaten);

    const descriptionEntries = [];
    const highlightedKeys = ['desc', 'reason', 'handling', 'error', 'fehlermeldung'];
    highlightedKeys.forEach((key) => {
      if (payload[key]) {
        descriptionEntries.push({
          label: payloadLabel(lang, key, key),
          value: payload[key],
        });
      }
    });

    drawSectionTitle(doc, 'Reklamationsbeschreibung', { index: 3 });
    drawKeyValueTable(doc, descriptionEntries.length > 0 ? descriptionEntries : [{ label: labelFor(lang, 'payload'), value: '–' }]);

    const remainingPayload = Object.entries(payload)
      .filter(([key]) => !['product', 'productName', 'article', 'articleNumber', 'item', 'lot', 'batch', 'udi', 'udiDi', ...highlightedKeys].includes(key))
      .map(([key, value]) => ({ label: payloadLabel(lang, key, key), value: (value ?? '').toString() }));
    if (remainingPayload.length > 0) {
      drawKeyValueTable(doc, remainingPayload);
    }

    drawSectionTitle(doc, 'Interne Analyse', { index: 4 });
    if (departments.length > 0) {
      drawKeyValueTable(doc, [{ label: labelFor(lang, 'departments'), value: departments.join(', ') }], { columns: 1 });
    }
    const evalText = textForEvaluation(complaint, lang);
    const cause = complaint.internalEvaluationCause || '';
    if (evalText || cause) {
      drawKeyValueTable(doc, [
        { label: labelFor(lang, 'internalEvaluation'), value: evalText || '–' },
        { label: labelFor(lang, 'internalCause'), value: cause || '–' },
      ], { columns: 1 });
    }

    drawSectionTitle(doc, 'Maßnahmen', { index: 5 });
    const actionText = plannedActions(complaint);
    drawKeyValueTable(doc, [
      { label: labels.actions, value: actionText || '–' },
    ], { columns: 1 });

    const uploads = Array.isArray(complaint.uploads) ? complaint.uploads : [];
    if (uploads.length > 0) {
      drawKeyValueTable(doc, [{ label: labelFor(lang, 'uploads'), value: uploads.map((u) => u.name || u.url || u.downloadUrl || 'Attachment').join('\n') }], { columns: 1 });
    }

    drawSectionTitle(doc, 'Abschluss / Status', { index: 6 });
    drawKeyValueTable(doc, [
      { label: labelFor(lang, 'status'), value: complaint.statusLabel || complaint.status || '–' },
      { label: labelFor(lang, 'decision'), value: complaint.decision || '–' },
      { label: labelFor(lang, 'notes'), value: complaint.adminNotes || '–' },
    ], { columns: 1 });
  } else {
    const summary = qmSummaryForLang(complaint, lang)
      || 'Zusammenfassung wird bereitgestellt / Summary will be provided soon';

    drawSectionTitle(doc, labels.product, { index: 1 });
    drawKeyValueTable(doc, [
      { label: payloadLabel(lang, 'product', 'Produkt'), value: product.name || '–' },
      { label: payloadLabel(lang, 'article', 'Artikelnummer'), value: product.articleNo || '–' },
      { label: labels.batch, value: product.batch || payload.batch || payload.lot || '–' },
      { label: labels.udi, value: product.udi || payload.udi || payload.udiDi || '–' },
    ]);

    drawSectionTitle(doc, labelFor(lang, 'customer'), { index: 2 });
    drawKeyValueTable(doc, [
      { label: labelFor(lang, 'customer'), value: customer.company || customer.contact || '–' },
      { label: labelFor(lang, 'email'), value: complaint.email || '-' },
      { label: 'Land', value: customer.country || '–' },
    ]);

    drawSectionTitle(doc, labels.qmSummary, { index: 3 });
    drawKeyValueTable(doc, [
      { label: labels.qmSummary, value: summary },
    ], { columns: 1 });

    const actionText = plannedActions(complaint);
    if (actionText) {
      drawSectionTitle(doc, labels.measures, { index: 4 });
      drawKeyValueTable(doc, [{ label: labels.measures, value: actionText }], { columns: 1 });
    }
  }

  doc.end();
  await done;
  const buffer = Buffer.concat(chunks);
  const filename = `${variant}_report_${complaint.ticket || 'report'}_${lang}.pdf`;
  const stored = await storeGeneratedFile(buffer, {
    ticket: complaint.ticket,
    filename,
    mime: 'application/pdf',
  });

  return stored ? { ...stored, lang, variant } : null;
}

export async function generateComplaintReport(complaint, { lang = 'de' } = {}) {
  return buildPdf(complaint, { lang, variant: 'internal' });
}

export async function generateInternalReport(complaint, { lang = 'de' } = {}) {
  return buildPdf(complaint, { lang, variant: 'internal' });
}

export async function generateExternalReport(complaint, { lang = 'de' } = {}) {
  return buildPdf(complaint, { lang, variant: 'external' });
}

export async function generateReportsForComplaint(complaint, { targetLangs = [] } = {}) {
  const langs = (Array.isArray(targetLangs) && targetLangs.length > 0)
    ? targetLangs
    : ['de'];
  const links = {};
  for (const lang of langs) {
    const normalized = normalizeLangValue(lang) || 'de';
    const res = await generateComplaintReport(complaint, { lang: normalized });
    if (res?.downloadUrl) links[normalized] = res.downloadUrl;
  }
  return links;
}

export async function generateDualReportsForComplaint(
  complaint,
  { preferredLang, includeFallbacks = true } = {},
) {
  const lang = resolveReportLanguage(complaint, { preferredLang, fallback: 'de' });
  const targets = new Set([lang]);
  if (includeFallbacks) {
    if (lang !== 'en') targets.add('en');
    if (lang !== 'de') targets.add('de');
  }

  const internalLinks = {};
  const externalLinks = {};
  for (const target of targets) {
    const internal = await generateInternalReport(complaint, { lang: target });
    if (internal?.downloadUrl) internalLinks[target] = internal.downloadUrl;
    const external = await generateExternalReport(complaint, { lang: target });
    if (external?.downloadUrl) externalLinks[target] = external.downloadUrl;
  }

  return {
    lang,
    internalLinks: normalizeReportLinksMap(internalLinks),
    externalLinks: normalizeReportLinksMap(externalLinks),
  };
}
