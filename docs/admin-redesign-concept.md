# Adminbereich Redesign – Design-Konzept

Dieses Konzept beschreibt ein modernes, ruhiges UI für den Adminbereich. Optisch orientiert es sich am Referenzbild (klare Kacheln, dezente Verläufe, großzügige Abstände, professionelle Typografie). Alle Module sind über eine strukturierte Sidebar erreichbar; das Dashboard steht oben links und öffnet die bestehende Ansicht.

## Leitplanken
- **Farbschema**: Petrol/Teal als Akzent (z. B. #009688 → #0fb9b1 Verlaufsoption), flankiert von kühlen Blau- und Grautönen (#0f172a, #1e293b, #334155, #e2e8f0, #f8fafc). Für Dark Mode invertierte Helligkeiten bei unveränderter Akzentfarbe. Akzentflächen maximal 20–25 % der Fläche, der Rest bewusst ruhig.
- **Typografie**: Sans Serif mit guter Screen-Lesbarkeit (z. B. Inter/Roboto). Headings mit 600–700 Gewicht, Body 400–500. Zeilenhöhe 1.4–1.6.
- **Layout & Rhythmus**: 8 px-baseline (Abstände 8/16/24/32). Karten mit 12–16 px Padding, 4–8 px Radius, sanfte Schatten (blur 16–24, opacity 8–12 %).
- **Icons**: Schlanke, konsistente Line-Icons (24 px grid). Gleiche Strichstärken, ruhige Farben (#64748b in Light, #94a3b8 in Dark); Akzent nur für aktive Zustände.
- **States & Feedback**: Farbcodierung dezent (Info #3b82f6, Success #10b981, Warning #f59e0b, Danger #ef4444). Immer mit Icon + Kurztext + optionaler Link/Aktion.

## Informationsarchitektur & Navigation
- **Sidebar (Hauptnavigation)** – fixierte Spalte, 280 px (Desktop), 72 px kollabiert, Overlay-Drawer auf Mobile. Gruppen mit Titel in Kleinkapitälchen/Muted. Einträge mit Icon + Label; Active- und Hover-Zustände durch Akzentbalken links und Hinterlegung.
  - Dashboard (bestehende Ansicht) – immer oberster Eintrag.
  - Vorgänge: Beschwerden, Pending/Review, Eskalationen (falls vorhanden), Übersetzungen.
  - Kunden & Reps: Kunden, Reps, Rep-Erinnerungen, Aktivität.
  - Inhalte: News, FAQ, Kataloge/Meta, Push-Broadcasts.
  - System: Gesundheit/Monitoring, Statistiken, Accounts/Users/Rollen, Einstellungen.
- **Topbar** – schmale Zeile über dem Haupt-Content: Pfad/Seitentitel links, rechte Seite mit Quick-Actions (z. B. „Check for Updates“, „Clear Cache“), Suche, Profil/Status, Theme-Toggle.
- **Breadcrumbs** optional unter dem Seitentitel; erleichtern Rücksprung aus Detailansichten.

## Dashboard Layout
- **Grid**: Zweispaltig (≥1200 px) mit 12-Spalten-Grid, Gutter 24 px; einspaltig unter 960 px. Beispielzeilen:
  1. **Systemstatus** (Maintenance/Backup) links, **Statistiken** rechts – großflächige Karten mit Akzent-Gradient, kreisförmige KPIs, dezente Grafen (sparklines oder bars) im neutralen Blau/Grau.
  2. **Benachrichtigungen** und **Aktivitätsfeed/News** als kartenbasierte Listen mit klaren Meta-Informationen (Tag, Zeit, Status-Badge, Sekundärtext). Scrollbare max-height statt endloser Seite.
  3. **Shortcut-Kacheln** zu häufigen Aktionen (z. B. „Neue Beschwerde“, „Push senden“, „FAQ aktualisieren“).
- **Kartenaufbau**: Titelzeile mit Icon + Label, rechts Actions (Filter, Refresh, „⋮“). Body mit primärer KPI, sekundärer Kennzahl, dezenter Trendvisualisierung. Footer mit Sekundäraktion („Backup“, „Details öffnen“).

## Kern-Views
- **Listen (Beschwerden, Kunden, Reps, News, FAQ)**: Header mit Titel, Filterbar (Status, Zeitraum, Kanal), Suchfeld, Primary CTA rechts. Tabellen als flache Karten mit zebra/hover backgrounds; sortierbare Spalten, Badge-Spalte für Status, Right-aligned Zahlen. Mobile: Karten-Stacks mit Key-Value-Paaren und oberer Statusleiste.
- **Detailseiten**: Zweispaltiges Layout (Inhalt links, Kontext rechts). Rechte Spalte für Timeline/Notizen/Verlauf, links Hauptdaten. Sektionen durch Kachelrahmen, klare Section-Titel, Inline-Tags für Metadaten.
- **Formulare**: Einspaltig bis 960 px, sonst zwei Spalten. Label oben, Hilfetext darunter, valide/Fehlerzustände mit Icons. Primäre Aktion sticky unten rechts (Desktop) oder Footer-Bar (Mobile). Stepper für längere Abläufe (z. B. neue Nachricht/Push-Kampagne).
- **Statistiken/Health**: Karten mit kompakten Charts (Bars/Lines/Doughnuts) auf neutralem Hintergrund; Akzentfarbe nur für Highlights. Legenden als Badges, Download/Export-Button in der Karten-Toolbar.

## Responsive Verhalten
- **Breakpoints**: 1440 (max width), 1200 (2→1 Spalte fallback), 960 (Sidebar auto-collapse), 720 (Drawer-Navigation), 480 (kompakte Typografie/Paddings). Grid und Komponenten skalieren mit 8 px-Raster.
- **Interaktionen**: Hover-Feedback nur Desktop; Mobile mit klare Tap-Ziele (min. 44 px). Sticky Topbar und optional Sticky Filterleiste.

## Dark-Mode Regeln
- Hintergrundstufen: #0b1220 (page), #111827 (pane), #1f2937 (card). Trennlinien transparent weiß (6–10 %).
- Textfarben: Primär #e5e7eb, Sekundär #cbd5e1, Muted #94a3b8. Akzent unverändert; Chart-Flächen mit 60–70 % Opacity.
- Schatten durch Outlines ersetzen (1 px weiß 6 % + 1 px schwarz 24 % bei modalen Elementen) falls nötig.

## Microcopy & Stati
- Ein-Wort-Titel, klare Buttons („Speichern“, „Backup starten“, „Push senden“). Tooltips für Icons ohne Label.
- Status-Badges kurzhalten (z. B. „Neu“, „In Prüfung“, „Geschlossen“, „Fehler“, „Aktiv“).

## Übergabe als Prompt (Kurzfassung)
> Entwirf ein Admin-Dashboard im Stil moderner Headless-CMS: ruhiges Petrol/Blau-Grau-Farbschema, klare Karten mit dezenten Schatten/Verläufen, Sidebar als Hauptnavigation mit Gruppen (Dashboard ganz oben, Vorgänge, Kunden & Reps, Inhalte, System). Topbar mit Seitentitel, Suche, Quick-Actions, Profil und Theme-Toggle. Dashboard zweispaltig mit Status-/Statistik-Karten, Notifications- und News-Listen, Shortcuts. Tabellen mit Badges und Filterbar, Detailseiten zwei-spaltig mit Timeline rechts, Formulare mit klaren Labels/Hilfetexten. Responsiv (12-Grid, Breakpoints 1200/960/720) und konsistente Line-Icons. Dark Mode mit invertierten Helligkeiten, gleichbleibendem Akzent.
