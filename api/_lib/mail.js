// /api/_lib/mail.js  (robust, lazy transport, 465/587 Auto)
import nodemailer from 'nodemailer';
import fs from 'fs';
import path from 'path';
import { mailConfigOk, resolveMailConfig } from './mail-config.js';
import { applyTestMailRouting, loadAppMeta } from './appMeta.js';

// ==== Absender / QM (via ENV übersteuerbar) ====
const MAIL = resolveMailConfig();
const FROM     = MAIL.from || 'DFS Complaints <noreply@dfs-diamon.com>';
const REPLY_TO = MAIL.replyTo || 'noreply@dfs-diamon.com';
const QM       = MAIL.qm || 'noreply@dfs-diamon.com';

// ==== SMTP-ENV ====
const SMTP_HOST = MAIL.host;                // z.B. mail.gmx.net
const SMTP_PORT = MAIL.port; // 587=STARTTLS, 465=SMTPS
const SMTP_USER = MAIL.user;                // z.B. no-reply_dfs-complaints@gmx.net
const SMTP_PASS = MAIL.pass;

let _transporter = null;

const { ok: mailOk, missing: missingMailEnv } = mailConfigOk(MAIL);

function ensureEnv() {
  if (!mailOk) {
    throw new Error(`SMTP env missing (${missingMailEnv.join(', ')})`);
  }
}

function getTransport() {
  if (_transporter) return _transporter;
  ensureEnv();

  // Brevo/Smtp2Go mögen keinen Verbindungs-Pool; halte die Config daher bewusst
  // schlank wie in api/_lib/mailer.js, das aktuell zuverlässig Gate-/Support-Post
  // versendet. Durch das Weglassen von pool und den TLS-Tweaks wird der Versand
  // robuster bei SMTP-Providern mit strikteren Limits.
  _transporter = nodemailer.createTransport({
    host: SMTP_HOST,
    port: SMTP_PORT,
    secure: SMTP_PORT === 465,
    auth: { user: SMTP_USER, pass: SMTP_PASS },
  });
  return _transporter;
}

export async function verifyTransport() {
  const tx = getTransport();
  return tx.verify();
}

// ---------------------------------------------------------------
//                 HTML-Layout (automatisch aus "text")
// ---------------------------------------------------------------
const CI = { blue:'#0b6bae', dark:'#1a1a1a', light:'#f6f8fb', border:'#e6ebf2' };

function textToParagraphs(txt=''){
  const blocks = String(txt).trim().split(/\n\s*\n/g);
  return blocks.map(s => `<p class="p">${escapeHtml(s).replace(/\n/g,'<br>')}</p>`).join('');
}

function htmlShell({ title, bodyHtml, lang = 'de' }){
  return `<!doctype html>
<html lang="${lang}"><head>
<meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
<title>${escapeHtml(title || '')}</title>
<style>
  body{margin:0;background:${CI.light};font-family:Inter,Segoe UI,Arial,Helvetica,sans-serif;color:${CI.dark}}
  a{color:${CI.blue};text-decoration:none}
  .wrap{padding:24px}
  .card{max-width:640px;margin:0 auto;background:#fff;border:1px solid ${CI.border};border-radius:16px;overflow:hidden;box-shadow:0 4px 14px rgba(0,0,0,.07)}
  .hdr{padding:20px 24px;border-bottom:1px solid ${CI.border};display:flex;gap:16px;align-items:center}
  .logo{width:120px;height:auto;display:block}
  .title{margin:0;color:${CI.blue};font-weight:700;font-size:18px;letter-spacing:.2px}
  .content{padding:24px}
  .p{margin:0 0 12px 0;line-height:1.55}
  .ftr{padding:16px 24px;border-top:1px solid ${CI.border};font-size:12px;color:#666;background:#fafbfe}
  @media (max-width:680px){.hdr{flex-direction:column;align-items:flex-start}.logo{width:140px}}
  @media (prefers-color-scheme: dark){
    body{background:#0e1013;color:#e9eef7}
    .card{background:#101418;border-color:#252a35}
    .hdr{border-color:#252a35}
    .ftr{background:#0e1013;border-color:#252a35;color:#9aa4b2}
  }
</style>
</head>
<body>
  <div class="wrap">
    <div class="card">
      <div class="hdr">
        <img class="logo" src="cid:dfslogo" alt="DFS-DIAMON">
        <h1 class="title">${escapeHtml(title || '')}</h1>
      </div>
      <div class="content">
        ${bodyHtml}
      </div>
      <div class="ftr">
        DFS-DIAMON GmbH · Ländenstraße 1 · 93339 Riedenburg · Germany ·
        <a href="mailto:complaint@dfs-diamon.de">complaint@dfs-diamon.de</a>
      </div>
    </div>
  </div>
</body></html>`;
}

function escapeHtml(s=''){ return String(s).replace(/[&<>"]/g, m => ({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;'}[m])); }

function logoAttachment(){
  // erwarte: /api/_assets/dfs-logo.png
  const p = path.join(process.cwd(), 'api', '_assets', 'dfs-logo.png');
  try {
    const content = fs.readFileSync(p);
    return [{ filename: 'dfs-logo.png', content, cid: 'dfslogo', contentType: 'image/png' }];
  } catch {
    return []; // ohne Logo senden, wenn Datei fehlt
  }
}

// ---------------------------------------------------------------
//                  I18N – unverändert zu deiner Logik
// ---------------------------------------------------------------
const SUPPORTED = new Set(['de','en','fr','it','es']);
const L = (lang) => SUPPORTED.has(lang) ? lang : 'de';

function cleanSubjectLine(subject) {
  return String(subject ?? '')
    .replace(/[\r\n]+/g, ' ')
    .replace(/\s{2,}/g, ' ')
    .trim();
}

function normalizeMessageBody(message) {
  return String(message ?? '')
    .replace(/\r\n/g, '\n')
    .trim();
}

const MC_SUBJECT_PREFIX = {
  de: '[DFS Kundenportal] Kopie Ihrer Nachricht',
  en: '[DFS Customer Portal] Copy of your message',
  fr: '[Portail DFS] Copie de votre message',
  it: '[Portale DFS] Copia del suo messaggio',
  es: '[Portal DFS] Copia de su mensaje',
};

const MC_SUBJECT_FALLBACK = {
  de: 'Ihre Nachricht an DFS-DIAMON',
  en: 'Your message to DFS-DIAMON',
  fr: 'Votre message à DFS-DIAMON',
  it: 'Il suo messaggio per DFS-DIAMON',
  es: 'Su mensaje a DFS-DIAMON',
};

const MC_GREETING = {
  de: (name) => `Guten Tag${name ? ` ${name}` : ''},`,
  en: (name) => `Dear ${name || 'customer'},`,
  fr: (name) => `Bonjour${name ? ` ${name}` : ''},`,
  it: (name) => `Gentile${name ? ` ${name}` : ''},`,
  es: (name) => `Hola${name ? ` ${name}` : ''},`,
};

const MC_INTRO = {
  de: {
    rep: 'vielen Dank für Ihre Nachricht über das DFS Kundenportal an Ihren Ansprechpartner bei DFS-DIAMON.',
    support: 'vielen Dank für Ihre Nachricht an den DFS Support über das DFS Kundenportal.',
  },
  en: {
    rep: 'thank you for your message via the DFS-DIAMON customer portal to your representative.',
    support: 'thank you for contacting the DFS support team via the DFS-DIAMON customer portal.',
  },
  fr: {
    rep: 'merci pour votre message transmis via le portail client DFS-DIAMON à votre interlocuteur commercial.',
    support: 'merci d’avoir contacté l’assistance DFS via le portail client DFS-DIAMON.',
  },
  it: {
    rep: 'grazie per il suo messaggio inviato tramite il portale clienti DFS-DIAMON al suo referente commerciale.',
    support: 'grazie per aver contattato il supporto DFS tramite il portale clienti DFS-DIAMON.',
  },
  es: {
    rep: 'gracias por su mensaje enviado a través del portal de clientes de DFS-DIAMON a su representante comercial.',
    support: 'gracias por contactar con el soporte de DFS a través del portal de clientes de DFS-DIAMON.',
  },
};

const MC_INFO = {
  de: 'Nachfolgend erhalten Sie eine Kopie Ihrer übermittelten Nachricht.',
  en: 'Below you will find a copy of the message you submitted.',
  fr: 'Vous trouverez ci-dessous une copie du message que vous avez transmis.',
  it: 'Di seguito trova una copia del messaggio trasmesso.',
  es: 'A continuación encontrará una copia del mensaje que envió.',
};

const MC_SUBJECT_LABEL = {
  de: 'Betreff',
  en: 'Subject',
  fr: 'Objet',
  it: 'Oggetto',
  es: 'Asunto',
};

const MC_MESSAGE_HEADING = {
  de: 'Nachricht',
  en: 'Message',
  fr: 'Message',
  it: 'Messaggio',
  es: 'Mensaje',
};

const MC_CLOSING = {
  de: 'Mit freundlichen Grüßen\nDFS-DIAMON Kundenportal',
  en: 'Kind regards\nDFS-DIAMON Customer Portal',
  fr: 'Cordialement\nPortail client DFS-DIAMON',
  it: 'Cordiali saluti\nPortale clienti DFS-DIAMON',
  es: 'Saludos cordiales\nPortal de clientes DFS-DIAMON',
};

function buildMessageConfirmation(lang, { name, subject, message, channel } = {}) {
  const channelKey = channel === 'support' ? 'support' : 'rep';
  const intro = MC_INTRO[lang][channelKey];
  const greeting = MC_GREETING[lang](name ? String(name).trim() : '');
  const info = MC_INFO[lang];
  const subjectLabel = MC_SUBJECT_LABEL[lang];
  const messageHeading = MC_MESSAGE_HEADING[lang];
  const closing = MC_CLOSING[lang];

  const cleanedSubject = cleanSubjectLine(subject);
  const subjectDisplay = cleanedSubject || MC_SUBJECT_FALLBACK[lang];
  const emailSubjectBase = MC_SUBJECT_PREFIX[lang];
  const emailSubject = cleanedSubject
    ? `${emailSubjectBase}: ${cleanedSubject}`
    : emailSubjectBase;

  const normalizedMessage = normalizeMessageBody(message);
  const messageDisplay = normalizedMessage || '—';

  const lines = [
    greeting,
    '',
    intro,
    info,
    '',
    `${subjectLabel}: ${subjectDisplay}`,
    '',
    `--- ${messageHeading} ---`,
    '',
    messageDisplay,
    '',
    closing,
  ];

  return {
    subject: emailSubject,
    text: lines.join('\n'),
  };
}

const TEXTS = {
  afterRegisterToCustomer: {
    de: (name)=>({ subject: 'Ihre Registrierung bei DFS-Diamon', text:
`Guten Tag ${name || ''},

vielen Dank für Ihre Registrierung bei der DFS-Diamon GmbH.
Ihr Kundenkonto wurde angelegt und befindet sich nun in Prüfung.
Nach erfolgreicher Freigabe informieren wir Sie per E-Mail.

Mit freundlichen Grüßen
DFS-Diamon GmbH – Quality Management` }),
    en: (name)=>({ subject: 'Your registration at DFS-Diamon', text:
`Dear ${name || 'customer'},

thank you for registering with DFS-Diamon GmbH.
Your account has been created and is pending review.
We will notify you by e-mail once it is approved.

Kind regards
DFS-DIAMON GmbH – Quality Management` }),
    fr: (name)=>({ subject: 'Votre inscription chez DFS-Diamon', text:
`Bonjour ${name || ''},

merci pour votre inscription auprès de DFS-Diamon GmbH.
Votre compte a été créé et est en cours de vérification.
Nous vous informerons par e-mail dès son approbation.

Cordialement
DFS-Diamon GmbH – Quality Management` }),
    it: (name)=>({ subject: 'Registrazione presso DFS-Diamon', text:
`Gentile ${name || ''},

grazie per la registrazione presso DFS-Diamon GmbH.
Il suo account è stato creato ed è in fase di verifica.
La informeremo via e-mail non appena sarà approvato.

Cordiali saluti
DFS-DIAMON GmbH – Quality Management` }),
    es: (name)=>({ subject: 'Su registro en DFS-Diamon', text:
`Hola ${name || ''},

gracias por registrarse en DFS-Diamon GmbH.
Su cuenta ha sido creada y está en revisión.
Le notificaremos por correo cuando sea aprobada.

Saludos cordiales
DFS-DIAMON GmbH – Quality Management` }),
  },

  afterRegisterToQM: {
    de: (email)=>({ subject: `Neue Kundenregistrierung: ${email}`, text: `Neue Registrierung eingegangen und wartet auf Freigabe: ${email}` }),
    en: (email)=>({ subject: `New customer registration: ${email}`, text: `A new registration is pending approval: ${email}` }),
    fr: (email)=>({ subject: `Nouvelle inscription client : ${email}`, text: `Une nouvelle inscription attend validation : ${email}` }),
    it: (email)=>({ subject: `Nuova registrazione cliente: ${email}`, text: `È in attesa di approvazione una nuova registrazione: ${email}` }),
    es: (email)=>({ subject: `Nuevo registro de cliente: ${email}`, text: `Hay un nuevo registro pendiente de aprobación: ${email}` }),
  },

  gateRequest: {
    de: (email, company)=>({ subject:'Freigabe-Passwort anfordern', text:
`Guten Tag Quality Management,

${email} hat soeben im DFS-DIAMON Kundenportal um Zusendung des temporären Registrierungs-Passworts gebeten.
Firma: ${company}

Bitte senden Sie dem Kunden das Freigabe-Passwort zu und unterstützen Sie bei Rückfragen.

Vielen Dank und freundliche Grüße
DFS-DIAMON Kundenportal` }),
    en: (email, company)=>({ subject:'Temporary password requested', text:
`Hello Quality Management,

${email} just requested the temporary registration password via the DFS-DIAMON customer portal.
Company: ${company}

Please provide the release password to the customer and assist with any questions.

Thank you and kind regards
DFS-DIAMON Customer Portal` }),
    fr: (email, company)=>({ subject:'Demande de mot de passe de déblocage', text:
`Bonjour Quality Management,

${email} vient de demander l’envoi du mot de passe d’inscription temporaire via le portail client DFS-DIAMON.
Entreprise : ${company}

Merci de transmettre au client le mot de passe de déblocage et de l’assister en cas de questions.

Merci et salutations distinguées
Portail client DFS-DIAMON` }),
    it: (email, company)=>({ subject:'Richiesta password di sblocco', text:
`Buongiorno Quality Management,

${email} ha appena richiesto tramite il portale clienti DFS-DIAMON l’invio della password di registrazione temporanea.
Azienda: ${company}

Si prega di inviare al cliente la password di sblocco e di offrirgli supporto per eventuali domande.

Grazie e cordiali saluti
Portale clienti DFS-DIAMON` }),
    es: (email, company)=>({ subject:'Solicitud de contraseña de desbloqueo', text:
`Hola Quality Management,

${email} acaba de solicitar a través del portal de clientes de DFS-DIAMON el envío de la contraseña de registro temporal.
Empresa: ${company}

Por favor, envíe al cliente la contraseña de desbloqueo y bríndele apoyo ante cualquier consulta.

Muchas gracias y un cordial saludo
Portal de clientes DFS-DIAMON` }),
  },

  approved: {
    de: (name)=>({ subject:'Ihr DFS-Kundenkonto wurde freigeschaltet', text:
`Guten Tag ${name || ''},

Ihr Kundenkonto bei der DFS-Diamon GmbH wurde soeben freigeschaltet.
Sie können sich ab sofort anmelden und Reklamationen online übermitteln.

Mit freundlichen Grüßen
DFS-DIAMON GmbH – Quality Management` }),
    en: (name)=>({ subject:'Your DFS account has been approved', text:
`Dear ${name || 'customer'},

your account at DFS-Diamon GmbH has just been approved.
You can now log in and submit complaints online.

Kind regards
DFS-DIAMON GmbH – Quality Management` }),
    fr: (name)=>({ subject:`Votre compte DFS a été activé`, text:
`Bonjour ${name || ''},

votre compte chez DFS-Diamon GmbH vient d’être activé.
Vous pouvez maintenant vous connecter et soumettre des réclamations en ligne.

Cordialement
DFS-DIAMON GmbH – Quality Management` }),
    it: (name)=>({ subject:`Il suo account DFS è stato attivato`, text:
`Gentile ${name || ''},

il suo account presso DFS-Diamon GmbH è stato approvato.
Può ora effettuare l’accesso e inviare reclami online.

Cordiali saluti
DFS-DIAMON GmbH – Quality Management` }),
    es: (name)=>({ subject:`Su cuenta de DFS ha sido activada`, text:
`Hola ${name || ''},

su cuenta en DFS-Diamon GmbH ha sido aprobada.
Ya puede iniciar sesión y enviar reclamaciones en línea.

Saludos cordiales
DFS-DIAMON GmbH – Quality Management` }),
  },

  complaintCustomer: {
    de: (ticket)=>({ subject:`Eingangsbestätigung – Reklamation [TICKET ${ticket}]`, text:
`Vielen Dank für Ihre Mitteilung.
Ihre Reklamation wurde unter der Ticketnummer ${ticket} erfasst.
Wir informieren Sie bei Statusänderungen.` }),
    en: (ticket)=>({ subject:`Acknowledgement – Complaint [TICKET ${ticket}]`, text:
`Thank you for your message.
Your complaint has been recorded under ticket ${ticket}.
We will inform you when the status changes.` }),
    fr: (ticket)=>({ subject:`Accusé de réception – Réclamation [TICKET ${ticket}]`, text:
`Merci pour votre message.
Votre réclamation a été enregistrée sous le ticket ${ticket}.
Nous vous informerons en cas de changement d’état.` }),
    it: (ticket)=>({ subject:`Conferma di ricezione – Reclamo [TICKET ${ticket}]`, text:
`Grazie per il suo messaggio.
Il reclamo è stato registrato con il ticket ${ticket}.
La informeremo in caso di cambiamenti di stato.` }),
    es: (ticket)=>({ subject:`Acuse de recibo – Reclamación [TICKET ${ticket}]`, text:
`Gracias por su mensaje.
Su reclamación se ha registrado con el ticket ${ticket}.
Le informaremos si cambia el estado.` }),
  },

  messageConfirmation: {
    de: (data)=>buildMessageConfirmation('de', data),
    en: (data)=>buildMessageConfirmation('en', data),
    fr: (data)=>buildMessageConfirmation('fr', data),
    it: (data)=>buildMessageConfirmation('it', data),
    es: (data)=>buildMessageConfirmation('es', data),
  },

  adminWelcomePassword: {
    de: ({ name, password }) => ({
      subject: 'Willkommen im DFS Kundenportal',
      text: `Guten Tag${name ? ` ${name}` : ''},

Ihr Zugang zum DFS Kundenportal wurde soeben aktiviert.
Für den ersten Login wurde automatisch folgendes Passwort vergeben (systemgeneriert):
${password}

Bitte ändern Sie dieses Passwort nach dem ersten Login in Ihrem Profilbereich.

Mit freundlichen Grüßen
DFS-DIAMON GmbH – Quality Management`,
    }),
    en: ({ name, password }) => ({
      subject: 'Welcome to the DFS customer portal',
      text: `Dear ${name || 'customer'},

Your access to the DFS customer portal has been created.
For your first login we generated the following temporary password:
${password}

This password was generated automatically by the system. Please change it after your first login via the profile section.

Kind regards
DFS-DIAMON GmbH – Quality Management`,
    }),
    fr: ({ name, password }) => ({
      subject: 'Bienvenue sur le portail client DFS',
      text: `Bonjour${name ? ` ${name}` : ''},

votre accès au portail client DFS-DIAMON vient d'être créé.
Pour votre première connexion, le mot de passe temporaire suivant a été généré automatiquement :
${password}

Il s'agit d'un mot de passe généré par le système. Merci de le modifier après votre première connexion dans votre profil.

Cordialement
DFS-DIAMON GmbH – Quality Management`,
    }),
    it: ({ name, password }) => ({
      subject: 'Accesso al portale clienti DFS',
      text: `Gentile${name ? ` ${name}` : ''},

abbiamo appena creato il suo accesso al portale clienti DFS-DIAMON.
Per il primo login è stata generata automaticamente la seguente password temporanea:
${password}

Si tratta di una password generata dal sistema. La preghiamo di cambiarla dopo il primo accesso tramite il profilo.

Cordiali saluti
DFS-DIAMON GmbH – Quality Management`,
    }),
    es: ({ name, password }) => ({
      subject: 'Bienvenido al portal de clientes de DFS',
      text: `Hola${name ? ` ${name}` : ''},

acabamos de crear su acceso al portal de clientes de DFS-DIAMON.
Para el primer inicio de sesión hemos generado automáticamente la siguiente contraseña temporal:
${password}

Se trata de una contraseña generada por el sistema. Cámbiela después de su primer inicio de sesión en el apartado del perfil.

Saludos cordiales
DFS-DIAMON GmbH – Quality Management`,
    }),
  },
};

export const tpl = {
  afterRegisterToCustomer: (name, lang='de')   => TEXTS.afterRegisterToCustomer[L(lang)](name),
  afterRegisterToQM:       (email, lang='de')  => TEXTS.afterRegisterToQM[L(lang)](email),
  gateRequest:             (email, lang='de')  => TEXTS.gateRequest[L(lang)](email),
  approved:                (name, lang='de')   => TEXTS.approved[L(lang)](name),
  complaintCustomer:       (ticket, lang='de') => TEXTS.complaintCustomer[L(lang)](ticket),
  messageConfirmation:     (data, lang='de')   => TEXTS.messageConfirmation[L(lang)](data),
  adminWelcomePassword:    (data, lang='de')   => TEXTS.adminWelcomePassword[L(lang)](data),
};

// ---- Senden: nimmt {subject,text}, baut HTML+Logo, nutzt lazy Transport ----
function cleanAddress(v) {
  return (typeof v === 'string' ? v : '').trim();
}

function normalizeAddressList(value) {
  if (!value) return [];
  const arr = Array.isArray(value) ? value : [value];
  return arr.map(cleanAddress).filter((addr) => addr.length > 0);
}

export async function send(
  to,
  { subject, text, lang = 'de', from, replyTo, cc },
  attachments = [],
) {
  const html = htmlShell({ title: subject, bodyHtml: textToParagraphs(text), lang });
  const atts = [...logoAttachment(), ...attachments];

  // Standard-Absender ist die konfigurierte MAIL.from (zertifiziert/verifiziert
  // bei Brevo). Der SMTP-Login (z. B. "apikey") ist *nicht* als From-Adresse
  // geeignet und führte dazu, dass Brevo die Mails zwar akzeptierte, aber
  // nicht zählte/auslieferte. Daher immer MAIL.from verwenden, sofern nicht
  // explizit übergeben.
  const fromAddress = cleanAddress(from) || FROM;
  const replyToAddress =
    replyTo !== undefined
      ? cleanAddress(replyTo)
      : REPLY_TO;

  let meta = null;
  try { meta = await loadAppMeta(); } catch (_) {}
  const routing = applyTestMailRouting(meta, { to, cc, subject });
  const toList = normalizeAddressList(routing.to?.length ? routing.to : to);
  const ccList = normalizeAddressList(routing.cc?.length ? routing.cc : cc);
  const subjectOut = routing.subject || subject;

  if (routing.suppressed) {
    console.warn('[mail] test mode active – suppressing mail send', { to });
    return { accepted: [], rejected: [], envelope: {}, messageId: null, testMode: true };
  }

  const mailOptions = {
    from: fromAddress,
    to: toList,
    subject: subjectOut,
    text,
    html,
    attachments: atts,
  };

  // Absender der SMTP-Sitzung als technischer Sender mitschicken, falls
  // vorhanden (wird von Brevo toleriert, aber nur, wenn es eine gültige Mail
  // ist; andernfalls weglassen).
  const senderAddress = cleanAddress(SMTP_USER);
  if (senderAddress && senderAddress.includes('@') && senderAddress !== fromAddress) {
    mailOptions.sender = senderAddress;
  }

  if (replyToAddress) {
    mailOptions.replyTo = replyToAddress;
  }

  if (ccList.length === 1) {
    mailOptions.cc = ccList[0];
  } else if (ccList.length > 1) {
    mailOptions.cc = ccList;
  }

  const info = await sendWithRetry(mailOptions);
  console.log('mail: sent', {
    to,
    messageId: info.messageId,
    accepted: info.accepted,
    response: info.response,
  });
  return info;
}

export async function notifyQM(msg) {
  if (!QM) return;
  return send(QM, msg);
}

async function sendWithRetry(mailOptions, { attempts = 3, baseDelayMs = 1000 } = {}) {
  let lastError;
  for (let attempt = 1; attempt <= attempts; attempt++) {
    try {
      return await getTransport().sendMail(mailOptions);
    } catch (err) {
      lastError = err;
      if (!isTemporarySmtpError(err) || attempt === attempts) {
        throw err;
      }

      const delay = baseDelayMs * attempt;
      console.warn('mail: temporary SMTP error, retrying', {
        attempt,
        delay,
        code: err?.code,
        responseCode: err?.responseCode,
        command: err?.command,
      });
      await wait(delay);
    }
  }

  throw lastError;
}

function isTemporarySmtpError(err) {
  const responseCode = typeof err?.responseCode === 'number' ? err.responseCode : null;
  if (responseCode && responseCode >= 400 && responseCode < 500) {
    return true;
  }

  const smtpCode = parseInt(String(err?.code ?? ''), 10);
  return smtpCode >= 400 && smtpCode < 500;
}

function wait(ms) {
  return new Promise((resolve) => setTimeout(resolve, ms));
}
