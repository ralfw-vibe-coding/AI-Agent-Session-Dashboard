import Foundation

/// Holds all app data and persists it as JSON in
/// ~/Library/Application Support/AgentSessions/sessions.json.
/// External changes to the file (by hand or by scripts) are picked up automatically.
@MainActor
final class Store: ObservableObject {
    @Published var data: AppData {
        didSet { if !isReloading { save() } }
    }

    let fileURL: URL
    private var isReloading = false
    private var lastSeenModDate: Date?
    private var pollTimer: Timer?

    init() {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("AgentSessions", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        fileURL = dir.appendingPathComponent("sessions.json")

        if FileManager.default.fileExists(atPath: fileURL.path) {
            if let loaded = Store.read(fileURL) {
                data = loaded
            } else {
                // Keep the unreadable file around instead of silently overwriting it.
                let backup = fileURL.deletingPathExtension()
                    .appendingPathExtension("broken-\(Int(Date().timeIntervalSince1970)).json")
                try? FileManager.default.moveItem(at: fileURL, to: backup)
                data = AppData()
                save()
            }
        } else {
            data = AppData()
            save()
        }
        lastSeenModDate = modificationDate()

        pollTimer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.reloadIfChanged() }
        }
    }

    // MARK: Queries

    var sortedSessions: [Session] {
        data.sessions.sorted { $0.createdAt < $1.createdAt }
    }

    func assistant(id: String) -> Assistant {
        data.assistants.first { $0.id == id } ?? .unknown
    }

    func sessionCount(for assistantID: String) -> Int {
        data.sessions.filter { $0.assistant == assistantID }.count
    }

    // MARK: Commands

    func addSession(title: String, assistant: String) {
        data.sessions.append(Session(title: title, assistant: assistant))
    }

    func removeSession(id: String) {
        data.sessions.removeAll { $0.id == id }
    }

    func addAssistant() {
        data.assistants.append(Assistant(id: UUID().uuidString.lowercased(), name: "Neuer Assistent", color: "#8E8E93"))
    }

    func removeAssistant(id: String) {
        guard sessionCount(for: id) == 0 else { return }
        data.assistants.removeAll { $0.id == id }
    }

    // MARK: Persistence

    private static func read(_ url: URL) -> AppData? {
        guard let raw = try? Data(contentsOf: url) else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try? decoder.decode(AppData.self, from: raw)
    }

    private func save() {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        guard let raw = try? encoder.encode(data) else { return }
        try? raw.write(to: fileURL, options: .atomic)
        lastSeenModDate = modificationDate()
    }

    private func modificationDate() -> Date? {
        (try? FileManager.default.attributesOfItem(atPath: fileURL.path))?[.modificationDate] as? Date
    }

    private func reloadIfChanged() {
        let mod = modificationDate()
        guard mod != lastSeenModDate else { return }
        lastSeenModDate = mod
        guard let loaded = Store.read(fileURL) else { return }
        isReloading = true
        data = loaded
        isReloading = false
    }
}
