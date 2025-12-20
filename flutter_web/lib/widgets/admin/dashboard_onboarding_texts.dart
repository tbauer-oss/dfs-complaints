class DashboardOnboardingText {
  final String title;
  final String body;

  const DashboardOnboardingText({
    required this.title,
    required this.body,
  });
}

class DashboardOnboardingTexts {
  static const Map<String, DashboardOnboardingText> _entries = {
    'open': DashboardOnboardingText(
      title: 'Offene Reklamationen',
      body:
          'Hier sehen Sie alle noch ungeklärten Fälle, die eine Entscheidung oder Maßnahme brauchen. Nutzen Sie diese Kachel für die tägliche Priorisierung und Bearbeitung. Ergebnis ist ein aktualisierter Status inklusive Entscheidungen und nächsten Schritten.',
    ),
    'all': DashboardOnboardingText(
      title: 'Alle Reklamationen',
      body:
          'Diese Übersicht bündelt alle Tickets – inklusive abgeschlossener Vorgänge. Ideal für Recherchen, Audits und historische Vergleiche. Das Ergebnis ist eine vollständige Trefferliste mit Filter- und Suchoptionen.',
    ),
    'complaintList': DashboardOnboardingText(
      title: 'Reklamationsliste',
      body:
          'Die tabellarische Gesamtübersicht ist für Auswertungen und Exporte gedacht. Nutzen Sie sie, wenn Sie Listen für Reporting oder Weitergabe benötigen. Ergebnis ist eine exportfähige Übersicht aller relevanten Reklamationen.',
    ),
    'capaReports': DashboardOnboardingText(
      title: 'CAPA / 8D-Reports',
      body:
          'Hier steuern Sie Korrektur- und Vorbeugemaßnahmen zu Reklamationen. Verwenden Sie die Kachel, wenn eine formalisierte Ursachenanalyse nötig ist. Ergebnis ist ein dokumentierter Maßnahmenplan mit Nachweisen.',
    ),
    'capaDashboard': DashboardOnboardingText(
      title: 'CAPA-Dashboard',
      body:
          'Das Dashboard zeigt offene CAPAs, Fälligkeiten und kritische Bereiche auf einen Blick. Nutzen Sie es zur täglichen Steuerung und Eskalation. Ergebnis ist ein klarer Überblick über Prioritäten und Risiken.',
    ),
    'fmea': DashboardOnboardingText(
      title: 'FMEA',
      body:
          'In der FMEA bewerten Sie Risiken strukturiert nach MDR/TD. Nutzen Sie diese Kachel bei neuen Produkt- oder Prozessrisiken. Ergebnis ist eine nachvollziehbare Risikobewertung inklusive Maßnahmen.',
    ),
    'prrc': DashboardOnboardingText(
      title: 'PRRC-Einstufungen',
      body:
          'Hier erfolgt die regulatorische Bewertung von Reklamationen durch die PRRC. Nutzen Sie die Funktion, wenn eine formale Einstufung erforderlich ist. Ergebnis ist eine dokumentierte PRRC-Entscheidung pro Fall.',
    ),
    'stats': DashboardOnboardingText(
      title: 'Statistik & KPIs',
      body:
          'Diese Kachel führt zu Kennzahlen und Trendanalysen. Sie unterstützt Management-Reviews und Monatsberichte. Ergebnis sind visuelle KPIs zur Entscheidungsunterstützung.',
    ),
    'pending': DashboardOnboardingText(
      title: 'Anträge / Pending',
      body:
          'Hier prüfen Sie neue Registrierungen und Anträge. Nutzen Sie die Kachel, wenn neue Nutzer auf Freigabe warten. Ergebnis ist eine geprüfte Freigabe oder Ablehnung mit sauberer Dokumentation.',
    ),
    'users': DashboardOnboardingText(
      title: 'Kundendatenbank',
      body:
          'Die Kundendatenbank bündelt Firmen, Ansprechpartner und Stammdaten. Nutzen Sie sie für Pflege, Recherche und Kontaktpflege. Ergebnis sind aktuelle Kundendatensätze für Support und Kommunikation.',
    ),
    'createCustomer': DashboardOnboardingText(
      title: 'Neuen Kunden anlegen',
      body:
          'Hier legen Sie neue Kundenkonten direkt im System an. Verwenden Sie die Kachel bei Onboarding neuer Partner oder Kunden. Ergebnis ist ein aktivierter Account mit hinterlegten Stammdaten.',
    ),
    'reps': DashboardOnboardingText(
      title: 'Vertreterverwaltung',
      body:
          'In der Vertreterverwaltung ordnen Sie Kunden den zuständigen Ansprechpartnern zu. Nutzen Sie sie bei Region- oder Zuständigkeitswechseln. Ergebnis ist eine saubere Zuordnung für Vertrieb und Support.',
    ),
    'news': DashboardOnboardingText(
      title: 'Neuigkeiten & Infoscreen',
      body:
          'Hier steuern Sie Inhalte für den Connect+-Infoscreen und Kundennews. Nutzen Sie die Kachel für Ankündigungen, Hinweise und Aktualisierungen. Ergebnis ist eine sichtbare Kommunikation im Portal.',
    ),
    'downloads': DashboardOnboardingText(
      title: 'Downloads',
      body:
          'Dieser Bereich verwaltet Dokumente und Dateien für Vertreter. Nutzen Sie die Kachel, wenn Unterlagen bereitgestellt oder aktualisiert werden müssen. Ergebnis ist eine gepflegte Download-Bibliothek.',
    ),
    'faq': DashboardOnboardingText(
      title: 'Wissensdatenbank (FAQ)',
      body:
          'Hier pflegen Sie FAQ-Artikel und Kategorien für Kunden und interne Teams. Nutzen Sie die Kachel bei wiederkehrenden Fragen. Ergebnis ist eine aktuelle Wissensbasis mit strukturierten Antworten.',
    ),
    'wiki': DashboardOnboardingText(
      title: 'Vertreter-Wiki',
      body:
          'Das Vertreter-Wiki bündelt Vertriebswissen und Produkthintergrund. Nutzen Sie die Kachel, wenn Informationen konsistent dokumentiert werden sollen. Ergebnis ist ein zentraler, leicht auffindbarer Wissenspool.',
    ),
    'products': DashboardOnboardingText(
      title: 'Artikelliste',
      body:
          'Die Artikelliste hält Produktdaten, Filter und Details bereit. Nutzen Sie sie für Datenpflege oder Produktrecherche. Ergebnis sind gepflegte Produktinformationen für Reklamationen und Kommunikation.',
    ),
    'audits': DashboardOnboardingText(
      title: 'Interne Audits',
      body:
          'In diesem Bereich planen und dokumentieren Sie interne Audits. Nutzen Sie die Kachel für Auditzyklen und Maßnahmenverfolgung. Ergebnis ist eine nachvollziehbare Audit-Historie.',
    ),
    'push': DashboardOnboardingText(
      title: 'Push-Mitteilungen',
      body:
          'Hier versenden Sie Push-Benachrichtigungen an Nutzergruppen. Nutzen Sie die Kachel für wichtige Hinweise oder kurzfristige Updates. Ergebnis ist eine direkte, sichtbare Kommunikation im Portal.',
    ),
    'internalChat': DashboardOnboardingText(
      title: 'Interne Nachrichten',
      body:
          'Der interne Chat unterstützt die Zusammenarbeit zwischen Teams. Nutzen Sie ihn für schnelle Abstimmungen zu Fällen oder Aufgaben. Ergebnis ist eine dokumentierte Kommunikation im Kontext der Arbeit.',
    ),
    'catalogs': DashboardOnboardingText(
      title: 'Kataloge',
      body:
          'Hier verwalten Sie Kataloglinks, Sprachen und Zugriffe. Nutzen Sie die Kachel, wenn Kataloge aktualisiert oder ergänzt werden müssen. Ergebnis sind aktuelle Kataloge im Portal.',
    ),
    'portalUsers': DashboardOnboardingText(
      title: 'User-Datenbank',
      body:
          'Die User-Datenbank enthält alle Portal-Mitarbeiter und Rollen. Nutzen Sie die Kachel für Berechtigungen und Nutzerpflege. Ergebnis sind korrekt gepflegte Rollen und Zugriffe.',
    ),
    'appMeta': DashboardOnboardingText(
      title: 'App-Version',
      body:
          'Hier verwalten Sie Versions- und Release-Informationen der App. Nutzen Sie die Kachel, wenn Release-Hinweise oder Versionsdaten aktualisiert werden. Ergebnis ist eine konsistente Release-Dokumentation.',
    ),
    'testMode': DashboardOnboardingText(
      title: 'Testmodus & Routing',
      body:
          'Dieser Bereich steuert Testeinstellungen und Versandoptionen. Nutzen Sie ihn für QA-Checks oder kontrollierte Testläufe. Ergebnis ist ein sauber konfigurierter Testbetrieb ohne Einfluss auf Live-Daten.',
    ),
    'systemHealth': DashboardOnboardingText(
      title: 'Systemstatus',
      body:
          'Hier prüfen Sie die Systemgesundheit und wichtige Konfigurationen. Nutzen Sie die Kachel bei Störungen oder regelmäßigen Checks. Ergebnis ist ein schneller Überblick über Stabilität und Zustand.',
    ),
    'activity': DashboardOnboardingText(
      title: 'Aktivitätsübersicht',
      body:
          'Die Aktivitätsübersicht zeigt Logins, Ticketbewegungen und Push-Aktivitäten. Nutzen Sie sie für Audits oder Nachvollziehbarkeit. Ergebnis ist ein transparentes Aktivitätsprotokoll.',
    ),
  };

  static DashboardOnboardingText? forTile(String tileId) => _entries[tileId];
}
