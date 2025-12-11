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