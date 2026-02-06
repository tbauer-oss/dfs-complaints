# dfs-complaints

## FMEA-Backend (erster Inkrement)
- Neue Admin-Endpunkte für FMEA-Stammdaten (`/api/admin/fmeas`) und Risikozeilen (`/api/admin/fmea-risks`).
- Authentifizierung/Autorisierung läuft über das bestehende Portal-Guarding mit der Tile-ID `fmea`.
- Siehe `api/_lib/store.js` für das KV-Modell (Redis/In-Memory) inkl. Risikobewertung (S×A, Ampelfarbe).

## FMEA-Frontend (zweiter Inkrement)
- Admin-Dashboard-Kachel „FMEA“ unter „Qualitätsmanagement“ mit Navigation ins neue FMEA-Modul.
- Administrationsseite mit FMEA-Liste, Kopfdatenerfassung und einfacher Risiko-Tabelle (inkl. Anlage/Bearbeitung/Löschung).
- Schreibzugriff nur für QM/Superuser; andere Nutzer sehen die FMEA-Daten read-only.

## FMEA-Verknüpfungen & Exporte (dritter Inkrement)
- Bidirektionale Pflege von verknüpften Reklamationen und CAPA/8D über die Risikozeilen (Felder `linkedComplaints`/`linkedCapas` + Synchronisation in den jeweiligen Datensätzen).
- Admin-API `GET /api/admin/fmea-links` liefert eine Monitoring-Liste aller Risiko-Verknüpfungen (inkl. Filter „ohne Verknüpfung“ im Frontend-Tab).
- Export-API `GET /api/admin/fmea-export?id=...&format=pdf|csv` erzeugt FMEA-PDF (Querformat) oder CSV mit allen 20 Spalten.
- Frontend: Tab-Wechsel zwischen Risikobearbeitung und Verknüpfungsmonitoring, CSV/PDF-Export-Buttons sowie zusätzliche Felder im Risiko-Dialog (Nachweise, Maßnahmen nach Maßnahme, Verknüpfungen usw.).

## Audit- & Review-Modul (ISO 13485/19011)
- Neue Audit-Datenmodelle (`auditors`, `audit_programs`, `audits`, `audit_findings`, `audit_actions`, `audit_annual_reports`) mit Audit-Trail-Feldern und Seed-Beispielen (Auditprogramm Q1–Q4, zwei Auditoren, drei Findings, drei Actions).
- Server-seitige Validierungen für Auditorenqualifikation, Unabhängigkeitsregeln und Nachaudit-Trigger (Major/Critical oder überfällige/ineffektive Maßnahmen markieren Audits als `nachauditRequired`).
- REST-APIs unter `/api/admin/auditors`, `/api/admin/audit-programs`, `/api/admin/audits`, `/api/admin/audit-findings`, `/api/admin/audit-actions`, `/api/admin/audit-annual-reports` mit Portal-Guarding (`tile: audits`).
- Standardisierte Fristlogik: automatische Due-Dates je Einstufung (Minor/Major/Critical), Eskalationslevel, Overdue-Erkennung und Wirksamkeitsprüfung-Flags.
- Node-Testabdeckung für Unabhängigkeitsblock, Re-Qual-Check, Fristberechnung und Nachaudit-Trigger (`node --test api/tests/audit.test.js`).

## Schulungswesen (DFS Connect+ Admin)
- Neuer Admin-Bereich „Schulungswesen“ inkl. Kachel im Admin-Dashboard und Tab-UI für Bedarfserhebung, Schulungsprogramm, Einzelmaßnahmen, Fragebogen-Templates und Archiv.
- REST-APIs unter `/api/admin/training-needs`, `/api/admin/training-programs`, `/api/admin/trainings`, `/api/admin/training-questionnaire-templates`, `/api/admin/training-questionnaires` mit Portal-Guarding (`tile: trainings`).
- Nummernlogik für Trainings (`TRN-YYYY-####`) über Redis-/In-Memory-Counter, Soft-Delete der Trainingsdatensätze und automatisches Zuweisen von Fragebögen bei Teilnehmerstatus „attended“.
- PDF-Exporte für Einzel-Schulungen (`/api/admin/training-pdf?id=...`) und Jahresprogramme (`/api/admin/training-program-pdf?year=...`).
- Tests für Nummern- und Fragebogen-Zuweisung (`node --test api/tests/training.test.js`).
