# FMEA Admin-Frontend – Übersicht & Filter

Diese Änderung ergänzt das FMEA-Modul im Admin-Dashboard um eine neue Übersicht-Ansicht, erweiterte Filter und eine kompaktere Risikotabelle.

## Anpassungen
- **Übersicht-Tab:** KPI-Kacheln (Risiken, PRRC-Status, letzte Änderung, Kategorien), Vor/Nach-Maßnahmen-Statistiken, offene Punkte sowie Kategorie-Auswertung mit Ampelfarben.
- **Risiken-Tab:** Dynamische Kategorienliste zum Sofort-Filtern, Volltextsuche und Filterchips (Ampelfarben vor/nach, neue Gefährdung, Restrisiko, fehlende Nachweise, Verknüpfungen). Tabelle als kompakte Karten mit ausklappbaren Details und Badges für Reklamations-/CAPA-Links.
- **Exports/Links:** Schnellzugriffe auf Export und Verknüpfungstab im neuen Übersicht-Tab.

## Speicherort
Alle Anpassungen liegen im Flutter-Web-Frontend in `lib/pages/admin_fmea_page.dart`.
