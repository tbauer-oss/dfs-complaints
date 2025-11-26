# Modul: Custom KPI Builder

Das Admin-Modul ermöglicht es, beliebige KPIs ohne Produkt-Release zu erstellen, zu speichern und sofort zu visualisieren. Admins kombinieren Datenfelder, definieren eigene Formeln und integrieren die Kennzahlen direkt in Dashboards oder exportieren sie.

## Ziel & Nutzer
- **Zielgruppe**: Administratoren/Analysten mit Schreibrechten.
- **Ziel**: Neue Kennzahlen in Minuten erstellen, ohne Deployments oder Entwicklerabhängigkeit.

## Hauptfunktionen
- **Flexible Datenquellen**: Auswahl beliebiger Felder (z. B. Artikel, Produktgruppe, Land, Kunde, Zeitraum) inkl. Lookup/Join-Unterstützung.
- **Eigene Formeln**: Freie Berechnung, z. B. `Reklamationen / Verkäufe * 100`, mit Syntax-Highlighting, Validierung und Vorschau auf Testdaten.
- **Filter & Parameter**: Zeiträume, Regionen, Kundensegmente oder Produktgruppen als dynamische Filter im KPI speicherbar.
- **Speicherung & Versionierung**: KPIs benennen, dauerhaft sichern, versionieren (Entwurf/Live) und mit Changelog versehen.
- **Automatische Charts**: Live-Visualisierungen (Bar, Line, Pie, Heatmap) auf Basis der Formel und Filter; Layout-Optionen wie Sortierung, Farbpalette, Legende.
- **Dashboard-Integration**: Einbindung erstellter KPIs in bestehende Admin-Dashboards und Widgets; Refresh-Intervalle konfigurierbar.
- **Export**: Ergebnisse als CSV oder PDF exportieren; optional geplanter Versand (E-Mail/S3) nach Zeitplan.

## Bedienablauf
1. **Datenfelder wählen** → Tabellen/Felder aus Katalog auswählen; Joins optional per UI-Assistent.
2. **Formel schreiben** → Syntax-Checker, Autocomplete für Felder/Funktionen, sofortige Vorschau mit Beispiel-Datensatz.
3. **Filter/Parameter setzen** → Standardfilter (Zeitraum, Region, Kunde) festlegen; Parameter definieren, die Dashboard-Nutzer später verändern dürfen.
4. **Visualisierung wählen** → Chart-Typ, Achsen, Aggregation, Farbschema konfigurieren; optional Zielwert/Threshold einblenden.
5. **Speichern & Bereitstellen** → KPI benennen, Kategorie/Tags setzen, Version veröffentlichen, Zugriffsrechte bestimmen und Widget/Export aktivieren.

## Berechtigungen & Sicherheit
- Rollenbasierte Rechte: Erstellen/Bearbeiten/Veröffentlichen nur für Admins; Ansicht für berechtigte Dashboard-Nutzer.
- Validierte Formeln gegen SQL-Injection/unsichere Funktionen; Limitierung von Ressourcenkosten (Timeout/Row-Limits).
- Audit-Log für Änderungen (wer/was/wann) und Rücksprung auf ältere Versionen.

## Qualität & Performance
- Vorschau-Latenz < 2 s für Standardfilter; Server-seitige Caching-Optionen für teure KPIs.
- Validierung verhindert fehlende Felder, Division durch 0, inkompatible Datentypen oder ungültige Aggregationen.
- Hintergrund-Refresh für Widgets, damit Dashboards ohne manuelles Reload aktualisiert werden.

## Nutzen
"Ermöglicht vollständig flexible KPIs ohne System-Update – Admins können jederzeit neue Analysen selbst anlegen."
