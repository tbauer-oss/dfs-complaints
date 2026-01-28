// api/_lib/trainingPdf.js – PDF-Exports für Schulungen
import PDFDocument from 'pdfkit';

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

export function createTrainingPdf(training, { questionnaires = [], templates = [], lang = 'de', finalize = true } = {}) {
  const doc = new PDFDocument({ size: 'A4', margin: 42, info: { Title: training.trainingNumber || 'Schulung' } });
  doc.fontSize(18).fillColor('#1B2A4E').text('Schulungsnachweis', { align: 'left' });
  doc.moveDown(0.3);
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

export function createTrainingProgramPdf(program, trainings = [], { finalize = true } = {}) {
  const doc = new PDFDocument({ size: 'A4', margin: 42, info: { Title: program.title || 'Schulungsprogramm' } });
  doc.fontSize(18).fillColor('#1B2A4E').text('Jahres-Schulungsprogramm', { align: 'left' });
  doc.moveDown(0.3);
  doc.fontSize(11).fillColor('#4B5563').text(`${safeText(program.title)} · Status: ${safeText(program.status)}`);
  doc.moveDown();

  drawSectionTitle(doc, 'Überblick');
  doc.text(`Jahr: ${safeText(program.year)}`);
  doc.text(`Koordinator: ${safeText(program.owner)}`);
  doc.text(`Budget gesamt: ${program.budgetTotal ? `${program.budgetTotal} €` : '—'}`);

  drawSectionTitle(doc, 'Schulungen');
  if (!trainings.length) {
    doc.text('Keine Schulungen zugeordnet.');
  } else {
    trainings.forEach((training, idx) => {
      doc.text(`${idx + 1}. ${safeText(training.trainingNumber)} · ${safeText(training.title)} · ${safeText(training.startDate)}`);
    });
  }

  if (finalize) doc.end();
  return doc;
}
