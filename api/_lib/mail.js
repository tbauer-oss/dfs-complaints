import nodemailer from 'nodemailer';

const FROM = process.env.MAIL_FROM || 'complaint@dfs-diamon.de';
const QM   = 'qualitymanagement@dfs-diamon.de';

export const mailer = nodemailer.createTransport({
  host: process.env.SMTP_HOST,
  port: Number(process.env.SMTP_PORT || 587),
  secure: !!process.env.SMTP_SECURE, // '1' => true
  auth: { user: process.env.SMTP_USER, pass: process.env.SMTP_PASS }
});

// Templates (kurz & sauber)
export const tpl = {
  afterRegisterToCustomer: (name) => ({
    subject: 'Ihre Registrierung bei DFS-Diamon',
    text:
`Vielen Dank für Ihre Registrierung bei der DFS-Diamon GmbH.
Ihr Kundenkonto wurde angelegt und befindet sich nun in Prüfung.
Nach erfolgreicher Freigabe informieren wir Sie per E-Mail.

Mit freundlichen Grüßen
DFS-Diamon GmbH – Quality Management`
  }),
  afterRegisterToQM: (email) => ({
    subject: `Neue Kundenregistrierung: ${email}`,
    text: `Eine neue Registrierung wurde eingereicht und wartet auf Freigabe: ${email}`
  }),
  approved: (name) => ({
    subject: 'Ihr DFS-Kundenkonto wurde freigeschaltet',
    text:
`Guten Tag ${name},

Ihr Kundenkonto bei der DFS-Diamon GmbH wurde soeben freigeschaltet.
Sie können sich ab sofort mit Ihrer registrierten E-Mailadresse anmelden
und Reklamationen online übermitteln.

Mit freundlichen Grüßen
DFS-Diamon GmbH – Quality Management`
  }),
  complaintDFS: (ticket, summary) => ({
    subject: `Neue Reklamation [TICKET ${ticket}]`,
    text:
`Es wurde eine neue Reklamation eingereicht.

Ticket: ${ticket}
${summary}

Diese E-Mail enthält die Reklamation als XML im Anhang sowie ggf. Bilder.`
  }),
  complaintCustomer: (ticket) => ({
    subject: `Eingangsbestätigung – Reklamation [TICKET ${ticket}]`,
    text:
`Vielen Dank für Ihre Mitteilung.
Ihre Reklamation wurde unter der Ticketnummer ${ticket} erfasst.
Sie erhalten eine Benachrichtigung, sobald sich der Bearbeitungsstatus ändert.

Mit freundlichen Grüßen
DFS-Diamon GmbH – Quality Management`
  }),
  profileChanged: (email) => ({
    subject: 'Hinweis: Ihre Stammdaten wurden geändert',
    text:
`Sie haben Ihre Stammdaten im DFS-Kundenkonto geändert.
Falls Sie das nicht waren, kontaktieren Sie bitte umgehend das Qualitätsmanagement.`
  }),
  profileChangedQM: (email) => ({
    subject: `Kundendaten geändert: ${email}`,
    text: `Der Kunde ${email} hat seine Stammdaten aktualisiert.`
  })
};

export async function send(to, { subject, text }, attachments = []) {
  return mailer.sendMail({ from: FROM, to, subject, text, attachments });
}
export async function notifyQM({ subject, text }) {
  return send(QM, { subject, text });
}
