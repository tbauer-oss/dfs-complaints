# dfs-complaints

Dieses Repository enthält alle relevanten Komponenten der DFS-Complaints-Plattform. Damit du nicht nur den Code siehst, sondern die Anwendung auch wirklich ausprobieren kannst, findest du hier eine kurze Übersicht sowie die wichtigsten Befehle für einen lokalen Testlauf.

## Projektaufbau

| Ordner        | Inhalt                                                                 |
| ------------- | ---------------------------------------------------------------------- |
| `api/`        | Serverless-Funktionen (Node.js, Vercel kompatibel) für Auth, Complaints usw. |
| `dfs_mobile/` | Flutter-Mobile-App (Android/iOS/Web)                                     |
| `flutter_web/`| Spezielles Flutter-Web-Frontend                                          |

## API lokal ausführen

Die API ist als Sammlung von Vercel Functions organisiert. Lokal lässt sie sich am einfachsten mit `vercel dev` starten. Dadurch steht ein vollständiger Mock der Serverless-Umgebung zur Verfügung und du kannst alle Endpunkte testen.

```bash
cd api
npm install            # einmalig, um Abhängigkeiten zu installieren
npx vercel dev         # startet die lokale Vercel-Laufzeit (http://localhost:3000)
```

Alternativ kannst du einzelne Handler direkt mit Node testen, z. B. `node gate.js`, musst dann aber selbst Request-/Response-Objekte (z. B. via Supertest) simulieren. Für echte Requests empfiehlt sich klar die Vercel-Emulation.

### KI-Chatbot aktivieren

Der neue Chatbot-Endpunkt (`POST /api/chatbot`) beantwortet Fragen zur Plattform auf Basis der Wissensartikel in `api/_assets/chatbot/knowledge.json`.

1. Hinterlege einen OpenAI-Schlüssel als `OPENAI_API_KEY` (optional auch `OPENAI_MODEL`). Ohne Schlüssel liefert der Endpoint eine statische Fallback-Antwort.
2. Starte `vercel dev` oder rufe `node chatbot.js` direkt auf.
3. Sende JSON wie folgt:

```bash
curl -X POST http://localhost:3000/api/chatbot \
  -H 'Content-Type: application/json' \
  -d '{
        "question": "Wie läuft eine Beschwerde ab?",
        "history": [{"role": "user", "message": "Gibt es ein SLA?"}]
      }'
```

Die Antwort enthält zusätzlich eine `sources`-Liste mit den verwendeten Wissensartikeln, damit nachvollziehbar bleibt, woraus die KI zitiert hat. Um neue Inhalte einzupflegen, erweitere `knowledge.json` oder lege zusätzliche JSON-Dateien im gleichen Verzeichnis ab.

## Flutter-Web-Client starten

```bash
cd flutter_web
flutter pub get
flutter run -d chrome    # oder: flutter build web
```

Damit öffnet sich ein Browserfenster mit dem Web-Frontend gegen deine lokale API. Achte darauf, dass CORS entsprechend deiner lokalen URL angepasst ist.

## Flutter-Mobile-App

```bash
cd dfs_mobile
flutter pub get
flutter run              # Gerät oder Emulator muss verbunden sein
```

Hiermit kannst du die mobile Oberfläche testen. Für die Web-Variante (`flutter run -d chrome`) greift die App auf dieselben Services wie der dedizierte Web-Client zurück.

## Nützliche Tipps

* Environment-Variablen für die API legst du lokal über eine `.env.local` im Ordner `api/` fest – exakt wie bei Vercel.
* Prüfe die serverseitigen Module im Ordner `api/_lib/`, dort findest du u. a. Mail-, Auth- und Storage-Helfer.
* Für Debugging kannst du in `vercel dev` die Option `--listen` verwenden, um den Port explizit festzulegen.

So solltest du nachvollziehen können, was im Projekt passiert, und du bekommst direkt etwas zu sehen.