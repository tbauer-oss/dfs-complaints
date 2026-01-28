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
          'Hier sehen Sie alle aktuell offenen Reklamationen, die noch geprüft, bewertet oder entschieden werden müssen. Diese Ansicht ist der zentrale Einstieg für die operative Reklamationsbearbeitung und hilft, keine offenen Fälle zu übersehen. Typischerweise starten Sie hier Ihre tägliche Bearbeitung und Priorisierung.',
    ),
    'all': DashboardOnboardingText(
      title: 'Alle Reklamationen',
      body:
          'Diese Übersicht enthält sämtliche Reklamationen – unabhängig vom Status. Sie eignet sich für gezielte Suchen, Filterungen und Rückverfolgung einzelner Fälle über den gesamten Lebenszyklus hinweg. Ideal für Nachfragen, Audits oder historische Auswertungen.',
    ),
    'complaintList': DashboardOnboardingText(
      title: 'Reklamationsliste & Export',
      body:
          'In dieser Ansicht können Reklamationsdaten strukturiert ausgewertet und exportiert werden. Sie dient insbesondere zur Weiterverarbeitung, Dokumentation oder Übergabe an externe Stellen. Typisch ist die Nutzung für Managementberichte oder regulatorische Nachweise.',
    ),
    'capaReports': DashboardOnboardingText(
      title: 'CAPA / 8D-Reports',
      body:
          'Hier werden CAPAs und 8D-Reports strukturiert erstellt, bearbeitet und dokumentiert. Der Fokus liegt auf Ursachenanalyse, Maßnahmenplanung und Wirksamkeitsprüfung. Dieser Bereich unterstützt die normkonforme Abarbeitung von Abweichungen und Reklamationen.',
    ),
    'capaDashboard': DashboardOnboardingText(
      title: 'CAPA-Dashboard',
      body:
          'Das CAPA-Dashboard zeigt den aktuellen Status aller Korrektur- und Vorbeugemaßnahmen. Es hilft, überfällige oder kritische CAPAs frühzeitig zu erkennen und deren Wirksamkeit zu überwachen. Ein zentrales Werkzeug für kontinuierliche Verbesserung.',
    ),
    'fmea': DashboardOnboardingText(
      title: 'FMEA',
      body:
          'In der FMEA werden Risiken systematisch identifiziert, bewertet und mit Maßnahmen verknüpft. Dieser Bereich unterstützt das präventive Risikomanagement gemäß MDR und ISO 14971. Typisch ist die Nutzung bei Produktänderungen, neuen Erkenntnissen oder Audits.',
    ),
    'prrc': DashboardOnboardingText(
      title: 'PRRC-Einstufungen',
      body:
          'In diesem Bereich erfolgt die regulatorische Bewertung von Reklamationen aus PRRC-Sicht. Hier wird beurteilt, ob ein sicherheitsrelevanter oder meldepflichtiger Sachverhalt vorliegt. Die Entscheidungen bilden die Grundlage für weitere Maßnahmen wie Meldungen, Sperren oder interne Abstimmungen.',
    ),
    'stats': DashboardOnboardingText(
      title: 'Statistik & KPIs',
      body:
          'Hier erhalten Sie einen Überblick über Kennzahlen, Trends und Auffälligkeiten im Reklamationswesen. Die Auswertungen unterstützen datenbasierte Entscheidungen und zeigen frühzeitig systematische Probleme auf. Diese Ansicht ist besonders relevant für Management, Reviews und Audits.',
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
          'Hier planen, dokumentieren und verfolgen Sie interne Audits. Der Bereich unterstützt die Auditvorbereitung, Maßnahmenverfolgung und Nachweisführung. Ein zentrales Werkzeug für das Qualitätsmanagementsystem.',
    ),
    'trainings': DashboardOnboardingText(
      title: 'Schulungswesen',
      body:
          'Hier erfassen Sie Schulungsbedarfe, koordinieren Jahresprogramme, dokumentieren Einzelmaßnahmen und prüfen die Wirksamkeit. Der Bereich bildet den gesamten Schulungsprozess inkl. Audit-Trail, Teilnehmerverwaltung und PDF-Export ab.',
    ),
    'push': DashboardOnboardingText(
      title: 'Push-Mitteilungen',
      body:
          'Hier erstellen und versenden Sie Push-Nachrichten an Kunden oder Nutzergruppen. Der Bereich dient der gezielten Kommunikation von Informationen, Updates oder Hinweisen. Push-Mitteilungen sind ein zentrales Kommunikationsinstrument innerhalb von DFS Connect+.',
    ),
    'internalChat': DashboardOnboardingText(
      title: 'Interne Nachrichten',
      body:
          'Der interne Chat unterstützt die Zusammenarbeit zwischen Teams. Nutzen Sie ihn für schnelle Abstimmungen zu Fällen oder Aufgaben. Ergebnis ist eine dokumentierte Kommunikation im Kontext der Arbeit.',
    ),
    'catalogs': DashboardOnboardingText(
      title: 'Kataloge & Stammdaten',
      body:
          'Dieser Bereich dient der Pflege zentraler Kataloge und Stammdaten, wie Kategorien, Sprachen oder systemweite Listen. Die hier gepflegten Daten werden in vielen Modulen verwendet. Änderungen sollten daher bewusst und kontrolliert erfolgen.',
    ),
    'portalUsers': DashboardOnboardingText(
      title: 'User-Datenbank',
      body:
          'In der User-Datenbank verwalten Sie interne Benutzer, Rollen und Berechtigungen. Sie steuern hier, wer Zugriff auf welche Funktionen und Daten hat. Änderungen wirken sich direkt auf Sichtbarkeit und Berechtigungen im System aus.',
    ),
    'appMeta': DashboardOnboardingText(
      title: 'App-Version & Releases',
      body:
          'Hier finden Sie Informationen zur aktuellen App-Version, Builds und Release-Hinweisen. Der Bereich unterstützt Transparenz über Änderungen und neue Funktionen. Besonders relevant für Tests, Rollouts und Support.',
    ),
    'testMode': DashboardOnboardingText(
      title: 'Testmodus & Routing',
      body:
          'In diesem Bereich konfigurieren Sie Testmodi, Routing-Logiken und Filter für E-Mails oder Push-Nachrichten. Er wird genutzt, um neue Funktionen sicher zu testen, ohne reale Kunden zu beeinflussen. Ein wichtiges Werkzeug für kontrollierte Änderungen.',
    ),
    'systemHealth': DashboardOnboardingText(
      title: 'Systemstatus',
      body:
          'Der Systemstatus zeigt den aktuellen Zustand zentraler Systemkomponenten. Er dient der schnellen Einschätzung von Verfügbarkeit, Fehlern oder Störungen. Typisch ist die Nutzung bei Supportfällen oder technischen Prüfungen.',
    ),
    'activity': DashboardOnboardingText(
      title: 'Aktivitätsübersicht',
      body:
          'Diese Übersicht zeigt relevante Systemaktivitäten wie Logins, Tickets oder Push-Vorgänge. Sie unterstützt Nachvollziehbarkeit und Transparenz im Systembetrieb. Besonders hilfreich bei Analysen oder Rückfragen.',
    ),
  };

  static DashboardOnboardingText? forTile(String tileId) => _entries[tileId];
}
