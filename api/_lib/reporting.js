// api/_lib/reporting.js
// PDF-Reporting für Reklamationen (Mehrsprachig erweiterbar)

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
  const doc = new PDFDocument({ size: 'A4', margin: 50 });
  const chunks = [];
  doc.on('data', (chunk) => chunks.push(chunk));
  const done = new Promise((resolve) => doc.on('end', resolve));

  const customer = describeCustomer(complaint);
  const product = describeProduct(complaint);
  const payload = (complaint.payload && typeof complaint.payload === 'object') ? complaint.payload : {};
  const departments = normalizeDepartments(complaint.internalDepartments);

  const title = variant === 'external' ? labels.externalTitle : labels.title;
  doc.fontSize(18).text(`${title} ${complaint.ticket || ''}`);
  doc.moveDown(1);

  doc.fontSize(12);
  doc.text(`${labelFor(lang, 'ticket')}: ${complaint.ticket || '-'}`);
  doc.text(`${labelFor(lang, 'status')}: ${complaint.statusLabel || complaint.status || '-'}`);
  doc.text(`${labelFor(lang, 'decision')}: ${(complaint.decision || '–')}`);
  doc.text(`${labelFor(lang, 'created')}: ${formatDate(complaint.createdAt || complaint.updatedAt)}`);
  doc.moveDown(0.5);

  doc.text(`${labelFor(lang, 'customer')}: ${customer.company || customer.contact || '-'}`);
  if (customer.customerNo) doc.text(`Kundennummer: ${customer.customerNo}`);
  if (customer.country) doc.text(`Land: ${customer.country}`);
  doc.text(`${labelFor(lang, 'email')}: ${(complaint.email || '-')}`);
  doc.moveDown(0.5);

  doc.fontSize(14).text(labels.product);
  doc.fontSize(12);
  if (product.name) doc.text(`${payloadLabel(lang, 'product', 'Produkt')}: ${product.name}`);
  if (product.articleNo) doc.text(`${payloadLabel(lang, 'article', 'Artikel')}: ${product.articleNo}`);
  if (product.batch) doc.text(`${labels.batch}: ${product.batch}`);
  if (product.udi) doc.text(`${labels.udi}: ${product.udi}`);
  doc.moveDown(0.5);

  doc.fontSize(14).text(labelFor(lang, 'payload'));
  doc.moveDown(0.3);
  doc.fontSize(12);
  for (const [key, val] of Object.entries(payload)) {
    const rendered = (val ?? '').toString().trim();
    if (!rendered) continue;
    doc.text(`${payloadLabel(lang, key, key)}: ${rendered}`);
  }
  doc.moveDown(0.5);

  if (departments.length > 0 && variant === 'internal') {
    doc.fontSize(14).text(labelFor(lang, 'departments'));
    doc.fontSize(12);
    departments.forEach((dep) => doc.text(`• ${dep}`));
    doc.moveDown(0.5);
  }

  if (variant === 'internal') {
    const evalText = textForEvaluation(complaint, lang);
    const cause = complaint.internalEvaluationCause || '';
    if (evalText || cause) {
      doc.fontSize(14).text(labelFor(lang, 'internalEvaluation'));
      doc.fontSize(12);
      if (evalText) doc.text(evalText, { align: 'left' });
      if (cause) doc.text(`${labelFor(lang, 'internalCause')}: ${cause}`);
      doc.moveDown(0.5);
    }

    const actionText = plannedActions(complaint);
    if (actionText) {
      doc.fontSize(14).text(labels.actions);
      doc.fontSize(12).text(actionText);
      doc.moveDown(0.5);
    }

    const uploads = Array.isArray(complaint.uploads) ? complaint.uploads : [];
    if (uploads.length > 0) {
      doc.fontSize(14).text(labelFor(lang, 'uploads'));
      doc.fontSize(12);
      uploads.forEach((u) => doc.text(`• ${u.name || u.url || u.downloadUrl || 'Attachment'}`));
      doc.moveDown(0.5);
    }

    if (complaint.adminNotes) {
      doc.fontSize(14).text(labels.notes);
      doc.fontSize(12).text(complaint.adminNotes);
    }
  } else {
    const summary = qmSummaryForLang(complaint, lang)
      || 'Zusammenfassung wird bereitgestellt / Summary will be provided soon';
    doc.fontSize(14).text(labels.qmSummary);
    doc.fontSize(12).text(summary, { align: 'left' });
    doc.moveDown(0.5);

    const actionText = plannedActions(complaint);
    if (actionText) {
      doc.fontSize(14).text(labels.measures);
      doc.fontSize(12).text(actionText);
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
