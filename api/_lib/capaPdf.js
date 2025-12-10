import PDFDocument from 'pdfkit';
import { fileURLToPath } from 'url';
import path from 'path';

const LABELS = {
  de: {
    title: 'CAPA / 8D-Report',
    meta: 'Stammdaten',
    capaNumber: 'CAPA-Nummer',
    status: 'Status',
    complaint: 'Verknüpfte Reklamation',
    responsible: 'Verantwortlich',
    created: 'Erstellt',
    updated: 'Aktualisiert',
    d1: 'D1 – Team & Problemdefinition',
    d2: 'D2 – Sofortmaßnahmen (Correction)',
    d3: 'D3 – Ursachenanalyse (Root Cause)',
    d4: 'D4 – Korrekturmaßnahmen',
    d5: 'D5 – Wirksamkeitsprüfung',
    d6: 'D6 – Vorbeugungsmaßnahmen',
    d7: 'D7 – Lessons Learned / Transfer',
    d8: 'D8 – Abschluss & Freigabe',
    teamLead: 'Teamleiter',
    area: 'Bereich',
    product: 'Produkt / Charge',
    problem: 'Problembeschreibung',
    team: 'Team',
    immediate: 'Sofortmaßnahmen',
    details: 'Details',
    causes: 'Ursachen',
    summary: 'Zusammenfassung',
    corrective: 'Korrekturmaßnahmen',
    verification: 'Verifizierung',
    effective: 'Maßnahmen wirksam?',
    preventive: 'Vorbeugung',
    lessons: 'Lessons Learned',
    approvals: 'Freigabe',
    signature: 'Freigabe & Unterschrift',
    signLabel: 'Digitale Signatur',
    signDate: 'Datum',
    yes: 'Ja',
    no: 'Nein',
  },
  en: {
    title: 'CAPA / 8D Report',
    meta: 'Meta data',
    capaNumber: 'CAPA number',
    status: 'Status',
    complaint: 'Linked complaint',
    responsible: 'Responsible',
    created: 'Created',
    updated: 'Updated',
    d1: 'D1 – Team & Problem Definition',
    d2: 'D2 – Immediate Actions (Correction)',
    d3: 'D3 – Root Cause Analysis',
    d4: 'D4 – Corrective Actions',
    d5: 'D5 – Verification of Effectiveness',
    d6: 'D6 – Preventive Actions',
    d7: 'D7 – Lessons Learned / Transfer',
    d8: 'D8 – Closure & Approval',
    teamLead: 'Team lead',
    area: 'Area',
    product: 'Product / Batch',
    problem: 'Problem description',
    team: 'Team',
    immediate: 'Immediate actions',
    details: 'Details',
    causes: 'Causes',
    summary: 'Summary',
    corrective: 'Corrective actions',
    verification: 'Verification',
    effective: 'Actions effective?',
    preventive: 'Preventive actions',
    lessons: 'Lessons learned',
    approvals: 'Approval',
    signature: 'Approval & Signature',
    signLabel: 'Digital signature',
    signDate: 'Date',
    yes: 'Yes',
    no: 'No',
  },
};

const COLORS = {
  primary: '#004b8d',
  accent: '#0d6efd',
  bannerBg: '#eef3f9',
  sectionBg: '#f4f7fb',
  border: '#c7d3e3',
  muted: '#4b5563',
  text: '#1b2735',
};

const LOGO_PATH = path.join(
  path.dirname(fileURLToPath(import.meta.url)),
  '../_assets/dfs-logo.png',
);

function resolveLabels(lang) {
  const key = (lang || '').toString().toLowerCase();
  if (LABELS[key]) return LABELS[key];
  if (key.startsWith('en')) return LABELS.en;
  return LABELS.de;
}

function formatDate(value) {
  if (!value && value !== 0) return '';
  const d = new Date(Number(value));
  if (Number.isNaN(d.valueOf())) return '';
  return d.toISOString().slice(0, 10);
}

function textBlock(doc, label, value) {
  doc.fillColor(COLORS.muted).font('Helvetica-Bold').text(label, { continued: true });
  doc.fillColor(COLORS.text).font('Helvetica').text(`: ${value || '-'}`);
}

function sectionHeader(doc, title) {
  doc.moveDown(0.7);
  const startX = doc.page.margins.left;
  const width = doc.page.width - doc.page.margins.left - doc.page.margins.right;
  const startY = doc.y;
  doc.save();
  doc.roundedRect(startX, startY - 4, width, 24, 6).fill(COLORS.sectionBg);
  doc.restore();
  doc.fillColor(COLORS.primary).font('Helvetica-Bold').fontSize(12).text(title, startX + 10, startY);
  doc.moveTo(startX, doc.y + 4).lineTo(startX + width, doc.y + 4).stroke(COLORS.border);
  doc.moveDown(0.3);
  doc.fontSize(10).fillColor(COLORS.text);
}

function renderList(doc, entries, formatter) {
  entries.forEach((entry, idx) => {
    formatter(entry, idx);
    doc.moveDown(0.2);
  });
  if (entries.length === 0) doc.text('-');
}

function drawHeader(doc, labels, report) {
  const availableWidth = doc.page.width - doc.page.margins.left - doc.page.margins.right;
  const startY = doc.y;
  const headerHeight = 78;

  doc.save();
  doc.roundedRect(doc.page.margins.left, startY, availableWidth, headerHeight, 8).fill(COLORS.bannerBg);
  doc.restore();

  try {
    doc.image(LOGO_PATH, doc.page.margins.left + 12, startY + 12, { width: 110, align: 'left' });
  } catch (e) {
    // Logo is optional; keep report generation robust without altering spacing.
  }

  doc
    .fillColor(COLORS.primary)
    .font('Helvetica-Bold')
    .fontSize(16)
    .text(labels.title, doc.page.margins.left + 140, startY + 16, {
      width: availableWidth - 150,
    });
  doc
    .fontSize(10)
    .font('Helvetica')
    .fillColor(COLORS.text)
    .text(`${labels.capaNumber}: ${report.capaNumber || report.id}`, {
      width: availableWidth - 150,
      align: 'left',
    })
    .text(`${labels.status}: ${report.status || '-'}`);

  doc.y = startY + headerHeight + 6;
  doc.moveDown(0.5);
}

function renderMetaSection(doc, labels, report) {
  sectionHeader(doc, labels.meta);
  const gridWidth = doc.page.width - doc.page.margins.left - doc.page.margins.right;
  const columnWidth = (gridWidth - 10) / 2;
  const startX = doc.page.margins.left;
  const startY = doc.y;

  const entries = [
    [labels.capaNumber, report.capaNumber || report.id],
    [labels.status, report.status || ''],
    [labels.responsible, report.responsibleUserId || ''],
    [labels.complaint, report.complaintId || ''],
    [labels.created, formatDate(report.createdAt)],
    [labels.updated, formatDate(report.updatedAt)],
  ];

  entries.forEach((entry, idx) => {
    const x = startX + (idx % 2) * (columnWidth + 10);
    const y = startY + Math.floor(idx / 2) * 38;
    doc.save();
    doc.roundedRect(x, y, columnWidth, 34, 6).stroke(COLORS.border);
    doc.restore();
    doc.fillColor(COLORS.muted).font('Helvetica-Bold').text(entry[0], x + 10, y + 8);
    doc.fillColor(COLORS.text).font('Helvetica').text(entry[1] || '-', x + 10, y + 22);
  });

  doc.y = startY + Math.ceil(entries.length / 2) * 38;
}

function renderSignatureSection(doc, labels) {
  sectionHeader(doc, labels.signature);
  const width = doc.page.width - doc.page.margins.left - doc.page.margins.right;
  const startX = doc.page.margins.left;
  const y = doc.y;
  const boxWidth = (width - 20) / 2;

  const signatureBox = (label) => {
    doc.save();
    doc.roundedRect(label.x, label.y, label.width, 70, 8).stroke(COLORS.border);
    doc.restore();
    doc.fillColor(COLORS.muted).font('Helvetica-Bold').text(label.title, label.x + 12, label.y + 12);
    doc
      .fillColor(COLORS.text)
      .font('Helvetica')
      .text('__________________________________________', label.x + 12, label.y + 30);
  };

  signatureBox({ x: startX, y, width: boxWidth, title: labels.signLabel });
  signatureBox({ x: startX + boxWidth + 20, y, width: boxWidth, title: labels.signDate });

  doc.y = y + 78;
}

export function createCapaPdf(report, { lang = 'de', stream = null, finalize = true } = {}) {
  const labels = resolveLabels(lang);
  const doc = new PDFDocument({ margin: 40, size: 'A4' });
  if (stream) doc.pipe(stream);
  const now = new Date();
  doc.info = {
    Title: `${labels.title} ${report.capaNumber || report.id}`,
    CreationDate: now,
    ModDate: new Date(report.updatedAt || report.createdAt || now),
  };

  drawHeader(doc, labels, report);
  renderMetaSection(doc, labels, report);

  const s = report.sections || {};

  sectionHeader(doc, labels.d1);
  textBlock(doc, labels.teamLead, s?.d1?.teamLead || '');
  textBlock(doc, labels.area, s?.d1?.area || '');
  textBlock(doc, labels.product, `${s?.d1?.product || ''} ${s?.d1?.batch || ''}`.trim());
  textBlock(doc, labels.problem, s?.d1?.problem || '');
  doc.font('Helvetica-Bold').text(labels.team);
  doc.font('Helvetica');
  renderList(doc, s?.d1?.teamMembers || [], m => {
    doc.text(`• ${m.name || ''} (${m.role || ''})`);
  });

  sectionHeader(doc, labels.d2);
  doc.font('Helvetica-Bold').text(labels.immediate);
  doc.font('Helvetica');
  renderList(doc, s?.d2?.immediateActions || [], a => {
    const parts = [a.action, formatDate(a.doneAt)].filter(Boolean).join(' | ');
    doc.text(`• ${parts}`);
    if (a.notes) doc.text(`  ${labels.details}: ${a.notes}`);
  });
  if (s?.d2?.details) doc.text(`${labels.details}: ${s.d2.details}`);

  sectionHeader(doc, labels.d3);
  renderList(doc, s?.d3?.causes || [], c => {
    doc.text(`• ${c.why || ''}`);
    if (c.root) doc.text(`  → ${c.root}`);
  });
  if (s?.d3?.summary) doc.text(`${labels.summary}: ${s.d3.summary}`);

  sectionHeader(doc, labels.d4);
  renderList(doc, s?.d4?.correctiveActions || [], c => {
    const head = [c.description, c.owner, formatDate(c.dueDate)].filter(Boolean).join(' | ');
    doc.text(`• ${head}`);
    const tail = [formatDate(c.completedAt), c.status, c.changeType].filter(Boolean).join(' | ');
    if (tail) doc.text(`  ${tail}`);
    if (c.notes) doc.text(`  ${c.notes}`);
  });

  sectionHeader(doc, labels.d5);
  if (s?.d5?.description) doc.text(s.d5.description);
  textBlock(doc, labels.effective, s?.d5?.effective ? labels.yes : labels.no);
  if (s?.d5?.followUp) doc.text(s.d5.followUp);

  sectionHeader(doc, labels.d6);
  renderList(doc, s?.d6?.preventiveActions || [], p => doc.text(`• ${p}`));

  sectionHeader(doc, labels.d7);
  renderList(doc, s?.d7?.lessons || [], l => doc.text(`• ${l}`));
  if (s?.d7?.transfer) doc.text(s.d7.transfer);

  sectionHeader(doc, labels.d8);
  renderList(doc, s?.d8?.approvals || [], a => {
    const line = [a.name, a.role, formatDate(a.date)].filter(Boolean).join(' | ');
    doc.text(`• ${line}`);
  });
  if (s?.d8?.closingNote) doc.text(s.d8.closingNote);

  renderSignatureSection(doc, labels);

  if (finalize) doc.end();
  return doc;
}
