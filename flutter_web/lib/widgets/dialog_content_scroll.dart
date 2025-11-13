
Skip to content
Navigation Menu
tbauer-oss
dfs-complaints

Code
Issues
Pull requests 10
Actions
Projects
Security
Insights

    Settings

Align flutter_web mobile UI with dfs_mobile #18
✨
Open
tbauer-oss wants to merge 1 commit into main from codex/update-flutter_web-for-mobile-responsiveness
+6,493 −3,263
Conversation 1
Commits 1
Checks 1
Files changed 30
Open
Align flutter_web mobile UI with dfs_mobile
#18
File filter
0 / 30 files viewed

337 changes: 163 additions & 174 deletions 337
flutter_web/lib/api/client.dart
Viewed

Large diffs are not rendered by default.
59 changes: 50 additions & 9 deletions 59
flutter_web/lib/l10n/app_de.arb
Viewed
Original file line number 	Diff line number 	Diff line change
@@ -20,16 +20,49 @@
  "theme_light": "Hell",
  "theme_dark": "Dunkel",

  "addAnother_title": "Weiteres Element hinzufügen?",
  "addAnother_body": "Möchtest du vor dem Absenden noch einen weiteren Artikel/Charge zur Reklamation hinzufügen?",
  "addAnother_no": "Nein, weiter",
  "addAnother_yes": "Ja, weiteres hinzufügen",
  "rep_overview_open": "Offen",
  "rep_overview_all": "Alle",
  "rep_overview_rejected": "Abgelehnt",
  "rep_overview_finished": "Abgeschlossen",
  "rep_menu_open_title": "Offene Reklamationen",
  "rep_menu_open_subtitle": "Bearbeiten & Entscheiden",
  "rep_menu_all_title": "Alle Reklamationen",
  "rep_menu_all_subtitle": "Filtern & Suchen",
  "rep_menu_customers_title": "Kundendatenbank",
  "rep_menu_customers_subtitle": "Firmen & Kontakte",
  "rep_menu_account_title": "Mein Account",
  "rep_menu_account_subtitle": "Profil & Passwort",
  "rep_filter_company_label": "Firmenname filtern",
  "rep_filter_show_closed": "Abgeschlossen anzeigen",
  "rep_filter_only_rejected": "Nur abgelehnte",
  "badge_new": "NEU",
  "complaint_ticket_missing": "(ohne Ticket)",

  "addAnother_title": "Weiteres Element hinzufügen?",
  "addAnother_body": "Möchtest du vor dem Absenden noch einen weiteren Artikel/Charge zur Reklamation hinzufügen?",
  "addAnother_no": "Nein, weiter",
  "addAnother_yes": "Ja, weiteres hinzufügen",
  "rep_contact_title": "Kontakt zum Vertreter",
  "rep_contact_intro": "Sie schreiben an {firstName} {lastName}. Bitte füllen Sie die folgenden Felder aus.",
  "@rep_contact_intro": {
    "placeholders": {
      "firstName": { "type": "String" },
      "lastName": { "type": "String" }
    }
  },
  "rep_contact_company_label": "Firma",
  "rep_contact_company_email_label": "Firmen-E-Mail",
  "rep_contact_subject_label": "Betreff",
  "rep_contact_message_label": "Nachricht",

  "rep_contact_validation": "Bitte Betreff und Nachricht ausfüllen.",
  "rep_contact_no_rep_email": "Es ist keine E-Mail-Adresse für diesen Vertreter hinterlegt.",
  "rep_contact_sent": "Nachricht erfolgreich gesendet.",
  "rep_contact_error": "Fehler beim Senden der Nachricht.",

  "rep_contact_discard_title": "Änderungen verwerfen?",
  "rep_contact_discard_text": "Sie haben bereits Text eingegeben. Möchten Sie die Seite wirklich verlassen?",

  "firstName": "Vorname",
  "lastName": "Nachname",  

  "complaint_sub": "Vielen Dank, dass Sie uns helfen, unsere Qualität stetig zu verbessern.",
  "hideDetails": "Details ausblenden",
  "showDetails": "Details anzeigen",
  "rep_not_assigned": "DFS-Diamon GmbH",
@@ -287,7 +320,7 @@
  "add_images": "Bild(er) hinzufügen",
  "images_selected": "{count} Datei(en) gewählt",
  "@images_selected": { "placeholders": { "count": { "type": "int" } } },
  "images_too_large": "Max. 8MB gesamt",
  "images_too_large": "Max. Gesamtgröße für Uploads: 10 MB",
  "returned_question": "Produkte bereits zurückgeschickt?*",
  "handling": "Gewünschte Behandlung*",
  "handling_replacement": "Ersatz",
@@ -297,6 +330,14 @@
  "send_failed": "Senden fehlgeschlagen",
  "sent_ticket": "Gesendet. Ticket: {ticket}",
  "@sent_ticket": { "placeholders": { "ticket": { "type": "String" } } },
  "addAnother_title": "Weitere Reklamation hinzufügen?",
  "@addAnother_title": { "description": "Dialogtitel nach dem Absenden einer Reklamation" },
  "addAnother_body": "Möchten Sie direkt eine weitere Reklamation erfassen?",
  "@addAnother_body": { "description": "Dialogtext nach dem Absenden einer Reklamation" },
  "addAnother_no": "Nein, zum Dashboard",
  "@addAnother_no": { "description": "Dialogaktion: keine weitere Reklamation" },
  "addAnother_yes": "Ja, weitere Reklamation",
  "@addAnother_yes": { "description": "Dialogaktion: weitere Reklamation erfassen" },
  "description": "Beschreibung",

  "reportComplaint": "Reklamation melden",
57 changes: 51 additions & 6 deletions 57
flutter_web/lib/l10n/app_en.arb
Viewed
Original file line number 	Diff line number 	Diff line change
@@ -20,11 +20,48 @@
  "theme_light": "Light",
  "theme_dark": "Dark",

  "addAnother_title": "Add another item?",
  "addAnother_body": "Do you want to add another product/lot to this complaint before you submit?",
  "addAnother_no": "No, continue",
  "addAnother_yes": "Yes, add another",
  "rep_overview_open": "Open",
  "rep_overview_all": "All",
  "rep_overview_rejected": "Rejected",
  "rep_overview_finished": "Completed",
  "rep_menu_open_title": "Open Complaints",
  "rep_menu_open_subtitle": "Review & Decide",
  "rep_menu_all_title": "All Complaints",
  "rep_menu_all_subtitle": "Filter & Search",
  "rep_menu_customers_title": "Customer Database",
  "rep_menu_customers_subtitle": "Companies & Contacts",
  "rep_menu_account_title": "My Account",
  "rep_menu_account_subtitle": "Profile & Password",
  "rep_filter_company_label": "Filter by company name",
  "rep_filter_show_closed": "Show completed",
  "rep_filter_only_rejected": "Only rejected",
  "badge_new": "NEW",
  "complaint_ticket_missing": "(no ticket)",
  "rep_contact_title": "Contact representative",
  "rep_contact_intro": "You are writing to {firstName} {lastName}. Please fill out the fields below.",
  "@rep_contact_intro": {
    "placeholders": {
      "firstName": { "type": "String" },
      "lastName": { "type": "String" }
    }
  },
  "rep_contact_company_label": "Company",
  "rep_contact_company_email_label": "Company email",
  "rep_contact_subject_label": "Subject",
  "rep_contact_message_label": "Message",

  "rep_contact_validation": "Please fill in subject and message.",
  "rep_contact_no_rep_email": "No email address is available for this representative.",
  "rep_contact_sent": "Message sent successfully.",
  "rep_contact_error": "Error while sending the message.",

  "rep_contact_discard_title": "Discard changes?",
  "rep_contact_discard_text": "You have already entered text. Do you really want to leave the page?",

  "firstName": "First name",
  "lastName": "Last name",

  "complaint_sub": "Thank you for helping us continuously improve our quality.",
  "hideDetails": "Hide details",
  "showDetails": "Show details",
  "catalogs_title": "Catalogs",
@@ -269,7 +306,7 @@
  "segment_dentist": "Dentistry",
  "segment_lab": "Dental Lab",
  "product_area_label": "Product category",
  "product_area_medical": "Medical product",
  "product_area_medical": "Medical device",
  "product_area_lab": "Lab product",
  "article": "Article number*",
  "articleNo": "Article",
@@ -288,7 +325,7 @@
  "add_images": "Add image(s)",
  "images_selected": "{count} file(s) selected",
  "@images_selected": { "placeholders": { "count": { "type": "int" } } },
  "images_too_large": "Max. 8MB total",
  "images_too_large": "Max. total upload size: 10 MB",
  "returned_question": "Products already returned?*",
  "handling": "Requested handling*",
  "handling_replacement": "Replacement",
@@ -298,6 +335,14 @@
  "send_failed": "Sending failed",
  "sent_ticket": "Sent. Ticket: {ticket}",
  "@sent_ticket": { "placeholders": { "ticket": { "type": "String" } } },
  "addAnother_title": "Add another complaint?",
  "@addAnother_title": { "description": "Dialog title shown after submitting a complaint" },
  "addAnother_body": "Would you like to submit another complaint right away?",
  "@addAnother_body": { "description": "Dialog body shown after submitting a complaint" },
  "addAnother_no": "No, go to dashboard",
  "@addAnother_no": { "description": "Dialog action: do not add another complaint" },
  "addAnother_yes": "Yes, add another",
  "@addAnother_yes": { "description": "Dialog action: add another complaint" },
  "description": "Description",

  "reportComplaint": "Report complaint",
57 changes: 51 additions & 6 deletions 57
flutter_web/lib/l10n/app_es.arb
Viewed
Original file line number 	Diff line number 	Diff line change
@@ -20,11 +20,48 @@
  "theme_light": "Claro",
  "theme_dark": "Oscuro",

  "addAnother_title": "¿Añadir otro elemento?",
  "addAnother_body": "¿Quieres añadir otro producto/lote a esta reclamación antes de enviar?",
  "addAnother_no": "No, continuar",
  "addAnother_yes": "Sí, añadir",
  "rep_overview_open": "Abiertas",
  "rep_overview_all": "Todas",
  "rep_overview_rejected": "Rechazadas",
  "rep_overview_finished": "Finalizadas",
  "rep_menu_open_title": "Reclamaciones abiertas",
  "rep_menu_open_subtitle": "Revisar y decidir",
  "rep_menu_all_title": "Todas las reclamaciones",
  "rep_menu_all_subtitle": "Filtrar y buscar",
  "rep_menu_customers_title": "Base de datos de clientes",
  "rep_menu_customers_subtitle": "Empresas y contactos",
  "rep_menu_account_title": "Mi cuenta",
  "rep_menu_account_subtitle": "Perfil y contraseña",
  "rep_filter_company_label": "Filtrar por empresa",
  "rep_filter_show_closed": "Mostrar finalizadas",
  "rep_filter_only_rejected": "Solo rechazadas",
  "badge_new": "NUEVO",
  "complaint_ticket_missing": "(sin número de ticket)",
  "rep_contact_title": "Contactar al representante",
  "rep_contact_intro": "Está escribiendo a {firstName} {lastName}. Por favor complete los campos siguientes.",
  "@rep_contact_intro": {
    "placeholders": {
      "firstName": { "type": "String" },
      "lastName": { "type": "String" }
    }
  },
  "rep_contact_company_label": "Empresa",
  "rep_contact_company_email_label": "Correo de la empresa",
  "rep_contact_subject_label": "Asunto",
  "rep_contact_message_label": "Mensaje",

  "rep_contact_validation": "Por favor, rellene el asunto y el mensaje.",
  "rep_contact_no_rep_email": "No hay ninguna dirección de correo disponible para este representante.",
  "rep_contact_sent": "Mensaje enviado correctamente.",
  "rep_contact_error": "Error al enviar el mensaje.",

  "rep_contact_discard_title": "¿Descartar los cambios?",
  "rep_contact_discard_text": "Ya ha introducido texto. ¿Realmente desea salir de la página?",

  "firstName": "Nombre",
  "lastName": "Apellido",

  "complaint_sub": "Gracias por ayudarnos a mejorar continuamente nuestra calidad.",
  "hideDetails": "Ocultar detalles",
  "showDetails": "Mostrar detalles",
  "catalogs_title": "Catálogos",
@@ -265,7 +302,7 @@
  "segment_dentist": "Odontología",
  "segment_lab": "Laboratorio dental",
  "product_area_label": "Área del producto",
  "product_area_medical": "Producto médico",
  "product_area_medical": "Producto sanitario",
  "product_area_lab": "Producto de laboratorio",
  "article": "N.º de artículo*",
  "articleNo": "Artículo",
@@ -284,7 +321,7 @@
  "add_images": "Añadir imagen(es)",
  "images_selected": "{count} archivo(s) seleccionado(s)",
  "@images_selected": { "placeholders": { "count": { "type": "int" } } },
  "images_too_large": "Máx. 8 MB en total",
  "images_too_large": "Tamaño total máximo de subida: 10 MB",
  "returned_question": "¿Productos ya devueltos?*",
  "handling": "Tratamiento solicitado*",
  "handling_replacement": "Reemplazo",
@@ -294,6 +331,14 @@
  "send_failed": "Error al enviar",
  "sent_ticket": "Enviado. Ticket: {ticket}",
  "@sent_ticket": { "placeholders": { "ticket": { "type": "String" } } },
  "addAnother_title": "¿Agregar otra reclamación?",
  "@addAnother_title": { "description": "Título del diálogo después de enviar una reclamación" },
  "addAnother_body": "¿Desea enviar otra reclamación ahora?",
  "@addAnother_body": { "description": "Texto del diálogo después de enviar una reclamación" },
  "addAnother_no": "No, ir al panel",
  "@addAnother_no": { "description": "Acción del diálogo: no agregar otra reclamación" },
  "addAnother_yes": "Sí, agregar otra",
  "@addAnother_yes": { "description": "Acción del diálogo: agregar otra reclamación" },
  "description": "Descripción",

  "reportComplaint": "Reportar reclamación",
57 changes: 51 additions & 6 deletions 57
flutter_web/lib/l10n/app_fr.arb
Viewed
Original file line number 	Diff line number 	Diff line change
@@ -20,11 +20,48 @@
  "theme_light": "Clair",
  "theme_dark": "Sombre",

  "addAnother_title": "Ajouter un autre élément ?",
  "addAnother_body": "Souhaitez-vous ajouter un autre produit/lot à cette réclamation avant l’envoi ?",
  "addAnother_no": "Non, continuer",
  "addAnother_yes": "Oui, ajouter",
  "rep_overview_open": "Ouvertes",
  "rep_overview_all": "Toutes",
  "rep_overview_rejected": "Rejetées",
  "rep_overview_finished": "Terminées",
  "rep_menu_open_title": "Réclamations ouvertes",
  "rep_menu_open_subtitle": "Examiner et décider",
  "rep_menu_all_title": "Toutes les réclamations",
  "rep_menu_all_subtitle": "Filtrer et rechercher",
  "rep_menu_customers_title": "Base clients",
  "rep_menu_customers_subtitle": "Sociétés et contacts",
  "rep_menu_account_title": "Mon compte",
  "rep_menu_account_subtitle": "Profil et mot de passe",
  "rep_filter_company_label": "Filtrer par société",
  "rep_filter_show_closed": "Afficher les terminées",
  "rep_filter_only_rejected": "Uniquement rejetées",
  "badge_new": "NOUVEAU",
  "complaint_ticket_missing": "(sans numéro de ticket)",
  "rep_contact_title": "Contacter le représentant",
  "rep_contact_intro": "Vous écrivez à {firstName} {lastName}. Veuillez remplir les champs ci-dessous.",
  "@rep_contact_intro": {
    "placeholders": {
      "firstName": { "type": "String" },
      "lastName": { "type": "String" }
    }
  },
  "rep_contact_company_label": "Entreprise",
  "rep_contact_company_email_label": "E-mail de l'entreprise",
  "rep_contact_subject_label": "Objet",
  "rep_contact_message_label": "Message",

  "rep_contact_validation": "Veuillez renseigner l'objet et le message.",
  "rep_contact_no_rep_email": "Aucune adresse e-mail n'est disponible pour ce représentant.",
  "rep_contact_sent": "Message envoyé avec succès.",
  "rep_contact_error": "Erreur lors de l'envoi du message.",

  "rep_contact_discard_title": "Annuler les modifications ?",
  "rep_contact_discard_text": "Vous avez déjà saisi du texte. Voulez-vous vraiment quitter la page ?",

  "firstName": "Prénom",
  "lastName": "Nom",

  "complaint_sub": "Merci de nous aider à améliorer continuellement notre qualité.",
  "hideDetails": "Masquer les détails",
  "showDetails": "Afficher les détails",
  "catalogs_title": "Catalogues",
@@ -266,7 +303,7 @@
  "segment_dentist": "Dentisterie",
  "segment_lab": "Laboratoire dentaire",
  "product_area_label": "Domaine du produit",
  "product_area_medical": "Produit médical",
  "product_area_medical": "Dispositif médical",
  "product_area_lab": "Produit de laboratoire",
  "article": "Numéro d’article*",
  "articleNo": "Article",
@@ -285,7 +322,7 @@
  "add_images": "Ajouter une ou plusieurs images",
  "images_selected": "{count} fichier(s) sélectionné(s)",
  "@images_selected": { "placeholders": { "count": { "type": "int" } } },
  "images_too_large": "Max. 8 Mo au total",
  "images_too_large": "Taille totale maximale des fichiers: 10 Mo",
  "returned_question": "Produits déjà retournés ?*",
  "handling": "Traitement souhaité*",
  "handling_replacement": "Remplacement",
@@ -295,6 +332,14 @@
  "send_failed": "Échec de l’envoi",
  "sent_ticket": "Envoyé. Ticket : {ticket}",
  "@sent_ticket": { "placeholders": { "ticket": { "type": "String" } } },
  "addAnother_title": "Ajouter une autre réclamation ?",
  "@addAnother_title": { "description": "Titre de la boîte de dialogue après l'envoi d'une réclamation" },
  "addAnother_body": "Souhaitez-vous saisir une autre réclamation maintenant ?",
  "@addAnother_body": { "description": "Texte de la boîte de dialogue après l'envoi d'une réclamation" },
  "addAnother_no": "Non, aller au tableau de bord",
  "@addAnother_no": { "description": "Action de dialogue : ne pas ajouter d'autre réclamation" },
  "addAnother_yes": "Oui, en ajouter une autre",
  "@addAnother_yes": { "description": "Action de dialogue : ajouter une autre réclamation" },
  "description": "Description",

  "reportComplaint": "Déclarer une réclamation",
55 changes: 50 additions & 5 deletions 55
flutter_web/lib/l10n/app_it.arb
Viewed
Original file line number 	Diff line number 	Diff line change
@@ -20,11 +20,48 @@
  "theme_light": "Chiaro",
  "theme_dark": "Scuro",

  "addAnother_title": "Aggiungere un altro elemento?",
  "addAnother_body": "Vuoi aggiungere un altro prodotto/lotto a questo reclamo prima dell’invio?",
  "addAnother_no": "No, continua",
  "addAnother_yes": "Sì, aggiungi",
  "rep_overview_open": "Aperte",
  "rep_overview_all": "Tutte",
  "rep_overview_rejected": "Rifiutate",
  "rep_overview_finished": "Completate",
  "rep_menu_open_title": "Reclami aperti",
  "rep_menu_open_subtitle": "Esaminare e decidere",
  "rep_menu_all_title": "Tutti i reclami",
  "rep_menu_all_subtitle": "Filtra e cerca",
  "rep_menu_customers_title": "Database clienti",
  "rep_menu_customers_subtitle": "Aziende e contatti",
  "rep_menu_account_title": "Il mio account",
  "rep_menu_account_subtitle": "Profilo e password",
  "rep_filter_company_label": "Filtra per azienda",
  "rep_filter_show_closed": "Mostra completati",
  "rep_filter_only_rejected": "Solo rifiutati",
  "badge_new": "NUOVO",
  "complaint_ticket_missing": "(senza ticket)",
  "rep_contact_title": "Contatta il rappresentante",
  "rep_contact_intro": "Stai scrivendo a {firstName} {lastName}. Compila i campi sottostanti.",
  "@rep_contact_intro": {
    "placeholders": {
      "firstName": { "type": "String" },
      "lastName": { "type": "String" }
    }
  },
  "rep_contact_company_label": "Azienda",
  "rep_contact_company_email_label": "E-mail aziendale",
  "rep_contact_subject_label": "Oggetto",
  "rep_contact_message_label": "Messaggio",

  "rep_contact_validation": "Compila oggetto e messaggio.",
  "rep_contact_no_rep_email": "Non è disponibile un indirizzo e-mail per questo rappresentante.",
  "rep_contact_sent": "Messaggio inviato con successo.",
  "rep_contact_error": "Errore durante l'invio del messaggio.",

  "rep_contact_discard_title": "Scartare le modifiche?",
  "rep_contact_discard_text": "Hai già inserito del testo. Vuoi davvero lasciare la pagina?",

  "firstName": "Nome",
  "lastName": "Cognome",

  "complaint_sub": "Grazie per aiutarci a migliorare continuamente la nostra qualità.",
  "hideDetails": "Nascondi dettagli",
  "showDetails": "Mostra dettagli",
  "catalogs_title": "Cataloghi",
@@ -285,7 +322,7 @@
  "add_images": "Aggiungi immagine/i",
  "images_selected": "{count} file selezionato/i",
  "@images_selected": { "placeholders": { "count": { "type": "int" } } },
  "images_too_large": "Max. 8 MB totali",
  "images_too_large": "Dimensione totale massima di upload: 10 MB",
  "returned_question": "Prodotti già restituiti?*",
  "handling": "Trattamento richiesto*",
  "handling_replacement": "Sostituzione",
@@ -295,6 +332,14 @@
  "send_failed": "Invio non riuscito",
  "sent_ticket": "Inviato. Ticket: {ticket}",
  "@sent_ticket": { "placeholders": { "ticket": { "type": "String" } } },
  "addAnother_title": "Aggiungere un'altra segnalazione?",
  "@addAnother_title": { "description": "Titolo della finestra di dialogo dopo l'invio di una segnalazione" },
  "addAnother_body": "Desideri inviare subito un'altra segnalazione?",
  "@addAnother_body": { "description": "Testo della finestra di dialogo dopo l'invio di una segnalazione" },
  "addAnother_no": "No, vai alla dashboard",
  "@addAnother_no": { "description": "Azione del dialogo: non aggiungere un'altra segnalazione" },
  "addAnother_yes": "Sì, aggiungi un'altra",
  "@addAnother_yes": { "description": "Azione del dialogo: aggiungere un'altra segnalazione" },
  "description": "Descrizione",

  "reportComplaint": "Segnala reclamo",
720 changes: 525 additions & 195 deletions 720
flutter_web/lib/main.dart
Viewed

Large diffs are not rendered by default.
11 changes: 7 additions & 4 deletions 11
flutter_web/lib/pages/account_page.dart
Viewed
Original file line number 	Diff line number 	Diff line change
@@ -2,6 +2,7 @@
import 'package:flutter/material.dart';
import '../api/client.dart';
import '../l10n/app_localizations.dart';
import '../widgets/dialog_content_scroll.dart';
import '../widgets/legal_footer.dart';

extension _L10nX on BuildContext {
@@ -104,7 +105,7 @@ class _AccountPageState extends State<AccountPage> {
                    context: context,
                    builder: (_) => AlertDialog(
                      title: Text(t.accountDeleteTitle),
                      content: Text(t.accountDeleteConfirm),
                      content: DialogContentScroll(child: Text(t.accountDeleteConfirm)),
                      actions: [
                        TextButton(
                          onPressed: () => Navigator.pop(context, false),
@@ -127,9 +128,11 @@ class _AccountPageState extends State<AccountPage> {
                      return AlertDialog(
                        // FIX: Key existierte nicht -> kompatibler Key + Fallback
                        title: Text(t.confirmPassword ?? 'Passwort bestätigen'),
                        content: TextField(
                          controller: ctrl, obscureText: true,
                          decoration: InputDecoration(labelText: t.gate_password),
                        content: DialogContentScroll(
                          child: TextField(
                            controller: ctrl, obscureText: true,
                            decoration: InputDecoration(labelText: t.gate_password),
                          ),
                        ),
                        actions: [
                          TextButton(
2,973 changes: 1,761 additions & 1,212 deletions 2,973
flutter_web/lib/pages/admin_page.dart
Viewed

Large diffs are not rendered by default.
1 change: 1 addition & 0 deletions 1
flutter_web/lib/pages/auth_page.dart
Viewed
Original file line number 	Diff line number 	Diff line change
@@ -1,4 +1,5 @@
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'dart:html' as html;
import '../api/client.dart';
import '../l10n/app_localizations.dart';
658 changes: 364 additions & 294 deletions 658
flutter_web/lib/pages/complaint_form_page.dart
Viewed

Large diffs are not rendered by default.
403 changes: 342 additions & 61 deletions 403
flutter_web/lib/pages/customer_home.dart
Viewed

Large diffs are not rendered by default.
1,127 changes: 626 additions & 501 deletions 1,127
flutter_web/lib/pages/dashboard_page.dart
Viewed

Large diffs are not rendered by default.
16 changes: 10 additions & 6 deletions 16
flutter_web/lib/pages/gate_page.dart
Viewed
Original file line number 	Diff line number 	Diff line change
@@ -1,9 +1,11 @@
// lib/pages/gate_page.dart
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'dart:html' as html;

import '../api/client.dart';
import '../l10n/app_localizations.dart';
import '../widgets/dialog_content_scroll.dart';

class GatePage extends StatefulWidget {
  final ApiClient api;
@@ -28,12 +30,14 @@ class _GatePageState extends State<GatePage> {
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Admin-Secret'),
        content: TextField(
          controller: secretCtrl,
          obscureText: true,
          decoration: const InputDecoration(
            labelText: 'X-Admin-Secret',
            border: OutlineInputBorder(),
        content: DialogContentScroll(
          child: TextField(
            controller: secretCtrl,
            obscureText: true,
            decoration: const InputDecoration(
              labelText: 'X-Admin-Secret',
              border: OutlineInputBorder(),
            ),
          ),
        ),
        actions: [
1 change: 1 addition & 0 deletions 1
flutter_web/lib/pages/legal_privacy_page.dart
Viewed
Original file line number 	Diff line number 	Diff line change
@@ -1,5 +1,6 @@
import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'dart:html' as html;
import '../l10n/app_localizations.dart';

396 changes: 306 additions & 90 deletions 396
flutter_web/lib/pages/login_page.dart
Viewed

Large diffs are not rendered by default.
25 changes: 18 additions & 7 deletions 25
flutter_web/lib/pages/my_complaints_page.dart
Viewed
Original file line number 	Diff line number 	Diff line change
@@ -1,6 +1,7 @@
// lib/pages/my_complaints_page.dart
import 'dart:async';
import 'dart:html' as html; // nur Web – für Link-Öffnen & mailto
import 'package:flutter/foundation.dart' show kIsWeb;
import 'dart:html' as html;
import 'package:flutter/material.dart';
import '../api/client.dart';
import '../models/complaint.dart';
@@ -244,10 +245,6 @@ class _MyComplaintsPageState extends State<MyComplaintsPage> {
                          Text(t.rep_banner_title(repName.isEmpty ? '—' : repName),
                              style: const TextStyle(fontWeight: FontWeight.w600)),
                          const SizedBox(height: 2),
                          Text([
                            if (repEmail.isNotEmpty) repEmail,
                            if (repRegion.isNotEmpty) repRegion,
                          ].join(' • ')),
                        ],
                      ),
                    ),
@@ -461,7 +458,14 @@ class _MyComplaintsPageState extends State<MyComplaintsPage> {
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(width: 180, child: Text(label, style: const TextStyle(fontWeight: FontWeight.w600))),
          Flexible(
            flex: 0,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 180),
              child: Text(label, style: const TextStyle(fontWeight: FontWeight.w600)),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(child: Text(value.isEmpty ? '—' : value)),
        ],
      ),
@@ -531,7 +535,14 @@ class _MyComplaintDetailsDialog extends StatelessWidget {
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(width: 170, child: Text(l, style: const TextStyle(fontWeight: FontWeight.w600))),
              Flexible(
                flex: 0,
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 170),
                  child: Text(l, style: const TextStyle(fontWeight: FontWeight.w600)),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(child: Text(v.isEmpty ? '—' : v)),
            ],
          ),
2,473 changes: 1,846 additions & 627 deletions 2,473
flutter_web/lib/pages/rep_dashboard_page.dart
Viewed

Large diffs are not rendered by default.
118 changes: 66 additions & 52 deletions 118
flutter_web/lib/pages/rep_login_page.dart
Viewed
Original file line number 	Diff line number 	Diff line change
@@ -3,7 +3,9 @@ import 'package:flutter/material.dart';
import '../api/client.dart';
import 'rep_dashboard_page.dart';
import '../l10n/app_localizations.dart';
import '../widgets/dialog_content_scroll.dart';
import '../widgets/legal_footer.dart';
import '../services/push_notifications.dart';

// L10n-Helper
extension _L10nX on BuildContext {
@@ -29,7 +31,15 @@ class _RepLoginPageState extends State<RepLoginPage> {
  void _setBusy(bool b) => setState(() => _busy = b);

  // --- Navigation ins Dashboard (ohne dfs_mode) ---
  void _goRepDashboard() {
  Future<void> _goRepDashboard() async {
    if (!mounted) return;
    final locale = Localizations.localeOf(context);
    try {
      await PushNotifications.instance
          .setup(widget.api, languageCode: locale.languageCode);
    } catch (e) {
      debugPrint('[push] rep setup failed: $e');
    }
    if (!mounted) return;
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => RepDashboardPage(api: widget.api)),
@@ -66,7 +76,7 @@ class _RepLoginPageState extends State<RepLoginPage> {
        await _openChangePwDialog();
        return;
      }
      _goRepDashboard();
      await _goRepDashboard();
    } catch (e) {
      _setErr(t.login_failed_with_error('$e')); // NEU (parametrisierter Key)
    } finally {
@@ -89,31 +99,33 @@ class _RepLoginPageState extends State<RepLoginPage> {
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setS) => AlertDialog(
          title: Text(t.register_temp_password_title), // NEU
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: mailCtrl,
                keyboardType: TextInputType.emailAddress,
                decoration: InputDecoration(
                  labelText: t.rep_email_label, // NEU
                  border: const OutlineInputBorder(),
          content: DialogContentScroll(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: mailCtrl,
                  keyboardType: TextInputType.emailAddress,
                  decoration: InputDecoration(
                    labelText: t.rep_email_label, // NEU
                    border: const OutlineInputBorder(),
                  ),
                ),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: secCtrl,
                obscureText: true,
                decoration: InputDecoration(
                  labelText: t.temp_password_label, // NEU
                  border: const OutlineInputBorder(),
                const SizedBox(height: 10),
                TextField(
                  controller: secCtrl,
                  obscureText: true,
                  decoration: InputDecoration(
                    labelText: t.temp_password_label, // NEU
                    border: const OutlineInputBorder(),
                  ),
                ),
              ),
              if (locErr != null) ...[
                const SizedBox(height: 8),
                Text(locErr!, style: const TextStyle(color: Colors.red)),
                if (locErr != null) ...[
                  const SizedBox(height: 8),
                  Text(locErr!, style: const TextStyle(color: Colors.red)),
                ],
              ],
            ],
            ),
          ),
          actions: [
            TextButton(
@@ -184,36 +196,38 @@ class _RepLoginPageState extends State<RepLoginPage> {
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setS) => AlertDialog(
          title: Text(t.new_password_title), // NEU
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: aCtrl,
                obscureText: true,
                decoration: InputDecoration(
                  labelText: t.new_password_min8, // NEU
                  border: const OutlineInputBorder(),
          content: DialogContentScroll(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: aCtrl,
                  obscureText: true,
                  decoration: InputDecoration(
                    labelText: t.new_password_min8, // NEU
                    border: const OutlineInputBorder(),
                  ),
                ),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: bCtrl,
                obscureText: true,
                decoration: InputDecoration(
                  labelText: t.new_password_repeat_label, // NEU
                  border: const OutlineInputBorder(),
                const SizedBox(height: 10),
                TextField(
                  controller: bCtrl,
                  obscureText: true,
                  decoration: InputDecoration(
                    labelText: t.new_password_repeat_label, // NEU
                    border: const OutlineInputBorder(),
                  ),
                  onSubmitted: (_) async {
                    if (!saving) {
                      await _submitChangePw(ctx, setS, aCtrl, bCtrl, (s) => locErr = s, () => saving = true);
                    }
                  },
                ),
                onSubmitted: (_) async {
                  if (!saving) {
                    await _submitChangePw(ctx, setS, aCtrl, bCtrl, (s) => locErr = s, () => saving = true);
                  }
                },
              ),
              if (locErr != null) ...[
                const SizedBox(height: 8),
                Text(locErr!, style: const TextStyle(color: Colors.red)),
                if (locErr != null) ...[
                  const SizedBox(height: 8),
                  Text(locErr!, style: const TextStyle(color: Colors.red)),
                ],
              ],
            ],
            ),
          ),
          actions: [
            TextButton(
@@ -240,7 +254,7 @@ class _RepLoginPageState extends State<RepLoginPage> {
    bCtrl.dispose();

    if (ok == true) {
      _goRepDashboard();
      await _goRepDashboard();
    }
  }

2 changes: 1 addition & 1 deletion 2
flutter_web/lib/pages/support_page.dart
Viewed
Original file line number 	Diff line number 	Diff line change
@@ -2,6 +2,7 @@
import 'package:flutter/material.dart';
import '../api/client.dart';
import '../l10n/app_localizations.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'dart:html' as html;
import '../widgets/legal_footer.dart';

@@ -55,7 +56,6 @@ class _SupportPageState extends State<SupportPage> {
  String _mapCategoryForApi(String code) {
    switch (code) {
      case 'improve':   // Vorschlag zur Verbesserung
        return 'feature';     // <- häufig akzeptiert
      case 'feedback':        // allgemeines Feedback
        return 'other';       // fallback
      case 'general':
22 changes: 22 additions & 0 deletions 22
flutter_web/lib/services/push_notifications.dart
Viewed
Original file line number 	Diff line number 	Diff line change
@@ -0,0 +1,22 @@
// lib/services/push_notifications.dart (web stub)
import 'dart:async';
import 'package:flutter/foundation.dart';
import '../api/client.dart';

@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(dynamic message) async {
  debugPrint('[push:web] background handler invoked (ignored).');
}

class PushNotifications {
  PushNotifications._();
  static final PushNotifications instance = PushNotifications._();

  Future<void> setup(ApiClient api, {String? languageCode}) async {
    debugPrint('[push:web] setup skipped.');
  }

  Future<void> deactivate(ApiClient api) async {
    debugPrint('[push:web] deactivate skipped.');
  }
}
34 changes: 34 additions & 0 deletions 34
flutter_web/lib/widgets/dialog_content_scroll.dart
Viewed
Original file line number 	Diff line number 	Diff line change
@@ -0,0 +1,34 @@
import 'package:flutter/material.dart';

/// Helper widget to avoid overflow errors inside [AlertDialog]s by
/// constraining the dialog body and making it scrollable when needed.
class DialogContentScroll extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry? padding;

  const DialogContentScroll({super.key, required this.child, this.padding});

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.maybeOf(context);
    final maxHeight = media?.size.height ?? 0;
    final resolvedChild = padding == null
        ? child
        : Padding(
            padding: padding!,
            child: child,
          );

    // Keep enough headroom for dialog actions while preventing the typical
    // "BOTTOM OVERFLOWED" errors on compact devices or with long contents.
    return ConstrainedBox(
      constraints: BoxConstraints(
        maxHeight: maxHeight > 0 ? maxHeight * 0.75 : 400,
      ),
      child: SingleChildScrollView(
        physics: const BouncingScrollPhysics(),
        child: resolvedChild,
      ),
    );
  }
}
16 changes: 10 additions & 6 deletions 16
flutter_web/lib/widgets/lang_action.dart
Viewed
Original file line number 	Diff line number 	Diff line change
@@ -56,9 +56,11 @@ class LangAction extends StatelessWidget {
                children: [
                  CountryFlag.fromCountryCode(
                    flagCode,
                    height: 16,
                    width: 24,
                    borderRadius: 2,
                    theme: const ImageTheme(
                      width: 24,
                      height: 16,
                      shape: RoundedRectangle(2), // Eckenradius in px
                    ),
                  ),
                  if (!flagsOnly) ...[
                    const SizedBox(width: 10),
@@ -80,9 +82,11 @@ class LangAction extends StatelessWidget {
          padding: const EdgeInsets.symmetric(horizontal: 6),
          child: CountryFlag.fromCountryCode(
            currentFlag,
            height: 18,
            width: 26,
            borderRadius: 3,
            theme: const ImageTheme(
              width: 26,
              height: 18,
              shape: RoundedRectangle(3),
            ),
          ),
        ),
      ),
9 changes: 8 additions & 1 deletion 9
flutter_web/lib/widgets/legal_footer.dart
Viewed
Original file line number 	Diff line number 	Diff line change
@@ -72,7 +72,14 @@ class LegalFooter extends StatelessWidget {
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        children: [
          SizedBox(width: 110, child: Text('$k:', style: const TextStyle(fontWeight: FontWeight.w600))),
          Flexible(
            flex: 0,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 110),
              child: Text('$k:', style: const TextStyle(fontWeight: FontWeight.w600)),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(child: Text(v)),
        ],
      ),
2 changes: 2 additions & 0 deletions 2
flutter_web/lib/widgets/logout_action.dart
Viewed
Original file line number 	Diff line number 	Diff line change
@@ -2,6 +2,7 @@
import 'package:flutter/material.dart';
import '../api/client.dart';
import '../l10n/app_localizations.dart';
import '../services/push_notifications.dart';

class LogoutAction extends StatelessWidget {
  final ApiClient api;
@@ -30,6 +31,7 @@ class LogoutAction extends StatelessWidget {
    return PopupMenuButton<String>(
      onSelected: (value) async {
        if (value == 'logout' && await _confirm(context)) {
          await PushNotifications.instance.deactivate(api);
          await api.logout();
          onLoggedOut?.call();
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(t.loggedOut)));
2 changes: 2 additions & 0 deletions 2
flutter_web/lib/widgets/logout_button.dart
Viewed
Original file line number 	Diff line number 	Diff line change
@@ -2,6 +2,7 @@
import 'package:flutter/material.dart';
import '../api/client.dart';
import '../l10n/app_localizations.dart';
import '../services/push_notifications.dart';

class LogoutButton extends StatelessWidget implements PreferredSizeWidget {
  final ApiClient api;
@@ -28,6 +29,7 @@ class LogoutButton extends StatelessWidget implements PreferredSizeWidget {
          icon: const Icon(Icons.logout),
          label: Text(t.logout),
          onPressed: () async {
            await PushNotifications.instance.deactivate(api);
            await api.logout();
            if (context.mounted) {
              ScaffoldMessenger.of(context)
69 changes: 69 additions & 0 deletions 69
flutter_web/lib/widgets/pdf_view_stub.dart
Viewed
Original file line number 	Diff line number 	Diff line change
@@ -0,0 +1,69 @@
// lib/widgets/pdf_view_stub.dart
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../l10n/app_localizations.dart';

/// Stub für Nicht-Web: öffnet die PDF extern und zeigt einen Hinweis.
class PdfInAppPage extends StatelessWidget {
  final String url;
  final String title;
  const PdfInAppPage({super.key, required this.url, required this.title});

  Future<void> _openExternal(BuildContext context) async {
    final t = AppLocalizations.of(context)!;
    final uri = Uri.tryParse(url);
    if (uri == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(t.catalog_open_error)),
      );
      return;
    }

    final success = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!success) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(t.catalog_open_error)),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context)!;
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(title: Text(title, overflow: TextOverflow.ellipsis)),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.picture_as_pdf_outlined, size: 48),
              const SizedBox(height: 12),
              Text(
                t.catalog_viewer_unavailable,
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyMedium,
              ),
              const SizedBox(height: 16),
              FilledButton.icon(
                onPressed: () => _openExternal(context),
                icon: const Icon(Icons.open_in_new),
                label: Text(t.catalog_open_external),
              ),
              const SizedBox(height: 12),
              SelectableText(
                url,
                textAlign: TextAlign.center,
                style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
54 changes: 54 additions & 0 deletions 54
flutter_web/lib/widgets/pdf_view_web.dart
Viewed
Original file line number 	Diff line number 	Diff line change
@@ -0,0 +1,54 @@
// lib/widgets/pdf_view_web.dart
import 'dart:html' as html;
import 'dart:ui' as ui show platformViewRegistry;
import 'package:flutter/material.dart';

class PdfInAppPage extends StatefulWidget {
  final String url;
  final String title;
  const PdfInAppPage({super.key, required this.url, required this.title});

  @override
  State<PdfInAppPage> createState() => _PdfInAppPageState();
}

class _PdfInAppPageState extends State<PdfInAppPage> {
  late final String _viewType;

  @override
  void initState() {
    super.initState();

    // 1) PDF-URL relativ zum aktuellen Base-Pfad auflösen
    final pdfUrl = Uri.base.resolve(widget.url).toString();

    // 2) Lokalen pdf.js-Viewer RELATIV aufrufen (kein führender Slash!)
    final viewerPath = 'pdfjs/web/viewer.html'
        '?file=${Uri.encodeComponent(pdfUrl)}#zoom=page-width&pagemode=none';

    // 3) Auch den Viewer relativ auflösen (deckt Unterpfade ab)
    final viewerUrl = Uri.base.resolve(viewerPath).toString();

    _viewType = 'pdfjs-${DateTime.now().millisecondsSinceEpoch}';

    // ignore: undefined_prefixed_name
    ui.platformViewRegistry.registerViewFactory(_viewType, (int viewId) {
      final frame = html.IFrameElement()
        ..src = viewerUrl
        ..style.border = '0'
        ..style.width = '100%'
        ..style.height = '100%';
      return frame;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(widget.title, overflow: TextOverflow.ellipsis)),
      body: SizedBox.expand(
        child: HtmlElementView(viewType: _viewType),
      ),
    );
  }
}
1 change: 1 addition & 0 deletions 1
flutter_web/lib/widgets/privacy_consent.dart
Viewed
Original file line number 	Diff line number 	Diff line change
@@ -1,5 +1,6 @@
// lib/widgets/privacy_consent.dart
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'dart:html' as html;
import '../constants.dart';

1 change: 1 addition & 0 deletions 1
flutter_web/pubspec.yaml
Viewed
Original file line number 	Diff line number 	Diff line change
@@ -16,6 +16,7 @@ dependencies:
  provider: ^6.1.2
  file_picker: ^10.3.3
  country_flags: ^2.2.0
  shared_preferences: ^2.3.2

flutter:
  uses-material-design: true
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

dfs-complaints/flutter_web/lib/api/client.dart at 80c1ea79006cb79422d3f10bb79aba198b05a8c5 · tbauer-oss/dfs-complaints
