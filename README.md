# Agent Sessions

Eine kleine macOS-Leiste am Bildschirmrand, die zeigt, wie viele KI-Agent-Sessions du gerade offen hast und welche.

## Wozu?

Wer mit mehreren KI-Agenten parallel arbeitet, startet schnell hier eine Claude-Code-Session, dort einen Codex-Thread und nebenbei eine Cowork-Aufgabe. Nach einer Stunde weiß man nicht mehr genau, wo überall noch etwas läuft oder auf eine Antwort wartet.

Agent Sessions macht diese verteilte Aufmerksamkeit sichtbar:

- Am Bildschirmrand steht dezent eine **Zahl**: So viele Sessions sind gerade aktiv.
- Fährst du mit der Maus darüber, klappt die **Liste** auf: Titel in der Farbe des jeweiligen Assistenten, die zuletzt aktive Session oben.
- Sessions von **Claude Code, Claude Cowork, Codex und ChatGPT Work** erkennt die App automatisch. Alles andere trägst du von Hand ein.
- Wer länger nichts tut, verschwindet von selbst ins **Archiv** und kommt bei neuer Aktivität zurück.

Reine Chats in den Desktop-Apps von Claude und ChatGPT werden bewusst nicht erfasst, nur Agent-Sessions.

## Installation

**Voraussetzungen:** macOS 14 (Sonoma) oder neuer sowie Xcode oder die Command Line Tools von Apple. Ob Swift vorhanden ist, prüfst du mit `swift --version`. Falls nicht, installierst du die Command Line Tools mit:

```bash
xcode-select --install
```

**Bauen und installieren:**

```bash
git clone <URL dieses Repositorys> agent-sessions
cd agent-sessions
./scripts/build-app.sh --install
```

Das Skript baut die App, kopiert sie nach `/Applications/Agent Sessions.app` und startet sie. Eine bereits laufende Version wird vorher beendet. Die App hat kein Dock-Icon, sie erscheint nur als Leiste am rechten Bildschirmrand.

**Automatisch beim Login starten:** Rechtsklick auf die Leiste → „Beim Anmelden starten“. macOS zeigt dazu eventuell eine Mitteilung oder einen Eintrag unter *Systemeinstellungen → Allgemein → Anmeldeobjekte*.

**Aktualisieren:** Neuen Stand holen (`git pull`) und erneut `./scripts/build-app.sh --install` ausführen. Deine Daten bleiben erhalten.

> **Hinweis:** Die App ist nur lokal signiert (ad hoc), nicht von Apple beglaubigt. Selbst gebaut läuft sie ohne Rückfrage. Gibst du die fertige `.app` an einen anderen Mac weiter, blockiert macOS sie zunächst. Dann hilft Rechtsklick → „Öffnen“ oder:
>
> ```bash
> xattr -dr com.apple.quarantine "/Applications/Agent Sessions.app"
> ```

## Bedienung

| Aktion | So geht's |
|---|---|
| Liste aufklappen | Maus über die Leiste bewegen. Sie klappt wieder zu, sobald die Maus sie verlässt. |
| Session manuell eintragen | **+** im Kopf der Liste, Titel tippen, Assistent per Farbpunkt wählen, ⏎. Esc bricht ab. |
| Umbenennen | Doppelklick auf den Titel oder Stift-Symbol beim Hover über einer Zeile. |
| Archivieren | Archiv-Symbol beim Hover über einer Zeile. |
| Löschen | Papierkorb beim Hover über einer Zeile. |
| Archiv ansehen | Archiv-Symbol im Kopf der Liste. Dort holt der Pfeil nach oben eine Session zurück. |
| Leiste verschieben | Kopfzeile (Griff ≡) mit der Maus ziehen. Beim Loslassen rastet die Leiste am nächsten Bildschirmrand ein, auch auf einem anderen Bildschirm. |
| Einstellungen | Rechtsklick auf die Leiste oder **…** im Kopf: automatische Erkennung, Auto-Archiv-Dauer, Rand und Position, Assistenten und Farben, Start beim Anmelden, Beenden. |

Das kleine Symbol vor jedem Titel zeigt die Herkunft:

- **Funkwellen:** automatisch erkannt
- **Hand:** manuell eingetragen

Die Leiste ist auf allen Spaces und über Vollbild-Apps sichtbar und nimmt anderen Apps nie den Fokus weg.

## Automatisch erkannte Sessions

Alle 15 Sekunden liest die App die Session-Daten, die die Assistenten ohnehin lokal ablegen. Sie liest nur und schreibt dort nie etwas.

| Assistent | Quelle | Herausgefiltert |
|---|---|---|
| Claude Code (Desktop-App) | `~/Library/Application Support/Claude/claude-code-sessions/*/*/local_*.json` | – |
| Claude Code (Terminal) | `~/.claude/projects/*/*.jsonl` mit `"entrypoint": "cli"` | SDK- und Headless-Läufe |
| Claude Cowork (lokal) | `~/Library/Application Support/Claude/local-agent-mode-sessions/*/*/local_*.json` | geplante Aufgaben |
| Claude Cowork (Cloud) | `…/local-agent-mode-sessions/*/*/remote-session-spaces.json` | Sessions, die vor dem ersten Start der App existierten |
| Codex und ChatGPT Work | `~/.codex/state_*.sqlite`, Tabelle `threads`; das Feld `originator` unterscheidet beide | Subagenten, Guardian-Reviews, Automationen |

### Regeln

- **Aktiv** ist eine Session, wenn sie in den letzten 4 Stunden aktiv war und nicht archiviert ist. Die Dauer ist im Menü einstellbar: 1, 2, 4, 8 oder 24 Stunden.
- **Auto-Archiv:** Nach dieser Zeit ohne Aktivität wandert eine Session ins Archiv. Bei neuer Aktivität erscheint sie wieder.
- **Archivieren von Hand:** Wirkt genauso. Die Session kommt zurück, sobald darin wieder etwas passiert.
- **Löschen:** Eine gelöschte erkannte Session taucht nie wieder auf.
- **Umbenennen:** Dein Titel ersetzt den des Assistenten. Ein leerer Titel stellt den Originaltitel wieder her.
- **Abgleich:** Im Assistenten archiviert heißt auch hier archiviert. Im Assistenten gelöscht heißt auch hier weg.
- **Sortierung:** In der Liste und im Archiv steht die zuletzt aktive Session oben.
- **Ausnahmen:** Manuelle Sessions und Cowork-Cloud-Sessions archivieren sich nie automatisch. Die archivierst du selbst.

**Zu Cowork in der Cloud:** Lokal stehen für Cloud-Sessions nur die Session-ID und die freigegebenen Ordner, kein Titel und keine Aktivität. Eine Session gilt deshalb als gestartet, sobald ihre ID zum ersten Mal auftaucht. Sie heißt nach ihrem Ordner, umbenennen kannst du sie trotzdem. Weil spätere Aktivität unsichtbar ist, bleibt sie aktiv, bis du sie archivierst.

**Wichtig:** Diese Dateiformate sind von den Herstellern nicht dokumentiert. Ändert ein Assistent nach einem Update sein Format, fällt nur diese eine Quelle aus, die App läuft weiter. Was der Scanner gerade findet, zeigt:

```bash
"/Applications/Agent Sessions.app/Contents/MacOS/AgentSessions" --scan
```

## Daten und Datenschutz

Die App greift nicht aufs Netz zu. Sie liest nur lokale Dateien.

Gespeichert wird in `~/Library/Application Support/AgentSessions/`:

| Datei | Inhalt |
|---|---|
| `sessions.json` | Manuelle Sessions, Assistenten und Farben, Einstellungen (Rand, Position, Auto-Archiv) sowie deine Entscheidungen zu erkannten Sessions: eigene Titel, archiviert, gelöscht (`autoStates`). |
| `cowork-cloud-seen.json` | Wann welche Cowork-Cloud-Session zum ersten Mal gesehen wurde. |

Erkannte Sessions selbst werden nicht gespeichert, sie werden bei jedem Scan neu gelesen.

`sessions.json` ist lesbares JSON und darf auch von Hand oder per Skript bearbeitet werden. Die App übernimmt Änderungen innerhalb von etwa 2 Sekunden. Eine manuelle Session sieht so aus:

```json
{ "title": "Refactoring Billing", "assistant": "claude-code" }
```

`id`, `createdAt` und `lastActivityAt` sind optional und werden ergänzt. Gültige Werte für `assistant` sind die `id`s unter `assistants`, z. B. `claude-code`, `claude-cowork`, `chatgpt-codex`, `chatgpt-work`, `gemini` oder `other`.

## Deinstallieren

1. Rechtsklick auf die Leiste → „Beim Anmelden starten“ abhaken, dann „Beenden“.
2. Die App, die Daten und die gespeicherten Einstellungen entfernen:

```bash
rm -rf "/Applications/Agent Sessions.app"
```

```bash
rm -rf ~/Library/Application\ Support/AgentSessions
```

```bash
defaults delete local.agentsessions.AgentSessions
```

## Weiterentwickeln

Die App ist ein Swift Package ohne Xcode-Projekt: SwiftUI für die Oberfläche, AppKit für das schwebende Fenster. Sie hat keine externen Abhängigkeiten.

```bash
swift build                          # Debug-Build
swift run                            # direkt starten (ohne App-Bundle; "Beim Anmelden starten" geht so nicht)
.build/debug/AgentSessions --scan    # nur den Scanner laufen lassen und Ergebnis ausgeben
./scripts/build-app.sh               # App-Bundle nach build/Agent Sessions.app
open "build/Agent Sessions.app"      # Bundle testen, ohne die installierte Version anzufassen
```

Beende die installierte Version vorher, sonst laufen zwei Leisten gleichzeitig. Beide teilen sich dieselben Daten.

Auch ohne Xcode-Projekt lässt sich das Paket in Xcode öffnen: `open Package.swift`.

### Aufbau

| Datei (`Sources/AgentSessions/`) | Inhalt |
|---|---|
| `main.swift` | App-Start als Hintergrund-App ohne Dock-Icon, Edit-Menü für ⌘C/⌘V/⌘A, Diagnose-Schalter `--scan` |
| `Models.swift` | Datentypen: Assistant, manuelle Session, erkannte Session, Listeneintrag (`RailItem`), Rand und Position, Farb-Helfer |
| `Store.swift` | Lädt und speichert `sessions.json`, führt manuelle und erkannte Sessions zusammen, setzt die Archiv-Regeln um |
| `SessionScanner.swift` | Liest die Session-Daten der Assistenten, eine Funktion pro Quelle |
| `EdgeRailController.swift` | Schwebendes `NSPanel`, Hover-Logik, Ziehen und Einrasten, Positionierung am Rand, Tastatur-Fokus bei Texteingabe |
| `RailViews.swift` | SwiftUI-Oberfläche: eingeklappte Leiste, Liste, Archiv, Umbenennen, Eingabeformular, Menü |
| `AssistantsSettingsView.swift` | Fenster zum Bearbeiten der Assistenten und ihrer Farben |

Außerdem: `Resources/Info.plist` (Bundle-Einstellungen, u. a. `LSUIElement` für „kein Dock-Icon“) und `scripts/build-app.sh` (baut das `.app`-Bundle, signiert ad hoc, installiert optional).

### Neue Quelle anbinden

Um einen weiteren Assistenten automatisch zu erkennen:

1. In `SessionScanner.swift` eine Funktion `scanXyz()` schreiben, die `[DetectedSession]` liefert:
   - `key`: eindeutig und stabil, nach dem Muster `"<quelle>:<session-id>"`.
   - `assistant`: die `id` eines Assistenten.
   - `title` und `lastActivity`.
   - `archived`: ob die Session im Assistenten selbst archiviert ist.
   - `autoArchives: false`, falls die Quelle keine Aktivität verrät.
2. Die Funktion in `collect()` aufrufen.
3. Falls nötig, den Assistenten mit Farbe in `Assistant.defaults` (`Models.swift`) ergänzen. Bestehende Installationen übernehmen neue Standard-Assistenten nicht automatisch. Dort fügt man sie unter „Assistenten bearbeiten…“ mit derselben `id` hinzu oder trägt sie in `sessions.json` ein.
4. Mit `--scan` prüfen, ob die Sessions gefunden werden.

Alle Regeln zum Aktiv-Sein, Archivieren und Sortieren stecken in `Store.items()` und gelten automatisch auch für neue Quellen.
