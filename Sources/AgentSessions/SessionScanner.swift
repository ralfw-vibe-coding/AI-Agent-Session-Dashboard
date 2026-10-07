import Foundation
import SQLite3

/// Finds interactive agent sessions in the local files of the AI assistants.
/// Reads only, never writes. The file formats are undocumented, so every
/// source fails quietly on its own if a format changes.
///
/// Sources:
/// - Claude desktop app, Code tab: ~/Library/Application Support/Claude/claude-code-sessions
/// - Claude Cowork (local VM):    ~/Library/Application Support/Claude/local-agent-mode-sessions/*/*/local_*.json
/// - Claude Cowork (cloud):        ~/Library/Application Support/Claude/local-agent-mode-sessions/*/*/remote-session-spaces.json
/// - Claude Code in the terminal: ~/.claude/projects/*/*.jsonl (entrypoint "cli")
/// - Codex and ChatGPT Work:      ~/.codex/state_*.sqlite, table threads
final class SessionScanner: @unchecked Sendable {
    /// Sessions older than this are ignored entirely (also not shown in the archive).
    private let lookback: TimeInterval = 14 * 86400
    private let interval: TimeInterval = 15

    private let queue = DispatchQueue(label: "AgentSessions.scanner", qos: .utility)
    private var timer: Timer?
    private let onResult: @MainActor ([DetectedSession]) -> Void

    /// Parsed files by path, reused while the modification date is unchanged. Only touched on `queue`.
    private var fileCache: [String: (modified: Date, session: DetectedSession?)] = [:]

    private let home = FileManager.default.homeDirectoryForCurrentUser

    /// When each Cowork cloud session was first seen, persisted across launches. Only touched on `queue`.
    private var coworkSeen: [String: Date]?
    private let coworkSeenURL = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("AgentSessions/cowork-cloud-seen.json")

    init(onResult: @escaping @MainActor ([DetectedSession]) -> Void) {
        self.onResult = onResult
    }

    func start() {
        guard timer == nil else { return }
        scan()
        timer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            self?.scan()
        }
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    func scan() {
        queue.async { [weak self] in
            guard let self else { return }
            let result = self.collect()
            DispatchQueue.main.async { self.onResult(result) }
        }
    }

    /// Synchronous scan; call only on `queue` or from the `--scan` diagnostics.
    func collect() -> [DetectedSession] {
        let cutoff = Date().addingTimeInterval(-lookback)
        var found: [DetectedSession] = []
        found += scanClaudeDesktop(folder: "claude-code-sessions", source: "claude-desktop", assistant: "claude-code", cutoff: cutoff)
        found += scanClaudeDesktop(folder: "local-agent-mode-sessions", source: "claude-cowork", assistant: "claude-cowork", cutoff: cutoff)
        found += scanCoworkCloud(cutoff: cutoff)
        found += scanClaudeCLI(cutoff: cutoff)
        found += scanCodex(cutoff: cutoff)
        return found
    }

    // MARK: Claude desktop app (Code tab and Cowork)

    private func scanClaudeDesktop(folder: String, source: String, assistant: String, cutoff: Date) -> [DetectedSession] {
        let root = home.appendingPathComponent("Library/Application Support/Claude/\(folder)")
        // Layout: <root>/<account>/<org>/local_<id>.json
        var result: [DetectedSession] = []
        for file in filesTwoLevelsDown(root, where: { $0.hasPrefix("local_") && $0.hasSuffix(".json") }) {
            let session = cached(file) { url in
                guard let raw = try? Data(contentsOf: url),
                      let json = try? JSONSerialization.jsonObject(with: raw) as? [String: Any],
                      let id = json["sessionId"] as? String,
                      let lastMs = json["lastActivityAt"] as? Double
                else { return nil }
                // Scheduled tasks are not interactive sessions.
                if json["sessionType"] as? String == "scheduled" || json["scheduledTaskId"] != nil { return nil }

                let cwd = (json["userSelectedFolders"] as? [String])?.first ?? json["cwd"] as? String
                let title = (json["title"] as? String).flatMap { $0.isEmpty ? nil : $0 }
                    ?? cwd.map { URL(fileURLWithPath: $0).lastPathComponent }
                    ?? "Ohne Titel"
                return DetectedSession(
                    key: "\(source):\(id)",
                    assistant: assistant,
                    title: title,
                    lastActivity: Date(timeIntervalSince1970: lastMs / 1000),
                    archived: json["isArchived"] as? Bool ?? false,
                    detail: cwd
                )
            }
            if let session, session.lastActivity >= cutoff { result.append(session) }
        }
        return result
    }

    // MARK: Claude Cowork in the cloud

    /// Cloud sessions are only listed locally with id and shared folders: no title,
    /// no timestamps, no archive state. A session counts as started when its id first
    /// shows up; later activity is invisible, so it auto-archives after the usual
    /// inactivity period from that moment.
    private func scanCoworkCloud(cutoff: Date) -> [DetectedSession] {
        let root = home.appendingPathComponent("Library/Application Support/Claude/local-agent-mode-sessions")
        let isFirstRun = loadCoworkSeen() == nil
        var seen = coworkSeen ?? [:]
        var changed = isFirstRun
        let now = Date()
        var entries: [(id: String, folders: [String])] = []

        for file in filesTwoLevelsDown(root, where: { $0 == "remote-session-spaces.json" }) {
            guard let raw = try? Data(contentsOf: file),
                  let json = try? JSONSerialization.jsonObject(with: raw) as? [String: Any],
                  let list = json["entries"] as? [[String: Any]]
            else { continue }
            let modified = modificationDate(file) ?? now

            for (index, entry) in list.enumerated() {
                guard let id = entry["sessionId"] as? String else { continue }
                entries.append((id, entry["folders"] as? [String] ?? []))
                guard seen[id] == nil else { continue }
                if isFirstRun {
                    // Existing sessions count as old. New entries are appended, so the last
                    // one is probably the current session: date it by the file's last change.
                    seen[id] = index == list.count - 1 ? modified : .distantPast
                } else {
                    seen[id] = now
                }
                changed = true
            }
        }

        if changed {
            coworkSeen = seen
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            try? encoder.encode(seen).write(to: coworkSeenURL, options: .atomic)
        }

        return entries.compactMap { entry in
            guard let firstSeen = seen[entry.id], firstSeen >= cutoff else { return nil }
            let names = entry.folders.map { URL(fileURLWithPath: $0).lastPathComponent }
            return DetectedSession(
                key: "claude-cowork-cloud:\(entry.id)",
                assistant: "claude-cowork",
                title: names.isEmpty ? "Cowork-Session" : names.joined(separator: " + "),
                lastActivity: firstSeen,
                archived: false,
                detail: (entry.folders + ["Cloud-Session: nur der Start ist bekannt"]).joined(separator: "\n")
            )
        }
    }

    private func loadCoworkSeen() -> [String: Date]? {
        if let coworkSeen { return coworkSeen }
        guard let raw = try? Data(contentsOf: coworkSeenURL) else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        coworkSeen = try? decoder.decode([String: Date].self, from: raw)
        return coworkSeen
    }

    // MARK: Claude Code in the terminal

    private func scanClaudeCLI(cutoff: Date) -> [DetectedSession] {
        let root = home.appendingPathComponent(".claude/projects")
        var result: [DetectedSession] = []
        let fm = FileManager.default
        guard let projects = try? fm.contentsOfDirectory(at: root, includingPropertiesForKeys: nil) else { return [] }

        for project in projects {
            guard let files = try? fm.contentsOfDirectory(
                at: project, includingPropertiesForKeys: [.contentModificationDateKey], options: [.skipsHiddenFiles]
            ) else { continue }

            for file in files where file.pathExtension == "jsonl" {
                guard let modified = modificationDate(file), modified >= cutoff else { continue }
                let session = cached(file, modified: modified) { url in
                    guard let header = Self.readCLIHeader(url), header.entrypoint == "cli" else { return nil }
                    return DetectedSession(
                        key: "claude-cli:\(header.sessionId)",
                        assistant: "claude-code",
                        title: URL(fileURLWithPath: header.cwd).lastPathComponent,
                        lastActivity: modified,
                        archived: false,
                        detail: header.cwd
                    )
                }
                if let session { result.append(session) }
            }
        }
        return result
    }

    /// Finds entrypoint, cwd and session id in the first lines of a transcript.
    private static func readCLIHeader(_ url: URL) -> (entrypoint: String, cwd: String, sessionId: String)? {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? handle.close() }
        guard let chunk = try? handle.read(upToCount: 256 * 1024) else { return nil }

        for line in chunk.split(separator: UInt8(ascii: "\n")) {
            guard let json = try? JSONSerialization.jsonObject(with: Data(line)) as? [String: Any],
                  let entrypoint = json["entrypoint"] as? String,
                  let cwd = json["cwd"] as? String,
                  let sessionId = json["sessionId"] as? String
            else { continue }
            return (entrypoint, cwd, sessionId)
        }
        return nil
    }

    // MARK: Codex and ChatGPT Work (same app, same database)

    private func scanCodex(cutoff: Date) -> [DetectedSession] {
        let root = home.appendingPathComponent(".codex")
        // The schema version is part of the file name (state_5.sqlite); take the newest.
        guard let names = try? FileManager.default.contentsOfDirectory(atPath: root.path) else { return [] }
        let dbName = names
            .filter { $0.hasPrefix("state_") && $0.hasSuffix(".sqlite") }
            .max { (Int($0.dropFirst(6).dropLast(7)) ?? 0) < (Int($1.dropFirst(6).dropLast(7)) ?? 0) }
        guard let dbName else { return [] }

        let dbPath = root.appendingPathComponent(dbName).path
        // While Codex runs, the -wal file exists and a normal read-only connection works.
        // Without it, a read-only connection can't set up WAL mode, but then nobody is
        // writing and the file can safely be opened as immutable.
        let isBeingWritten = FileManager.default.fileExists(atPath: dbPath + "-wal")
        var components = URLComponents()
        components.scheme = "file"
        components.path = dbPath
        components.queryItems = isBeingWritten ? nil : [URLQueryItem(name: "immutable", value: "1")]
        guard let uri = components.string else { return [] }

        var db: OpaquePointer?
        guard sqlite3_open_v2(uri, &db, SQLITE_OPEN_READONLY | SQLITE_OPEN_URI, nil) == SQLITE_OK else {
            sqlite3_close(db)
            return []
        }
        defer { sqlite3_close(db) }
        sqlite3_busy_timeout(db, 1000)

        // Only threads started by the user: no subagents, guardian reviews, automations or exec runs.
        let sql = """
            SELECT id, coalesce(name, ''), title, coalesce(updated_at_ms, updated_at * 1000),
                   archived, coalesce(originator, ''), cwd
            FROM threads
            WHERE source IN ('vscode', 'cli')
              AND coalesce(thread_source, 'user') = 'user'
              AND updated_at >= ?
            """
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return [] }
        defer { sqlite3_finalize(stmt) }
        sqlite3_bind_int64(stmt, 1, Int64(cutoff.timeIntervalSince1970))

        func text(_ col: Int32) -> String {
            sqlite3_column_text(stmt, col).map { String(cString: $0) } ?? ""
        }

        var result: [DetectedSession] = []
        while sqlite3_step(stmt) == SQLITE_ROW {
            let id = text(0)
            let name = text(1)
            let rawTitle = text(2)
            let updatedMs = sqlite3_column_int64(stmt, 3)
            let archived = sqlite3_column_int64(stmt, 4) != 0
            let originator = text(5)
            let cwd = text(6)

            result.append(DetectedSession(
                key: "codex:\(id)",
                assistant: originator == "codex_work_desktop" ? "chatgpt-work" : "chatgpt-codex",
                title: name.isEmpty ? Self.codexFallbackTitle(rawTitle) : name,
                lastActivity: Date(timeIntervalSince1970: Double(updatedMs) / 1000),
                archived: archived,
                detail: cwd.isEmpty ? nil : cwd
            ))
        }
        return result
    }

    /// Without a thread name the title is the first prompt, sometimes prefixed with attachment headers.
    private static func codexFallbackTitle(_ raw: String) -> String {
        let line = raw.split(separator: "\n")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .first { !$0.isEmpty && !$0.hasPrefix("#") }
            ?? "Ohne Titel"
        return line.count > 60 ? String(line.prefix(60)) + "…" : line
    }

    // MARK: Helpers

    private func filesTwoLevelsDown(_ root: URL, where match: (String) -> Bool) -> [URL] {
        let fm = FileManager.default
        var result: [URL] = []
        for level1 in (try? fm.contentsOfDirectory(at: root, includingPropertiesForKeys: nil)) ?? [] {
            for level2 in (try? fm.contentsOfDirectory(at: level1, includingPropertiesForKeys: nil)) ?? [] {
                for file in (try? fm.contentsOfDirectory(at: level2, includingPropertiesForKeys: nil)) ?? []
                where match(file.lastPathComponent) {
                    result.append(file)
                }
            }
        }
        return result
    }

    private func modificationDate(_ url: URL) -> Date? {
        (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate
    }

    private func cached(_ url: URL, modified: Date? = nil, parse: (URL) -> DetectedSession?) -> DetectedSession? {
        guard let modified = modified ?? modificationDate(url) else { return nil }
        if let hit = fileCache[url.path], hit.modified == modified { return hit.session }
        let session = parse(url)
        fileCache[url.path] = (modified, session)
        return session
    }
}
