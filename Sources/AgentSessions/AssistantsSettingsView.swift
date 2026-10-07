import AppKit
import SwiftUI

struct AssistantsSettingsView: View {
    @ObservedObject var store: Store

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Farbe und Name pro KI-Assistent. Reihenfolge per Drag & Drop. Assistenten mit aktiven Sessions lassen sich nicht löschen.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            List {
                ForEach($store.data.assistants) { $assistant in
                    let inUse = store.sessionCount(for: assistant.id)
                    HStack(spacing: 10) {
                        ColorPicker("", selection: Binding(
                            get: { Color(hex: assistant.color) },
                            set: { assistant.color = $0.hexString }
                        ), supportsOpacity: false)
                        .labelsHidden()

                        TextField("Name", text: $assistant.name)
                            .textFieldStyle(.plain)

                        Spacer()

                        if inUse > 0 {
                            Text("\(inUse)")
                                .monospacedDigit()
                                .foregroundStyle(.secondary)
                                .help("Aktive Sessions")
                        }

                        Button {
                            store.removeAssistant(id: assistant.id)
                        } label: {
                            Image(systemName: "trash")
                        }
                        .buttonStyle(.borderless)
                        .disabled(inUse > 0)
                    }
                    .padding(.vertical, 2)
                }
                .onMove { store.data.assistants.move(fromOffsets: $0, toOffset: $1) }
            }
            .listStyle(.bordered)

            HStack {
                Button("Assistent hinzufügen") { store.addAssistant() }
                Spacer()
                Button("Daten-Datei zeigen") {
                    NSWorkspace.shared.activateFileViewerSelecting([store.fileURL])
                }
            }
        }
        .padding(16)
        .frame(minWidth: 380, minHeight: 360)
    }
}
