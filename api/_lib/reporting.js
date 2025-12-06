// api/_lib/reporting.js
// Neu implementierte Report-Logik für Reklamationen im DFS-CI-Design.
// Architekturziele:
// - Nur saubere, wartbare Funktionen ohne Altlasten.
// - Klare Trennung von internen und externen Reports.
// - Sprachen: intern ausschließlich DE, extern DE & EN.
// - Automatisches, idempotentes Generieren beim Statuswechsel auf "Abgeschlossen".

import fs from 'fs';
import path from 'path';
import PDFDocument from 'pdfkit';
import { storeGeneratedFile } from './uploads.js';
import { normalizeLangValue } from './store.js';
import { normalizeReportLinksMap, normalizeDepartments } from './departments.js';
import { getProductByArticle } from './products.js';

const STATUS_CLOSED = 5; // siehe store.js Status.CLOSED

const COLORS = {
  primary: '#005AA9',
  primaryDark: '#0B345E',
  accent: '#0E6CC4',
  lightBackground: '#F4F6F9',
  border: '#D5DBE5',
  text: '#1F2933',
};

const LOGO_CANDIDATES = [
  path.resolve(process.cwd(), 'flutter_web', 'assets', 'dfs_logo.png'),
  path.resolve(process.cwd(), 'flutter_web', 'assets', 'dfs_logo.svg'),
];
let cachedLogo = undefined;

const INTERNAL_LANGUAGE = 'de';
const EXTERNAL_LANGUAGES = ['de', 'en'];

const SECTION_TITLES = {
  internal: {
    de: {
      title: 'Interner Reklamationsbericht',
      base: 'Stammdaten',
      product: 'Produktdaten',
      complaint: 'Reklamationsdetails',
      analysis: 'Analyse',
      actions: 'Maßnahmen',
      closure: 'Abschluss / Status',
      attachments: 'Anhänge',
    },
  },
  external: {
    de: {
      title: 'Externer Reklamationsbericht',
      base: 'Kundendaten',
      product: 'Produktdaten',
      complaint: 'Reklamationsdetails',
      actions: 'Maßnahmen / Entscheidung',
    },
    en: {
      title: 'External Complaint Report',
      base: 'Customer Data',
      product: 'Product Data',
      complaint: 'Complaint Details',
      actions: 'Actions / Decision',
    },
  },
};

const LABELS = {
  de: {
    ticket: 'Ticketnummer',
    status: 'Status',
    decision: 'Entscheidung',
    created: 'Erstellt am',
    language: 'Sprache',
    customer: 'Kunde',
    contact: 'Ansprechpartner',
    email: 'E-Mail',
    customerNo: 'Kundennummer',
    country: 'Land',
    productName: 'Produkt',
    articleNo: 'Artikelnummer',
    batch: 'Charge / LOT',
    udi: 'UDI-DI',
    quantity: 'Menge',
    segment: 'Produktbereich',
    productType: 'Produkttyp',
    description: 'Beschreibung',
    reason: 'Reklamationsgrund',
    handling: 'Gewünschte Behandlung',
    actions: 'Maßnahmen',
    qmSummary: 'QM Zusammenfassung für Kunden',
    internalEval: 'Interne Bewertung / Analyse',
    internalCause: 'Vermutete Ursache',
    departments: 'Betroffene Abteilungen',
    notes: 'Interne Notizen',
    uploads: 'Anhänge',
    decisionText: 'Entscheidung',
    actionNote: 'Erläuterung',
  },
  en: {
    ticket: 'Ticket',
    status: 'Status',
    decision: 'Decision',
    created: 'Created at',
    language: 'Language',
    customer: 'Customer',
    contact: 'Contact',
    email: 'Email',
    customerNo: 'Customer No.',
    country: 'Country',
    productName: 'Product',
    articleNo: 'Article No.',
    batch: 'Batch / LOT',
    udi: 'UDI-DI',
    quantity: 'Quantity',
    segment: 'Segment',
    productType: 'Product type',
    description: 'Description',
    reason: 'Reason',
    handling: 'Requested handling',
    actions: 'Actions',
    qmSummary: 'Customer Summary',
    internalEval: 'Internal evaluation',
    internalCause: 'Likely cause',
    departments: 'Affected departments',
    notes: 'Internal notes',
    uploads: 'Attachments',
    decisionText: 'Decision',
    actionNote: 'Explanation',
  },
};

function resolveLogoBuffer() {
  if (cachedLogo !== undefined) return cachedLogo;
  for (const candidate of LOGO_CANDIDATES) {
    if (fs.existsSync(candidate)) {
      cachedLogo = fs.readFileSync(candidate);
      return cachedLogo;
    }
  }
  cachedLogo = null;
  return cachedLogo;
}

function ensureSpace(doc, requiredHeight) {
  const bottom = doc.page.height - doc.page.margins.bottom;
  if (doc.y + requiredHeight > bottom) doc.addPage();
}

function drawSectionTitle(doc, title, index) {
  const startX = doc.page.margins.left;
  const usableWidth = doc.page.width - doc.page.margins.left - doc.page.margins.right;
  const label = index ? `${index}. ${title}` : title;

  ensureSpace(doc, 32);
  const barWidth = 6;
  const barHeight = 16;
  const y = doc.y;

  doc.save();
  doc.fillColor(COLORS.primary).rect(startX, y, barWidth, barHeight).fill();
  doc.fillColor(COLORS.primaryDark).font('Helvetica-Bold').fontSize(13);
  doc.text(label, startX + barWidth + 8, y - 2, { width: usableWidth - barWidth - 8 });
  doc.strokeColor(COLORS.border).lineWidth(0.8).moveTo(startX, doc.y + 6).lineTo(startX + usableWidth, doc.y + 6).stroke();
  doc.restore();
  doc.moveDown(0.8);
}

function drawKeyValue(doc, pairs, { columns = 2 } = {}) {
  if (!pairs || pairs.length === 0) return;
  const startX = doc.page.margins.left;
  const usableWidth = doc.page.width - doc.page.margins.left - doc.page.margins.right;
  const gap = 14;
  const columnWidth = (usableWidth - gap * (columns - 1)) / columns;
  const padding = 9;
  const spacing = 12;

  const rows = [];
  for (let i = 0; i < pairs.length; i += columns) rows.push(pairs.slice(i, i + columns));

  rows.forEach((row) => {
    let rowHeight = 0;
    row.forEach(({ label, value }) => {
      const lh = doc.heightOfString(label, { width: columnWidth - padding * 2 });
      const vh = doc.heightOfString(value, { width: columnWidth - padding * 2 });
      rowHeight = Math.max(rowHeight, lh + vh + padding * 2 + 8);
    });

    ensureSpace(doc, rowHeight + spacing);
    const baseY = doc.y;

    row.forEach(({ label, value }, idx) => {
      const x = startX + idx * (columnWidth + gap);
      doc.save();
      doc.lineWidth(0.8).strokeColor(COLORS.border).fillColor('#FFFFFF');
      doc.roundedRect(x, baseY, columnWidth, rowHeight, 6).fillAndStroke();
      doc.fillColor(COLORS.primary).font('Helvetica-Bold').fontSize(10);
      doc.text(label, x + padding, baseY + padding, { width: columnWidth - padding * 2 });
      const lh = doc.heightOfString(label, { width: columnWidth - padding * 2 });
      doc.fillColor(COLORS.text).font('Helvetica').fontSize(11);
      doc.text(value || '–', x + padding, baseY + padding + lh + 4, { width: columnWidth - padding * 2 });
      doc.restore();
    });

    doc.y = baseY + rowHeight + spacing;
  });
}

function drawHeader(doc, { title, ticket, created, status, logo }) {
  const { left, right } = doc.page.margins;
  const usableWidth = doc.page.width - left - right;
  const padding = 16;
  const logoWidth = 150;
  const headerHeight = 90;

  const startY = doc.y;
  doc.save();
  doc.fillColor(COLORS.primary).rect(left, startY, usableWidth, 6).fill();
  doc.fillColor(COLORS.lightBackground).roundedRect(left, startY + 6, usableWidth, headerHeight, 8).fill();
  doc.restore();

  const textX = left + padding;
  const contentY = startY + 6 + padding;

  if (logo) {
    doc.save();
    doc.image(logo, left + usableWidth - logoWidth, contentY - 4, { fit: [logoWidth - padding, 48], align: 'right' });
    doc.restore();
  }

  doc.save();
  doc.fillColor(COLORS.primaryDark).font('Helvetica-Bold').fontSize(12);
  doc.text('DFS-DIAMON GmbH', textX, contentY);
  doc.fillColor(COLORS.text).font('Helvetica').fontSize(10);
  doc.text('Reklamation / Complaint Management', textX, doc.y + 2);
  doc.fillColor(COLORS.primaryDark).font('Helvetica-Bold').fontSize(18);
  doc.text(title, textX, doc.y + 8, { width: usableWidth - logoWidth - padding });

  const badgeY = doc.y + 6;
  const badgeText = status ? `Status: ${status}` : '';
  if (badgeText) drawBadge(doc, badgeText, { y: badgeY });

  doc.fillColor(COLORS.text).font('Helvetica').fontSize(10);
  doc.text(ticket, textX, badgeY + 26);
  doc.text(created, textX, doc.y + 4);
  doc.moveDown(2);
  doc.restore();
}

function drawBadge(doc, text, { color = COLORS.primary, y }) {
  if (!text) return;
  const paddingX = 8;
  const paddingY = 4;
  const width = doc.widthOfString(text, { fontSize: 10 }) + paddingX * 2;
  const x = doc.page.width - doc.page.margins.right - width;
  const startY = y ?? doc.y;
  doc.save();
  doc.fillColor(color).roundedRect(x, startY, width, 20, 8).fill();
  doc.fillColor('#FFFFFF').fontSize(10).text(text, x + paddingX, startY + paddingY - 1, { width: width - paddingX * 2, align: 'center' });
  doc.restore();
}

function formatDate(ts) {
  if (!ts) return '';
  try { return new Date(ts).toLocaleString('de-DE'); }
  catch { return ''; }
}

function safe(value) {
  if (value === undefined || value === null) return '';
  if (typeof value === 'string') return value.trim();
  return String(value);
}

function resolveLang(lang) {
  const normalized = normalizeLangValue(lang) || 'de';
  return (normalized === 'en') ? 'en' : 'de';
}

function resolveCustomerLang(complaint, preferred) {
  const candidates = [preferred, complaint?.reportLang, complaint?.lang, complaint?.language, complaint?.customer?.language, complaint?.account?.language];
  for (const c of candidates) {
    const norm = normalizeLangValue(c);
    if (norm === 'de' || norm === 'en') return norm;
  }
  return 'de';
}

async function describeProduct(complaint) {
  const payload = (complaint?.payload && typeof complaint.payload === 'object') ? complaint.payload : {};
  const article = complaint?.product?.articleNumber || payload.articleNumber || payload.article || '';
  let catalogProduct = null;
  if (article) {
    try { catalogProduct = await getProductByArticle(article); }
    catch (err) { console.warn('[reporting] product lookup failed', err?.message || err); }
  }
  return {
    name: complaint?.product?.productName || payload.product || payload.productName || catalogProduct?.productName || '',
    article,
    batch: complaint?.product?.batch || payload.batch || payload.lot || payload.LOT || '',
    udi: payload.udi || payload.udiDi || complaint?.product?.udiDi || catalogProduct?.basicUdiDi || '',
    quantity: payload.qty || payload.quantity || '',
    segment: payload.segment || '',
    productType: payload.productType || '',
  };
}

function describeCustomer(complaint) {
  const payload = (complaint?.payload && typeof complaint.payload === 'object') ? complaint.payload : {};
  const customer = complaint?.customer || complaint?.account || {};
  return {
    company: complaint?.company || customer.company || payload.company || payload.customerName || payload.company_name || '',
    contact: complaint?.contact || customer.contact || payload.contactPerson || payload.contact || '',
    email: complaint?.email || payload.email || '',
    country: complaint?.country || customer.country || payload.country || '',
    customerNo: complaint?.customerNumber || customer.customerNumber || payload.customerNumber || payload.customerNo || '',
  };
}

function statusLabel(status) {
  const numeric = Number(status);
  switch (numeric) {
    case 1: return 'Eingegangen';
    case 2: return 'In Bearbeitung';
    case 3: return 'Rückfrage erforderlich';
    case 4: return 'In Nacharbeit';
    case 5: return 'Abgeschlossen';
    default: return '';
  }
}

function internalAnalysisEntries(complaint, lang) {
  const entries = [];
  const departments = normalizeDepartments(complaint?.internalDepartments);
  if (departments.length) entries.push({ label: LABELS[lang].departments, value: departments.join(', ') });
  if (complaint?.internalEvaluationText_de) entries.push({ label: LABELS[lang].internalEval, value: safe(complaint.internalEvaluationText_de) });
  if (complaint?.internalEvaluationCause) entries.push({ label: LABELS[lang].internalCause, value: safe(complaint.internalEvaluationCause) });
  if (complaint?.adminNotes) entries.push({ label: LABELS[lang].notes, value: safe(complaint.adminNotes) });
  return entries;
}

function qmSummaryForLang(complaint, lang) {
  const translations = complaint?.qmCustomerSummaryTranslations || {};
  const preferred = lang && translations[lang];
  if (preferred) return safe(preferred);
  return safe(complaint?.qmCustomerSummary_de || complaint?.qmCustomerSummary || complaint?.qmCustomerSummary_en || '');
}

function plannedActions(complaint) {
  const payload = (complaint?.payload && typeof complaint.payload === 'object') ? complaint.payload : {};
  const actions = payload.plannedActions || payload.actions || payload.measures || payload.massnahmen || payload['maßnahmen'];
  return safe(actions);
}

function externalActionsBlock(complaint, lang) {
  const labels = LABELS[lang];
  const summary = qmSummaryForLang(complaint, lang) || '–';
  const actions = plannedActions(complaint) || '–';
  const decision = safe(complaint?.decision) || '–';
  return [
    { label: labels.decisionText, value: decision },
    { label: labels.actionNote, value: summary },
    { label: labels.actions, value: actions },
  ];
}

function complaintDescriptionEntries(complaint, lang) {
  const payload = (complaint?.payload && typeof complaint.payload === 'object') ? complaint.payload : {};
  const labels = LABELS[lang];
  const map = [];
  if (payload.desc || payload.description) map.push({ label: labels.description, value: safe(payload.desc || payload.description) });
  if (payload.reason) map.push({ label: labels.reason, value: safe(payload.reason) });
  if (payload.handling) map.push({ label: labels.handling, value: safe(payload.handling) });
  return map;
}

async function buildReportBuffer({ complaint, variant, lang }) {
  const language = resolveLang(lang);
  const labels = LABELS[language];
  const sections = SECTION_TITLES[variant][language] || SECTION_TITLES[variant].de;
  const logo = resolveLogoBuffer();
  const customer = describeCustomer(complaint);
  const product = await describeProduct(complaint);
  const payload = (complaint?.payload && typeof complaint.payload === 'object') ? complaint.payload : {};
  const statusText = statusLabel(complaint?.status);

  const doc = new PDFDocument({ size: 'A4', margin: variant === 'external' ? 44 : 52 });
  const chunks = [];
  doc.on('data', (c) => chunks.push(c));
  const done = new Promise((resolve, reject) => { doc.on('end', resolve); doc.on('error', reject); });

  drawHeader(doc, {
    title: sections.title,
    ticket: `${labels.ticket}: ${safe(complaint?.ticket) || '–'}`,
    created: `${labels.created}: ${formatDate(complaint?.createdAt || complaint?.updatedAt)}`,
    status: statusText,
    logo,
  });

  const baseEntries = [
    { label: labels.ticket, value: safe(complaint?.ticket) || '–' },
    { label: labels.status, value: statusText || '–' },
    { label: labels.decision, value: safe(complaint?.decision) || '–' },
    { label: labels.language, value: language.toUpperCase() },
    { label: labels.customer, value: safe(customer.company) || '–' },
    { label: labels.contact, value: safe(customer.contact) || '–' },
    { label: labels.email, value: safe(customer.email) || '–' },
    { label: labels.customerNo, value: safe(customer.customerNo) || '–' },
    { label: labels.country, value: safe(customer.country) || '–' },
  ];

  const productEntries = [
    { label: labels.productName, value: safe(product.name) || '–' },
    { label: labels.articleNo, value: safe(product.article) || '–' },
    { label: labels.segment, value: safe(product.segment) || '–' },
    { label: labels.productType, value: safe(product.productType) || '–' },
    { label: labels.batch, value: safe(product.batch) || '–' },
    { label: labels.quantity, value: safe(product.quantity) || '–' },
    { label: labels.udi, value: safe(product.udi) || '–' },
  ];

  const complaintEntries = complaintDescriptionEntries(complaint, language);
  if (!complaintEntries.length) complaintEntries.push({ label: labels.description, value: '–' });

  drawSectionTitle(doc, sections.base, 1);
  drawKeyValue(doc, baseEntries);

  drawSectionTitle(doc, sections.product, 2);
  drawKeyValue(doc, productEntries);

  drawSectionTitle(doc, sections.complaint, 3);
  drawKeyValue(doc, complaintEntries, { columns: 1 });

  if (variant === 'internal') {
    drawSectionTitle(doc, sections.analysis, 4);
    const analysisEntries = internalAnalysisEntries(complaint, language);
    drawKeyValue(doc, analysisEntries.length ? analysisEntries : [{ label: labels.internalEval, value: '–' }], { columns: 1 });

    drawSectionTitle(doc, sections.actions, 5);
    const actions = plannedActions(complaint) || '–';
    const summary = qmSummaryForLang(complaint, language) || '–';
    drawKeyValue(doc, [
      { label: labels.actions, value: actions },
      { label: labels.qmSummary, value: summary },
    ], { columns: 1 });

    const uploads = Array.isArray(complaint?.uploads) ? complaint.uploads : [];
    if (uploads.length) {
      drawSectionTitle(doc, sections.attachments);
      drawKeyValue(doc, [{ label: labels.uploads, value: uploads.map((u) => safe(u.name || u.url || u.downloadUrl || 'Attachment')).join('\n') }], { columns: 1 });
    }

    drawSectionTitle(doc, sections.closure, 6);
    drawKeyValue(doc, [
      { label: labels.status, value: statusText || '–' },
      { label: labels.decision, value: safe(complaint?.decision) || '–' },
      { label: labels.notes, value: safe(complaint?.adminNotes) || '–' },
    ], { columns: 1 });
  } else {
    drawSectionTitle(doc, sections.actions, 4);
    const actions = externalActionsBlock(complaint, language);
    drawKeyValue(doc, actions, { columns: 1 });
  }

  doc.end();
  await done;
  return Buffer.concat(chunks);
}

function buildFilename(variant, lang, ticket) {
  const safeTicket = safe(ticket) || 'report';
  const langSuffix = (lang || 'de').toUpperCase();
  const variantLabel = variant === 'internal' ? 'Internal' : 'External';
  return `ComplaintReport_${variantLabel}_${safeTicket}_${langSuffix}.pdf`;
}

async function storeReport(buffer, { complaint, variant, lang }) {
  const filename = buildFilename(variant, lang, complaint?.ticket);
  const stored = await storeGeneratedFile(buffer, {
    ticket: complaint?.ticket,
    filename,
    mime: 'application/pdf',
  });
  if (!stored?.downloadUrl) return null;
  return { downloadUrl: stored.downloadUrl, filename, lang: resolveLang(lang), variant };
}

async function generateSingleReport(complaint, variant, lang) {
  const buffer = await buildReportBuffer({ complaint, variant, lang });
  return storeReport(buffer, { complaint, variant, lang });
}

export async function generateComplaintReports(complaint, { preferredLang } = {}) {
  if (!complaint || Number(complaint.status) !== STATUS_CLOSED) return null;

  const targetCustomerLang = resolveCustomerLang(complaint, preferredLang);
  const requiredExternal = new Set(EXTERNAL_LANGUAGES);
  requiredExternal.add(targetCustomerLang); // falls preferredLang en/de, Set sichert Mindestumfang

  const existingInternal = normalizeReportLinksMap(complaint.internalReportLinks || {});
  const existingExternal = normalizeReportLinksMap(complaint.externalReportLinks || {});

  const internalLinks = { ...existingInternal };
  const externalLinks = { ...existingExternal };

  // Intern: nur Deutsch, idempotent
  if (!internalLinks[INTERNAL_LANGUAGE]) {
    try {
      const internal = await generateSingleReport(complaint, 'internal', INTERNAL_LANGUAGE);
      if (internal?.downloadUrl) internalLinks[INTERNAL_LANGUAGE] = internal.downloadUrl;
    } catch (err) {
      console.error('[reporting] internal report failed', err?.message || err);
    }
  }

  // Extern: Deutsch & Englisch (mindestens)
  for (const lang of requiredExternal) {
    const resolved = resolveLang(lang);
    if (externalLinks[resolved]) continue;
    try {
      const external = await generateSingleReport(complaint, 'external', resolved);
      if (external?.downloadUrl) externalLinks[resolved] = external.downloadUrl;
    } catch (err) {
      console.error('[reporting] external report failed', resolved, err?.message || err);
    }
  }

  const normalizedInternal = normalizeReportLinksMap(internalLinks);
  const normalizedExternal = normalizeReportLinksMap(externalLinks);
  const hasLinks = Object.keys(normalizedInternal).length || Object.keys(normalizedExternal).length;
  if (!hasLinks) return null;

  const defaultExternal = normalizedExternal[targetCustomerLang]
    || normalizedExternal.de
    || normalizedExternal.en
    || Object.values(normalizedExternal)[0]
    || null;

  return {
    lang: targetCustomerLang,
    internalLinks: normalizedInternal,
    externalLinks: normalizedExternal,
    defaultExternalLink: defaultExternal,
  };
}

export function shouldGenerateReports(previousStatus, nextStatus) {
  const prev = Number(previousStatus);
  const next = Number(nextStatus);
  return next === STATUS_CLOSED && prev !== STATUS_CLOSED;
}
