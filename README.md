# Agent Sessions

Kleine macOS-Leiste am Bildschirmrand, die zeigt, wie viele KI-Agent-Sessions gerade aktiv sind.

- **Eingeklappt:** Anzahl plus ein Farbpunkt pro Session (Farbe = Assistent).
- **Maus drüber:** Die Liste klappt auf, sortiert nach letzter Aktivität (oben die jüngste). Das Icon zeigt die Herkunft: 📡 automatisch erkannt, ✋ manuell eingetragen.
- **Hover über einer Zeile:** ✏️ umbenennen (oder Doppelklick auf den Titel), 🗄 archivieren, 🗑 löschen.
- **🗄 im Kopf** blendet das Archiv ein, ebenfalls nach letzter Aktivität sortiert. Dort holt ⤴ eine Session zurück.
- **+** trägt eine Session manuell ein: Titel tippen, Assistent per Farbpunkt wählen, ⏎. Esc bricht ab.
- **Titelleiste (≡) ziehen** verschiebt die Leiste frei. Beim Loslassen rastet sie am nächstgelegenen Bildschirmrand ein, an der Stelle, wo du sie losgelassen hast, auch auf einem anderen Bildschirm.
- **Rechtsklick** oder **…** öffnet das Menü: automatische Erkennung an/aus, Auto-Archiv-Dauer, Bildschirmrand, Position, Assistenten bearbeiten, Start beim Anmelden, Beenden.

Die Leiste ist auf allen Spaces und über Vollbild-Apps sichtbar und nimmt anderen Apps nicht den Fokus weg.

## Automatisch erkannte Sessions

Alle 15 Sekunden liest die App (nur lesend) die lokalen Session-Daten der Assistenten:

| Assistent | Quelle | Ausgefiltert |
|---|---|---|
| Claude Code (Desktop-App) | `~/Library/Application Support/Claude/claude-code-sessions` | – |
| Claude Cowork (lokal) | `~/Library/Application Support/Claude/local-agent-mode-sessions/*/*/local_*.json` | geplante Aufgaben |
| Claude Cowork (Cloud) | `…/local-agent-mode-sessions/*/*/remote-session-spaces.json` | – |
| Claude Code (Terminal) | `~/.claude/projects/*/*.jsonl` mit `entrypoint: "cli"` | SDK- und Headless-Läufe |
| Codex / ChatGPT Work | `~/.codex/state_*.sqlite`, Tabelle `threads` (`originator` unterscheidet beide) | Subagenten, Guardian-Reviews, Automationen |

**Cowork in der Cloud:** Lokal stehen nur Session-ID und freigegebene Ordner, kein Titel und keine Aktivität. Eine Session gilt als gestartet, sobald ihre ID zum ersten Mal auftaucht, und heißt nach ihrem Ordner. Spätere Aktivität sieht die App nicht, deshalb archivieren sich diese Sessions nie automatisch – du archivierst sie selbst. Archiviert bleiben sie archiviert, bis du sie mit ⤴ zurückholst. Wann welche ID zuerst gesehen wurde, steht in `~/Library/Application Support/AgentSessions/cowork-cloud-seen.json`.

Reine Chats in den Claude- und ChatGPT-Apps tauchen dort nicht auf und werden daher nicht erfasst.

Regeln:

- **Aktiv** ist eine Session, wenn sie in den letzten 4 Stunden aktiv war (einstellbar) und nicht archiviert ist.
- **Archivieren:** Die Session verschwindet aus der aktiven Liste. Bei neuer Aktivität erscheint sie wieder. Längere Inaktivität archiviert automatisch.
- **Löschen:** Die Session taucht nie wieder auf.
- **Umbenennen:** Der eigene Titel gilt statt des Titels aus dem Assistenten. Ein leerer Titel stellt den Originaltitel wieder her.
- Im Assistenten **archiviert** heißt in der App archiviert, im Assistenten **gelöscht** heißt in der App weg.
- **Manuelle Sessions** und **Cowork-Cloud-Sessions** werden nie automatisch archiviert.

Die Formate dieser Dateien sind nicht offiziell dokumentiert. Ändert ein Assistent sein Format, fällt nur diese eine Quelle aus.

Diagnose: `.build/debug/AgentSessions --scan` (bzw. `"build/Agent Sessions.app/Contents/MacOS/AgentSessions" --scan`) listet alles, was der Scanner findet.

## Bauen und starten

Voraussetzung: macOS 14+, Xcode oder die Command Line Tools.

```bash
./scripts/build-app.sh            # baut "build/Agent Sessions.app"
open "build/Agent Sessions.app"
./scripts/build-app.sh --install  # baut, kopiert nach /Applications und startet
```

Für die Entwicklung reicht `swift run`.

## Daten

Alles, was du selbst festlegst, liegt in `~/Library/Application Support/AgentSessions/sessions.json`: manuelle Sessions, Assistenten und Farben, Einstellungen, außerdem Titel, Archiv- und Lösch-Status erkannter Sessions (`autoStates`). Erkannte Sessions selbst werden nicht gespeichert. Die App merkt Änderungen an der Datei innerhalb von ~2 Sekunden.

## Aufbau

| Datei | Inhalt |
|---|---|
| `Sources/AgentSessions/main.swift` | App-Start (Accessory-App ohne Dock-Icon), Edit-Menü für ⌘C/⌘V |
| `Models.swift` | Assistant, Session, erkannte Sessions, Rand/Position, Farb-Helfer |
| `Store.swift` | Laden/Speichern der JSON-Datei, Auto-Reload, Archiv-Regeln |
| `SessionScanner.swift` | Liest die Session-Daten von Claude, Cowork und Codex |
| `EdgeRailController.swift` | Schwebendes `NSPanel`, Hover-Logik, Positionierung am Rand |
| `RailViews.swift` | SwiftUI: eingeklappt, Liste, Archiv, Umbenennen, Eingabeformular, Menü |
| `AssistantsSettingsView.swift` | Fenster zum Bearbeiten der Assistenten und Farben |
