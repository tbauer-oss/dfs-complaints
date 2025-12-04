// api/_lib/reporting.js
// PDF-Reporting für Reklamationen (Mehrsprachig erweiterbar)

import PDFDocument from 'pdfkit';
import { storeGeneratedFile } from './uploads.js';
import { normalizeLangValue } from './store.js';
import {
  normalizeEvaluationText,
  normalizeEvaluationTranslations,
  normalizeDepartments,
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

export async function generateComplaintReport(complaint, { lang = 'de' } = {}) {
  const target = normalizeLangValue(lang) || 'de';
  const labels = REPORT_LANGS[target] || REPORT_LANGS.en;
  const doc = new PDFDocument({ size: 'A4', margin: 50 });
  const chunks = [];
  doc.on('data', (chunk) => chunks.push(chunk));
  const done = new Promise((resolve) => doc.on('end', resolve));

  doc.fontSize(18).text(`${labels.title} ${complaint.ticket || ''}`);
  doc.moveDown(1);

  doc.fontSize(12);
  doc.text(`${labelFor(target, 'ticket')}: ${complaint.ticket || '-'} `);
  doc.text(`${labelFor(target, 'status')}: ${complaint.statusLabel || complaint.status || '-'} `);
  doc.text(`${labelFor(target, 'decision')}: ${(complaint.decision || '–')}`);
  doc.text(`${labelFor(target, 'created')}: ${formatDate(complaint.createdAt || complaint.updatedAt)}`);
  doc.moveDown(0.5);

  doc.text(`${labelFor(target, 'customer')}: ${(complaint.company || complaint.contact || '')}`);
  doc.text(`${labelFor(target, 'email')}: ${(complaint.email || '-')}`);
  doc.moveDown(0.5);

  doc.fontSize(14).text(labelFor(target, 'payload'));
  doc.moveDown(0.3);
  doc.fontSize(12);
  const payload = (complaint.payload && typeof complaint.payload === 'object') ? complaint.payload : {};
  for (const [key, val] of Object.entries(payload)) {
    const rendered = (val ?? '').toString().trim();
    if (!rendered) continue;
    doc.text(`${payloadLabel(target, key, key)}: ${rendered}`);
  }
  doc.moveDown(0.5);

  const departments = normalizeDepartments(complaint.internalDepartments);
  if (departments.length > 0) {
    doc.fontSize(14).text(labelFor(target, 'departments'));
    doc.fontSize(12);
    departments.forEach((dep) => doc.text(`• ${dep}`));
    doc.moveDown(0.5);
  }

  const evalText = textForEvaluation(complaint, target);
  const cause = complaint.internalEvaluationCause || '';
  if (evalText || cause) {
    doc.fontSize(14).text(labelFor(target, 'internalEvaluation'));
    doc.fontSize(12);
    if (evalText) doc.text(evalText, { align: 'left' });
    if (cause) doc.text(`${labelFor(target, 'internalCause')}: ${cause}`);
    doc.moveDown(0.5);
  }

  const uploads = Array.isArray(complaint.uploads) ? complaint.uploads : [];
  if (uploads.length > 0) {
    doc.fontSize(14).text(labelFor(target, 'uploads'));
    doc.fontSize(12);
    uploads.forEach((u) => doc.text(`• ${u.name || u.url || u.downloadUrl || 'Attachment'}`));
  }

  doc.end();
  await done;
  const buffer = Buffer.concat(chunks);
  const filename = `complaint-${complaint.ticket || 'report'}-${target}.pdf`;
  const stored = await storeGeneratedFile(buffer, {
    ticket: complaint.ticket,
    filename,
    mime: 'application/pdf',
  });

  return stored ? { ...stored, lang: target } : null;
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
