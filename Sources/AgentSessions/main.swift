import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var store: Store!
    private var rail: EdgeRailController!

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.mainMenu = makeMainMenu()
        store = Store()
        rail = EdgeRailController(store: store)
        rail.show()
    }

    /// Never visible (accessory app), but required so ⌘C/⌘V/⌘A/⌘Z work in text fields.
    private func makeMainMenu() -> NSMenu {
        let main = NSMenu()

        let appItem = NSMenuItem()
        let appMenu = NSMenu()
        appMenu.addItem(withTitle: "Beenden", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        appItem.submenu = appMenu
        main.addItem(appItem)

        let editItem = NSMenuItem()
        let edit = NSMenu(title: "Bearbeiten")
        edit.addItem(withTitle: "Widerrufen", action: Selector(("undo:")), keyEquivalent: "z")
        let redo = edit.addItem(withTitle: "Wiederholen", action: Selector(("redo:")), keyEquivalent: "z")
        redo.keyEquivalentModifierMask = [.command, .shift]
        edit.addItem(.separator())
        edit.addItem(withTitle: "Ausschneiden", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        edit.addItem(withTitle: "Kopieren", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        edit.addItem(withTitle: "Einsetzen", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        edit.addItem(withTitle: "Alles auswählen", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        editItem.submenu = edit
        main.addItem(editItem)

        return main
    }
}

// Diagnostics: `AgentSessions --scan` lists what the scanner finds and exits.
if CommandLine.arguments.contains("--scan") {
    let found = SessionScanner { _ in }.collect().sorted { $0.lastActivity > $1.lastActivity }
    for s in found {
        let age = shortAge(from: s.lastActivity, to: Date())
        print("\(age.padding(toLength: 6, withPad: " ", startingAt: 0)) \(s.archived ? "A" : " ") \(s.assistant.padding(toLength: 14, withPad: " ", startingAt: 0)) \(s.title)")
    }
    print("\(found.count) Sessions")
    exit(0)
}

MainActor.assumeIsolated {
    let app = NSApplication.shared
    let delegate = AppDelegate()
    app.delegate = delegate
    app.setActivationPolicy(.accessory)
    app.run()
}
