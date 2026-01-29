// api/_lib/trainingPdf.js – PDF-Exports für Schulungen
import fs from 'node:fs';
import path from 'node:path';
import PDFDocument from 'pdfkit';

const LOGO_PATH = path.join(process.cwd(), 'api', '_assets', 'dfs-logo.png');

function drawSectionTitle(doc, title) {
  doc.moveDown(0.5);
  doc.fontSize(13).fillColor('#0F1A2B').text(title, { underline: true });
  doc.moveDown(0.3);
  doc.fillColor('#0F1A2B').fontSize(10);
}

function safeText(value, fallback = '—') {
  const text = `${value ?? ''}`.trim();
  return text.length ? text : fallback;
}

function plannedPeriodLabel(item) {
  const value = item.plannedPeriodValue || '';
  if (!value) return '—';
  switch (item.plannedPeriodType) {
    case 'date':
      return `Datum: ${value}`;
    case 'month':
      return `Monat: ${value}`;
    case 'quarter':
      return `Quartal: ${value.split('-').last} ${value.split('-').first}`;
    case 'halfYear':
      return `Halbjahr: ${value.split('-').last} ${value.split('-').first}`;
    default:
      return value;
  }
}

function loadLogo() {
  try {
    if (fs.existsSync(LOGO_PATH)) {
      return fs.readFileSync(LOGO_PATH);
    }
  } catch (err) {
    console.error('[trainingPdf] logo missing', err);
  }
  return null;
}

function drawHeader(doc, title) {
  const logo = loadLogo();
  const headerTop = doc.page.margins.top - 10;
  const startX = doc.page.margins.left;
  if (logo) {
    doc.image(logo, startX, headerTop, { width: 90 });
  }
  doc
    .fontSize(18)
    .fillColor('#1B2A4E')
    .text(title, startX + (logo ? 110 : 0), headerTop + 10, { align: 'left' });
  doc.moveDown(1.2);
}

function drawFooter(doc) {
  const bottom = doc.page.height - doc.page.margins.bottom + 8;
  doc.fontSize(9).fillColor('#6B7280');
  doc.text('DFS-Diamon GmbH', doc.page.margins.left, bottom, { align: 'left' });
  doc.text(`Seite ${doc.page.pageNumber}`, doc.page.margins.left, bottom, {
    align: 'right',
    width: doc.page.width - doc.page.margins.left - doc.page.margins.right,
  });
  doc.fillColor('#0F1A2B').fontSize(10);
}

function wrapText(doc, text, width) {
  const content = text || '';
  return doc.splitTextToSize(content, width);
}

function drawTable(doc, { columns, rows, rowPadding = 6, onPageBreak }) {
  const startX = doc.page.margins.left;
  const availableWidth = doc.page.width - doc.page.margins.left - doc.page.margins.right;
  const totalRatio = columns.reduce((sum, col) => sum + col.ratio, 0);
  const widths = columns.map((col) => (availableWidth * col.ratio) / totalRatio);
  const headerHeight = 22;
  let y = doc.y + 6;

  const ensureSpace = (height) => {
    if (y + height > doc.page.height - doc.page.margins.bottom - 20) {
      doc.addPage();
      y = typeof onPageBreak === 'function' ? onPageBreak(doc) : doc.page.margins.top;
    }
  };

  ensureSpace(headerHeight);
  doc.rect(startX, y, availableWidth, headerHeight).fill('#EEF2F7');
  doc.fillColor('#0F1A2B').fontSize(9);
  let x = startX;
  columns.forEach((col, idx) => {
    doc.text(col.label, x + rowPadding, y + 6, { width: widths[idx] - rowPadding * 2, align: 'left' });
    x += widths[idx];
  });
  y += headerHeight;

  rows.forEach((row) => {
    const cellLines = row.map((cell, idx) => wrapText(doc, cell, widths[idx] - rowPadding * 2));
    const lineHeight = 12;
    const maxLines = Math.max(...cellLines.map((lines) => lines.length || 1));
    const rowHeight = maxLines * lineHeight + rowPadding * 2;
    ensureSpace(rowHeight);
    doc.rect(startX, y, availableWidth, rowHeight).strokeColor('#E5E7EB').lineWidth(0.5).stroke();
    x = startX;
    cellLines.forEach((lines, idx) => {
      const text = lines.length ? lines.join('\n') : '—';
      doc.fillColor('#111827').fontSize(9).text(text, x + rowPadding, y + rowPadding, {
        width: widths[idx] - rowPadding * 2,
      });
      x += widths[idx];
    });
    y += rowHeight;
  });

  doc.moveDown(1);
}

export function createTrainingPdf(training, { questionnaires = [], templates = [], lang = 'de', finalize = true } = {}) {
  const doc = new PDFDocument({ size: 'A4', margin: 42, info: { Title: training.trainingNumber || 'Schulung' } });
  drawHeader(doc, 'Schulungsnachweis');
  doc.fontSize(11).fillColor('#4B5563');
  doc.fontSize(11).fillColor('#4B5563').text(`Nummer: ${safeText(training.trainingNumber)} · Status: ${safeText(training.status)}`);
  doc.moveDown();

  drawSectionTitle(doc, 'Stammdaten');
  doc.text(`Titel: ${safeText(training.title)}`);
  doc.text(`Kategorie: ${safeText(training.category)}`);
  doc.text(`Typ/Format: ${safeText(training.type)} / ${safeText(training.format)}`);
  doc.text(`Zeitraum: ${safeText(training.startDate)}${training.endDate ? ` – ${training.endDate}` : ''}`);
  doc.text(`Trainer/Anbieter: ${safeText(training.trainer)}`);
  doc.text(`Ort/Link: ${safeText(training.location)}`);
  doc.text(`Zielgruppe: ${safeText(training.targetGroup)}`);
  doc.text(`Abteilungen: ${Array.isArray(training.departments) && training.departments.length ? training.departments.join(', ') : '—'}`);
  doc.text(`Bezug/Grund: ${safeText(training.reason)}`);

  drawSectionTitle(doc, 'Teilnehmer');
  if (!training.participants?.length) {
    doc.text('Keine Teilnehmer erfasst.');
  } else {
    training.participants.forEach((participant, idx) => {
      doc.text(`${idx + 1}. ${safeText(participant.name)} · ${safeText(participant.status)} · ${safeText(participant.email)}`);
    });
  }

  drawSectionTitle(doc, 'Wirksamkeitskontrolle');
  if (!questionnaires.length) {
    doc.text('Keine Fragebögen dokumentiert.');
  } else {
    const templateById = Object.fromEntries(templates.map((t) => [t.id, t]));
    questionnaires.forEach((q, idx) => {
      const template = templateById[q.templateId];
      doc.text(
        `${idx + 1}. ${safeText(template?.title)} · Teilnehmer-ID: ${safeText(q.participantId)} · Score: ${q.score || 0} · Wirksam: ${
          q.effective === null || q.effective === undefined ? '—' : q.effective ? 'Ja' : 'Nein'
        }`,
      );
      if (q.summary) {
        doc.fillColor('#374151').fontSize(9).text(`Hinweis: ${q.summary}`);
        doc.fillColor('#0F1A2B').fontSize(10);
      }
    });
  }

  drawSectionTitle(doc, 'Anhänge');
  if (!training.attachments?.length) {
    doc.text('Keine Anhänge hinterlegt.');
  } else {
    training.attachments.forEach((att, idx) => {
      doc.text(`${idx + 1}. ${safeText(att.name)} (${safeText(att.type)})`);
    });
  }

  if (finalize) doc.end();
  return doc;
}

export function createTrainingProgramPdf(programItems = [], executions = [], { year, filters = {}, finalize = true } = {}) {
  const doc = new PDFDocument({
    size: 'A4',
    margin: 42,
    info: { Title: `Schulungsprogramm ${year || ''}`.trim() },
  });
  const title = `Schulungsprogramm ${year || ''}`.trim();
  drawHeader(doc, title);
  doc.on('pageAdded', () => drawFooter(doc));
  drawFooter(doc);
  doc.fontSize(10).fillColor('#4B5563');
  doc.text(`Exportiert: ${new Date().toLocaleString('de-DE')}`);
  const activeFilters = Object.entries(filters)
    .filter(([, value]) => value)
    .map(([label, value]) => `${label}: ${value}`)
    .join(' · ');
  if (activeFilters) {
    doc.text(`Filter: ${activeFilters}`);
  }
  doc.moveDown();

  drawSectionTitle(doc, 'Geplante Schulungen');
  if (!programItems.length) {
    doc.text('Keine geplanten Schulungen gefunden.');
  } else {
    const rows = programItems.map((item) => {
      const statusLabel = safeText(item.status);
      const topicLines = [
        safeText(item.title || item.trainingTitle),
        item.trainerProvider ? `Anbieter: ${item.trainerProvider}` : '',
        item.location ? `Ort/Link: ${item.location}` : '',
        item.duration ? `Dauer: ${item.duration}` : '',
        item.notes ? `Notizen: ${item.notes}` : '',
        item.cancellationReason ? `Begründung: ${item.cancellationReason}` : '',
      ]
        .filter(Boolean)
        .join('\n');
      return [
        safeText(item.plannedPeriodLabel || plannedPeriodLabel(item)),
        topicLines,
        safeText(item.department),
        safeText(item.format),
        statusLabel,
        safeText(item.responsiblePerson || item.owner),
      ];
    });
    drawTable(doc, {
      columns: [
        { label: 'Zeitraum', ratio: 0.16 },
        { label: 'Thema', ratio: 0.3 },
        { label: 'Abteilung/Team', ratio: 0.16 },
        { label: 'Format', ratio: 0.1 },
        { label: 'Status', ratio: 0.12 },
        { label: 'Verantwortlich', ratio: 0.16 },
      ],
      rows,
      onPageBreak: () => {
        drawHeader(doc, title);
        return doc.y;
      },
    });
  }

  drawSectionTitle(doc, 'Durchführungen');
  const byProgram = new Map();
  executions.forEach((execution) => {
    const key = execution.linkedProgramId || 'unlinked';
    if (!byProgram.has(key)) byProgram.set(key, []);
    byProgram.get(key).push(execution);
  });

  if (!executions.length) {
    doc.text('Keine Durchführungen dokumentiert.');
  } else {
    programItems.forEach((item) => {
      const list = byProgram.get(item.id) || [];
      if (!list.length) return;
      doc.fontSize(10).fillColor('#1B2A4E').text(`${safeText(item.title || item.trainingTitle)}`, { continued: false });
      const rows = list.map((entry) => [
        safeText(entry.startDate || entry.executionDate),
        safeText(entry.actualParticipants || entry.participants?.length),
        safeText(entry.executionNotes || entry.notes),
      ]);
      drawTable(doc, {
        columns: [
          { label: 'Datum', ratio: 0.2 },
          { label: 'Teilnehmer', ratio: 0.2 },
          { label: 'Notizen', ratio: 0.6 },
        ],
        rows,
        onPageBreak: () => {
          drawHeader(doc, title);
          return doc.y;
        },
      });
    });
  }
  if (finalize) doc.end();
  return doc;
}
