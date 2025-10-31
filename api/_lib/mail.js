// /api/_lib/mail.js  (robust, lazy transport, 465/587 Auto)
import nodemailer from 'nodemailer';
import fs from 'fs';
import path from 'path';

// ==== Absender / QM (via ENV übersteuerbar) ====
const FROM     = process.env.MAIL_FROM || 'DFS Complaints <no-reply_dfs-complaints@gmx.net>';
const REPLY_TO = process.env.MAIL_REPLY_TO || 'complaint@dfs-diamon.de';
const QM       = process.env.MAIL_QM || 'complaint@dfs-diamon.de';

// ==== SMTP-ENV ====
const SMTP_HOST = process.env.SMTP_HOST;                // z.B. mail.gmx.net
const SMTP_PORT = Number(process.env.SMTP_PORT || 587); // 587=STARTTLS, 465=SMTPS
const SMTP_USER = process.env.SMTP_USER;                // z.B. no-reply_dfs-complaints@gmx.net
const SMTP_PASS = process.env.SMTP_PASS;

let _transporter = null;

function ensureEnv() {
  if (!SMTP_HOST || !SMTP_USER || !SMTP_PASS) {
    throw new Error('SMTP env missing (SMTP_HOST, SMTP_USER, SMTP_PASS)');
  }
}

function getTransport() {
  if (_transporter) return _transporter;
  ensureEnv();
  _transporter = nodemailer.createTransport({
    host: SMTP_HOST,
    port: SMTP_PORT,
    secure: SMTP_PORT === 465,           // <-- Korrekt: NUR 465 ist "secure:true"
    auth: { user: SMTP_USER, pass: SMTP_PASS },
    tls: { minVersion: 'TLSv1.2', servername: SMTP_HOST },
    pool: true, maxConnections: 2, maxMessages: 20,
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
};

export const tpl = {
  afterRegisterToCustomer: (name, lang='de')   => TEXTS.afterRegisterToCustomer[L(lang)](name),
  afterRegisterToQM:       (email, lang='de')  => TEXTS.afterRegisterToQM[L(lang)](email),
  approved:                (name, lang='de')   => TEXTS.approved[L(lang)](name),
  complaintCustomer:       (ticket, lang='de') => TEXTS.complaintCustomer[L(lang)](ticket),
};

// ---- Senden: nimmt {subject,text}, baut HTML+Logo, nutzt lazy Transport ----
export async function send(to, { subject, text, lang = 'de' }, attachments = []) {
  const html = htmlShell({ title: subject, bodyHtml: textToParagraphs(text), lang });
  const atts = [...logoAttachment(), ...attachments];

  const VISIBLE_FROM = 'DFS-DIAMON QM <complaint@dfs-diamon.de>';
  const GMX_LOGIN   = process.env.SMTP_USER; // z.B. no-reply_dfs-complaints@gmx.net

  const info = await getTransport().sendMail({
    from: VISIBLE_FROM,          // sichtbarer From (was der Kunde sieht)
    sender: GMX_LOGIN,           // RFC 5322 "Sender" (wer technisch sendet)
    replyTo: 'complaint@dfs-diamon.de', // Antworten hierhin
    envelope: {                  // SMTP-Envelope (MAIL FROM) = GMX (verhindert Ablehnung)
      from: GMX_LOGIN,
      to: Array.isArray(to) ? to : [to],
    },
    to,
    subject,
    text,
    html,
    attachments: atts,
  });
  console.log('mail: sent', { to, messageId: info.messageId });
  return info;
}

export async function notifyQM(msg) {
  if (!QM) return;
  return send(QM, msg);
}
