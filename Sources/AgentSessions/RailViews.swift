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
        let sessions = store.sortedSessions
        let count = Text("\(sessions.count)")
            .font(.system(size: 12, weight: .semibold, design: .rounded))
            .monospacedDigit()
            .foregroundStyle(sessions.isEmpty ? .tertiary : .primary)

        if store.data.edge.isVertical {
            VStack(spacing: 6) {
                count
                if !sessions.isEmpty {
                    VStack(spacing: 3) { dots(sessions) }
                }
            }
            .padding(.vertical, 8)
            .frame(width: 26)
        } else {
            HStack(spacing: 6) {
                count
                if !sessions.isEmpty {
                    HStack(spacing: 3) { dots(sessions) }
                }
            }
            .padding(.horizontal, 10)
            .frame(height: 24)
        }
    }

    @ViewBuilder
    private func dots(_ sessions: [Session]) -> some View {
        ForEach(sessions.prefix(maxDots)) { s in
            Circle()
                .fill(Color(hex: store.assistant(id: s.assistant).color))
                .frame(width: 6, height: 6)
        }
    }
}

// MARK: Expanded

struct ExpandedList: View {
    @ObservedObject var store: Store
    @ObservedObject var rail: EdgeRailController

    var body: some View {
        let sessions = store.sortedSessions

        VStack(alignment: .leading, spacing: 1) {
            HStack(spacing: 8) {
                Text(headerText(sessions.count))
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                Button {
                    rail.isAdding ? rail.endAdding() : rail.beginAdding()
                } label: {
                    Image(systemName: rail.isAdding ? "xmark" : "plus")
                }
                .buttonStyle(.borderless)
                .help(rail.isAdding ? "Abbrechen" : "Neue Session")

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

            ForEach(sessions) { session in
                SessionRow(session: session, assistant: store.assistant(id: session.assistant)) {
                    store.removeSession(id: session.id)
                }
            }

            if rail.isAdding {
                AddSessionForm(store: store) { rail.endAdding() }
            } else if sessions.isEmpty {
                Text("Mit + eine Session hinzufügen")
                    .font(.system(size: 11))
                    .foregroundStyle(.tertiary)
                    .padding(6)
            }
        }
        .padding(6)
        .frame(width: 250)
    }

    private func headerText(_ n: Int) -> String {
        switch n {
        case 0: "Keine aktiven Sessions"
        case 1: "1 aktive Session"
        default: "\(n) aktive Sessions"
        }
    }
}

struct SessionRow: View {
    let session: Session
    let assistant: Assistant
    let onDelete: () -> Void
    @State private var hovering = false

    var body: some View {
        let color = Color(hex: assistant.color)

        HStack(spacing: 7) {
            Capsule()
                .fill(color)
                .frame(width: 3, height: 14)
            Text(session.title.isEmpty ? "Ohne Titel" : session.title)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(color)
                .lineLimit(1)
                .truncationMode(.tail)
            Spacer(minLength: 6)
            if hovering {
                Button(action: onDelete) {
                    Image(systemName: "xmark.circle.fill")
                }
                .buttonStyle(.borderless)
                .foregroundStyle(.secondary)
                .help("Session entfernen")
            } else {
                TimelineView(.periodic(from: .now, by: 60)) { context in
                    Text(shortAge(from: session.createdAt, to: context.date))
                        .font(.system(size: 10))
                        .monospacedDigit()
                        .foregroundStyle(.tertiary)
                }
            }
        }
        .frame(height: 20)
        .padding(.horizontal, 6)
        .background(
            RoundedRectangle(cornerRadius: 5)
                .fill(Color.primary.opacity(hovering ? 0.07 : 0))
        )
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
        .help("\(assistant.name) · seit \(session.createdAt.formatted(date: .abbreviated, time: .shortened))")
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
