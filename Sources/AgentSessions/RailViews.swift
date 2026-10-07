import AppKit
import ServiceManagement
import SwiftUI

struct RailRootView: View {
    @ObservedObject var store: Store
    @ObservedObject var rail: EdgeRailController

    var body: some View {
        let shape = edgeShape(store.data.edge, radius: rail.isExpanded ? 10 : 8)

        Group {
            if rail.isExpanded {
                ExpandedList(store: store, rail: rail)
            } else {
                CollapsedBadge(store: store)
            }
        }
        .background(VisualEffectBackground())
        .clipShape(shape)
        .overlay(shape.stroke(Color.primary.opacity(0.15), lineWidth: 1))
        .contextMenu { RailMenuItems(store: store, rail: rail) }
        .fixedSize()
        .onGeometryChange(for: CGSize.self) { $0.size } action: { rail.contentSizeDidChange($0) }
    }

    /// Flat on the screen-edge side, rounded on the inner side.
    private func edgeShape(_ edge: ScreenEdge, radius r: CGFloat) -> UnevenRoundedRectangle {
        switch edge {
        case .left:
            UnevenRoundedRectangle(topLeadingRadius: 0, bottomLeadingRadius: 0, bottomTrailingRadius: r, topTrailingRadius: r)
        case .right:
            UnevenRoundedRectangle(topLeadingRadius: r, bottomLeadingRadius: r, bottomTrailingRadius: 0, topTrailingRadius: 0)
        case .top:
            UnevenRoundedRectangle(topLeadingRadius: 0, bottomLeadingRadius: r, bottomTrailingRadius: r, topTrailingRadius: 0)
        case .bottom:
            UnevenRoundedRectangle(topLeadingRadius: r, bottomLeadingRadius: 0, bottomTrailingRadius: 0, topTrailingRadius: r)
        }
    }
}

// MARK: Collapsed

struct CollapsedBadge: View {
    @ObservedObject var store: Store
    private let maxDots = 12

    var body: some View {
        let active = store.items().active
        let count = Text("\(active.count)")
            .font(.system(size: 12, weight: .semibold, design: .rounded))
            .monospacedDigit()
            .foregroundStyle(active.isEmpty ? .tertiary : .primary)

        if store.data.edge.isVertical {
            VStack(spacing: 6) {
                count
                if !active.isEmpty {
                    VStack(spacing: 3) { dots(active) }
                }
            }
            .padding(.vertical, 8)
            .frame(width: 26)
        } else {
            HStack(spacing: 6) {
                count
                if !active.isEmpty {
                    HStack(spacing: 3) { dots(active) }
                }
            }
            .padding(.horizontal, 10)
            .frame(height: 24)
        }
    }

    @ViewBuilder
    private func dots(_ items: [RailItem]) -> some View {
        ForEach(items.prefix(maxDots)) { item in
            Circle()
                .fill(Color(hex: store.assistant(id: item.assistant).color))
                .frame(width: 6, height: 6)
        }
    }
}

// MARK: Expanded

struct ExpandedList: View {
    @ObservedObject var store: Store
    @ObservedObject var rail: EdgeRailController
    private let maxArchived = 20

    var body: some View {
        let (active, archived) = store.items()

        VStack(alignment: .leading, spacing: 1) {
            HStack(spacing: 8) {
                Text(headerText(active.count))
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                Button {
                    rail.showArchive.toggle()
                } label: {
                    Image(systemName: rail.showArchive ? "archivebox.fill" : "archivebox")
                }
                .buttonStyle(.borderless)
                .help(rail.showArchive ? "Archiv ausblenden" : "Archiv zeigen (\(archived.count))")

                Button {
                    rail.isAdding ? rail.endAdding() : rail.beginAdding()
                } label: {
                    Image(systemName: rail.isAdding ? "xmark" : "plus")
                }
                .buttonStyle(.borderless)
                .help(rail.isAdding ? "Abbrechen" : "Session manuell eintragen")

                Menu {
                    RailMenuItems(store: store, rail: rail)
                } label: {
                    Image(systemName: "ellipsis")
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
                .fixedSize()
            }
            .padding(.horizontal, 6)
            .padding(.bottom, 3)

            ForEach(active) { item in
                ItemRow(item: item, isArchived: false, store: store, rail: rail)
            }

            if rail.isAdding {
                AddSessionForm(store: store) { rail.endAdding() }
            } else if active.isEmpty {
                Text("Keine aktiven Sessions. Mit + manuell eintragen.")
                    .font(.system(size: 11))
                    .foregroundStyle(.tertiary)
                    .padding(6)
            }

            if rail.showArchive {
                Divider().padding(.vertical, 4)
                Text("Archiv")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 6)
                    .padding(.bottom, 2)
                if archived.isEmpty {
                    Text("Leer")
                        .font(.system(size: 11))
                        .foregroundStyle(.tertiary)
                        .padding(6)
                }
                ForEach(archived.prefix(maxArchived)) { item in
                    ItemRow(item: item, isArchived: true, store: store, rail: rail)
                }
                if archived.count > maxArchived {
                    Text("+ \(archived.count - maxArchived) ältere")
                        .font(.system(size: 10))
                        .foregroundStyle(.tertiary)
                        .padding(.horizontal, 6)
                        .padding(.top, 2)
                }
            }
        }
        .padding(6)
        .frame(width: 270)
    }

    private func headerText(_ n: Int) -> String {
        switch n {
        case 0: "Keine aktiven Sessions"
        case 1: "1 aktive Session"
        default: "\(n) aktive Sessions"
        }
    }
}

struct ItemRow: View {
    let item: RailItem
    let isArchived: Bool
    @ObservedObject var store: Store
    @ObservedObject var rail: EdgeRailController
    @State private var hovering = false

    var body: some View {
        let assistant = store.assistant(id: item.assistant)
        let color = Color(hex: assistant.color)
        let isRenaming = rail.renamingID == item.id

        HStack(spacing: 6) {
            Capsule()
                .fill(color)
                .frame(width: 3, height: 14)
            Image(systemName: item.kindSymbol)
                .font(.system(size: 8))
                .foregroundStyle(.tertiary)
                .frame(width: 11)
                .help(item.kindLabel)

            if isRenaming {
                RenameField(initial: item.title) { newTitle in
                    if let newTitle { store.rename(item, to: newTitle) }
                    rail.endRename()
                }
            } else {
                Text(item.title.isEmpty ? "Ohne Titel" : item.title)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(color)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .onTapGesture(count: 2) { rail.beginRename(item.id) }
                Spacer(minLength: 6)

                if hovering {
                    actions
                } else {
                    TimelineView(.periodic(from: .now, by: 60)) { context in
                        Text(shortAge(from: item.lastActivity, to: context.date))
                            .font(.system(size: 10))
                            .monospacedDigit()
                            .foregroundStyle(.tertiary)
                    }
                }
            }
        }
        .frame(height: 20)
        .padding(.horizontal, 6)
        .opacity(isArchived && !hovering ? 0.65 : 1)
        .background(
            RoundedRectangle(cornerRadius: 5)
                .fill(Color.primary.opacity(hovering && !isRenaming ? 0.07 : 0))
        )
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
        .help(tooltip(assistant))
    }

    @ViewBuilder
    private var actions: some View {
        HStack(spacing: 6) {
            iconButton("pencil", help: "Umbenennen (oder Doppelklick auf den Titel)") {
                rail.beginRename(item.id)
            }
            if isArchived {
                if !item.archivedInSource {
                    iconButton("tray.and.arrow.up", help: "Wieder aktiv") { store.unarchive(item) }
                }
            } else {
                iconButton("archivebox", help: "Archivieren – kommt bei neuer Aktivität zurück") { store.archive(item) }
            }
            iconButton("trash", help: item.kind == .auto ? "Löschen – taucht nie wieder auf" : "Löschen") {
                store.delete(item)
            }
        }
    }

    private func iconButton(_ symbol: String, help: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol).font(.system(size: 10))
        }
        .buttonStyle(.borderless)
        .foregroundStyle(.secondary)
        .help(help)
    }

    private func tooltip(_ assistant: Assistant) -> String {
        var lines = ["\(assistant.name) · \(item.kindLabel.lowercased())"]
        if let detail = item.detail { lines.append(detail) }
        lines.append("Letzte Aktivität: \(item.lastActivity.formatted(date: .abbreviated, time: .shortened))")
        if item.archivedInSource { lines.append("Im Assistenten archiviert") }
        return lines.joined(separator: "\n")
    }
}

struct RenameField: View {
    let initial: String
    /// nil = cancelled
    let onDone: (String?) -> Void
    @State private var text = ""
    @FocusState private var focused: Bool

    var body: some View {
        TextField("Titel", text: $text)
            .textFieldStyle(.roundedBorder)
            .font(.system(size: 12))
            .focused($focused)
            .onSubmit { onDone(text) }
            .onExitCommand { onDone(nil) }
            .onAppear {
                text = initial
                DispatchQueue.main.async { focused = true }
            }
    }
}

struct AddSessionForm: View {
    @ObservedObject var store: Store
    let onDone: () -> Void

    @State private var title = ""
    @AppStorage("lastAssistantID") private var assistantID = "claude-code"
    @FocusState private var focused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            TextField("Worum geht's?", text: $title)
                .textFieldStyle(.roundedBorder)
                .font(.system(size: 12))
                .focused($focused)
                .onSubmit(submit)
                .onExitCommand(perform: onDone)

            HStack(spacing: 6) {
                ForEach(store.data.assistants) { a in
                    Circle()
                        .fill(Color(hex: a.color))
                        .frame(width: 14, height: 14)
                        .overlay(
                            Circle()
                                .stroke(Color.primary.opacity(a.id == selectedID ? 0.85 : 0), lineWidth: 1.5)
                                .padding(-3)
                        )
                        .contentShape(Circle())
                        .onTapGesture {
                            assistantID = a.id
                            focused = true
                        }
                        .help(a.name)
                }
            }
            .padding(.horizontal, 3)

            Text("\(store.assistant(id: selectedID).name)  ·  ⏎ hinzufügen, esc abbrechen")
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 4)
        .padding(.vertical, 6)
        .onAppear { DispatchQueue.main.async { focused = true } }
    }

    private var selectedID: String {
        store.data.assistants.contains { $0.id == assistantID }
            ? assistantID
            : (store.data.assistants.first?.id ?? Assistant.unknown.id)
    }

    private func submit() {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        store.addSession(title: trimmed, assistant: selectedID)
        title = ""
        onDone()
    }
}

// MARK: Menu

struct RailMenuItems: View {
    @ObservedObject var store: Store
    let rail: EdgeRailController

    var body: some View {
        Button("Neue Session…") { rail.beginAdding() }
        Divider()
        Picker("Bildschirmrand", selection: $store.data.edge) {
            ForEach(ScreenEdge.allCases) { Text($0.label).tag($0) }
        }
        Picker("Position", selection: $store.data.position) {
            ForEach(EdgePosition.allCases) { Text($0.label(for: store.data.edge)).tag($0) }
        }
        Divider()
        Toggle("Sessions automatisch erkennen", isOn: $store.data.autoDetect)
        Picker("Automatisch archivieren nach", selection: $store.data.autoArchiveHours) {
            ForEach([1.0, 2, 4, 8, 24], id: \.self) { Text("\(Int($0)) Std. Inaktivität").tag($0) }
        }
        .disabled(!store.data.autoDetect)
        Divider()
        Button("Assistenten bearbeiten…") { rail.openSettings() }
        Toggle("Beim Anmelden starten", isOn: Binding(
            get: { SMAppService.mainApp.status == .enabled },
            set: { setLaunchAtLogin($0) }
        ))
        Button("Daten-Datei im Finder zeigen") {
            NSWorkspace.shared.activateFileViewerSelecting([store.fileURL])
        }
        Divider()
        Button("Beenden") { NSApp.terminate(nil) }
    }

    private func setLaunchAtLogin(_ on: Bool) {
        do {
            if on {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            let alert = NSAlert()
            alert.messageText = "Anmeldeobjekt konnte nicht geändert werden"
            alert.informativeText = "\(error.localizedDescription)\n\nTipp: Die App muss als .app-Bundle laufen (scripts/build-app.sh)."
            NSApp.activate()
            alert.runModal()
        }
    }
}

// MARK: Helpers

struct VisualEffectBackground: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = .popover
        view.blendingMode = .behindWindow
        view.state = .active
        return view
    }

    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {}
}
