import Foundation

/// Holds all app data and persists it as JSON in
/// ~/Library/Application Support/AgentSessions/sessions.json.
/// External changes to the file (by hand or by scripts) are picked up automatically.
///
/// Combines manual sessions with sessions detected by `SessionScanner`.
/// Only the user's decisions about detected sessions (title, archived, deleted)
/// are persisted, never the detected sessions themselves.
@MainActor
final class Store: ObservableObject {
    @Published var data: AppData {
        didSet {
            if !isReloading { save() }
            if oldValue.autoDetect != data.autoDetect { updateScanner() }
        }
    }

    /// Latest scan result; not persisted.
    @Published private(set) var detected: [DetectedSession] = []
    private var scanner: SessionScanner?

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
        updateScanner()
    }

    private func updateScanner() {
        if data.autoDetect {
            if scanner == nil {
                scanner = SessionScanner { [weak self] found in self?.detected = found }
            }
            scanner?.start()
        } else {
            scanner?.stop()
            detected = []
        }
    }

    // MARK: Queries

    /// Active sessions and archive, each sorted by last activity, most recent first.
    func items(now: Date = Date()) -> (active: [RailItem], archived: [RailItem]) {
        var active: [RailItem] = []
        var archived: [RailItem] = []

        for s in data.sessions {
            let item = RailItem(
                id: "manual:\(s.id)", kind: .manual, title: s.title, assistant: s.assistant,
                lastActivity: s.lastActivityAt, detail: nil, archivedInSource: false
            )
            if s.archivedAt == nil { active.append(item) } else { archived.append(item) }
        }

        let inactivityLimit = data.autoArchiveHours * 3600
        for d in detected {
            let state = data.autoStates[d.key] ?? AutoSessionState()
            if state.deleted { continue }

            let activity = max(d.lastActivity, state.unarchivedAt ?? .distantPast)
            let item = RailItem(
                id: d.key, kind: .auto, title: state.title ?? d.title, assistant: d.assistant,
                lastActivity: activity, detail: d.detail, archivedInSource: d.archived
            )
            // Archived by the user counts only until the session shows new activity.
            let archivedByUser = state.archivedAt.map { $0 >= activity } ?? false
            let inactive = d.autoArchives && now.timeIntervalSince(activity) > inactivityLimit
            if d.archived || archivedByUser || inactive {
                archived.append(item)
            } else {
                active.append(item)
            }
        }

        let byActivity: (RailItem, RailItem) -> Bool = { $0.lastActivity > $1.lastActivity }
        return (active.sorted(by: byActivity), archived.sorted(by: byActivity))
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

    func rename(_ item: RailItem, to newTitle: String) {
        let title = newTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        switch item.kind {
        case .manual:
            guard !title.isEmpty else { return }
            updateManual(item) { $0.title = title }
        case .auto:
            // An empty title falls back to the assistant's own title.
            data.autoStates[item.id, default: AutoSessionState()].title = title.isEmpty ? nil : title
        }
    }

    func archive(_ item: RailItem) {
        let now = Date()
        switch item.kind {
        case .manual:
            updateManual(item) { $0.archivedAt = now }
        case .auto:
            data.autoStates[item.id, default: AutoSessionState()].archivedAt = now
            data.autoStates[item.id]?.unarchivedAt = nil
        }
    }

    func unarchive(_ item: RailItem) {
        let now = Date()
        switch item.kind {
        case .manual:
            updateManual(item) {
                $0.archivedAt = nil
                $0.lastActivityAt = now
            }
        case .auto:
            data.autoStates[item.id, default: AutoSessionState()].archivedAt = nil
            data.autoStates[item.id]?.unarchivedAt = now
        }
    }

    func delete(_ item: RailItem) {
        switch item.kind {
        case .manual:
            data.sessions.removeAll { "manual:\($0.id)" == item.id }
        case .auto:
            data.autoStates[item.id, default: AutoSessionState()].deleted = true
        }
    }

    private func updateManual(_ item: RailItem, _ change: (inout Session) -> Void) {
        guard let index = data.sessions.firstIndex(where: { "manual:\($0.id)" == item.id }) else { return }
        change(&data.sessions[index])
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
