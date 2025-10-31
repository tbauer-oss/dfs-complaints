// /api/_lib/mail.js
import nodemailer from 'nodemailer';

function toBool(v){ if(typeof v==='boolean')return v; const s=String(v??'').toLowerCase(); return s==='1'||s==='true'||s==='yes'; }

const FROM = process.env.MAIL_FROM || 'no-reply_dfs-complaints@outlook.com';
const QM   = process.env.MAIL_QM   || 'qualitymanagement@dfs-diamon.de';

export const mailer = nodemailer.createTransport({
  host: process.env.SMTP_HOST,
  port: Number(process.env.SMTP_PORT || 587),
  secure: toBool(process.env.SMTP_SECURE),
  auth: { user: process.env.SMTP_USER, pass: process.env.SMTP_PASS }
});

export async function verifyTransport(){ return mailer.verify(); }

// ---- I18N ----
const SUPPORTED = new Set(['de','en','fr','it','es']);
const L = (lang) => SUPPORTED.has(lang) ? lang : 'de';

const TEXTS = {
  afterRegisterToCustomer: {
    de: (name)=>({
      subject: 'Ihre Registrierung bei DFS-Diamon',
      text: `Guten Tag ${name || ''},

vielen Dank für Ihre Registrierung bei der DFS-Diamon GmbH.
Ihr Kundenkonto wurde angelegt und befindet sich nun in Prüfung.
Nach erfolgreicher Freigabe informieren wir Sie per E-Mail.

Mit freundlichen Grüßen
DFS-Diamon GmbH – Quality Management`
    }),
    en: (name)=>({
      subject: 'Your registration at DFS-Diamon',
      text: `Dear ${name || 'customer'},

thank you for registering with DFS-Diamon GmbH.
Your account has been created and is pending review.
We will notify you by e-mail once it is approved.

Kind regards
DFS-Diamon GmbH – Quality Management`
    }),
    fr: (name)=>({
      subject: 'Votre inscription chez DFS-Diamon',
      text: `Bonjour ${name || ''},

merci pour votre inscription auprès de DFS-Diamon GmbH.
Votre compte a été créé et est en cours de vérification.
Nous vous informerons par e-mail dès son approbation.

Cordialement
DFS-Diamon GmbH – Quality Management`
    }),
    it: (name)=>({
      subject: 'Registrazione presso DFS-Diamon',
      text: `Gentile ${name || ''},

grazie per la registrazione presso DFS-Diamon GmbH.
Il suo account è stato creato ed è in fase di verifica.
La informeremo via e-mail non appena sarà approvato.

Cordiali saluti
DFS-Diamon GmbH – Quality Management`
    }),
    es: (name)=>({
      subject: 'Su registro en DFS-Diamon',
      text: `Hola ${name || ''},

gracias por registrarse en DFS-Diamon GmbH.
Su cuenta ha sido creada y está en revisión.
Le notificaremos por correo cuando sea aprobada.

Saludos cordiales
DFS-Diamon GmbH – Quality Management`
    }),
  },

  afterRegisterToQM: {
    // Für QM reicht DE/EN; kannst du erweitern
    de: (email)=>({ subject: `Neue Kundenregistrierung: ${email}`, text: `Neue Registrierung eingegangen und wartet auf Freigabe: ${email}` }),
    en: (email)=>({ subject: `New customer registration: ${email}`, text: `A new registration is pending approval: ${email}` }),
    fr: (email)=>({ subject: `Nouvelle inscription client : ${email}`, text: `Une nouvelle inscription attend validation : ${email}` }),
    it: (email)=>({ subject: `Nuova registrazione cliente: ${email}`, text: `È in attesa di approvazione una nuova registrazione: ${email}` }),
    es: (email)=>({ subject: `Nuevo registro de cliente: ${email}`, text: `Hay un nuevo registro pendiente de aprobación: ${email}` }),
  },

  approved: {
    de: (name)=>({ subject:'Ihr DFS-Kundenkonto wurde freigeschaltet', text:`Guten Tag ${name || ''},

Ihr Kundenkonto bei der DFS-Diamon GmbH wurde soeben freigeschaltet.
Sie können sich ab sofort anmelden und Reklamationen online übermitteln.

Mit freundlichen Grüßen
DFS-Diamon GmbH – Quality Management`}),
    en: (name)=>({ subject:'Your DFS account has been approved', text:`Dear ${name || 'customer'},

your account at DFS-Diamon GmbH has just been approved.
You can now log in and submit complaints online.

Kind regards
DFS-Diamon GmbH – Quality Management`}),
    fr: (name)=>({ subject:`Votre compte DFS a été activé`, text:`Bonjour ${name || ''},

votre compte chez DFS-Diamon GmbH vient d’être activé.
Vous pouvez maintenant vous connecter et soumettre des réclamations en ligne.

Cordialement
DFS-Diamon GmbH – Quality Management`}),
    it: (name)=>({ subject:`Il suo account DFS è stato attivato`, text:`Gentile ${name || ''},

il suo account presso DFS-Diamon GmbH è stato approvato.
Può ora effettuare l’accesso e inviare reclami online.

Cordiali saluti
DFS-Diamon GmbH – Quality Management`}),
    es: (name)=>({ subject:`Su cuenta de DFS ha sido activada`, text:`Hola ${name || ''},

su cuenta en DFS-Diamon GmbH ha sido aprobada.
Ya puede iniciar sesión y enviar reclamaciones en línea.

Saludos cordiales
DFS-Diamon GmbH – Quality Management`}),
  },

  complaintCustomer: {
    de: (ticket)=>({ subject:`Eingangsbestätigung – Reklamation [TICKET ${ticket}]`, text:`Vielen Dank für Ihre Mitteilung.
Ihre Reklamation wurde unter der Ticketnummer ${ticket} erfasst.
Wir informieren Sie bei Statusänderungen.` }),
    en: (ticket)=>({ subject:`Acknowledgement – Complaint [TICKET ${ticket}]`, text:`Thank you for your message.
Your complaint has been recorded under ticket ${ticket}.
We will inform you when the status changes.` }),
    fr: (ticket)=>({ subject:`Accusé de réception – Réclamation [TICKET ${ticket}]`, text:`Merci pour votre message.
Votre réclamation a été enregistrée sous le ticket ${ticket}.
Nous vous informerons en cas de changement d’état.` }),
    it: (ticket)=>({ subject:`Conferma di ricezione – Reclamo [TICKET ${ticket}]`, text:`Grazie per il suo messaggio.
Il reclamo è stato registrato con il ticket ${ticket}.
La informeremo in caso di cambiamenti di stato.` }),
    es: (ticket)=>({ subject:`Acuse de recibo – Reclamación [TICKET ${ticket}]`, text:`Gracias por su mensaje.
Su reclamación se ha registrado con el ticket ${ticket}.
Le informaremos si cambia el estado.` }),
  },
};

// Exportierte Template-Funktionen
export const tpl = {
  afterRegisterToCustomer: (name, lang='de') => TEXTS.afterRegisterToCustomer[L(lang)](name),
  afterRegisterToQM:       (email, lang='de') => TEXTS.afterRegisterToQM[L(lang)](email),
  approved:                (name, lang='de') => TEXTS.approved[L(lang)](name),
  complaintCustomer:       (ticket, lang='de') => TEXTS.complaintCustomer[L(lang)](ticket),
};

export async function send(to, { subject, text }, attachments = []) {
  return mailer.sendMail({ from: FROM, to, subject, text, replyTo: FROM, attachments });
}
export async function notifyQM(msg) {
  if (!QM) return;
  return send(QM, msg);
}
