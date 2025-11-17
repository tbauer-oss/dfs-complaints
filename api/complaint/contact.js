
Skip to content
Navigation Menu
tbauer-oss
dfs-complaints

Code
Issues
Pull requests 6
Actions
Projects
Wiki
Security 1
Insights

    Settings

Add customer complaint contact form #75
✨
Open
tbauer-oss wants to merge 1 commit into main from codex/add-contact-form-for-complaints-in-customer-area
+506 −3
Conversation 1
Commits 1
Checks 1
Files changed 9
Open
Add customer complaint contact form
#75
File filter
0 / 9 files viewed

16 changes: 15 additions & 1 deletion 16
api/_lib/mail.js
Viewed
Original file line number 	Diff line number 	Diff line change
@@ -445,9 +445,15 @@ function cleanAddress(v) {
  return (typeof v === 'string' ? v : '').trim();
}

function normalizeAddressList(value) {
  if (!value) return [];
  const arr = Array.isArray(value) ? value : [value];
  return arr.map(cleanAddress).filter((addr) => addr.length > 0);
}

export async function send(
  to,
  { subject, text, lang = 'de', from, replyTo },
  { subject, text, lang = 'de', from, replyTo, cc },
  attachments = [],
) {
  const html = htmlShell({ title: subject, bodyHtml: textToParagraphs(text), lang });
@@ -459,6 +465,8 @@ export async function send(
      ? cleanAddress(replyTo)
      : (fromAddress === SMTP_USER ? REPLY_TO : fromAddress);

  const ccList = normalizeAddressList(cc);

  const mailOptions = {
    from: fromAddress,
    to,
@@ -476,6 +484,12 @@ export async function send(
    mailOptions.replyTo = replyToAddress;
  }

  if (ccList.length === 1) {
    mailOptions.cc = ccList[0];
  } else if (ccList.length > 1) {
    mailOptions.cc = ccList;
  }

  const info = await getTransport().sendMail(mailOptions);
  console.log('mail: sent', { to, messageId: info.messageId });
  return info;
161 changes: 161 additions & 0 deletions 161
api/complaint/contact.js
Copied!
Viewed
Original file line number 	Diff line number 	Diff line change
@@ -0,0 +1,161 @@
// api/complaint/contact.js
export const config = { runtime: 'nodejs' };

import { setCors, noContent, ok, bad, methodNotAllowed, readJson } from '../_lib/http.js';
import { getAuthUser } from '../_lib/auth.js';
import { complaintGet, userByEmail } from '../_lib/store.js';
import { getRepOf } from '../_lib/repsStore.js';
import { send, tpl } from '../_lib/mail.js';

const QM_MAIL = process.env.MAIL_QM || 'complaint@dfs-diamon.de';
const LANGS = new Set(['de', 'en', 'fr', 'it', 'es']);

const S = (v) => (v ?? '').toString().trim();
const lower = (v) => S(v).toLowerCase();

function firstNonEmpty(...values) {
  for (const value of values) {
    const s = S(value);
    if (s.length > 0) return s;
  }
  return '';
}

function normLang(value) {
  const raw = String(value || '').toLowerCase();
  const two = raw.split(/[-_]/)[0];
  return LANGS.has(two) ? two : 'de';
}

function sanitizeSubject(value) {
  return S(value).replace(/[\r\n]+/g, ' ').trim();
}

function normalizeMessage(value) {
  return S(value).replace(/\r\n/g, '\n');
}

export default async function handler(req, res) {
  setCors(req, res);
  if (req.method === 'OPTIONS') return noContent(res);
  if (req.method !== 'POST') return methodNotAllowed(res);

  const user = getAuthUser(req);
  if (!user?.email) return bad(res, 'unauthorized', 401);

  try {
    const body = readJson(req);
    const ticket = S(body?.ticket).toUpperCase();
    const subject = sanitizeSubject(body?.subject);
    const message = normalizeMessage(body?.message);

    if (!ticket) return bad(res, 'ticket required', 400);
    if (!subject || !message) return bad(res, 'subject and message required', 400);

    const comp = await complaintGet(ticket);
    if (!comp) return bad(res, 'not found', 404);

    const userMail = lower(user.email);
    const compMail = lower(comp.email);
    if (!userMail || userMail !== compMail) return bad(res, 'forbidden', 403);

    let rep = null;
    try {
      rep = await getRepOf(userMail);
    } catch (err) {
      console.warn('[complaint/contact] failed to load rep', err?.message || err);
    }
    const repEmail = S(rep?.email);
    const hasRep = repEmail.includes('@');

    const target = hasRep ? repEmail : QM_MAIL;
    if (!target) return bad(res, 'recipient missing', 500);
    const cc = hasRep && QM_MAIL ? [QM_MAIL] : [];

    let account = null;
    try {
      account = await userByEmail(userMail);
    } catch (err) {
      console.warn('[complaint/contact] failed to load account', err?.message || err);
    }
    const payload = (comp?.payload && typeof comp.payload === 'object') ? comp.payload : {};

    const company = firstNonEmpty(
      account?.company,
      comp?.company,
      payload?.company,
      payload?.customerName,
      payload?.firma,
    );

    const accountName = `${S(account?.firstName)} ${S(account?.lastName)}`.trim();
    const contactName = firstNonEmpty(
      account?.contact,
      account?.contactName,
      account?.name,
      accountName,
      payload?.contact,
      payload?.contactName,
    );

    const lang = normLang(user?.lang || account?.lang || payload?.lang || req.headers['accept-language']);

    const repDisplay = hasRep
      ? firstNonEmpty(
          [S(rep?.firstName), S(rep?.lastName)].filter(Boolean).join(' ').trim(),
          repEmail,
        )
      : '';

    const lines = [
      'Kontakt über das DFS Kundenportal – Reklamation',
      '',
      `Ticket: ${ticket}`,
      `Kunde: ${company || '(unbekannt)'}`,
      `Kunden-E-Mail: ${user.email}`,
    ];
    if (contactName) lines.push(`Kontaktperson: ${contactName}`);
    if (hasRep) {
      lines.push(`Zugewiesener Ansprechpartner: ${repDisplay}`);
    } else {
      lines.push('Kein Ansprechpartner zugeordnet – Nachricht wird an complaint@dfs-diamon.de gesendet.');
    }
    lines.push('');
    lines.push(`Betreff: ${subject}`);
    lines.push('');
    lines.push('--- Nachricht ---');
    lines.push('');
    lines.push(message);

    const mailSubject = `[DFS Complaint ${ticket}] ${subject}`;

    await send(target, {
      subject: mailSubject,
      text: lines.join('\n'),
      lang: 'de',
      cc,
    });

    if (user.email) {
      try {
        const confirmation = tpl.messageConfirmation(
          {
            name: contactName,
            subject,
            message,
            channel: hasRep ? 'rep' : 'support',
          },
          lang,
        );
        await send(user.email, { ...confirmation, lang });
      } catch (err) {
        console.error('[complaint/contact] confirmation mail failed', err);
      }
    }

    return ok(res, { ok: true, viaRep: hasRep });
  } catch (err) {
    console.error('[complaint/contact] error', err);
    return bad(res, 'server error', 500);
  }
}
15 changes: 15 additions & 0 deletions 15
flutter_web/lib/api/client.dart
Viewed
Original file line number 	Diff line number 	Diff line change
@@ -1009,6 +1009,21 @@ class ApiClient {
    return const <String, dynamic>{};
  }

  Future<void> complaintContact({
    required String ticket,
    required String subject,
    required String message,
  }) async {
    final r = await _post(
      '/api/complaint/contact',
      {'ticket': ticket, 'subject': subject, 'message': message},
      auth: true,
    );
    if (!_ok2xx(r.statusCode)) {
      throw ApiError(r.statusCode, _extractMessage(r.body));
    }
  }

  Future<List<Map<String, dynamic>>> complaintListRaw() async {
    final r = await _get('/api/complaint/mine', auth: true);
    if (!_ok2xx(r.statusCode)) {
26 changes: 26 additions & 0 deletions 26
flutter_web/lib/l10n/app_de.arb
Viewed
Original file line number 	Diff line number 	Diff line change
@@ -119,6 +119,32 @@
  "@allCompanies": { "description": "Filteroption, um alle Unternehmen anzuzeigen" },
  "yourCompany": "Ihr Unternehmen",
  "we_are_here_for_you": "Wir sind für Sie da.",
  "complaint_contact_button": "Kontakt aufnehmen",
  "complaint_contact_title": "Nachricht zu Ticket {ticket}",
  "@complaint_contact_title": {
    "placeholders": {
      "ticket": { "type": "String" }
    }
  },
  "complaint_contact_intro_rep": "Ihre Nachricht wird an {repName} ({repEmail}) gesendet. complaint@dfs-diamon.de erhält eine Kopie.",
  "@complaint_contact_intro_rep": {
    "placeholders": {
      "repName": { "type": "String" },
      "repEmail": { "type": "String" }
    }
  },
  "complaint_contact_intro_qm": "Es ist kein Ansprechpartner zugeordnet. Ihre Nachricht wird direkt an {email} gesendet.",
  "@complaint_contact_intro_qm": {
    "placeholders": {
      "email": { "type": "String" }
    }
  },
  "complaint_contact_subject_prefill": "Rückfrage zu Ticket {ticket}",
  "@complaint_contact_subject_prefill": {
    "placeholders": {
      "ticket": { "type": "String" }
    }
  },
  "rep_contact_form": "Nachricht senden",
  "rep_contact_title": "Kontakt zum Vertreter",
  "rep_contact_intro": "Sie schreiben an {firstName} {lastName}. Bitte füllen Sie die folgenden Felder aus.",
26 changes: 26 additions & 0 deletions 26
flutter_web/lib/l10n/app_en.arb
Viewed
Original file line number 	Diff line number 	Diff line change
@@ -121,6 +121,32 @@
  "@allCompanies": { "description": "Filter option to show all companies" },
  "yourCompany": "Your company",
  "we_are_here_for_you": "We are here for you.",
  "complaint_contact_button": "Contact",
  "complaint_contact_title": "Message about ticket {ticket}",
  "@complaint_contact_title": {
    "placeholders": {
      "ticket": { "type": "String" }
    }
  },
  "complaint_contact_intro_rep": "Your message will be sent to {repName} ({repEmail}). complaint@dfs-diamon.de receives a copy.",
  "@complaint_contact_intro_rep": {
    "placeholders": {
      "repName": { "type": "String" },
      "repEmail": { "type": "String" }
    }
  },
  "complaint_contact_intro_qm": "No representative is assigned. Your message will be sent directly to {email}.",
  "@complaint_contact_intro_qm": {
    "placeholders": {
      "email": { "type": "String" }
    }
  },
  "complaint_contact_subject_prefill": "Question about ticket {ticket}",
  "@complaint_contact_subject_prefill": {
    "placeholders": {
      "ticket": { "type": "String" }
    }
  },
  "rep_contact_form": "Send message",
  "rep_not_assigned": "Currently no representative is assigned.",
  "rep_contact_title": "Contact representative",
26 changes: 26 additions & 0 deletions 26
flutter_web/lib/l10n/app_es.arb
Viewed
Original file line number 	Diff line number 	Diff line change
@@ -117,6 +117,32 @@
  "@allCompanies": { "description": "Opción de filtro para mostrar todas las empresas" },
  "yourCompany": "Su empresa",
  "we_are_here_for_you": "Estamos aquí para usted.",
  "complaint_contact_button": "Contactar",
  "complaint_contact_title": "Mensaje sobre el ticket {ticket}",
  "@complaint_contact_title": {
    "placeholders": {
      "ticket": { "type": "String" }
    }
  },
  "complaint_contact_intro_rep": "Su mensaje se enviará a {repName} ({repEmail}). complaint@dfs-diamon.de recibirá una copia.",
  "@complaint_contact_intro_rep": {
    "placeholders": {
      "repName": { "type": "String" },
      "repEmail": { "type": "String" }
    }
  },
  "complaint_contact_intro_qm": "No hay ningún representante asignado. Su mensaje se enviará directamente a {email}.",
  "@complaint_contact_intro_qm": {
    "placeholders": {
      "email": { "type": "String" }
    }
  },
  "complaint_contact_subject_prefill": "Consulta sobre el ticket {ticket}",
  "@complaint_contact_subject_prefill": {
    "placeholders": {
      "ticket": { "type": "String" }
    }
  },
  "rep_contact_form": "Enviar mensaje",
  "rep_not_assigned": "Actualmente no hay ningún representante asignado.",
  "rep_contact_title": "Contacto con el representante",
26 changes: 26 additions & 0 deletions 26
flutter_web/lib/l10n/app_fr.arb
Viewed
Original file line number 	Diff line number 	Diff line change
@@ -118,6 +118,32 @@
  "@allCompanies": { "description": "Option de filtre pour afficher toutes les entreprises" },
  "yourCompany": "Votre entreprise",
  "we_are_here_for_you": "Nous sommes là pour vous.",
  "complaint_contact_button": "Contacter",
  "complaint_contact_title": "Message concernant le ticket {ticket}",
  "@complaint_contact_title": {
    "placeholders": {
      "ticket": { "type": "String" }
    }
  },
  "complaint_contact_intro_rep": "Votre message sera envoyé à {repName} ({repEmail}). complaint@dfs-diamon.de recevra une copie.",
  "@complaint_contact_intro_rep": {
    "placeholders": {
      "repName": { "type": "String" },
      "repEmail": { "type": "String" }
    }
  },
  "complaint_contact_intro_qm": "Aucun interlocuteur n’est attribué. Votre message sera envoyé directement à {email}.",
  "@complaint_contact_intro_qm": {
    "placeholders": {
      "email": { "type": "String" }
    }
  },
  "complaint_contact_subject_prefill": "Question concernant le ticket {ticket}",
  "@complaint_contact_subject_prefill": {
    "placeholders": {
      "ticket": { "type": "String" }
    }
  },
  "rep_contact_form": "Envoyer un message",
  "rep_not_assigned": "Actuellement aucun représentant n’est attribué.",
  "rep_contact_title": "Contacter le représentant",
26 changes: 26 additions & 0 deletions 26
flutter_web/lib/l10n/app_it.arb
Viewed
Original file line number 	Diff line number 	Diff line change
@@ -118,6 +118,32 @@
  "@allCompanies": { "description": "Opzione di filtro per mostrare tutte le aziende" },
  "yourCompany": "La vostra azienda",
  "we_are_here_for_you": "Siamo qui per voi.",
  "complaint_contact_button": "Contattare",
  "complaint_contact_title": "Messaggio sul ticket {ticket}",
  "@complaint_contact_title": {
    "placeholders": {
      "ticket": { "type": "String" }
    }
  },
  "complaint_contact_intro_rep": "Il suo messaggio verrà inviato a {repName} ({repEmail}). complaint@dfs-diamon.de riceverà una copia.",
  "@complaint_contact_intro_rep": {
    "placeholders": {
      "repName": { "type": "String" },
      "repEmail": { "type": "String" }
    }
  },
  "complaint_contact_intro_qm": "Non è assegnato alcun referente. Il messaggio verrà inviato direttamente a {email}.",
  "@complaint_contact_intro_qm": {
    "placeholders": {
      "email": { "type": "String" }
    }
  },
  "complaint_contact_subject_prefill": "Richiesta sul ticket {ticket}",
  "@complaint_contact_subject_prefill": {
    "placeholders": {
      "ticket": { "type": "String" }
    }
  },
  "rep_contact_form": "Inviare messaggio",
  "rep_not_assigned": "Attualmente non è assegnato alcun referente.",
  "rep_contact_title": "Contatta il rappresentante",
187 changes: 185 additions & 2 deletions 187
flutter_web/lib/pages/my_complaints_page.dart
Viewed
Original file line number 	Diff line number 	Diff line change
@@ -8,6 +8,8 @@ import '../models/complaint.dart';
import '../l10n/app_localizations.dart';
import '../widgets/legal_footer.dart';

const _kComplaintMail = 'complaint@dfs-diamon.de';

class MyComplaintsPage extends StatefulWidget {
  final ApiClient api;
  const MyComplaintsPage({super.key, required this.api});
@@ -317,6 +319,27 @@ class _MyComplaintsPageState extends State<MyComplaintsPage> {
    }
  }

  Future<void> _openComplaintContactForm(Complaint c) async {
    final t = AppLocalizations.of(context)!;
    final initialSubject = t.complaint_contact_subject_prefill(c.ticket);

    final sent = await showDialog<bool>(
      context: context,
      builder: (ctx) => _ComplaintContactDialog(
        api: widget.api,
        complaint: c,
        rep: _myRep,
        initialSubject: initialSubject,
      ),
    );

    if (sent == true && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(t.rep_contact_sent)),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context)!;
@@ -449,6 +472,24 @@ class _MyComplaintsPageState extends State<MyComplaintsPage> {
                                  label: Text(t.attachments_add),
                                );

                                final contactButton = TextButton.icon(
                                  onPressed:
                                      _busy ? null : () => _openComplaintContactForm(c),
                                  icon: const Icon(Icons.mail_outline),
                                  label: Text(t.complaint_contact_button),
                                );

                                final actionButtons = Wrap(
                                  spacing: 8,
                                  runSpacing: 8,
                                  crossAxisAlignment: WrapCrossAlignment.center,
                                  alignment: WrapAlignment.end,
                                  children: [
                                    attachmentsButton,
                                    contactButton,
                                  ],
                                );

                                final infoWrap = Wrap(
                                  spacing: 8,
                                  runSpacing: 8,
@@ -485,7 +526,7 @@ class _MyComplaintsPageState extends State<MyComplaintsPage> {
                                          const SizedBox(height: 8),
                                          Align(
                                            alignment: Alignment.centerRight,
                                            child: attachmentsButton,
                                            child: actionButtons,
                                          ),
                                        ],
                                      );
@@ -496,7 +537,7 @@ class _MyComplaintsPageState extends State<MyComplaintsPage> {
                                      children: [
                                        Expanded(child: infoWrap),
                                        const SizedBox(width: 12),
                                        attachmentsButton,
                                        actionButtons,
                                      ],
                                    );
                                  },
@@ -853,6 +894,148 @@ class _StatusPill extends StatelessWidget {
  }
}

class _ComplaintContactDialog extends StatefulWidget {
  final ApiClient api;
  final Complaint complaint;
  final MyRep? rep;
  final String initialSubject;

  const _ComplaintContactDialog({
    required this.api,
    required this.complaint,
    required this.initialSubject,
    this.rep,
  });

  @override
  State<_ComplaintContactDialog> createState() => _ComplaintContactDialogState();
}

class _ComplaintContactDialogState extends State<_ComplaintContactDialog> {
  late final TextEditingController _subjectCtrl;
  final TextEditingController _messageCtrl = TextEditingController();
  bool _sending = false;

  @override
  void initState() {
    super.initState();
    _subjectCtrl = TextEditingController(text: widget.initialSubject);
  }

  @override
  void dispose() {
    _subjectCtrl.dispose();
    _messageCtrl.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    final t = AppLocalizations.of(context)!;
    final subject = _subjectCtrl.text.trim();
    final message = _messageCtrl.text.trim();

    if (subject.isEmpty || message.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(t.rep_contact_validation)),
      );
      return;
    }

    setState(() => _sending = true);
    try {
      await widget.api.complaintContact(
        ticket: widget.complaint.ticket,
        subject: subject,
        message: message,
      );
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } catch (e) {
      if (!mounted) return;
      final errText = (e is ApiError && e.message.isNotEmpty)
          ? '${t.rep_contact_error} (${e.message})'
          : t.rep_contact_error;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(errText)),
      );
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context)!;
    final rep = widget.rep;
    final repEmail = (rep?.email ?? '').trim();
    final hasRep = repEmail.isNotEmpty;
    final displayName = (rep?.displayName ?? '').trim();
    final repName = displayName.isNotEmpty ? displayName : repEmail;

    final infoText = hasRep
        ? t.complaint_contact_intro_rep(repName, repEmail)
        : t.complaint_contact_intro_qm(_kComplaintMail);

    return AlertDialog(
      title: Text(t.complaint_contact_title(widget.complaint.ticket)),
      content: SizedBox(
        width: 520,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                infoText,
                style: Theme.of(context)
                    .textTheme
                    .bodyMedium
                    ?.copyWith(color: Theme.of(context).colorScheme.onSurface.withOpacity(.8)),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _subjectCtrl,
                decoration: InputDecoration(
                  labelText: t.rep_contact_subject_label,
                  prefixIcon: const Icon(Icons.subject),
                ),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _messageCtrl,
                minLines: 5,
                maxLines: 10,
                decoration: InputDecoration(
                  labelText: t.rep_contact_message_label,
                  alignLabelWithHint: true,
                  prefixIcon: const Icon(Icons.message_outlined),
                ),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _sending ? null : () => Navigator.of(context).pop(false),
          child: Text(t.cancel),
        ),
        ElevatedButton.icon(
          onPressed: _sending ? null : _send,
          icon: _sending
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.send_outlined),
          label: Text(t.send),
        ),
      ],
    );
  }
}

class _KeyValuePill extends StatelessWidget {
  final IconData icon;
  final String label;
Footer
© 2025 GitHub, Inc.
Footer navigation

    Terms
    Privacy
    Security
    Status
    Community
    Docs
    Contact

Copied!
