# dfs-complaints

## FMEA-Backend (erster Inkrement)
- Neue Admin-Endpunkte für FMEA-Stammdaten (`/api/admin/fmeas`) und Risikozeilen (`/api/admin/fmea-risks`).
- Authentifizierung/Autorisierung läuft über das bestehende Portal-Guarding mit der Tile-ID `fmea`.
- Siehe `api/_lib/store.js` für das KV-Modell (Redis/In-Memory) inkl. Risikobewertung (S×A, Ampelfarbe).