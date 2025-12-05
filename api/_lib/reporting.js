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
import { getProductByArticle } from './products.js';

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
  returned: { de: 'Produkte bereits zurückgeschickt?*', en: 'Products already returned?*' },
  privacy: { de: 'Ich stimme der Datenschutzerklärung zu.*', en: 'I agree to the privacy policy.*' },
  injuryDesc: { de: 'Beschreibung der Verletzung*', en: 'Description of injury*' },
};

const STATUS_LABELS = {
  1: 'Eingegangen',
  2: 'In Bearbeitung',
  3: 'Rückfrage erforderlich',
  4: 'In Nacharbeit',
  5: 'Abgeschlossen',
};

const DFS_BLUE = '#005AA9';
const DFS_DARK = '#0B345E';
const DFS_BLUE_LIGHT = '#0E6CC4';
const LIGHT_GREY = '#F4F6F9';
const BORDER_GREY = '#D5DBE5';
const TEXT_DARK = '#1F2933';
let cachedLogo;

function ensureSpace(doc, requiredHeight) {
  const bottomLimit = doc.page.height - doc.page.margins.bottom;
  if (doc.y + requiredHeight > bottomLimit) {
    doc.addPage();
  }
}

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

  ensureSpace(doc, 32);
  doc.moveDown(0.3);

  const barHeight = 18;
  const barWidth = 6;
  const titleY = doc.y;

  doc
    .save()
    .fillColor(DFS_BLUE)
    .rect(startX, titleY - 2, barWidth, barHeight)
    .fill()
    .restore();

  doc
    .save()
    .fillColor(DFS_DARK)
    .font('Helvetica-Bold')
    .fontSize(13)
    .text(label, startX + barWidth + 8, titleY - 1, { width: availableWidth - barWidth - 8 });

  doc
    .strokeColor(BORDER_GREY)
    .lineWidth(0.8)
    .moveTo(startX, doc.y + 10)
    .lineTo(startX + availableWidth, doc.y + 10)
    .stroke();
  doc.restore();

  doc.moveDown(0.8);
}

function drawKeyValueTable(doc, entries, { columns = 2 } = {}) {
  if (!entries || entries.length === 0) return;

  const startX = doc.page.margins.left;
  const usableWidth = doc.page.width - doc.page.margins.left - doc.page.margins.right;
  const gap = 14;
  const columnWidth = (usableWidth - gap * (columns - 1)) / columns;
  const padding = 9;
  const rowSpacing = 12;

  const rows = [];
  for (let i = 0; i < entries.length; i += columns) {
    rows.push(entries.slice(i, i + columns));
  }

  rows.forEach((row) => {
    let rowHeight = 0;
    row.forEach((entry) => {
      const label = (entry?.label || '').toString();
      const value = ((entry?.value ?? '') || '–').toString();
      const labelHeight = doc.heightOfString(label, { width: columnWidth - padding * 2 });
      const valueHeight = doc.heightOfString(value, { width: columnWidth - padding * 2 });
      rowHeight = Math.max(rowHeight, labelHeight + valueHeight + padding * 2 + 8);
    });

    ensureSpace(doc, rowHeight + rowSpacing);
    const baseY = doc.y;

    row.forEach((entry, idx) => {
      const label = (entry?.label || '').toString();
      const value = ((entry?.value ?? '') || '–').toString();
      const x = startX + idx * (columnWidth + gap);

      doc
        .save()
        .lineWidth(0.8)
        .strokeColor(BORDER_GREY)
        .fillColor('#FFFFFF')
        .roundedRect(x, baseY, columnWidth, rowHeight, 6)
        .fillAndStroke();

      doc
        .fillColor(DFS_BLUE)
        .font('Helvetica-Bold')
        .fontSize(10)
        .text(label, x + padding, baseY + padding, { width: columnWidth - padding * 2 });

      const labelHeight = doc.heightOfString(label, { width: columnWidth - padding * 2 });
      doc
        .fillColor(TEXT_DARK)
        .font('Helvetica')
        .fontSize(11)
        .text(value, x + padding, baseY + padding + labelHeight + 4, {
          width: columnWidth - padding * 2,
        });
      doc.restore();
    });

    doc.y = baseY + rowHeight + rowSpacing;
  });
}

function drawBadge(doc, text, { color = DFS_BLUE, x, y } = {}) {
  if (!text) return { width: 0, height: 0 };
  const paddingX = 8;
  const paddingY = 4;
  const width = doc.widthOfString(text, { fontSize: 10 }) + paddingX * 2;
  const height = 20;
  const startX = typeof x === 'number' ? x : (doc.page.width - doc.page.margins.right - width);
  const startY = typeof y === 'number' ? y : doc.y;
  doc
    .save()
    .fillColor(color)
    .roundedRect(startX, startY, width, height, 8)
    .fill();
  doc
    .fillColor('#FFFFFF')
    .fontSize(10)
    .text(text, startX + paddingX, startY + paddingY - 1, {
      width: width - paddingX * 2,
      align: 'center',
    })
    .restore();
  return { width, height };
}

function drawHeader(doc, { title, ticket, dateLabel, status, logoBuffer }) {
  const { left, right } = doc.page.margins;
  const startY = doc.y;
  const usableWidth = doc.page.width - left - right;
  const topBar = 6;
  const padding = 16;
  const logoAreaWidth = 140;
  const textWidth = usableWidth - logoAreaWidth - padding * 2;

  const titleHeight = doc.heightOfString(title, { width: textWidth, align: 'left' });
  const metaHeight = doc.heightOfString(dateLabel, { width: textWidth });
  const headerHeight = Math.max(86, titleHeight + metaHeight + padding * 2 + 10);

  doc
    .save()
    .fillColor(DFS_BLUE)
    .rect(left, startY, usableWidth, topBar)
    .fill()
    .restore();

  doc
    .save()
    .fillColor(LIGHT_GREY)
    .roundedRect(left, startY + topBar, usableWidth, headerHeight, 8)
    .fill()
    .restore();

  const contentY = startY + topBar + padding;
  const titleX = left + padding;

  if (logoBuffer) {
    doc
      .save()
      .image(logoBuffer, left + usableWidth - logoAreaWidth, contentY, { fit: [logoAreaWidth - padding, 50], align: 'right' })
      .restore();
  }

  doc
    .save()
    .fillColor(DFS_DARK)
    .font('Helvetica-Bold')
    .fontSize(12)
    .text('DFS-DIAMON GmbH', titleX, contentY);
  doc
    .fillColor(TEXT_DARK)
    .font('Helvetica')
    .fontSize(10)
    .text('Reklamation / Complaint Management', titleX, doc.y + 2);

  doc
    .fillColor(DFS_DARK)
    .font('Helvetica-Bold')
    .fontSize(18)
    .text(title, titleX, doc.y + 8, { width: textWidth });

  const metaY = doc.y + 6;
  const badge = drawBadge(doc, status, { color: DFS_BLUE_LIGHT, x: left + usableWidth - logoAreaWidth, y: metaY });

  doc
    .save()
    .fillColor(DFS_BLUE)
    .font('Helvetica-Bold')
    .fontSize(10)
    .text(ticket, titleX, metaY, { width: textWidth - badge.width - 12 });
  doc
    .fillColor(TEXT_DARK)
    .font('Helvetica')
    .fontSize(10)
    .text(dateLabel, titleX, doc.y + 4, { width: textWidth - badge.width - 12 });
  doc.restore();

  doc.y = startY + topBar + headerHeight + 12;
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

function statusLabelFor(complaint) {
  if (complaint?.statusLabel) return complaint.statusLabel;
  const status = complaint?.status;
  if (status == null) return '';
  const numeric = Number(status);
  return STATUS_LABELS[numeric] || '';
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

async function describeProduct(complaint) {
  const p = (complaint.payload && typeof complaint.payload === 'object') ? complaint.payload : {};
  const articleNo = complaint.product?.articleNumber || p.articleNumber || p.article || p.item || '';

  let catalogProduct = null;
  if (articleNo) {
    catalogProduct = await getProductByArticle(articleNo).catch(() => null);
  }

  const resolvedName = complaint.product?.productName
    || p.product
    || p.productName
    || catalogProduct?.productName
    || catalogProduct?.tdNumberAndName
    || '';

  const resolvedUdi = p.udi
    || p.udiDi
    || p.udidi
    || complaint.product?.udiDi
    || catalogProduct?.basicUdiDi
    || catalogProduct?.udiSingleUnit
    || catalogProduct?.udiVe
    || '';

  return {
    name: resolvedName,
    articleNo,
    batch: complaint.product?.batch || p.batch || p.lot || p.LOT || '',
    udi: resolvedUdi,
  };
}

function describeCustomer(complaint) {
  const p = (complaint.payload && typeof complaint.payload === 'object') ? complaint.payload : {};
  return {
    company: complaint.company
      || complaint.customer?.company
      || complaint.account?.company
      || p.customerName
      || p.company
      || complaint.customer?.name
      || '',
    contact: complaint.contact
      || complaint.customer?.contact
      || complaint.customer?.contactPerson
      || complaint.account?.contact
      || p.contact
      || '',
    country: complaint.country
      || complaint.customer?.country
      || complaint.customer?.address?.country
      || complaint.account?.country
      || p.country
      || '',
    customerNo: complaint.customerNumber
      || complaint.customer?.customerNumber
      || complaint.account?.customerNumber
      || p.customerNumber
      || '',
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
  const product = await describeProduct(complaint);
  const payload = (complaint.payload && typeof complaint.payload === 'object') ? complaint.payload : {};
  const departments = normalizeDepartments(complaint.internalDepartments);
  const title = variant === 'external' ? labels.externalTitle : labels.title;
  const statusText = statusLabelFor(complaint) || complaint.status || '-';

  drawHeader(doc, {
    title,
    ticket: `${labelFor(lang, 'ticket')}: ${complaint.ticket || '-'}`,
    dateLabel: `${labelFor(lang, 'created')}: ${formatDate(complaint.createdAt || complaint.updatedAt)}`,
    status: `${labelFor(lang, 'status')}: ${statusText}`,
    logoBuffer,
  });

  const baseInfoEntries = [
    { label: labelFor(lang, 'ticket'), value: complaint.ticket || '–' },
    { label: labelFor(lang, 'status'), value: statusText || '–' },
    { label: labelFor(lang, 'decision'), value: complaint.decision || '–' },
    { label: 'Datum / Uhrzeit', value: formatDate(complaint.createdAt || complaint.updatedAt) || '–' },
    { label: 'Sprache', value: (lang || '–').toUpperCase() },
    { label: labelFor(lang, 'customer'), value: customer.company || customer.contact || '–' },
    { label: 'Kontakt', value: customer.contact || '–' },
    { label: labelFor(lang, 'email'), value: complaint.email || '–' },
    { label: 'Kundennummer', value: customer.customerNo || '–' },
    { label: 'Land', value: customer.country || '–' },
  ];

  const productEntries = [
    { label: payloadLabel(lang, 'product', 'Produktname'), value: product.name || '–' },
    { label: payloadLabel(lang, 'article', 'Artikelnummer'), value: product.articleNo || '–' },
    { label: payloadLabel(lang, 'segment', 'Produktbereich'), value: payload.segment || '–' },
    { label: payloadLabel(lang, 'productType', 'Produkttyp'), value: payload.productType || '–' },
    { label: labels.batch, value: product.batch || payload.batch || payload.lot || '–' },
    { label: payloadLabel(lang, 'qty', 'Menge'), value: payload.qty || payload.quantity || '–' },
    { label: payloadLabel(lang, 'expiry', 'Ablaufdatum'), value: payload.expiry || payload.expiration || '–' },
    { label: labels.udi, value: product.udi || payload.udi || payload.udiDi || '–' },
  ];

  const descriptionKeys = ['desc', 'reason', 'handling', 'error', 'fehlermeldung', 'applied', 'injury', 'injuryDesc', 'returned', 'privacy'];
  const productKeys = ['product', 'productName', 'article', 'articleNumber', 'item', 'lot', 'batch', 'udi', 'udiDi', 'qty', 'quantity', 'expiry', 'expiration', 'segment', 'productType'];
  const descriptionEntries = descriptionKeys
    .filter((key) => payload[key])
    .map((key) => ({ label: payloadLabel(lang, key, key), value: payload[key] }));

  const remainingPayload = Object.entries(payload)
    .filter(([key]) => !productKeys.includes(key) && !descriptionKeys.includes(key))
    .map(([key, value]) => ({ label: payloadLabel(lang, key, key), value: (value ?? '').toString() }));

  if (variant === 'internal') {
    drawSectionTitle(doc, 'Stammdaten', { index: 1 });
    drawKeyValueTable(doc, baseInfoEntries);

    drawSectionTitle(doc, 'Produktdaten', { index: 2 });
    drawKeyValueTable(doc, productEntries);

    drawSectionTitle(doc, 'Reklamationsbeschreibung', { index: 3 });
    const complaintEntries = descriptionEntries.concat(remainingPayload);
    drawKeyValueTable(doc, complaintEntries.length > 0 ? complaintEntries : [{ label: labelFor(lang, 'payload'), value: '–' }], { columns: 1 });

    drawSectionTitle(doc, 'Interne Analyse', { index: 4 });
    const analysisEntries = [];
    if (departments.length > 0) {
      analysisEntries.push({ label: labelFor(lang, 'departments'), value: departments.join(', ') });
    }
    const evalText = textForEvaluation(complaint, lang);
    if (evalText) {
      analysisEntries.push({ label: labelFor(lang, 'internalEvaluation'), value: evalText });
    }
    if (complaint.internalEvaluationCause) {
      analysisEntries.push({ label: labelFor(lang, 'internalCause'), value: complaint.internalEvaluationCause });
    }
    drawKeyValueTable(doc, analysisEntries.length > 0 ? analysisEntries : [{ label: labelFor(lang, 'internalEvaluation'), value: '–' }], { columns: 1 });

    drawSectionTitle(doc, 'Maßnahmen', { index: 5 });
    const measuresEntries = [];
    const actionText = plannedActions(complaint);
    measuresEntries.push({ label: labels.actions, value: actionText || '–' });
    const summaryText = qmSummaryForLang(complaint, lang);
    if (summaryText) {
      measuresEntries.push({ label: labels.qmSummary, value: summaryText });
    }
    drawKeyValueTable(doc, measuresEntries, { columns: 1 });

    const uploads = Array.isArray(complaint.uploads) ? complaint.uploads : [];
    if (uploads.length > 0) {
      drawKeyValueTable(doc, [{ label: labelFor(lang, 'uploads'), value: uploads.map((u) => u.name || u.url || u.downloadUrl || 'Attachment').join('\n') }], { columns: 1 });
    }

    drawSectionTitle(doc, 'Abschluss / Status', { index: 6 });
    drawKeyValueTable(doc, [
      { label: labelFor(lang, 'status'), value: statusText || '–' },
      { label: labelFor(lang, 'decision'), value: complaint.decision || '–' },
      { label: labelFor(lang, 'notes'), value: complaint.adminNotes || '–' },
    ], { columns: 1 });
  } else {
    drawSectionTitle(doc, 'Stammdaten', { index: 1 });
    drawKeyValueTable(doc, baseInfoEntries);

    drawSectionTitle(doc, 'Produktdaten', { index: 2 });
    drawKeyValueTable(doc, productEntries);

    drawSectionTitle(doc, 'Reklamationsbeschreibung', { index: 3 });
    const complaintEntries = descriptionEntries.concat(remainingPayload);
    drawKeyValueTable(doc, complaintEntries.length > 0 ? complaintEntries : [{ label: labelFor(lang, 'payload'), value: '–' }], { columns: 1 });

    const summary = qmSummaryForLang(complaint, lang)
      || 'Zusammenfassung wird bereitgestellt / Summary will be provided soon';
    const actionText = plannedActions(complaint);

    drawSectionTitle(doc, labels.measures, { index: 4 });
    const measuresEntries = [
      { label: labels.qmSummary, value: summary },
      { label: labels.measures, value: actionText || '–' },
    ];
    drawKeyValueTable(doc, measuresEntries, { columns: 1 });
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
