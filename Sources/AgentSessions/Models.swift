import AppKit
import SwiftUI

enum ScreenEdge: String, Codable, CaseIterable, Identifiable {
    case top, bottom, left, right

    var id: String { rawValue }

    var label: String {
        switch self {
        case .top: "Oben"
        case .bottom: "Unten"
        case .left: "Links"
        case .right: "Rechts"
        }
    }

    /// Left/right edges: the rail runs vertically.
    var isVertical: Bool { self == .left || self == .right }
}

enum EdgePosition: String, Codable, CaseIterable, Identifiable {
    case start, center, end

    var id: String { rawValue }

    func label(for edge: ScreenEdge) -> String {
        switch self {
        case .center: "Mitte"
        case .start: edge.isVertical ? "Oben" : "Links"
        case .end: edge.isVertical ? "Unten" : "Rechts"
        }
    }
}

struct Assistant: Codable, Identifiable, Hashable {
    var id: String
    var name: String
    /// "#RRGGBB"
    var color: String

    static let defaults: [Assistant] = [
        Assistant(id: "claude-code", name: "Claude Code", color: "#D97757"),
        Assistant(id: "claude-cowork", name: "Claude Cowork", color: "#C9A227"),
        Assistant(id: "chatgpt-work", name: "ChatGPT Work", color: "#10A37F"),
        Assistant(id: "chatgpt-codex", name: "ChatGPT Codex", color: "#5B7CFA"),
        Assistant(id: "gemini", name: "Gemini", color: "#A970FF"),
        Assistant(id: "other", name: "Andere", color: "#8E8E93"),
    ]

    static let unknown = Assistant(id: "?", name: "Unbekannt", color: "#8E8E93")
}

/// A session the user entered by hand. Only the user changes it.
struct Session: Codable, Identifiable, Hashable {
    var id: String
    var title: String
    /// Assistant id, e.g. "claude-code".
    var assistant: String
    var createdAt: Date
    var lastActivityAt: Date
    var archivedAt: Date?

    init(id: String = UUID().uuidString, title: String, assistant: String, createdAt: Date = Date()) {
        self.id = id
        self.title = title
        self.assistant = assistant
        self.createdAt = createdAt
        self.lastActivityAt = createdAt
    }

    // Lenient decoding so the JSON file can be written by hand or by scripts.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(String.self, forKey: .id) ?? UUID().uuidString
        title = try c.decodeIfPresent(String.self, forKey: .title) ?? ""
        assistant = try c.decodeIfPresent(String.self, forKey: .assistant) ?? "other"
        createdAt = (try? c.decodeIfPresent(Date.self, forKey: .createdAt)) ?? Date()
        lastActivityAt = (try? c.decodeIfPresent(Date.self, forKey: .lastActivityAt)) ?? createdAt
        archivedAt = try? c.decodeIfPresent(Date.self, forKey: .archivedAt)
    }
}

/// What the user did with an automatically detected session.
struct AutoSessionState: Codable, Hashable {
    /// Title chosen by the user; overrides the assistant's title.
    var title: String?
    /// Archived by the user. The session comes back with any activity after this moment.
    var archivedAt: Date?
    /// Unarchived by the user; counts as activity.
    var unarchivedAt: Date?
    /// Deleted by the user: never show again.
    var deleted = false

    init() {}

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        title = try? c.decodeIfPresent(String.self, forKey: .title)
        archivedAt = try? c.decodeIfPresent(Date.self, forKey: .archivedAt)
        unarchivedAt = try? c.decodeIfPresent(Date.self, forKey: .unarchivedAt)
        deleted = (try? c.decodeIfPresent(Bool.self, forKey: .deleted)) ?? false
    }
}

struct AppData: Codable {
    var edge: ScreenEdge = .right
    var position: EdgePosition = .center
    var assistants: [Assistant] = Assistant.defaults
    var sessions: [Session] = []
    var autoDetect = true
    /// Detected sessions without activity for this long drop into the archive.
    var autoArchiveHours: Double = 4
    /// Keyed by DetectedSession.key.
    var autoStates: [String: AutoSessionState] = [:]

    init() {}

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        edge = (try? c.decodeIfPresent(ScreenEdge.self, forKey: .edge)) ?? .right
        position = (try? c.decodeIfPresent(EdgePosition.self, forKey: .position)) ?? .center
        assistants = try c.decodeIfPresent([Assistant].self, forKey: .assistants) ?? Assistant.defaults
        sessions = try c.decodeIfPresent([Session].self, forKey: .sessions) ?? []
        autoDetect = (try? c.decodeIfPresent(Bool.self, forKey: .autoDetect)) ?? true
        autoArchiveHours = (try? c.decodeIfPresent(Double.self, forKey: .autoArchiveHours)) ?? 4
        autoStates = (try? c.decodeIfPresent([String: AutoSessionState].self, forKey: .autoStates)) ?? [:]
    }
}

/// A session found in an assistant's local files.
struct DetectedSession: Hashable {
    /// "<source>:<session id>", stable across scans.
    let key: String
    let assistant: String
    let title: String
    let lastActivity: Date
    /// Archived inside the assistant itself.
    let archived: Bool
    /// Working folder, shown in the tooltip.
    let detail: String?
    /// false: stays active until the user archives it, regardless of inactivity.
    var autoArchives = true
}

/// One line in the rail: a manual or a detected session, ready to display.
struct RailItem: Identifiable, Hashable {
    enum Kind { case manual, auto }

    let id: String
    let kind: Kind
    let title: String
    let assistant: String
    let lastActivity: Date
    let detail: String?
    let archivedInSource: Bool

    var kindSymbol: String {
        kind == .manual ? "hand.raised.fill" : "dot.radiowaves.left.and.right"
    }

    var kindLabel: String {
        kind == .manual ? "Manuell eingetragen" : "Automatisch erkannt"
    }
}

extension Color {
    init(hex: String) {
        var s = hex.trimmingCharacters(in: .whitespaces)
        if s.hasPrefix("#") { s.removeFirst() }
        var value: UInt64 = 0
        guard s.count == 6, Scanner(string: s).scanHexInt64(&value) else {
            self = .gray
            return
        }
        self = Color(
            .sRGB,
            red: Double((value >> 16) & 0xFF) / 255,
            green: Double((value >> 8) & 0xFF) / 255,
            blue: Double(value & 0xFF) / 255
        )
    }

    var hexString: String {
        guard let c = NSColor(self).usingColorSpace(.sRGB) else { return "#8E8E93" }
        func byte(_ v: CGFloat) -> Int { Int((min(max(v, 0), 1) * 255).rounded()) }
        return String(format: "#%02X%02X%02X", byte(c.redComponent), byte(c.greenComponent), byte(c.blueComponent))
    }
}

/// "jetzt", "12m", "3h", "2d"
func shortAge(from start: Date, to now: Date) -> String {
    let s = Int(now.timeIntervalSince(start))
    if s < 60 { return "jetzt" }
    if s < 3600 { return "\(s / 60)m" }
    if s < 86400 { return "\(s / 3600)h" }
    return "\(s / 86400)d"
}
