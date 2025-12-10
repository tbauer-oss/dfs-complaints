import PDFDocument from 'pdfkit';

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
    yes: 'Yes',
    no: 'No',
  },
};

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
  doc.font('Helvetica-Bold').text(label, { continued: true });
  doc.font('Helvetica').text(`: ${value || '-'}`);
}

function sectionHeader(doc, title) {
  doc.moveDown(0.7);
  doc.font('Helvetica-Bold').fontSize(12).text(title);
  doc.moveTo(doc.x, doc.y + 2).lineTo(550, doc.y + 2).stroke('#999999');
  doc.moveDown(0.3);
  doc.fontSize(10);
}

function renderList(doc, entries, formatter) {
  entries.forEach((entry, idx) => {
    formatter(entry, idx);
    doc.moveDown(0.2);
  });
  if (entries.length === 0) doc.text('-');
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

  doc.fontSize(16).font('Helvetica-Bold').text(labels.title);
  doc.moveDown(0.5);
  doc.fontSize(10);

  sectionHeader(doc, labels.meta);
  textBlock(doc, labels.capaNumber, report.capaNumber || report.id);
  textBlock(doc, labels.status, report.status || '');
  textBlock(doc, labels.responsible, report.responsibleUserId || '');
  if (report.complaintId) textBlock(doc, labels.complaint, report.complaintId);
  textBlock(doc, labels.created, formatDate(report.createdAt));
  textBlock(doc, labels.updated, formatDate(report.updatedAt));

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

  if (finalize) doc.end();
  return doc;
}
