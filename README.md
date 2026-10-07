# Agent Sessions

Kleine macOS-Leiste am Bildschirmrand, die zeigt, wie viele KI-Agent-Sessions gerade offen sind.

- **Eingeklappt:** Anzahl plus ein Farbpunkt pro Session (Farbe = Assistent).
- **Maus drüber:** Die Liste klappt auf und zeigt Titel in Assistentenfarbe und das Alter („3h“).
- **+** fügt eine Session hinzu: Titel tippen, Assistent per Farbpunkt wählen, ⏎. Esc bricht ab.
- **✕** (erscheint beim Hover über einer Zeile) entfernt die Session.
- **Rechtsklick** oder **…** öffnet das Menü: Bildschirmrand (oben/unten/links/rechts), Position (Anfang/Mitte/Ende), Assistenten bearbeiten, Start beim Anmelden, Beenden.

Die Leiste ist auf allen Spaces und über Vollbild-Apps sichtbar und nimmt anderen Apps nicht den Fokus weg.

## Bauen und starten

Voraussetzung: macOS 14+, Xcode oder die Command Line Tools.

```bash
./scripts/build-app.sh            # baut "build/Agent Sessions.app"
open "build/Agent Sessions.app"
./scripts/build-app.sh --install  # baut, kopiert nach /Applications und startet
```

Für die Entwicklung reicht `swift run`.

## Daten

Alles liegt in `~/Library/Application Support/AgentSessions/sessions.json`. Die App merkt Änderungen an der Datei innerhalb von ~2 Sekunden. So können später auch Skripte oder Hooks (z. B. Claude-Code-Hooks) Sessions eintragen:

```json
{
  "edge": "right",
  "position": "center",
  "assistants": [{ "id": "claude-code", "name": "Claude Code", "color": "#D97757" }],
  "sessions": [
    { "id": "…", "title": "Refactoring Billing", "assistant": "claude-code", "createdAt": "2026-10-07T12:00:00Z" }
  ]
}
```

Bei Sessions sind `id` und `createdAt` optional, sie werden dann ergänzt.

## Aufbau

| Datei | Inhalt |
|---|---|
| `Sources/AgentSessions/main.swift` | App-Start (Accessory-App ohne Dock-Icon), Edit-Menü für ⌘C/⌘V |
| `Models.swift` | Assistant, Session, Rand/Position, Farb-Helfer |
| `Store.swift` | Laden/Speichern der JSON-Datei, Auto-Reload |
| `EdgeRailController.swift` | Schwebendes `NSPanel`, Hover-Logik, Positionierung am Rand |
| `RailViews.swift` | SwiftUI: eingeklappt, Liste, Eingabeformular, Menü |
| `AssistantsSettingsView.swift` | Fenster zum Bearbeiten der Assistenten und Farben |
